"""Generate deterministic input and unquantized float logits for the AXI TB."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "verification" / "resnet20"))
from float_reference import write_fixture

DATA = Path(__file__).with_name("data")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DATA)
    args = parser.parse_args()
    logits = write_fixture(args.data_dir, args.data_dir / "weight.bin")
    print("Float reference logits:", logits)


if __name__ == "__main__":
    main()
