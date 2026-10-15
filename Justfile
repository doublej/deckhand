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

# The way onto a phone that is not on this network. `just device` needs the phone discoverable
# over Bonjour, and no VPN can arrange that — iOS advertises the pairing service on its physical
# link only, never into a tunnel. So the alternative is not a better tunnel: it is the phone
# fetching the build over HTTPS and installing it itself.
#
# **It is the ordinary development signature, and that is the surprise.** Apple documents
# over-the-air install as needing an Ad Hoc or Enterprise profile, and the whole Ad Hoc apparatus
# was built here first: a distribution certificate, which needs the developer portal, which needs
# an account, which on a Mac nobody is sitting at needs an App Store Connect key. None of it is
# necessary. Measured on 2026-09-13, iOS 26, a Release build signed with `iOS Team Provisioning
# Profile: dev.jurrejan.deckhand`: it installed. The device is in the profile, which appears to be
# the whole of what the installer checks.
#
# Three things fall out of that and all three are better than the Ad Hoc build would have been:
# `aps-environment` stays `development`, so the daemon goes on pushing to the sandbox APNs host
# and the Lock Screen card keeps working; `get-task-allow` stays true, so a debugger still
# attaches; and nothing expires before the profile does, 2027-09-09.
#
# The one real limit is the profile's device list. A phone that has never had a build from this
# Mac is not in it, and adding one needs Xcode at an unlocked screen.

# Build and publish a build a phone anywhere can install.
[group('build')]
release: generate
    #!/usr/bin/env zsh
    set -e
    root={{ justfile_directory() }}/.build/adhoc
    rm -rf $root && mkdir -p $root
    xcodebuild {{ project }} -configuration Release -destination 'generic/platform=iOS' \
        -archivePath $root/Deckhand.xcarchive -allowProvisioningUpdates archive
    just publish-release

# Split from `release` so a failed publish can be retried without paying for the archive again,
# and so a build already made can be put back up after `just unpublish-release`.

# Package the archive and put it behind install.jurrejan.com.
[group('build')]
publish-release:
    #!/usr/bin/env zsh
    set -e
    root={{ justfile_directory() }}/.build/adhoc
    app=$root/Deckhand.xcarchive/Products/Applications/Deckhand.app
    if [[ ! -d $app ]]; then echo 'nothing archived — run: just release'; exit 1; fi
    rm -rf $root/Payload $root/site && mkdir -p $root/Payload $root/site
    cp -R $app $root/Payload/
    # `zip` from the archive root, because an ipa is a zip whose only top-level entry is Payload.
    cd $root && zip -qry site/Deckhand.ipa Payload && cd {{ justfile_directory() }}
    version=$(plutil -extract CFBundleShortVersionString raw -o - $app/Info.plist)
    sed "s|__VERSION__|$version|" {{ justfile_directory() }}/tools/manifest.plist > $root/site/manifest.plist
    sips -Z 57 {{ justfile_directory() }}/deckhand/Assets.xcassets/AppIcon.appiconset/icon.png --out $root/site/icon-57.png > /dev/null
    sips -Z 512 {{ justfile_directory() }}/deckhand/Assets.xcassets/AppIcon.appiconset/icon.png --out $root/site/icon-512.png > /dev/null
    cp {{ justfile_directory() }}/tools/install-page.html $root/site/index.html
    # --force because this hostname exists to be republished: every build lands on the same one.
    cdy site install $root/site --force
    # And then the config back, because `cdy site` regenerates it and the generated one serves
    # `manifest.plist` with no content type at all. iOS reports that as "cannot connect to
    # install.jurrejan.com" — a sentence about the wrong thing entirely, and the reason this line
    # is not optional. EDITOR is a copy so the edit goes through cdy's own validate-and-rollback.
    EDITOR="cp {{ justfile_directory() }}/tools/install.caddy" cdy edit install
    echo 'open https://install.jurrejan.com in Safari on the phone'

# The ipa is readable by anyone who knows the hostname. It carries the app binary and no secrets
# — the pairing token is typed on the phone — but there is no reason to leave it up between
# builds either.

# Take the install page down again.
[group('build')]
unpublish-release:
    cdy rm install --force

# Follow the daemon log (the same file Console.app shows under ~/Library/Logs).
[group('develop')]
logs:
    tail -f ~/Library/Logs/Deckhand/deckhand.log

