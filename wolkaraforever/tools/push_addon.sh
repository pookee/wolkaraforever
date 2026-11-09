#!/bin/bash
# Copy an Interface mobile add-on into the game's Interface/AddOns on the device, as the add-on's
# own commit says to install it.
#
# usage: wolkaraforever/tools/push_addon.sh [--dry-run] [--addon NAME]...
#
#   --addon NAME  the folder under addons/ to copy (repeatable). Default: WolkaraRoue, the
#                 Interface mobile. WolkaraRoueDuo is scarrdi94's iPhone Duo interface
#                 (jklock/wolkaraforever#26), installed beside it to be tried; the two switch
#                 with the "Interface Duo" menu tile or /wolkaraui, only one is active at a time.
#
# The game reads its add-ons when its interface loads, so this refuses while a game session is
# live; like every tool that writes the game's files, it also refuses while an update is
# writing. Every file is read back from the device and compared before success is reported.
# It only adds and replaces: a file removed from the add-on stays on the device. The add-on's
# settings are not touched - they live in the game's WTF folder, not beside the add-on.
#
# One exception, for WolkaraRoueDuo only: a character whose AddOns.txt has no line for it gets
# "WolkaraRoueDuo: disabled", so its first install never runs two interfaces at once (its .toc
# also says DefaultState: disabled). A line already there - the player's own choice - is kept.
# The AddOns.txt as it was is kept under build/wtf-backups/<time>/ (ignored, never committed).
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
. wolkaraforever/tools/env.sh
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
[ -n "$device" ] || { echo "push_addon: set DEVICE in local.env (see local.env.example)" >&2; exit 2; }
usage() { echo "usage: wolkaraforever/tools/push_addon.sh [--dry-run] [--addon WolkaraRoue|WolkaraRoueDuo]..." >&2; exit 2; }
dry=0
addons=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry=1 ;;
        --addon) [ $# -ge 2 ] || usage; addons+=("$2"); shift ;;
        *) usage ;;
    esac
    shift
done
[ ${#addons[@]} -gt 0 ] || addons=(WolkaraRoue)
for name in "${addons[@]}"; do
    case "$name" in
        WolkaraRoue|WolkaraRoueDuo) ;;
        *) echo "push_addon: unknown add-on $name" >&2; usage ;;
    esac
    [ -f "addons/$name/$name.toc" ] || { echo "push_addon: addons/$name/$name.toc is missing" >&2; exit 1; }
done

state=$(bash wolkaraforever/tools/pilot.sh state 2>&1) || { echo "$state" >&2; exit 1; }
if echo "$state" | grep -q "a game session is live"; then
    echo "push_addon: a game session is live; quit the game first (the Quit tile of the Interface mobile menu saves)" >&2
    exit 1
fi
echo "$state" | grep -qE "update writing: 0 file" ||
    { echo "push_addon: an update may be writing; try again when it has stopped" >&2; exit 1; }
session=$(echo "$state" | sed -n 's/^ *session: *//p' | head -1)

copy_to() {
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "$1" --destination "Documents/$2" > /dev/null
}

# Every character's AddOns.txt, from the container listing pilot.sh state just took.
character_addon_lists() {
    [ -n "$session" ] && [ -f "$session/files.json" ] ||
        { echo "push_addon: no container listing to find the characters' AddOns.txt in" >&2; return 1; }
    python3 -I - "$session/files.json" <<'EOF'
import json, sys
prefix = "Documents/World of Warcraft/_forever_/WTF/Account/"
for item in json.load(open(sys.argv[1]))["result"]["files"]:
    path = item["relativePath"]
    if path.startswith(prefix) and path.endswith("/AddOns.txt") and path.count("/") == 8:
        print(path[len("Documents/"):])
EOF
}

keep_duo_off() {
    local lists backup="" list
    lists=$(character_addon_lists) || return 1
    if [ -z "$lists" ]; then
        echo "push_addon: no character has an AddOns.txt yet; WolkaraRoueDuo's DefaultState: disabled applies"
        return 0
    fi
    while IFS= read -r list; do
        local character=${list%/AddOns.txt}
        character=${character##*/}
        DEVICE_LOG_FILE="$list" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
        local fetched=build/device-log-files/AddOns.txt
        if grep -q '^WolkaraRoueDuo:' "$fetched"; then
            echo "push_addon: $character: WolkaraRoueDuo already has a state there, kept"
            continue
        fi
        [ -n "$backup" ] || { backup="build/wtf-backups/$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$backup"; }
        local keep="$backup/$character-AddOns.txt"
        cp "$fetched" "$keep"
        local updated="$keep.new"
        cp "$keep" "$updated"
        [ -z "$(tail -c 1 "$updated")" ] || printf '\n' >> "$updated"
        printf 'WolkaraRoueDuo: disabled\n' >> "$updated"
        if [ "$dry" = 1 ]; then
            echo "push_addon: would mark WolkaraRoueDuo disabled in $list"
            continue
        fi
        copy_to "$updated" "$list"
        DEVICE_LOG_FILE="$list" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
        cmp -s "$fetched" "$updated" ||
            { echo "push_addon: $list read back from the device is not the one copied (original kept at $keep)" >&2; return 1; }
        echo "push_addon: $character: WolkaraRoueDuo starts disabled (original kept at $keep)"
    done <<< "$lists"
}

for name in "${addons[@]}"; do
    addon=addons/$name
    destination="World of Warcraft/_forever_/Interface/AddOns/$name"
    files=$(cd "$addon" && ls -- *.toc *.lua *.xml 2>/dev/null)
    [ -n "$files" ] || { echo "push_addon: nothing to copy in $addon" >&2; exit 1; }
    echo "push_addon: $(echo "$files" | wc -l | tr -d ' ') file(s) to $destination"
    # The state comes first, so the folder never appears enabled for a character.
    [ "$name" != WolkaraRoueDuo ] || keep_duo_off
    if [ "$dry" = 1 ]; then echo "$files"; echo "push_addon: dry run, nothing copied"; continue; fi

    for file in $files; do copy_to "$addon/$file" "$destination/$file"; done
    for file in $files; do
        DEVICE_LOG_FILE="$destination/$file" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
        cmp -s "build/device-log-files/$file" "$addon/$file" ||
            { echo "push_addon: $file read back from the device is not the one copied" >&2; exit 1; }
    done
    echo "push_addon: $name done; every file read back identical."
done
[ "$dry" = 1 ] || echo "push_addon: the game loads it at its next login or /reload."
