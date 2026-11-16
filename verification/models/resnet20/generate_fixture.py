"""Generate full-model data explicitly for a selected output directory."""
import argparse
from pathlib import Path
from float_reference import write_fixture

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--weights", type=Path, default=Path(__file__).with_name("weight.bin"))
    args = parser.parse_args()
    print("Float reference logits:", write_fixture(args.out, args.weights))
