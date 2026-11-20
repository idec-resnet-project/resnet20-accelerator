# How to use toy controller TB 

## Setup

```bash
# Clone repository
git clone -b feat/memory-hyunkeon-1.0.0 https://github.com/idec-resnet-project/resnet20-accelerator.git

# Enter project directory
cd resnet20-accelerator

# Run behavioral simulation
./scripts/behav_sim.bat tb_axi_bottleneck_stepbystep --gui
```

## Use Your Own Core RTL

1. Replace the RTL files in `rtl/compute` with your own implementation.

2. Run the behavioral simulation:

```bash
./scripts/behav_sim.bat tb_axi_bottleneck_stepbystep --gui
```

> [!CAUTION]
> Do not modify the port definitions in `rtl/compute/axi_bottleneck.sv`.

## PASS criteria

- SNR >  50 dB or inf

## Appendix

```bash
# Run behavioral simulation
./scripts/behav_sim.bat tb_axi_bottleneck_conv1x1 --gui
# without gui
./scripts/behav_sim.bat tb_axi_bottleneck_conv1x1
# without gui, skip complie
./scripts/behav_sim.bat tb_axi_bottleneck_conv1x1 --skip-compile

# Run synthesis simulation
./scripts/synthesis_sim.bat tb_axi_bottleneck_conv1x1 --gui

```