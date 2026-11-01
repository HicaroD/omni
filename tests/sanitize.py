"""Instrument Telia's generated C and bundled runtime through its C compiler."""
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, env):
    subprocess.run(args, cwd=ROOT, env=env, check=True, timeout=120)


with tempfile.TemporaryDirectory(prefix="omni-sanitize-") as temp:
    work = Path(temp)
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
    # Telia discovers cc/gcc/clang on PATH. Wrap them only for these builds,
    # keeping instrumentation independent of application native dependencies.
    native_cc = shutil.which("cc")
    if native_cc is None:
        raise SystemExit("A C compiler is required.")
    for name in ("cc", "gcc", "clang"):
        wrapper = work / name
        wrapper.write_text(f'#!/bin/sh\nexec {shlex.quote(native_cc)} {shlex.join(flags)} "$@"\n')
        wrapper.chmod(0o755)
    env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ["PATH"], UBSAN_OPTIONS="halt_on_error=1")
    compiler = os.environ.get("TELIA", "telia")
    run(compiler, "build", str(ROOT), "-o", str(work / "omni"), env=env)
    run(compiler, "test", "--color=never", env=env)
    run("python3", str(ROOT / "tests" / "terminal.py"), env=dict(env, OMNI_BINARY=str(work / "omni")))
