"""Generate the ResNet-20 core command manifest and float reference."""
import argparse
import re
import sys
from pathlib import Path

RESNET = Path(__file__).resolve().parents[2] / "resnet20"
sys.path.insert(0, str(RESNET))
from float_reference import write_fixture


def read_program():
    source = (RESNET / "resnet20.c").read_text(encoding="utf-8")
    table = source.split("const instruction_t resnet20_instruction_set[] = {", 1)[1].split("};", 1)[0]
    entries = re.findall(r"\{([A-Z_]+),\s*([\d, ]+)\}", table)
    opcodes = {"INPUT": 1, "SKIP": 128, "SKIP_CONV": 192, "CONV_RELU": 80,
               "CONV_RESIDUAL_RELU": 112, "CONV_RESIDUAL_RELU_GAP": 116, "FC_OUT": 66}
    names = ["input", "stem"]
    for stage in range(1, 4):
        for block in range(3):
            prefix = f"layer{stage}.{block}"
            names.extend((prefix + (".projection" if stage > 1 and block == 0 else ".skip"),
                          prefix + ".conv1", prefix + ".conv2"))
    names.append("fc")
    return [(name, opcodes[op], *map(int, values.split(",")))
            for name, (op, values) in zip(names, entries, strict=True)]


def generate(out, weights_path):
    logits = write_fixture(out, weights_path)
    manifest = []
    offset = 0
    for row in read_program():
        _, _, _, _, cin, cout, size, _, _ = row
        manifest.append(" ".join(map(str, (*row, offset))))
        offset += cin * cout * size * size + cout
    if offset * 2 != weights_path.stat().st_size:
        raise ValueError(f"Command table consumes {offset * 2} bytes")
    (out / "layers.txt").write_text("\n".join(manifest) + "\n", encoding="ascii", newline="\n")
    print("Float reference logits:", logits)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--weights", default=RESNET / "weight.bin", type=Path)
    args = parser.parse_args()
    generate(args.out, args.weights)


if __name__ == "__main__":
    main()
