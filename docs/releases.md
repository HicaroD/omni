# Publishing Omni releases

The `Release` workflow builds Apple Silicon binaries using Telia v0.3.0 on
`macos-14`, targeting macOS 14 or later. It runs native and terminal tests,
checks that the binary links only to macOS system libraries, ad-hoc signs it,
and tests the packaged executable outside the checkout. No Telia runtime
installation is needed by users. These binaries are not notarized by Apple.

The workflow publishes only after all checks pass. Compiler or test failures
block publication; fix them before shipping. Installer tests also run on
relevant pushes and pull requests and can be run locally with `make test-install`.

Current release blocker: local `make unit` and `make test-release` with the
published Telia v0.3.0 compiler fail during C compilation with undeclared
`_telia_runtime_kind_*` identifiers (including `InvalidPath` and
`FileOpenFailed`). Resolve this build failure before tagging the first release.
The standalone binary and minimum macOS version cannot be fully verified until
the release build passes.

## Create a release

1. Ensure the intended commit is pushed to `master` and tests pass.
2. Choose a new version, such as `v0.1.0` or `v0.1.0-rc.1`.
3. Tag that commit and push the tag:

   ```sh
   git tag v0.1.0 COMMIT_SHA
   git push origin v0.1.0
   ```

4. Check the **Release** workflow in GitHub Actions. It publishes:
   - `omni-v0.1.0-darwin-arm64.tar.gz` (contains only `omni`)
   - `checksums.txt`
   - `install.sh`

Versions with a suffix are prereleases and are not selected by the installer's
default latest-stable lookup. Set `OMNI_VERSION` to install one explicitly.
Existing published versions are not overwritten.

The repository must be public for the anonymous one-line installer to work.
A pushed installer alone is not enough: publish a stable release before
advertising the command as ready to use.

## Manual installation

Download the archive and `checksums.txt` from the same GitHub release, then run:

```sh
shasum -a 256 -c checksums.txt
tar -xzf omni-v0.1.0-darwin-arm64.tar.gz omni
mkdir -p "$HOME/.local/bin"
install -m 755 omni "$HOME/.local/bin/omni"
```

Checksums detect corrupted downloads; they are not independent signatures.
The installer trusts the script and assets served by this GitHub repository.
