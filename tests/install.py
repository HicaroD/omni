"""Exercise the real shell installer with local release fixtures and no network."""
import hashlib
import io
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import tempfile
import unittest


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omni installer ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.tools = self.root / "tools"
        self.downloads = self.root / "downloads"
        self.tmp = self.root / "tmp"
        for path in (self.home, self.tools, self.downloads, self.tmp):
            path.mkdir()
        self.env = {
            **{k: v for k, v in os.environ.items() if not k.startswith("OMNI_")},
            "HOME": str(self.home),
            "PATH": f"{self.tools}:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(self.tmp),
            "FIXTURES": str(self.downloads),
            "DOWNLOAD_LOG": str(self.root / "requests"),
        }
        self.script("uname", 'case "$1" in -s) echo "${TEST_OS:-Darwin}";; -m) echo "${TEST_ARCH:-arm64}";; esac')
        self.script("sw_vers", 'echo "${TEST_MACOS:-14.0}"')
        self.script("curl", f"exec {shlex.quote(sys.executable)} {shlex.quote(str(self.root / 'curl.py'))} \"$@\"")
        (self.root / "curl.py").write_text('''import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
url = args[-1]
with open(os.environ["DOWNLOAD_LOG"], "a") as log:
    log.write(url + "\\n")
if os.environ.get("TEST_FAIL_DOWNLOAD") in ("all", url.rsplit("/", 1)[-1]):
    sys.exit(22)
if url.endswith("/latest"):
    print("https://github.com/HicaroD/omni/releases/tag/" + os.environ.get("TEST_LATEST", "v0.1.0"), end="")
else:
    source = Path(os.environ["FIXTURES"]) / url.rsplit("/", 1)[-1]
    if not source.is_file():
        sys.exit(22)
    shutil.copyfile(source, args[args.index("--output") + 1])
''')
        self.release()

    def script(self, name, body):
        path = self.tools / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def release(self, version="v0.1.0", payload=b"#!/bin/sh\necho omni\n", member="omni", symlink=False):
        archive = self.downloads / f"omni-{version}-darwin-arm64.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            info = tarfile.TarInfo(member)
            info.mode = 0o755
            if symlink:
                info.type = tarfile.SYMTYPE
                info.linkname = "/bin/sh"
                tar.addfile(info)
            else:
                info.size = len(payload)
                tar.addfile(info, io.BytesIO(payload))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.downloads / "checksums.txt").write_text(f"{digest}  {archive.name}\n")

    @property
    def binary(self):
        return self.home / ".local/bin/omni"

    def run_installer(self, success=True, piped=False, **env):
        result = subprocess.run(
            ["/bin/sh"] if piped else ["/bin/sh", str(INSTALLER)],
            input=INSTALLER.read_text() if piped else None,
            env={**self.env, **env}, text=True, capture_output=True, timeout=10,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(list(self.tmp.iterdir()), [], "temporary downloads were not cleaned up")
        if self.binary.parent.exists():
            self.assertEqual(list(self.binary.parent.glob(".omni.*")), [])
        return result

    def seed_existing_binary(self):
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("previous installation")

    def test_latest_install_from_stdin(self):
        result = self.run_installer(piped=True)
        self.assertEqual(self.binary.read_bytes(), b"#!/bin/sh\necho omni\n")
        self.assertEqual(self.binary.stat().st_mode & 0o777, 0o755)
        self.assertIn("Add this directory to PATH", result.stdout)
        self.assertIn("brew install ripgrep", result.stdout)
        self.assertIn("/releases/latest", (self.root / "requests").read_text())

    def test_pinned_version_skips_latest(self):
        self.run_installer(OMNI_VERSION="v0.1.0")
        self.assertNotIn("/latest", (self.root / "requests").read_text())

    def test_pinned_prerelease(self):
        self.release("v0.2.0-rc.1")
        self.run_installer(OMNI_VERSION="v0.2.0-rc.1")

    def test_upgrade_and_reinstall(self):
        self.run_installer()
        self.release("v0.2.0", b"new binary")
        self.run_installer(OMNI_VERSION="v0.2.0")
        self.run_installer(OMNI_VERSION="v0.2.0")
        self.assertEqual(self.binary.read_bytes(), b"new binary")

    def test_custom_directory_with_spaces(self):
        target = self.home / "my tools/bin"
        result = self.run_installer(OMNI_BIN_DIR=str(target), PATH=f"{self.env['PATH']}:{target}")
        self.assertTrue((target / "omni").is_file())
        self.assertNotIn("Add this directory to PATH", result.stdout)

    def test_existing_ripgrep(self):
        self.script("rg", "exit 0")
        result = self.run_installer()
        self.assertNotIn("brew install ripgrep", result.stdout)

    def test_reject_unsupported_platforms(self):
        for env in ({"TEST_OS": "Linux"}, {"TEST_ARCH": "x86_64"}, {"TEST_MACOS": "13.7"}):
            with self.subTest(env=env):
                self.run_installer(success=False, **env)
        self.assertFalse((self.root / "requests").exists())

    def test_reject_relative_directory(self):
        self.run_installer(success=False, OMNI_BIN_DIR="relative/bin")
        self.assertFalse(self.binary.exists())

    def test_reject_invalid_versions(self):
        for version in ("latest", "v1", "../v0.1.0", "v0.1.0/extra", "v0.1.0;echo bad"):
            with self.subTest(version=version):
                self.run_installer(success=False, OMNI_VERSION=version)
        self.assertFalse((self.root / "requests").exists())

    def test_failed_latest_lookup(self):
        self.run_installer(success=False, TEST_FAIL_DOWNLOAD="all")
        self.assertFalse(self.binary.exists())

    def test_invalid_latest_redirect(self):
        self.run_installer(success=False, TEST_LATEST="latest")
        self.assertFalse(self.binary.exists())

    def test_failed_download_keeps_existing_binary(self):
        self.seed_existing_binary()
        for name in ("omni-v0.1.0-darwin-arm64.tar.gz", "checksums.txt"):
            with self.subTest(name=name):
                self.run_installer(success=False, TEST_FAIL_DOWNLOAD=name)
                self.assertEqual(self.binary.read_text(), "previous installation")

    def test_corruption_keeps_existing_binary(self):
        self.seed_existing_binary()
        archive = self.downloads / "omni-v0.1.0-darwin-arm64.tar.gz"
        archive.write_bytes(archive.read_bytes() + b"corrupt")
        result = self.run_installer(success=False)
        self.assertIn("Checksum mismatch", result.stderr)
        self.assertEqual(self.binary.read_text(), "previous installation")

    def test_missing_invalid_or_duplicate_checksum(self):
        checksums = self.downloads / "checksums.txt"
        valid = checksums.read_text()
        for content in ("", "bad  omni-v0.1.0-darwin-arm64.tar.gz\n", valid + valid,
                        f"{'z' * 64}  omni-v0.1.0-darwin-arm64.tar.gz\n"):
            with self.subTest(content=content):
                checksums.write_text(content)
                self.run_installer(success=False)
                self.assertFalse(self.binary.exists())

    def test_missing_member_keeps_existing_binary(self):
        self.seed_existing_binary()
        self.release(member="not-omni")
        self.run_installer(success=False)
        self.assertEqual(self.binary.read_text(), "previous installation")

    def test_symlink_member_is_rejected(self):
        self.release(symlink=True)
        self.run_installer(success=False)
        self.assertFalse(self.binary.exists())

    def test_target_directory_is_not_overwritten(self):
        self.binary.mkdir(parents=True)
        self.run_installer(success=False)
        self.assertTrue(self.binary.is_dir())

    def test_install_failure_keeps_existing_binary(self):
        self.seed_existing_binary()
        self.script("install", "exit 1")
        self.run_installer(success=False)
        self.assertEqual(self.binary.read_text(), "previous installation")

    def test_existing_symlink_is_replaced_not_followed(self):
        other = self.home / "other"
        other.write_text("do not change")
        self.binary.parent.mkdir(parents=True)
        self.binary.symlink_to(other)
        self.run_installer()
        self.assertFalse(self.binary.is_symlink())
        self.assertEqual(other.read_text(), "do not change")


if __name__ == "__main__":
    unittest.main()
