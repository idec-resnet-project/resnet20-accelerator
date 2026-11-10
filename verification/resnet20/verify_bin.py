"""Compare the exported ResNet-20 against the original on CIFAR-10 test images."""

import argparse
import copy
from io import BytesIO
import math
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from resnet20 import (
    DEFAULT_BIN, Q_FORMAT, QMAX, QMIN, SCALE, WORD_DTYPE, ResidualAdd, checked_asset,
    fold_batch_norm, load_pretrained, parameter_layers, round_to_fixed,
)


TEST_URL = (
    "https://huggingface.co/datasets/uoft-cs/cifar10/resolve/main/plain_text/"
    "test-00000-of-00001.parquet"
)
TEST_SHA256 = "841389e6f2d64f28bf17310e430aebac20ec3ba611a3c5e231dc93c645ce84de"
MEAN = (0.4914, 0.4822, 0.4465)
STD = (0.2023, 0.1994, 0.2010)


def read_binary(path, model):
    layers = list(parameter_layers(model))
    words_per_file = sum(layer.weight.numel() + layer.bias.numel() for _, layer in layers)
    payload = path.read_bytes()
    expected = words_per_file * WORD_DTYPE.itemsize
    if len(payload) != expected:
        raise ValueError(f"{path}: expected {expected} bytes, found {len(payload)}")
    words = np.frombuffer(payload, dtype=WORD_DTYPE).astype(np.int64)
    offset = 0
    result = {}
    for name, layer in layers:
        bias_offset = offset + layer.weight.numel()
        end = bias_offset + layer.bias.numel()
        weight = torch.from_numpy(words[offset:bias_offset]).reshape(layer.weight.shape)
        bias = torch.from_numpy(words[bias_offset:end])
        result[name] = (weight, bias)
        offset = end
    return result


