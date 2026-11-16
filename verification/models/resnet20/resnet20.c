#include <stddef.h>
#include <stdint.h>

/* Example PS addresses. Replace these with the Vivado address map. */
#define WEIGHT_BASE       0x20000000
#define FEATURE_BASE      0x21000000u
#define LOGIT_BASE        0x21010000u
#define AXI_LITE_BASE     0x43C00000u
#define INSTRUCTION_REG   (AXI_LITE_BASE + 0x00u)
#define STATE_REG         INSTRUCTION_REG
#define FEATURE_DMA_BASE  0x40400000u
#define KERNEL_DMA_BASE   0x40410000u
#define BIAS_DMA_BASE     0x40420000u
#define OUTPUT_DMA_BASE   0x40430000u

#define WORD_BYTES        2u
#define WEIGHT_BIN_BYTES  543380u
#define POLL_LIMIT        10000000u

/* Board hooks. DMA start is nonblocking. DMA wait checks errors and times out.
 * Implement MMIO ordering and DMA cache maintenance in these hooks. */
extern void axi_write32(uintptr_t reg, uint32_t value);
extern uint32_t axi_read32(uintptr_t reg);
extern int dma_start_tx(uintptr_t dma, uintptr_t src, size_t bytes);
extern int dma_start_rx(uintptr_t dma, uintptr_t dst, size_t bytes);
extern int dma_wait_tx(uintptr_t dma);
extern int dma_wait_rx(uintptr_t dma);

/* Draft 32-bit layout: input[0], output[1], core[6:2], skip[7],
 * stride-1[8], padding[9], W-1[15:10], H-1[21:16], Cin-1[27:22],
 * PL state[31:28] on read. PL clears stale DONE when it accepts a command. */
enum {
    INPUT_ENABLE   = 1u << 0,
    OUTPUT_ENABLE  = 1u << 1,
    CORE_GAP       = 1u << 2,
    CORE_RELU      = 1u << 4,
    CORE_RESIDUAL  = 1u << 5,
    CORE_MAC       = 1u << 6,
    SAVE_SKIP      = 1u << 7,
    PL_DONE        = 1u << 28,
};
#define PL_ERROR (UINT32_C(1) << 31)

typedef enum {
    INPUT = INPUT_ENABLE,
    SKIP = SAVE_SKIP,
    SKIP_CONV = SAVE_SKIP | CORE_MAC,
    CONV_RELU = CORE_MAC | CORE_RELU,
    CONV_RESIDUAL_RELU = CORE_MAC | CORE_RESIDUAL | CORE_RELU,
    CONV_RESIDUAL_RELU_GAP = CORE_MAC | CORE_RESIDUAL | CORE_RELU | CORE_GAP,
    FC_OUT = CORE_MAC | OUTPUT_ENABLE,
} opcode_t;

typedef struct {
    opcode_t op;
    uint8_t width, height, cin;  /* Input feature dimensions. */
    uint8_t cout, kernel_size;   /* PS DMA lengths. PL uses its layer schedule. */
    uint8_t stride, padding;
} instruction_t;

const instruction_t resnet20_instruction_set[] = {
    /* op                     W   H  Cin Cout  K  S  P */
    {INPUT,                  32, 32,  3,  0,  0, 1, 0},
    {CONV_RELU,              32, 32,  3, 16,  3, 1, 1}, /* stem */

    {SKIP,                   32, 32, 16,  0,  0, 1, 0}, /* layer1.0 */
    {CONV_RELU,              32, 32, 16, 16,  3, 1, 1},
    {CONV_RESIDUAL_RELU,     32, 32, 16, 16,  3, 1, 1},
    {SKIP,                   32, 32, 16,  0,  0, 1, 0}, /* layer1.1 */
    {CONV_RELU,              32, 32, 16, 16,  3, 1, 1},
    {CONV_RESIDUAL_RELU,     32, 32, 16, 16,  3, 1, 1},
    {SKIP,                   32, 32, 16,  0,  0, 1, 0}, /* layer1.2 */
    {CONV_RELU,              32, 32, 16, 16,  3, 1, 1},
    {CONV_RESIDUAL_RELU,     32, 32, 16, 16,  3, 1, 1},

    {SKIP_CONV,              32, 32, 16, 32,  1, 2, 0}, /* layer2.0 */
    {CONV_RELU,              32, 32, 16, 32,  3, 2, 1},
    {CONV_RESIDUAL_RELU,     16, 16, 32, 32,  3, 1, 1},
    {SKIP,                   16, 16, 32,  0,  0, 1, 0}, /* layer2.1 */
    {CONV_RELU,              16, 16, 32, 32,  3, 1, 1},
    {CONV_RESIDUAL_RELU,     16, 16, 32, 32,  3, 1, 1},
    {SKIP,                   16, 16, 32,  0,  0, 1, 0}, /* layer2.2 */
    {CONV_RELU,              16, 16, 32, 32,  3, 1, 1},
    {CONV_RESIDUAL_RELU,     16, 16, 32, 32,  3, 1, 1},

    {SKIP_CONV,              16, 16, 32, 64,  1, 2, 0}, /* layer3.0 */
    {CONV_RELU,              16, 16, 32, 64,  3, 2, 1},
    {CONV_RESIDUAL_RELU,      8,  8, 64, 64,  3, 1, 1},
    {SKIP,                    8,  8, 64,  0,  0, 1, 0}, /* layer3.1 */
    {CONV_RELU,               8,  8, 64, 64,  3, 1, 1},
    {CONV_RESIDUAL_RELU,      8,  8, 64, 64,  3, 1, 1},
    {SKIP,                    8,  8, 64,  0,  0, 1, 0}, /* layer3.2 */
    {CONV_RELU,               8,  8, 64, 64,  3, 1, 1},
    {CONV_RESIDUAL_RELU_GAP,  8,  8, 64, 64,  3, 1, 1},
    {FC_OUT,                  1,  1, 64, 10,  1, 1, 0},
};

