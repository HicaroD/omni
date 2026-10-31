"""Instrument generated Telia C and the native adapter without changing Telia."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, env):
    subprocess.run(args, cwd=ROOT, env=env, check=True, timeout=120)


with tempfile.TemporaryDirectory(prefix="omni-sanitize-") as temp:
    work = Path(temp)
    package = work / "vendor" / "platform"
    shutil.copytree(ROOT / "vendor" / "platform", package)
    manifest = json.loads((package / "native.json").read_text())
    sanitizers = os.environ.get("OMNI_SANITIZERS", "undefined")
    flags = [f"-fsanitize={sanitizers}", "-fno-omit-frame-pointer"]
    print(f"Checking sanitizer runtime: {sanitizers}", flush=True)
    probe = work / "probe.c"
    probe.write_text("int main(void) { return 0; }\n")
    subprocess.run(["cc", *flags, str(probe), "-o", str(work / "probe")], check=True, timeout=30)
    try:
        subprocess.run([str(work / "probe")], check=True, timeout=5)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"The {sanitizers} runtime hangs on this host; no sanitizer tests were run.")
    for target in manifest["targets"].values():
        target["compile_flags"] = flags
        target["link_flags"] = flags
    (package / "native.json").write_text(json.dumps(manifest))
    env = dict(os.environ, T_VENDOR_PATH=str(work / "vendor"), UBSAN_OPTIONS="halt_on_error=1")
    compiler = os.environ.get("TELIA", "telia")
    run(compiler, "build", str(ROOT), "-o", str(work / "omni"), env=env)
    run(compiler, "test", "--color=never", env=env)
    run("python3", str(ROOT / "tests" / "terminal.py"), env=dict(env, OMNI_BINARY=str(work / "omni")))
