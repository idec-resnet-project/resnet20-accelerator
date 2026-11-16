"""Fold, quantize, and export the published ResNet-20 checkpoint."""

import argparse
import hashlib
import os
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
import torch

from resnet20 import (
    DEFAULT_BIN, Q_FORMAT, QMAX, QMIN, WORD_DTYPE, fold_batch_norm, load_pretrained,
    parameter_layers, round_to_fixed,
)


@torch.inference_mode()
def export(checkpoint, output):
    model = fold_batch_norm(load_pretrained(checkpoint))
    payload = bytearray()
    peak = {"weight": 0.0, "bias": 0.0}
    print(f"{'layer':<25} {'weight byte':>11} {'bias byte':>10} {'weights':>8} {'biases':>7}")
    for name, layer in parameter_layers(model):
        offsets = []
        for kind, values in (("weight", layer.weight), ("bias", layer.bias)):
            offsets.append(len(payload))
            peak[kind] = max(peak[kind], values.abs().max().item())
            # PyTorch stores [Cout, Cin, Kh, Kw], with Kw contiguous in C order.
            words = round_to_fixed(values)
            if not ((words >= QMIN) & (words <= QMAX)).all():
                raise ValueError(f"{name}.{kind} is outside {Q_FORMAT} after rounding")
            payload.extend(np.asarray(words, dtype=WORD_DTYPE, order="C").tobytes())
        print(f"{name:<25} {offsets[0]:>11} {offsets[1]:>10} "
              f"{layer.weight.numel():>8} {layer.bias.numel():>7}")

    # Replace the output only after the complete payload has been written.
    with NamedTemporaryFile(dir=output.parent, delete=False) as stream:
        temporary = Path(stream.name)
    try:
        temporary.write_bytes(payload)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Peak magnitudes: weight={peak['weight']:.6f}, bias={peak['bias']:.6f}")
    print(f"{output}: {len(payload)} bytes, SHA-256 {hashlib.sha256(payload).hexdigest()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, help="Local copy of the published checkpoint")
    parser.add_argument("--output", type=Path, default=DEFAULT_BIN)
    args = parser.parse_args()
    export(args.checkpoint, args.output)


if __name__ == "__main__":
    main()
