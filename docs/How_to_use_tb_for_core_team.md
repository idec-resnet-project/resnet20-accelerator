# How to use toy controller TB 

## Setup

```bash
# Clone repository
git clone -b feat/memory-hyunkeon-1.0.0 https://github.com/idec-resnet-project/resnet20-accelerator.git

# Enter project directory
cd resnet20-accelerator

# Run behavioral simulation
./scripts/behav_sim.bat tb_axi_bottleneck --gui --no-wdb
```

## Use Your Own Core RTL

1. Replace the RTL files in `tb/libs/rtl/` with your own implementation.

2. Run the behavioral simulation:

```bash
./scripts/behav_sim.bat tb_axi_bottleneck --gui --no-wdb
```

> [!CAUTION]
> Do not modify the port definitions in `core.sv`.

## PASS criteria

- SNR ~ 54.61 dB

## Appendix

```bash
# Run behavioral simulation
./scripts/behav_sim.bat tb_axi_bottleneck --gui
# without gui
./scripts/behav_sim.bat tb_axi_bottleneck
# without gui, skip complie
./scripts/behav_sim.bat tb_axi_bottleneck --skip-compile

# Run synthesis simulation
./scripts/synthesis_sim.bat tb_axi_bottleneck --gui

```
