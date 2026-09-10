set shell := ["zsh", "-uo", "pipefail", "-c"]
set unstable := true

default:
    @just --list
    @echo ''
    @echo "branch: $(git branch --show-current 2>/dev/null || echo 'n/a')"

sim := "iPhone 17 Pro Max"
phone := "Pocketline Swing"
project := "-project Deckhand.xcodeproj -scheme Deckhand"

[group('setup')]
install:
    swift package resolve
    uv sync --all-groups --directory daemon
    @command -v swiftlint >/dev/null 2>&1 || echo 'warn: swiftlint not installed — run: brew install swiftlint'
    @command -v xcodegen >/dev/null 2>&1 || echo 'warn: xcodegen not installed — run: brew install xcodegen'

[group('setup')]
generate:
    xcodegen generate

[group('develop')]
xcode: generate
    open Deckhand.xcodeproj

# Run the Mac daemon in the foreground; it prints the address and token to pair with.
[group('develop')]
daemon:
    uv run --directory daemon deckhand-daemon

# Copy the APNs signing key out of 1Password so the daemon can reach the Lock Screen.

# onenv cannot run under launchd: 1Password has no way to ask for a fingerprint there.
[group('setup')]
sync-apns:
    @mkdir -p ~/Library/Application\ Support/Deckhand
    @onenv get deckhand APNS_KEY > ~/Library/Application\ Support/Deckhand/apns.p8
    @onenv get deckhand APNS_KEY_ID > ~/Library/Application\ Support/Deckhand/apns-key-id
    @chmod 600 ~/Library/Application\ Support/Deckhand/apns.p8 ~/Library/Application\ Support/Deckhand/apns-key-id
    @echo 'push key written; restart the daemon to pick it up'

# Follow the daemon log (the same file Console.app shows under ~/Library/Logs).
[group('develop')]
logs:
    tail -f ~/Library/Logs/Deckhand/deckhand.log

# Redraw the app icon from the mark's own geometry.
[group('develop')]
icon:
    swift run IconMaker deckhand/Assets.xcassets/AppIcon.appiconset/icon.png

# The pairing token the app needs.
[group('develop')]
token:
    @cat ~/Library/Application\ Support/Deckhand/token

# Build and run the app in the simulator against a daemon on this Mac.
[group('develop')]
sim: generate
    xcodebuild {{ project }} -destination 'platform=iOS Simulator,name={{ sim }}' -configuration Debug build
    xcrun simctl boot '{{ sim }}' || true
    xcrun simctl install booted "$(xcodebuild {{ project }} -destination 'platform=iOS Simulator,name={{ sim }}' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Deckhand.app"
    xcrun simctl launch booted dev.jurrejan.deckhand -deckhand.host 127.0.0.1:4180 -deckhand.token "$(just token)"

# Build, install and start the app on the iPhone, already paired with this Mac.
# `phone` is a device name out of `xcrun devicectl list devices` and has to be the phone
# JJ is actually holding: two are paired here and the *other* one is named "iphone", an
# iPhone 12 Pro deliberately behind on builds. Installing to the wrong one succeeds and
# says "App installed", which is how a build lands where nobody is looking.
# Needs Xcode signed in and the phone unlocked (the developer disk image will not

# mount on a locked device).
[group('develop')]
device: generate
    xcodebuild {{ project }} -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath .build/device build
    xcrun devicectl device install app --device '{{ phone }}' .build/device/Build/Products/Debug-iphoneos/Deckhand.app
    xcrun devicectl device process launch --device '{{ phone }}' dev.jurrejan.deckhand \
        -- -deckhand.host m2-2.local -deckhand.token "$(just token)"

[group('quality')]
lint:
    swiftlint lint --strict

[group('quality')]
lint-fix:
    swiftlint --fix && swiftlint lint --strict

[group('quality')]
just-fmt-check:
    just --fmt --check

[group('quality')]
test:
    swift test

[group('quality')]
daemon-test:
    uv run --directory daemon pytest -q

[group('quality')]
daemon-lint:
    uv run --directory daemon ruff check src tests

# Every demo artifact parses, names itself, answers through the app, and stays inside the CSP.
[group('quality')]
demo-check:
    python3 demos/check.py

# Drives the app in the simulator against a running daemon (`just daemon` first).
[group('quality')]
ui-test: generate
    TEST_RUNNER_DECKHAND_TOKEN="$(just token)" TEST_RUNNER_DECKHAND_HOST=127.0.0.1:4180 \
        xcodebuild test {{ project }} -destination 'platform=iOS Simulator,name={{ sim }}'