# Regenerate docs/commands.md's tables from the routes, the MCP tools and the deckhand command.
[group('develop')]
commands-doc:
    uv run --directory daemon python tools/commands_doc.py

# Redraw the app icon from the mark's own geometry.
[group('develop')]
icon:
    swift run IconMaker deckhand/Assets.xcassets/AppIcon.appiconset/icon.png
    swift run IconMaker --mac mac/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
    cd mac/Assets.xcassets/AppIcon.appiconset && for s in 16 32 128 256 512; do sips -z $s $s icon_512x512@2x.png --out icon_${s}x${s}.png >/dev/null; [[ $s == 512 ]] || sips -z $((s * 2)) $((s * 2)) icon_512x512@2x.png --out icon_${s}x${s}@2x.png >/dev/null; done

# The pairing token the app needs.
[group('develop')]
token:
    @cat ~/Library/Application\ Support/Deckhand/token

# A six-digit code a phone or headset trades for a token of its own; waits to say who paired.
[group('develop')]
pair:
    @uv run --directory daemon python -m deckhand_daemon.pairing pair

# Every device paired with a code, and when each was last heard from.
[group('develop')]
devices:
    @uv run --directory daemon python -m deckhand_daemon.pairing devices

# Take one device's token away; the others keep theirs.
[group('develop')]
forget id:
    @uv run --directory daemon python -m deckhand_daemon.pairing forget {{ id }}

# How far a clip survives being sped up and silence-trimmed (`--report` re-reads the last run).
[group('develop')]
audio-bench *args:
    uv run --directory daemon python tools/audio_bench.py {{ args }}

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
        -- -deckhand.host "$(scutil --get LocalHostName).local" -deckhand.token "$(just token)"

# The manager and the session cards for the person at the Mac (`mac/App.swift`). It asks to send
# notifications on its first run. Stopped by path, not `pkill -x Deckhand`, which would also take
# the simulator's copy of the phone app.

# Build the Mac app, put it in ~/Applications and start it.
[group('develop')]
mac: generate
    xcodebuild -project Deckhand.xcodeproj -scheme DeckhandMac -configuration Release -derivedDataPath .build/mac -allowProvisioningUpdates build
    pkill -f 'Deckhand.app/Contents/MacOS/Deckhand' || true
    ditto .build/mac/Build/Products/Release/Deckhand.app ~/Applications/Deckhand.app
    open ~/Applications/Deckhand.app

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
    uv run --directory daemon ruff check src tests tools

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
    @echo '→ Checking every branch shares one root...'
    just roots
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
    xcodebuild -project Deckhand.xcodeproj -scheme DeckhandMac -configuration Debug -derivedDataPath .build/mac build

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

# Writes this Mac's plist from the template (`rm` first: the old install was a symlink into a
# checkout, and `>` would write through it). A job that is already loaded is left running, so a
# second run never drops a phone mid-clip; `just restart-agent` picks up a changed plist.

# Run the daemon at login, on port 4180, from this checkout.
[group('ops')]
install-agent:
    @[[ "$(git rev-parse --git-dir 2>/dev/null)" == "$(git rev-parse --git-common-dir 2>/dev/null)" ]] \
        || { echo 'This is a worktree: launchd would run it after it is gone. Install from the main checkout.'; exit 1; }
    @mkdir -p ~/Library/Logs/Deckhand ~/Library/LaunchAgents
    rm -f ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    sed -e "s|@HOME@|$HOME|g" -e "s|@REPO@|{{ justfile_directory() }}|g" \
        launchd/com.jurrejan.deckhand.plist.in > ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    @plutil -lint -s ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    @launchctl print gui/$(id -u)/com.jurrejan.deckhand >/dev/null 2>&1 \
        && echo 'already running; `just restart-agent` picks up a changed plist' \
        || launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    @curl -sf --retry 20 --retry-delay 1 --retry-connrefused http://127.0.0.1:4180/health >/dev/null && echo 'daemon is up on :4180'

# Stop the daemon and start it again from its plist, which `kickstart` would not re-read.
[group('ops')]
restart-agent:
    launchctl bootout gui/$(id -u)/com.jurrejan.deckhand 2>/dev/null || true
    while launchctl print gui/$(id -u)/com.jurrejan.deckhand >/dev/null 2>&1; do sleep 0.2; done
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jurrejan.deckhand.plist
    @curl -sf --retry 20 --retry-delay 1 --retry-connrefused http://127.0.0.1:4180/health >/dev/null && echo 'daemon is up on :4180'

