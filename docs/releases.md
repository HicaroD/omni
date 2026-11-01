# Publishing Omni releases

The `Release` workflow builds with Telia v0.3.2 on `macos-15` for Apple Silicon
and macOS 14+. It tests the editor, installer, and standalone package, checks
system-only linking, and ad-hoc signs the binary. Publication requires all checks
to pass. Binaries need no Telia installation and are not notarized by Apple.

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