typedef enum {
    RUN_OK = 0,
    RUN_DMA_ERROR = -1,
    RUN_PL_ERROR = -2,
    RUN_TIMEOUT = -3,
    RUN_WEIGHT_LENGTH_ERROR = -4,
} run_result_t;

static uint32_t pack_instruction(const instruction_t *inst)
{
    return (uint32_t)inst->op
        | (((uint32_t)inst->stride - 1u) << 8)
        | ((uint32_t)inst->padding << 9)
        | (((uint32_t)inst->width - 1u) << 10)
        | (((uint32_t)inst->height - 1u) << 16)
        | (((uint32_t)inst->cin - 1u) << 22);
}

static run_result_t wait_pl_done(void)
{
    for (unsigned poll = 0; poll < POLL_LIMIT; ++poll) {
        const uint32_t state = axi_read32(STATE_REG);
        if (state & PL_ERROR) {
            return RUN_PL_ERROR;
        }
        if (state & PL_DONE) {
            return RUN_OK;
        }
    }
    return RUN_TIMEOUT;
}

/* Load weight.bin at WEIGHT_BASE and the Q5.10 input at FEATURE_BASE before run.
 * On any error, reset active PL/DMA channels before restarting inference. */
run_result_t run(const instruction_t *instructions, size_t count)
{
    size_t weight_offset = 0;

    for (size_t i = 0; i < count; ++i) {
        const instruction_t *inst = &instructions[i];
        const int uses_weights = (inst->op & CORE_MAC) != 0;
        const size_t kernel_bytes = (size_t)inst->cin * inst->cout
            * inst->kernel_size * inst->kernel_size * WORD_BYTES;
        const size_t bias_bytes = (size_t)inst->cout * WORD_BYTES;

        if (uses_weights && weight_offset + kernel_bytes + bias_bytes > WEIGHT_BIN_BYTES) {
            return RUN_WEIGHT_LENGTH_ERROR;
        }
        if (inst->op == FC_OUT && dma_start_rx(OUTPUT_DMA_BASE, LOGIT_BASE, bias_bytes)) {
            return RUN_DMA_ERROR;
        }

        axi_write32(INSTRUCTION_REG, pack_instruction(inst));

        if (inst->op == INPUT) {
            const size_t feature_bytes = (size_t)inst->width * inst->height * inst->cin * WORD_BYTES;
            if (dma_start_tx(FEATURE_DMA_BASE, FEATURE_BASE, feature_bytes)
                || dma_wait_tx(FEATURE_DMA_BASE)) {
                return RUN_DMA_ERROR;
            }
        } else if (uses_weights) {
            const uintptr_t kernel_src = WEIGHT_BASE + weight_offset;
            const uintptr_t bias_src = kernel_src + kernel_bytes;
            if (dma_start_tx(KERNEL_DMA_BASE, kernel_src, kernel_bytes)
                || dma_start_tx(BIAS_DMA_BASE, bias_src, bias_bytes)
                || dma_wait_tx(KERNEL_DMA_BASE)
                || dma_wait_tx(BIAS_DMA_BASE)) {
                return RUN_DMA_ERROR;
            }
            weight_offset += kernel_bytes + bias_bytes;
        }

        const run_result_t result = wait_pl_done();
        if (result != RUN_OK) {
            return result;
        }
        if (inst->op == FC_OUT && dma_wait_rx(OUTPUT_DMA_BASE)) {
            return RUN_DMA_ERROR;
        }
    }

    return weight_offset == WEIGHT_BIN_BYTES ? RUN_OK : RUN_WEIGHT_LENGTH_ERROR;
}

run_result_t resnet20_run(void)
{
    return run(resnet20_instruction_set,
               sizeof resnet20_instruction_set / sizeof resnet20_instruction_set[0]);
}
