#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { INPUT = 1, SKIP = 128, SKIP_CONV = 192, CONV_RELU = 80,
       RESIDUAL_RELU = 112, RESIDUAL_GAP = 116, FC_OUT = 66 };
enum { CAPACITY = 32 * 32 * 16, MAX_KERNEL = 64 * 64 * 3 * 3, SCALE = 1024 };

typedef struct {
    float feature[CAPACITY];
    float skip[CAPACITY];
    float scratch[CAPACITY];
    float weights[MAX_KERNEL];
    float biases[64];
    int feature_count;
    int skip_count;
    int logits[10];
} Model;

void *resnet20_create(void)
{
    return calloc(1, sizeof(Model));
}

void resnet20_destroy(void *handle)
{
    free(handle);
}

void resnet20_reset(void *handle)
{
    Model *model = handle;
    model->feature_count = 0;
    model->skip_count = 0;
}

static float from_word(int word)
{
    return (float)(int16_t)(uint16_t)word / SCALE;
}

static int to_word(float value)
{
    float rounded = roundf(value * SCALE);
    if (rounded > INT16_MAX) return INT16_MAX;
    if (rounded < INT16_MIN) return INT16_MIN;
    return (int)rounded;
}

void resnet20_store(void *handle, int stream, int index, int word)
{
    Model *model = handle;
    switch (stream) {
    case 0: model->feature[index] = from_word(word); break;
    case 1: model->weights[index] = from_word(word); break;
    case 2: model->biases[index] = from_word(word); break;
    }
}

static float convolve(const Model *model, const float *kernel, int w, int h, int cin,
                      int k, int stride, int pad, int ox, int oy, float acc)
{
    for (int ic = 0; ic < cin; ++ic) {
        for (int ky = 0; ky < k; ++ky) {
            int iy = oy * stride + ky - pad;
            if (iy < 0 || iy >= h) continue;
            for (int kx = 0; kx < k; ++kx) {
                int ix = ox * stride + kx - pad;
                if (ix >= 0 && ix < w) {
                    int feature_index = (iy * w + ix) * cin + ic;
                    int kernel_index = (ic * k + ky) * k + kx;
                    acc += model->feature[feature_index] * kernel[kernel_index];
                }
            }
        }
    }
    return acc;
}

/* Returns zero on success. All intermediate activations stay in float. */
int resnet20_step(void *handle, int op, int w, int h, int cin, int cout,
                  int k, int stride, int pad)
{
    Model *model = handle;
    int input_count = w * h * cin;
    if (input_count <= 0 || input_count > CAPACITY) return 1;

    if (op == INPUT) {
        model->skip_count = 0;
        model->feature_count = input_count;
        return 0;
    }
    if (model->feature_count != input_count) return 1;
    if (op == SKIP) {
        memcpy(model->skip, model->feature, input_count * sizeof(float));
        model->skip_count = input_count;
        return 0;
    }
    if (op != SKIP_CONV && op != CONV_RELU && op != RESIDUAL_RELU &&
        op != RESIDUAL_GAP && op != FC_OUT) return 1;
    if (cout <= 0 || cout > 64 || k <= 0 || k > 3 || stride <= 0 ||
        w + 2 * pad < k || h + 2 * pad < k) return 1;

    int out_w = (w + 2 * pad - k) / stride + 1;
    int out_h = (h + 2 * pad - k) / stride + 1;
    int out_count = out_w * out_h * cout;
    if (out_count <= 0 || out_count > CAPACITY) return 1;
    if (op == FC_OUT && (out_w != 1 || out_h != 1 || cout > 10)) return 1;
    if ((op == RESIDUAL_RELU || op == RESIDUAL_GAP) &&
        model->skip_count != out_count) return 1;

    int kernel_size = cin * k * k;
    if (kernel_size * cout > MAX_KERNEL) return 1;

    for (int y = 0; y < out_h; ++y) {
        for (int x = 0; x < out_w; ++x) {
            for (int oc = 0; oc < cout; ++oc) {
                int index = (y * out_w + x) * cout + oc;
                float value = convolve(model, model->weights + oc * kernel_size, w, h, cin,
                                       k, stride, pad, x, y, model->biases[oc]);
                if (op == RESIDUAL_RELU || op == RESIDUAL_GAP) value += model->skip[index];
                if (op == CONV_RELU || op == RESIDUAL_RELU || op == RESIDUAL_GAP)
                    value = fmaxf(value, 0.0f);
                model->scratch[index] = value;
            }
        }
    }
    if (op == SKIP_CONV) {
        memcpy(model->skip, model->scratch, out_count * sizeof(float));
        model->skip_count = out_count;
    } else if (op == RESIDUAL_GAP) {
        for (int oc = 0; oc < cout; ++oc) {
            float sum = 0.0f;
            for (int i = oc; i < out_count; i += cout) sum += model->scratch[i];
            model->feature[oc] = sum / (out_w * out_h);
        }
        model->feature_count = cout;
    } else if (op == FC_OUT) {
        for (int oc = 0; oc < cout; ++oc) model->logits[oc] = to_word(model->scratch[oc]);
    } else {
        memcpy(model->feature, model->scratch, out_count * sizeof(float));
        model->feature_count = out_count;
    }
    return 0;
}

int resnet20_logit(void *handle, int channel)
{
    const Model *model = handle;
    return model->logits[channel];
}
