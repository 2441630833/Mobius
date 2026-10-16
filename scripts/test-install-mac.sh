#!/usr/bin/env bash
# Isolated behavioral tests; no real downloads, /Applications writes or processes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
export REAL_CP REAL_MV
REAL_CP=$(command -v cp)
REAL_MV=$(command -v mv)
cat > "$SANDBOX/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -e
case "${0##*/}" in
    defaults)
        [ -f "$2" ] || exit 1
        case "$3" in
            CFBundleIdentifier) cat "$2" ;;
            CFBundleExecutable) echo Mobius ;;
            CFBundleShortVersionString) echo 1.0 ;;
        esac ;;
    curl)
        case "$*" in
            *api.github.com*) printf '{"tag_name": "v2", "url": "https://example.test/Mobius-macOS-arm64.%s"}\n' "$ASSET_TYPE"
                # ZIP uses the other release naming convention.
                [ "$ASSET_TYPE" != zip ] || echo 'https://example.test/Mobius-darwin-arm64.zip' ;;
            *code.icns*) exit 1 ;;
            *) echo download >> "$CALLS"
               [ "$FAILURE" != download ] || exit 22
               while [ "$1" != -o ]; do shift; done
               touch "$2" ;;
        esac ;;
    hdiutil)
        if [ "$1" = attach ]; then
            "$REAL_CP" -R "$PAYLOAD/." "$4/"
        else
            echo detach >> "$CALLS"
        fi ;;
    unzip) mkdir -p "$5"; "$REAL_CP" -R "$PAYLOAD/." "$5/" ;;
    cp)
        [ "$FAILURE" != copy ] || exit 1
        "$REAL_CP" "$@" ;;
    mv)
        if [ "$FAILURE" = swap ] && [[ "$1" == */.mobius-install-*/Mobius.app ]]; then
            exit 1
        fi
        "$REAL_MV" "$@" ;;
    pgrep) exit 1 ;;
    uname) echo arm64 ;;
    lsregister) printf '%s\n' "$*" >> "$CALLS" ;;
    *) : ;;
esac
MOCK
chmod +x "$SANDBOX/bin/mock"
for name in defaults curl hdiutil unzip cp mv pgrep uname lsregister killall xattr codesign osascript sleep; do
    "$REAL_CP" "$SANDBOX/bin/mock" "$SANDBOX/bin/$name"
done

make_app() {
    mkdir -p "$1/Contents/MacOS" "$1/Contents/Resources"
    printf '%s\n' "${2:-com.mobius.ide}" > "$1/Contents/Info.plist"
    printf '#!/bin/sh\nexit 0\n' > "$1/Contents/MacOS/Mobius"
    chmod +x "$1/Contents/MacOS/Mobius"
}

setup_case() {
    CASE_DIR="$SANDBOX/$1"
    mkdir -p "$CASE_DIR/Applications" "$CASE_DIR/home/Applications" "$CASE_DIR/payload"
    export HOME="$CASE_DIR/home" PAYLOAD="$CASE_DIR/payload" CALLS="$CASE_DIR/calls"
    export FAILURE=none ASSET_TYPE=dmg
    touch "$CALLS"
    make_app "$PAYLOAD/Release Mobius.app"
    # Substitute fixed system paths in a private copy, never in the real installer.
    sed -e "s|TARGET_DIR=\"/Applications\"|TARGET_DIR=\"$CASE_DIR/Applications\"|" \
        -e "s|^LSREGISTER=.*|LSREGISTER=\"$SANDBOX/bin/lsregister\"|" \
        "$ROOT/scripts/install-mac.sh" > "$CASE_DIR/install.sh"
    TARGET="$CASE_DIR/Applications/Mobius.app"
    OLD="$CASE_DIR/Applications/Mobius 1.0.app"
    USER_OLD="$HOME/Applications/Mobius.app"
    make_app "$OLD"
    make_app "$USER_OLD"
    make_app "$CASE_DIR/Applications/Other.app" com.example.other
    make_app "$CASE_DIR/Applications/Mobius Preview.app" com.mobius.preview
    ln -s "$CASE_DIR/Applications/Other.app" "$CASE_DIR/Applications/Alias.app"
}

run_installer() {
    PATH="$SANDBOX/bin:$PATH" bash "$CASE_DIR/install.sh" "$@" > "$CASE_DIR/output" 2>&1
}

assert_clean_install() {
    [ -x "$TARGET/Contents/MacOS/Mobius" ]
    [ "$(cat "$TARGET/Contents/.mobius-installed-tag")" = v2 ]
    [ ! -e "$OLD" ] && [ ! -e "$USER_OLD" ]
    [ -d "$CASE_DIR/Applications/Other.app" ]
    [ -d "$CASE_DIR/Applications/Mobius Preview.app" ]
    # Git Bash may emulate symlinks as copies; either representation must survive.
    [ -d "$CASE_DIR/Applications/Alias.app" ]
    grep -q -- '-f ' "$CALLS"
    [ -z "$(find "$CASE_DIR/Applications" -maxdepth 1 -name '.mobius-install-*' -print)" ]
}

for mode in dmg zip; do
    setup_case "update-$mode"
    export ASSET_TYPE="$mode"
    make_app "$TARGET"
    echo old > "$TARGET/old-marker"
    run_installer || { cat "$CASE_DIR/output"; exit 1; }
    assert_clean_install
    [ ! -e "$TARGET/old-marker" ]
    echo "PASS: $mode update removes renamed and per-user copies, preserves other apps"
done

setup_case same-tag
make_app "$TARGET"
echo v2 > "$TARGET/Contents/.mobius-installed-tag"
run_installer
assert_clean_install
! grep -q download "$CALLS"
echo 'PASS: same-tag repairs duplicates without a download'

setup_case check
run_installer --check
[ ! -e "$TARGET" ] && [ -d "$OLD" ] && [ -d "$USER_OLD" ]
[ ! -s "$CALLS" ]
echo 'PASS: --check is read-only'

for failure in download copy swap invalid; do
    setup_case "failure-$failure"
    make_app "$TARGET"
    echo preserved > "$TARGET/old-marker"
    export FAILURE="$failure"
    if [ "$failure" = invalid ]; then
        echo com.example.other > "$PAYLOAD/Release Mobius.app/Contents/Info.plist"
    fi
    if run_installer; then
        echo "FAIL: $failure unexpectedly succeeded"; exit 1
    fi
    [ "$(cat "$TARGET/old-marker")" = preserved ]
    [ -d "$OLD" ] && [ -d "$USER_OLD" ]
    [ -z "$(find "$CASE_DIR/Applications" -maxdepth 1 -name '.mobius-install-*' -print)" ]
    if [ "$failure" != download ]; then grep -q detach "$CALLS"; fi
    echo "PASS: $failure preserves the old installation and duplicates"
done

setup_case foreign-target
make_app "$TARGET" com.example.other
if run_installer; then echo 'FAIL: replaced a foreign app'; exit 1; fi
[ "$(cat "$TARGET/Contents/Info.plist")" = com.example.other ]
[ -d "$OLD" ] && [ -d "$USER_OLD" ]
echo 'PASS: refuses to overwrite a foreign app at the canonical path'

setup_case fresh
run_installer
assert_clean_install
echo 'PASS: fresh canonical install migrates existing noncanonical copies'

setup_case damaged
make_app "$TARGET"
echo v2 > "$TARGET/Contents/.mobius-installed-tag"
rm "$TARGET/Contents/MacOS/Mobius"
run_installer
assert_clean_install
grep -q download "$CALLS"
echo 'PASS: damaged same-tag installation is repaired before duplicate cleanup'
