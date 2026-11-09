#!/bin/bash
# The Interface mobile add-on (addons/WolkaraRoue), checked on the Mac: every Lua file compiles
# as the game's Lua 5.1 would read it, every file the .toc lists exists, and the save module
# saves as tests/test_mobile_addon_save.lua expects; the turning wheels and their four pages, the
# cooldown text, the touch and long press on a spell, the bag placement, the game's windows, the
# minimap, the chat, the moves of old saves, the player's auras and the tidy screen behave as
# tests/test_mobile_addon_turn.lua, test_mobile_addon_cooldown.lua, test_mobile_addon_press.lua,
# test_mobile_addon_bags.lua, test_mobile_addon_windows.lua, test_mobile_addon_minimap.lua,
# test_mobile_addon_chat.lua, test_mobile_addon_settings.lua, test_mobile_addon_buffs.lua and
# test_mobile_addon_tidy.lua expect.
#
# usage: wolkaraforever/tools/test_mobile_addon.sh
#
# Needs LuaJIT (brew install luajit), which reads Lua 5.1 like the game.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
addon=addons/WolkaraRoue
command -v luajit > /dev/null || { echo "test_mobile_addon: needs luajit (brew install luajit)" >&2; exit 1; }

for file in "$addon"/*.lua; do
    luajit -bl "$file" > /dev/null || { echo "test_mobile_addon: $file does not compile" >&2; exit 1; }
done
while read -r line; do
    line=${line%$'\r'}
    case "$line" in ''|'#'*) continue ;; esac
    [ -f "$addon/$line" ] || { echo "test_mobile_addon: the .toc lists $line, which is missing" >&2; exit 1; }
done < "$addon/WolkaraRoue.toc"
echo "mobile add-on: $(ls "$addon"/*.lua | wc -l | tr -d ' ') Lua files compile, every .toc entry exists: PASS"

luajit wolkaraforever/tools/tests/test_mobile_addon_save.lua "$addon/Save.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_turn.lua "$addon/Turn.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_cooldown.lua "$addon/Actions.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_press.lua "$addon/Actions.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_bags.lua "$addon/Bags.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_windows.lua "$addon/Windows.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_minimap.lua "$addon/Minimap.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_chat.lua "$addon/Chat.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_settings.lua "$addon/Core.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_buffs.lua "$addon/Buffs.lua"
luajit wolkaraforever/tools/tests/test_mobile_addon_tidy.lua "$addon/Hud.lua" "$addon/Shortcuts.lua" "$addon/Free.lua"

# scarrdi94's iPhone Duo interface (jklock/wolkaraforever#26), installed beside ours to be tried:
# it compiles, its .toc is complete, and both carry the same switch between them.
duo=addons/WolkaraRoueDuo
if [ -d "$duo" ]; then
    for file in "$duo"/*.lua; do
        luajit -bl "$file" > /dev/null || { echo "test_mobile_addon: $file does not compile" >&2; exit 1; }
    done
    while read -r line; do
        line=${line%$'\r'}
        case "$line" in ''|'#'*) continue ;; esac
        [ -f "$duo/$line" ] || { echo "test_mobile_addon: the Duo .toc lists $line, which is missing" >&2; exit 1; }
    done < "$duo/WolkaraRoueDuo.toc"
    grep -qx '## DefaultState: disabled' "$duo/WolkaraRoueDuo.toc" ||
        { echo "test_mobile_addon: WolkaraRoueDuo must start disabled" >&2; exit 1; }
    cmp -s "$addon/Switch.lua" "$duo/Switch.lua" ||
        { echo "test_mobile_addon: the two add-ons' Switch.lua differ" >&2; exit 1; }
    for toc in "$addon/WolkaraRoue.toc" "$duo/WolkaraRoueDuo.toc"; do
        grep -qx 'Switch.lua' "$toc" || { echo "test_mobile_addon: $toc does not load Switch.lua" >&2; exit 1; }
    done
    luajit wolkaraforever/tools/tests/test_mobile_addon_switch.lua "$addon/Switch.lua" "$duo/Switch.lua"
    echo "mobile add-on Duo: $(ls "$duo"/*.lua | wc -l | tr -d ' ') Lua files compile, every .toc entry exists, starts disabled, same switch: PASS"
fi
