# ShowItems

ShowItems is a World of Warcraft addon (Classic-era clients, interface 16001) that tracks equipment slots in small movable windows. A tracking window shows the item you wear in a slot, lets you use it with one click, and lists the items from your bags that fit the slot so you can swap them quickly. The addon also saves equipment sets and window layouts per character.

[Русская версия](README.ru.md)

## Features

- **Tracking windows.** Track any of the 19 equipment slots. Each tracked slot gets its own small window with the item icon and cooldown. Left-click uses the item. Drag to move a window.
- **Magnet.** Windows snap together when you drop them close to each other. A dropped window takes the size of the one it joins. Hold Ctrl while dragging to move one window out of its group.
- **Bag item menu.** Hover over a tracking window to list the items from your bags that fit the slot. Click an item to equip it. In combat the item is queued and equipped when combat ends, and a small picture of it shows on the window.
- **Window menu.** Right-click a tracking window for the same item list plus buttons to lock windows, resize the group and track or untrack slots.
- **Character window menu.** While the mouse is over a slot in the character window, the bag items that fit it are listed next to the slot. Each item has a star: starred (favorite) items come first in the list. A favorite that is neither in your bags nor worn is forgotten after a day. The menu has an optional shimmering glow.
- **Short item tooltips.** The menus show a short tooltip with the item name and its characteristics instead of the full tooltip with comparison tooltips.
- **Sets.** Pick slots, type a name and press Save to store the items you wear (or items you choose from your bags). Equip a set from your bags with one click, or bind a key to it. Items come from your bags only, never from the bank. In combat a set key swaps weapons only.
- **Profiles.** Save the layout of your windows (tracked slots, positions, sizes, spacing, groups, opacity, lock and key bindings) under a name and load it later. The addon keeps the last 5 automatic snapshots (taken before a reset, before loading a profile and before restoring a snapshot). Sets are not part of profiles.
- **Key bindings.** Bind a key to use a tracked slot, or to equip a set. Bindings are applied as override bindings, so your own saved key bindings are never changed.
- **Settings.** Lock windows, glow, enable or disable the addon, window spacing, transparency, window size, common size and reset.
- **Minimap button and addon compartment entry.**
- Settings are stored per character.

## Install

1. Download the latest release zip from the [Releases](../../releases) page.
2. Extract it so that the `ShowItems` folder is inside your AddOns folder (the folder must contain `ShowItems.toc`).
3. Start the game, or type `/reload` if it is already running.

## How to use

- **Track or untrack a slot:** in the character window, Ctrl+right click a slot to select it. Ctrl+Shift+right click several slots to select all of them. Then choose Track or Untrack in the menu that opens. You can also click the eye button in a tracking window menu and click slots there.
- **Use an item:** left-click a tracking window.
- **Move windows:** drag them. Windows snap together near each other. Ctrl+drag moves one window alone.
- **Swap an item:** hover over a tracking window or over a slot in the character window and click an item from the list.
- **Resize:** use the resize button in the right-click menu of a window and drag the triangle that appears at the corner of the group. The Settings tab also has size, spacing and transparency controls.
- **Sets tab:** click the slots around the panel to choose them, type a name and press Save. Right-click a slot to choose an item from your bags for it. Equip puts a set on from your bags, Bind Key assigns a key, Delete removes the set.
- **Help:** hover over the small "SI" label at the top-left of the ShowItems window to see a short help tooltip.

## Minimap button

- Left-click: list of sets (click a set to equip it)
- Right-click: settings
- Shift+left-click: enable or disable the addon (a gray icon means disabled)
- Drag: move the button around the minimap

In the addon compartment (the collapsed addon menu), left-click opens settings and right-click enables or disables the addon.

## Slash commands

- `/si` or `/showitems`: open the window on the tab used last
- `/si sets`: open the Sets tab
- `/si profiles`: open the Profiles tab
- `/si help`: list the commands
- `/si reset`: untrack all slots and reset positions, sizes and key bindings (a snapshot is taken first, see Profiles)

## Known limits

- Tracking windows are secure frames, so they cannot be created, moved, resized or changed in combat. Changes are applied after combat.
- Equipment changes from addon code are blocked in combat on this client. Sets cannot be equipped in combat, except that a set key swaps weapons (main hand, off hand, ranged) in combat.
- Items are taken from your bags only, never from the bank.
- The addon was developed and tested for the WoW "Forever" client (interface 16001). Other clients are not verified.

## Credits

The look of the window, parts of its code and the tab textures (`ItemRackButtons`, `ItemRackOptTabs`, `ShowItemsLock`) are based on the ItemRack addon (GPL-3.0). The Sets tab follows the ItemRack principle. Details: [NOTICE.md](NOTICE.md).

## License

ShowItems is free software released under the GNU General Public License, version 3 (GPL-3.0), see [LICENSE](LICENSE). Parts of it (the widget code in `Window.lua`, the icon list in `Sets.lua` and three textures) are adapted from or copied from ItemRack, which is also licensed under GPL-3.0. Copyright (C) the ItemRack authors and mybermudaislands. See [NOTICE.md](NOTICE.md) for the evidence.

## Development

- Tests (a mock of the WoW API, run with Lua 5.1 from the repository root): `lua5.1 tests/showitems_test.lua`
- `tools/` holds scripts that generate the glow and star textures.
- Maintainer notes: [RELEASING.md](RELEASING.md). Notes for AI assistants: [AGENTS.md](AGENTS.md).