def requantize(acc, divisor):
    """Signed nearest division with ties away from zero and int16 saturation."""
    magnitude = (acc.abs() + divisor // 2) // divisor
    return (magnitude * acc.sign()).clamp(QMIN, QMAX)


class FixedAffine(nn.Module):
    def __init__(self, layer, weight, bias):
        super().__init__()
        self.weight = weight.to(torch.float64)
        self.bias = bias.to(torch.float64) * SCALE
        self.conv = isinstance(layer, nn.Conv2d)
        if self.conv:
            self.stride = layer.stride
            self.padding = layer.padding

    def forward(self, x):
        # These are integer MACs evaluated in float64 for speed. Each partial
        # sum is bounded by 576 * 32768**2 + 32768 * SCALE, well below 2**53.
        x = x.to(torch.float64)
        if self.conv:
            acc = F.conv2d(x, self.weight, self.bias, self.stride, self.padding)
        else:
            acc = F.linear(x, self.weight, self.bias)
        return requantize(acc.to(torch.int64), SCALE)


class FixedResidualAdd(ResidualAdd):
    def forward(self, main, shortcut):
        return super().forward(main, shortcut).clamp(QMIN, QMAX)


class FixedAverage(nn.Module):
    def forward(self, x):
        area = x.shape[-2] * x.shape[-1]
        return requantize(x.sum(dim=(-2, -1), keepdim=True), area)


def binary_models(folded, tensors):
    weights_only = copy.deepcopy(folded)
    for name, layer in parameter_layers(weights_only):
        weight, bias = tensors[name]
        layer.weight.copy_(weight / SCALE)
        layer.bias.copy_(bias / SCALE)

    fixed = copy.deepcopy(folded)
    for name, layer in list(parameter_layers(fixed)):
        fixed.set_submodule(name, FixedAffine(layer, *tensors[name]))
    for name, layer in list(fixed.named_modules()):
        if isinstance(layer, ResidualAdd):
            fixed.set_submodule(name, FixedResidualAdd())
    fixed.avgpool = FixedAverage()
    return weights_only, fixed


def test_batches(path, count, batch_size):
    import pyarrow.parquet as parquet
    from PIL import Image

    dataset = parquet.ParquetFile(path)
    if not 1 <= count <= dataset.metadata.num_rows:
        raise ValueError(f"Image count must be in 1..{dataset.metadata.num_rows}")
    mean = torch.tensor(MEAN).view(1, 3, 1, 1)
    std = torch.tensor(STD).view(1, 3, 1, 1)
    for batch in dataset.iter_batches(batch_size=batch_size, columns=["img", "label"]):
        images, labels = [], []
        for row in batch.slice(0, count).to_pylist():
            with Image.open(BytesIO(row["img"]["bytes"])) as image:
                images.append(np.asarray(image.convert("RGB")))
            labels.append(row["label"])
        pixels = torch.from_numpy(np.stack(images)).permute(0, 3, 1, 2).float() / 255
        yield (pixels - mean) / std, torch.tensor(labels)
        count -= len(labels)
        if count == 0:
            break


class Comparison:
    def __init__(self):
        self.noise = 0.0
        self.correct = 0
        self.agreement = 0

    def update(self, logits, reference, labels):
        self.noise += (logits.to(torch.float64) - reference).square().sum().item()
        predicted = logits.argmax(dim=1)
        self.correct += (predicted == labels).sum().item()
        self.agreement += (predicted == reference.argmax(dim=1)).sum().item()

    def snr(self, signal):
        return math.inf if self.noise == 0 else 10 * math.log10(signal / self.noise)


@torch.inference_mode()
def verify(args):
    original = load_pretrained(args.checkpoint)
    folded = fold_batch_norm(original)
    weights_only, fixed = binary_models(folded, read_binary(args.bin, folded))
    dataset = checked_asset(args.test_parquet, TEST_URL, TEST_SHA256)
    results = {name: Comparison() for name in (
        "folded FP32", f"{Q_FORMAT} weights/biases", f"{Q_FORMAT} full inference",
    )}
    signal = 0.0
    correct = 0
    for inputs, labels in test_batches(dataset, args.samples, args.batch_size):
        reference = original(inputs)
        signal += reference.to(torch.float64).square().sum().item()
        correct += (reference.argmax(dim=1) == labels).sum().item()
        quantized_input = round_to_fixed(inputs).clamp(QMIN, QMAX).to(torch.int64)
        outputs = (folded(inputs), weights_only(inputs), fixed(quantized_input) / SCALE)
        for result, logits in zip(results.values(), outputs):
            result.update(logits, reference, labels)

    print(f"CIFAR-10 test images: {args.samples}")
    print(f"Original FP32 top-1: {correct / args.samples:.2%}")
    print(f"{'Model':<23} {'Logit SNR':>12} {'Top-1':>9} {'FP32 agreement':>15}")
    for name, result in results.items():
        print(f"{name:<23} {result.snr(signal):>9.2f} dB "
              f"{result.correct / args.samples:>9.2%} {result.agreement / args.samples:>15.2%}")
    if not results["folded FP32"].snr(signal) >= 90:
        raise SystemExit("FAIL: BN folding check is below 90 dB")
    if not all(result.snr(signal) >= args.min_snr for result in list(results.values())[1:]):
        raise SystemExit(f"FAIL: binary logit SNR is below {args.min_snr:g} dB")
    print(f"PASS: both binary inference modes reached {args.min_snr:g} dB")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, help="Local copy of the published checkpoint")
    parser.add_argument("--bin", type=Path, default=DEFAULT_BIN)
    parser.add_argument("--test-parquet", type=Path, help="Local copy of the CIFAR-10 test parquet")
    parser.add_argument("--samples", type=int, default=1024)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--min-snr", type=float, default=30.0)
    args = parser.parse_args()
    if min(args.samples, args.batch_size, args.threads) < 1 or not math.isfinite(args.min_snr):
        parser.error("Counts must be positive and the SNR threshold must be finite")
    torch.set_num_threads(args.threads)
    verify(args)


if __name__ == "__main__":
    main()