# `web_url`/`remote_url` are where deckhand-web and the off-network edge answer, published on
# /health so no client carries them; `web_dir`/`xr_dir` are the deckhand-web and deckhand-xr
# checkouts, beside this one unless said (or DECKHAND_WEB_DIR / DECKHAND_XR_DIR).

# Everything on a fresh Mac: the daemon, deckhand-web, deckhand-windows and their permissions.
[group('setup')]
setup web_url="" remote_url="" web_dir="" xr_dir="":
    #!/usr/bin/env zsh
    set -euo pipefail
    command -v uv >/dev/null || { echo 'Needs uv first:  curl -LsSf https://astral.sh/uv/install.sh | sh'; exit 1; }
    command -v claude >/dev/null || echo 'note: no `claude` on PATH. Deckhand lists Claude Code sessions, so there will be none yet.'
    uv sync --directory daemon
    data="$HOME/Library/Application Support/Deckhand"
    mkdir -p "$data"
    [[ -z "{{ web_url }}" ]] || print -r -- "{{ web_url }}" > "$data/web-url"
    [[ -z "{{ remote_url }}" ]] || print -r -- "{{ remote_url }}" > "$data/remote-url"
    just install-agent
    beside="$(dirname {{ justfile_directory() }})"
    web="${DECKHAND_WEB_DIR:-{{ web_dir }}}"; web="${web:-$beside/deckhand-web}"
    if [[ -f "$web/Justfile" ]]; then
        command -v bun >/dev/null || { echo 'deckhand-web needs bun:  curl -fsSL https://bun.sh/install | bash'; exit 1; }
        [[ -d "$web/node_modules" ]] || (cd "$web" && bun install)
        just --justfile "$web/Justfile" install-agent
    else
        echo "deckhand-web: none at $web, skipped. The headset's panels need it, the phone does not (web_dir=<folder>)."
    fi
    xr="${DECKHAND_XR_DIR:-{{ xr_dir }}}"; xr="${xr:-$beside/deckhand-xr}"
    if [[ -f "$xr/windows/Justfile" ]]; then
        command -v swift >/dev/null || { echo 'deckhand-windows needs Swift:  xcode-select --install'; exit 1; }
        just --justfile "$xr/windows/Justfile" install-agent
    else
        echo "deckhand-windows: none at $xr/windows, skipped. Only the headset shows Mac windows (xr_dir=<folder>)."
    fi
    if ! command -v tmux >/dev/null; then
        echo
        echo "Install tmux (brew install tmux) and run Claude Code inside it."
        echo "Deckhand finds which terminal each session is in through it, and types into it when you ask."
    fi
    echo
    echo 'Done. Open Deckhand on your phone or headset; it finds this Mac by itself.'
    echo 'Then pair it:  just pair  (or Pair a device, on Deckhand'"'"'s page in utt)'

# The three login agents, the Mac app, the `deckhand` command, the MCP entry and the skill link.
# The data folder stays, because it holds the token every paired device uses; the last line says
# how to remove that too.

# Take everything `just setup` put on this Mac off it again.
[group('setup')]
teardown:
    #!/usr/bin/env zsh
    set -uo pipefail
    for label in com.jurrejan.deckhand com.jurrejan.deckhand-web com.jurrejan.deckhand-windows; do
        launchctl bootout gui/$(id -u)/$label 2>/dev/null && echo "stopped $label"
        rm -f ~/Library/LaunchAgents/$label.plist
    done
    pkill -f 'Applications/Deckhand.app/Contents/MacOS/Deckhand' 2>/dev/null || true
    rm -rf ~/Applications/Deckhand.app
    command -v claude >/dev/null && claude mcp remove --scope user deckhand 2>/dev/null && echo 'removed the deckhand MCP server'
    [[ -L ~/.claude/skills/deckhand ]] && rm ~/.claude/skills/deckhand && echo 'removed the deckhand skill link'
    uv tool uninstall deckhand-daemon 2>/dev/null && echo 'removed the deckhand command'
    echo
    echo "Kept: $HOME/Library/Application Support/Deckhand (token, settings, clips) and ~/Library/Logs/Deckhand*."
    echo "To remove those too:  rm -rf ~/Library/Application\ Support/Deckhand ~/Library/Logs/Deckhand ~/Library/Logs/DeckhandWeb"

