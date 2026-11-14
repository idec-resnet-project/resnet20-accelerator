"""Generate the input and float logits for the final ResNet-20 block and FC."""

import argparse
import math
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "verification" / "resnet20"))

from float_reference import SCALE, WeightReader, block, conv, fixture_input, relu

WEIGHT_OFFSET_BYTES = 394_368


def quantize(value):
    scaled = value * SCALE
    rounded = math.floor(scaled + 0.5) if scaled >= 0 else math.ceil(scaled - 0.5)
    return max(-32768, min(32767, rounded))


def write_fixture(output):
    weight_path = (REPO / "tb" / "tb_axi_bottleneck" / "resnet20" / "data" / "weight.bin")
    weights = WeightReader(weight_path)
    feature = fixture_input()
    channels = [[word / SCALE for word in feature[c::3]] for c in range(3)]
    tensor = relu(conv((channels, 32, 32), weights, 16))

    for out_channels, block_count in ((16, 3), (32, 3), (64, 2)):
        for index in range(block_count):
            stride = 2 if out_channels != 16 and index == 0 else 1
            tensor = block(tensor, weights, out_channels, stride)

    planes, height, width = tensor
    if (height, width, len(planes)) != (8, 8, 64) or weights.offset * 2 != WEIGHT_OFFSET_BYTES:
        raise ValueError("Unexpected final-block input shape or weight offset")

    fixed_planes = [[quantize(value) for value in plane] for plane in planes]
    stream = [plane[pixel] for pixel in range(height * width) for plane in fixed_planes]
    quantized = [[word / SCALE for word in plane] for plane in fixed_planes]
    final_planes, _, _ = block((quantized, height, width), weights, 64, 1)
    pooled = [sum(plane) / len(plane) for plane in final_planes]
    kernels, biases = weights.affine(64, 10, 1)
    if weights.offset != len(weights.words):
        raise ValueError("Unused weight words")
    logits = [sum(weight * value for weight, value in zip(kernel, pooled)) + bias
              for kernel, bias in zip(kernels, biases)]

    output.mkdir(parents=True, exist_ok=True)
    (output / "input_q5_10.hex").write_text(
        "".join(f"{word & 0xffff:04x}\n" for word in stream), encoding="ascii", newline="\n"
    )
    (output / "reference_logits_float.txt").write_text(
        "".join(f"{value:.17g}\n" for value in logits), encoding="ascii", newline="\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    write_fixture(parser.parse_args().out)
