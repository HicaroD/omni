#!/bin/sh
# Install a prebuilt Omni release. No compiler or administrator privileges needed.
set -eu

fail() {
    printf 'omni: %s\n' "$*" >&2
    exit 1
}

download() {
    curl --fail --silent --show-error --location --retry 3 \
        --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' "$@"
}

main() {
    [ "$(uname -s)" = Darwin ] || fail 'Only macOS is supported.'
    [ "$(uname -m)" = arm64 ] || fail 'Only native Apple Silicon (arm64) shells are supported. If using Rosetta, open a native terminal.'
    os_version=$(sw_vers -productVersion)
    [ "${os_version%%.*}" -ge 14 ] || fail 'macOS 14 or later is required.'

    for tool in curl tar shasum mktemp install; do
        command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool"
    done
    bin_dir=${OMNI_BIN_DIR:-"$HOME/.local/bin"}
    case "$bin_dir" in
        /*) ;;
        *) fail 'OMNI_BIN_DIR must be an absolute path.' ;;
    esac

    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/omni-install.XXXXXX")
    staged=''
    trap 'rm -rf "$work_dir"; if [ -n "$staged" ]; then rm -f "$staged"; fi' EXIT
    trap 'exit 1' HUP INT TERM

    releases=https://github.com/HicaroD/omni/releases
    version=${OMNI_VERSION:-}
    if [ -z "$version" ]; then
        # Follow GitHub's latest-stable redirect without parsing API JSON.
        latest=$(download --output /dev/null --write-out '%{url_effective}' "$releases/latest") ||
            fail 'Could not resolve the latest release. Check connectivity and whether a public release exists.'
        version=${latest##*/}
    fi
    printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$' ||
        fail 'Expected a version such as v0.1.0 or v0.1.0-rc.1.'

    archive="omni-$version-darwin-arm64.tar.gz"
    base="$releases/download/$version"
    printf 'Downloading Omni %s...\n' "$version"
    download --output "$work_dir/$archive" "$base/$archive" || fail 'Could not download the release archive.'
    download --output "$work_dir/checksums.txt" "$base/checksums.txt" || fail 'Could not download release checksums.'
    expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$work_dir/checksums.txt")
    [ "${#expected}" -eq 64 ] || fail 'Missing or invalid release checksum.'
    case "$expected" in *[!0-9a-f]*) fail 'Invalid release checksum.' ;; esac
    actual=$(shasum -a 256 "$work_dir/$archive")
    [ "${actual%% *}" = "$expected" ] || fail 'Checksum mismatch; existing installation was not changed.'

    # Only extract the single expected member, never arbitrary archive paths.
    tar -xzf "$work_dir/$archive" -C "$work_dir" omni || fail 'Could not extract the release binary.'
    [ -f "$work_dir/omni" ] && [ ! -L "$work_dir/omni" ] || fail 'Archive does not contain a regular omni binary.'
    mkdir -p "$bin_dir"
    [ ! -d "$bin_dir/omni" ] || fail "$bin_dir/omni is a directory."
    staged=$(mktemp "$bin_dir/.omni.XXXXXX")
    install -m 755 "$work_dir/omni" "$staged"
    mv -f "$staged" "$bin_dir/omni"
    staged=''

    printf 'Installed Omni %s to %s/omni\n' "$version" "$bin_dir"
    case ":$PATH:" in
        *:"$bin_dir":*) ;;
        *) printf 'Add this directory to PATH in your shell configuration: %s\n' "$bin_dir" ;;
    esac
    if ! command -v rg >/dev/null 2>&1; then
        printf 'Project search requires ripgrep. With Homebrew: brew install ripgrep\n'
    fi
}

# Keep execution behind a complete function definition for curl | sh use.
main "$@"
