import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def synthesis_inputs(root, tb_name):
    tb_dir = root / "tb" / tb_name
    manifest = tb_dir / f"{tb_name}.f"
    source = (tb_dir / f"{tb_name}.sv").read_text()
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
    source = re.sub(r"^\s*`(?:ifndef TB_CORE_POST_SYNTHESIS|endif)\s*$", "", source, flags=re.MULTILINE)
    top = "core" if tb_name == "tb_core" else "axi_bottleneck"
    instance = re.search(rf"\b{top}\s*(?:#\s*\((.*?)\))?\s+dut\s*\(", source, re.DOTALL)
    if instance is None:
        raise ValueError(f"Cannot find {top} dut in {tb_name}")
    constants = dict(re.findall(r"localparam\s+int\s+(\w+)\s*=\s*(\d+)\s*;", source))
    generics = []
    for name, value in re.findall(r"\.(\w+)\s*\(([^()]*)\)", instance.group(1) or ""):
        value = constants.get(value.strip(), value.strip())
        if value == "'0":
            value = "0"
        if not re.fullmatch(r"\d+", value):
            raise ValueError(f"Unsupported synthesis parameter {name}={value} in {tb_name}")
        generics.append(f"{name}={value}")
    rtl_dirs = {root / "tb/libs/rtl"}
    if top == "axi_bottleneck":
        rtl_dirs.add(root / "rtl/compute")
    sources = []
    for entry in manifest.read_text().splitlines():
        entry = entry.strip()
        if not entry or entry.startswith(("#", "//")):
            continue
        path = (tb_dir / entry).resolve()
        if path.parent in rtl_dirs:
            if not path.is_file():
                raise ValueError(f"Source not found: {path}")
            sources.append(path)
    if not sources:
        raise ValueError(f"No synthesis sources in {manifest}")
    return top, sources, generics


def main():
    tb_name = sys.argv[1] if len(sys.argv) == 2 else "tb_core"
    if len(sys.argv) > 2 or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", tb_name):
        print("Usage: synthesis.py [testbench]", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parents[1]
    try:
        top, sources, generics = synthesis_inputs(root, tb_name)
    except (OSError, ValueError) as error:
        print(f"[ ERROR ] {error}", file=sys.stderr)
        return 1
    vivado_name = "vivado.bat" if os.name == "nt" else "vivado"
    vivado = shutil.which(vivado_name)
    if not vivado:
        print(f"[ ERROR ] {vivado_name} not found. Add Vivado bin to PATH.", file=sys.stderr)
        return 1

    design_dir = "reference_rtl" if top == "core" else top
    build = root / ".log" / "synth" / tb_name / "zedboard" / design_dir
    build.mkdir(parents=True, exist_ok=True)
    log = build / "synthesis.log"
    env = os.environ.copy()
    env["TB_CORE_SYNTH_ROOT"] = root.as_posix()
    env["TB_SYNTH_TOP"] = top
    env["TB_SYNTH_SOURCES"] = "\n".join(path.as_posix() for path in sources)
    env["TB_SYNTH_GENERICS"] = " ".join(generics)

    print(f"[ INFO ] Synthesizing {top} for {tb_name} on ZedBoard", flush=True)
    try:
        result = subprocess.run(
            [vivado, "-mode", "tcl", "-log", "synthesis.log", "-journal", "synthesis.jou"],
            cwd=build,
            env=env,
            input=f'source {{{root.as_posix()}/fpga/zedboard/synthesis.tcl}}\n',
            text=True,
        )
    except OSError as error:
        print(f"[ ERROR ] Could not start Vivado: {error}", file=sys.stderr)
        return 1

    artifacts = (build / f"{top}.dcp", build / f"{top}_funcsim.v")
    if result.returncode or any(not file.is_file() or not file.stat().st_size for file in artifacts):
        print(f"[ ERROR ] Synthesis failed. See {log}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
