# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.1] - 2026-11-22

### Changed

- License changed from MIT to GPL-3.0 (only). A comparison with ItemRack showed copied textures (`ItemRackButtons.blp`, `ItemRackOptTabs.tga`) and adapted code (widget templates in `Window.lua`, icon list in `Sets.lua`), so the whole addon follows the ItemRack license.
- `LICENSE` now holds the GPL-3.0 text. `NOTICE.md`, `README.md`, `README.ru.md` and `AGENTS.md` describe the origin of the ItemRack parts. No behavior change.

## [0.3.0] - 2026-11-22

Initial public release. Earlier versions (0.1.0 and 0.2.0) were local only and are not published separately.

### Added

- MIT license (`LICENSE`), `## Author:` in the toc, and `NOTICE.md` listing the textures that come from ItemRack (GPL-3.0) and are not covered by MIT.
- Maintainer documents: `RELEASING.md`, `AGENTS.md`, `NEXT-CHAT-PROMPT.md`.

- Tracking windows for the 19 equipment slots: item icon, cooldown, left-click to use the item, drag to move, magnet that snaps windows together.
- Menu of bag items that fit a slot, on hover and on right-click of a tracking window, with a combat equip queue.
- Menu of bag items on the character window slots, with favorite stars and an optional glow.
- Short item tooltips (name and characteristics only).
- Sets tab: save, equip, delete and bind a key to equipment sets (items from bags only).
- Profiles tab: named window layouts and automatic snapshots.
- Settings tab: lock, glow, enable, spacing, transparency, window size, slot key bindings, reset.
- Minimap button, addon compartment entry and the `/si` and `/showitems` slash commands.
