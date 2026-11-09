# ResNet-20 Accelerator on FPGA

### 회로 디자인
- verification/[reference_rtl](verification/reference_rtl)/*.v
    - 구현 예정인 각 모듈 (완성된 디지털 회로 아님)
    - single MAC 구조
    - mac(conv, fc), relu, pooling등을 수행함.

### Testbench 구성
- tb/tb_core/[tb_core.v](tb/tb_core/tb_core.v)
    - rtl_dummy들을 연결하고, tb 수행

### 참고

```text
- zynq proccessor
    └ ResNet.c
   ↕
- AXI-interconnet
   ↕
- DMA
   ↕
- axi_bottleneck.v              : axi interface 컨트롤
    └ top_bottleneck.v
        └ BRAM_buffer.v         : 버퍼 저장소
        └ bottleneck.v          : 메인 모듈
            ┠ controller.v      : 컨트롤러 (tb의 일부 동작 수행)
            └ core.v            : 연산 수행 모듈 (tb 대상)
                └ mac.v         : dummy rtl 영역
                └ relu.v
                └ ...
```

# How to run Behavioral simulation

- in Linux jump to step 3

1. open git bash
2. bash setup (if you need)

    ```bash
    export PATH="/c/{vivado path}/bin:$PATH"
    ```

3. download

    ```bash
    git clone https://github.com/idec-resnet-project/resnet20-accelerator.git
    cd resnet20-accelerator
    ```

4. run

    ```bash
    # without Vivado GUI
    bash scripts/behav_sim.sh tb_core

    # with Vivado GUI
    bash scripts/behav_sim.sh tb_core --gui
    ```

# Appendix

- [TB bottleneck structure & flow](docs/bottleneck_flow.md)
- [input model & data arrange rules](docs/appendix.md)