[group('quality')]
loc-check:
    #!/usr/bin/env zsh
    setopt null_glob
    eval "$(python3 -c "
    import json, shlex
    c = json.load(open('.quality.json'))
    print(f'WARN={c[\"loc\"][\"warn\"]}')
    print(f'ERROR={c[\"loc\"][\"error\"]}')
    g = c['globs']
    print(f'GLOBS=({shlex.join(g)})')
    ")"
    err=0
    for pattern in $GLOBS; do
        for f in ${~pattern}; do
            lines=$(wc -l < "$f")
            if (( lines > ERROR )); then echo "error: $f ($lines lines, max $ERROR)"; err=1
            elif (( lines > WARN )); then echo "warn: $f ($lines lines, target ≤$WARN — don't trim, split the file!)"; fi
        done
    done
    exit $err

[group('quality')]
dir-check:
    #!/usr/bin/env zsh
    setopt null_glob
    eval "$(python3 -c "
    import json, shlex
    c = json.load(open('.quality.json'))
    print(f'MAX={c[\"dir\"][\"max_files\"]}')
    g = c['globs']
    print(f'GLOBS=({shlex.join(g)})')
    ")"
    err=0
    typeset -A counts
    for pattern in $GLOBS; do
        for f in ${~pattern}; do
            dir=${f:h}
            counts[$dir]=$(( ${counts[$dir]:-0} + 1 ))
        done
    done
    for dir count in ${(kv)counts}; do
        if (( count > MAX )); then
            echo "error: $dir ($count files, max $MAX)"
            err=1
        fi
    done
    exit $err

[group('quality')]
roots:
    #!/usr/bin/env zsh
    roots=(${(f)"$(git rev-list --max-parents=0 --branches)"})
    (( ${#roots} == 1 )) && exit 0
    echo "error: branches descend from ${#roots} roots; only 7b260ed (chore: scaffold project) is this project"
    for r in $roots; do echo "  $r: $(git branch --format='%(refname:short)' --contains $r | tr '\n' ' ')"; done
    exit 1

[group('quality')]
check:
    @echo '→ Checking Justfile format...'
    just just-fmt-check
    @echo '→ Checking file lengths...'
    just loc-check
    @echo '→ Checking directory sizes...'
    just dir-check
    @echo '→ Running lint...'
    just lint
    @echo '→ Running build...'
    just build
    @echo '→ Running tests...'
    just test
    @echo '→ Linting the daemon...'
    just daemon-lint
    @echo '→ Testing the daemon...'
    just daemon-test
    @echo '→ Checking the demo artifacts...'
    just demo-check

[group('build')]
build: generate
    swift build
    xcodebuild {{ project }} -destination 'platform=iOS Simulator,name={{ sim }}' -configuration Debug build

[group('build')]
build-release:
    swift build -c release

[group('cleanup')]
clean:
    swift package clean
    rm -rf .build/

# Open this project's CLAUDE.md tree in the project-atlas viewer, https://github.com/doublej/project-atlas (via the global `atlas` CLI)
[group('docs')]
claude-tree:
    atlas tree

[group('scaffold')]
update-scaffold *ARGS:
    #!/usr/bin/env zsh
    set -euo pipefail
    repo="${COOKIECUTTER_TEMPLATES:-}"
    if [[ -z "$repo" && -f .template-meta.json ]]; then
        repo=$(python3 -c "import json; print(json.load(open('.template-meta.json'))['template_source']['path'])" 2>/dev/null || true)
    fi
    if [[ -z "$repo" || ! -d "$repo" ]]; then
        echo "error: cookiecutter-templates repo not found — set \$COOKIECUTTER_TEMPLATES or fix template_source.path in .template-meta.json" >&2
        exit 1
    fi
    python3 "$repo/tools/update_scaffold.py" {{ ARGS }}

# Run the daemon at login, on port 4180.
[group('ops')]
install-agent:
    ln -sf {{ justfile_directory() }}/launchd/com.jurrejan.deckhand.plist ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    @curl -sf --retry 20 --retry-delay 1 --retry-connrefused http://127.0.0.1:4180/health && echo ' ← daemon is up'

[group('ops')]
uninstall-agent:
    launchctl bootout gui/$(id -u)/com.jurrejan.deckhand || true
    rm -f ~/Library/LaunchAgents/com.jurrejan.deckhand.plist

# Tell every session on this Mac that the phone exists. Personal scope, not per project:
# whether the phone can be reached has nothing to do with the folder a session is running in.

# `-n` so a second run replaces the link instead of nesting one inside it.
[group('ops')]
install-skill:
    ln -sfn {{ justfile_directory() }}/skills/deckhand ~/.claude/skills/deckhand
    @head -2 ~/.claude/skills/deckhand/SKILL.md | tail -1
