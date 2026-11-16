"""Generate deterministic Q5.10 input, weights, and float logits for toy."""

import argparse
import struct
from pathlib import Path

SCALE = 1024
INPUT_SIZE = 8
INPUT_CHANNELS = 3
BLOCK_CHANNELS = 4
DEFAULT_OUTPUT = Path(__file__).resolve().parents[3] / "tb/libs/models/toy/data"


def samples():
    state = 20
    while True:
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        yield state >> 16


def affine_words(source, cin, cout, kernel_size, biases=None):
    kernels = [(next(source) % 5 - 2) * (SCALE // 8)
               for _ in range(cout * cin * kernel_size ** 2)]
    if biases is None:
        biases = [(next(source) % 5 - 2) * (SCALE // 8) for _ in range(cout)]
    return kernels, biases


def convolve(feature, layer, kernel_size, stride, padding):
    kernels, biases = ([word / SCALE for word in words] for words in layer)
    size = len(feature)
    cin = len(feature[0][0])
    out_size = (size + 2 * padding - kernel_size) // stride + 1
    output = []
    for y in range(out_size):
        row = []
        for x in range(out_size):
            pixel = []
            for oc, bias in enumerate(biases):
                value = bias
                for ic in range(cin):
                    for ky in range(kernel_size):
                        iy = y * stride + ky - padding
                        for kx in range(kernel_size):
                            ix = x * stride + kx - padding
                            if 0 <= iy < size and 0 <= ix < size:
                                tap = ((oc * cin + ic) * kernel_size + ky) * kernel_size + kx
                                value += feature[iy][ix][ic] * kernels[tap]
                pixel.append(value)
            row.append(pixel)
        output.append(row)
    return output


def reference_logits(input_words, layers):
    values = iter(word / SCALE for word in input_words)
    feature = [[[next(values) for _ in range(INPUT_CHANNELS)] for _ in range(INPUT_SIZE)]
               for _ in range(INPUT_SIZE)]
    skip_layer, first_layer, second_layer, fc_layer = layers
    shortcut = convolve(feature, skip_layer, kernel_size=1, stride=2, padding=0)
    first = convolve(feature, first_layer, kernel_size=3, stride=2, padding=1)
    activated = [[[max(0.0, value) for value in pixel] for pixel in row] for row in first]
    second = convolve(activated, second_layer, kernel_size=3, stride=1, padding=1)
    size = len(second)
    pooled = [sum(max(0.0, second[y][x][c] + shortcut[y][x][c])
                  for y in range(size) for x in range(size)) / (size ** 2)
              for c in range(BLOCK_CHANNELS)]
    return convolve([[pooled]], fc_layer, kernel_size=1, stride=1, padding=0)[0][0]


def write_fixture(output):
    source = samples()
    input_words = [(next(source) % 25 - 12) * (SCALE // 16)
                   for _ in range(INPUT_SIZE ** 2 * INPUT_CHANNELS)]
    layers = (
        affine_words(source, INPUT_CHANNELS, BLOCK_CHANNELS, 1),
        affine_words(source, INPUT_CHANNELS, BLOCK_CHANNELS, 3),
        affine_words(source, BLOCK_CHANNELS, BLOCK_CHANNELS, 3),
        affine_words(source, BLOCK_CHANNELS, 3, 1, biases=[768, -640, 512]),
    )
    weights = [word for layer in layers for stream in layer for word in stream]
    logits = reference_logits(input_words, layers)

    output.mkdir(parents=True, exist_ok=True)
    (output / "input_q5_10.hex").write_bytes(
        "".join(f"{word & 0xFFFF:04x}\n" for word in input_words).encode("ascii"))
    (output / "weight.bin").write_bytes(struct.pack(f"<{len(weights)}h", *weights))
    (output / "reference_logits_float.txt").write_bytes(
        "".join(f"{value:.17g}\n" for value in logits).encode("ascii"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    write_fixture(parser.parse_args().out)