# Put a hand on a remote machine: uv, the daemon's source, and its locked environment.
# Nothing is registered as a service — a hand's whole life is the ssh link the daemon opens,

# so this only has to leave the code somewhere `uv run` can find it.
[group('ops')]
install-hand alias:
    ssh -o BatchMode=yes -o ConnectTimeout=4 {{ alias }} 'command -v uv >/dev/null || (curl -LsSf https://astral.sh/uv/install.sh | sh)'
    rsync -a --delete --exclude .venv --exclude __pycache__ --exclude '*.pyc' --exclude tests \
        {{ justfile_directory() }}/daemon/ {{ alias }}:.deckhand/
    ssh -o BatchMode=yes {{ alias }} 'PATH="$HOME/.local/bin:$PATH" uv sync --no-dev --directory ~/.deckhand'
    @echo '{{ alias }} has a hand — the daemon starts it over ssh when it needs one'

# The same, for a machine that answers ssh with PowerShell. A separate recipe rather than a
# branch: nothing in the POSIX one survives the crossing — there is no rsync on Windows, `VAR=x
# cmd` is not a thing, and `~` is not a path. What the two share is the shape, not a line.
#
# tar rather than rsync, and a tarball rather than a pipe: Windows has bsdtar in System32, and
# PowerShell is not a safe pipe for binary stdin. What is copied is the same set of files the

# POSIX recipe copies, so a hand is the same thing on every machine.
[group('ops')]
install-hand-win alias:
    #!/usr/bin/env zsh
    set -e
    tar czf /tmp/deckhand-hand.tgz \
        -C {{ justfile_directory() }}/daemon \
        --exclude .venv --exclude __pycache__ --exclude '*.pyc' --exclude tests .
    scp -q /tmp/deckhand-hand.tgz {{ alias }}:deckhand-hand.tgz
    rm -f /tmp/deckhand-hand.tgz
    # Piped as a script rather than passed as a command line: the login shell on that machine is
    # PowerShell and it eats an inline `$variable` before the inner one ever sees it. The
    # delimiter carries no indentation of its own: `just` strips a recipe's leading whitespace
    # before the shell sees it, so a quoted `<<'    PS'` would never match the line that ends it
    # — the heredoc then runs to the end of the recipe, and PowerShell reads `PS` as `Get-Process`.
    ssh -o BatchMode=yes {{ alias }} 'powershell -NoProfile -Command -' <<'PS'
    $ErrorActionPreference = "Stop"
    $root = Join-Path $HOME ".deckhand"
    # A hand running out of this folder holds its own .exe open, and uv cannot replace a locked
    # file — the install fails with "Access is denied" halfway through and leaves half a venv.
    # Stopping it is safe and is not a special case: a hand's whole life is the ssh link the
    # daemon opened, and the daemon opens a new one within the minute.
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($root, "OrdinalIgnoreCase") } |
        Stop-Process -Force
    Start-Sleep -Seconds 1
    if (Test-Path $root) { Remove-Item -Recurse -Force $root }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    tar xzf (Join-Path $HOME "deckhand-hand.tgz") -C $root
    Remove-Item (Join-Path $HOME "deckhand-hand.tgz")
    uv sync --no-dev --directory $root
    PS
    echo '{{ alias }} has a hand — the daemon starts it over ssh when it needs one'

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

# Give every session on this Mac the seven tools as well as the skill. User scope, the same reason:
# a session started from the phone is an ordinary `claude` in an ordinary shell, so one entry in
# ~/.claude.json reaches every one of them and the daemon injects nothing.

# `--project` rather than `--directory`: the server has to keep the session's own cwd.
[group('ops')]
install-mcp:
    claude mcp remove --scope user deckhand 2>/dev/null || true
    claude mcp add --scope user deckhand -- uv run --project {{ justfile_directory() }}/daemon deckhand-mcp
    @claude mcp list 2>/dev/null | grep deckhand || true

[group('ops')]
uninstall-mcp:
    claude mcp remove --scope user deckhand

# `deckhand` on PATH: the same seven tools, for a shell. Editable, so it follows this checkout.
[group('ops')]
install-cli:
    uv tool install --force --editable {{ justfile_directory() }}/daemon
    @deckhand prime | head -2
