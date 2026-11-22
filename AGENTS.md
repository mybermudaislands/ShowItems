# AGENTS.md (ShowItems)

General workspace rules (git, secrets, language, release procedure) live outside this repository, in the maintainer's workspace. They are not copied here.

## Commit identity

Use the GitHub noreply identity, never a private email. Set it repo-locally (not globally):

```
git config user.name mybermudaislands
git config user.email 317432022+mybermudaislands@users.noreply.github.com
```

## Layout

- Repo root = the project folder. Addon folder: `ShowItems\` (toc: `ShowItems\ShowItems.toc`, interface 16001).
- Release is tag-driven (`vX.Y.Z`). The pipeline `.github\workflows\release.yml` is disabled until the repo variable `RELEASE_ENABLED` is `true`. See `RELEASING.md`.
- Local-only, ignored: `_old_*` folders, `*.zip`.
- `NEXT-CHAT-PROMPT.md`: hand-off prompt for a new AI conversation (project state and the Sets tab task).
- License: GPL-3.0 only (`LICENSE`), because code and textures are adapted from ItemRack (GPL-3.0). Evidence and credits are in `NOTICE.md`. Keep new code compatible with GPL-3.0 and do not relicense.

## Architecture (load order from the toc)

- `Core.lua`: shared namespace `SI`, saved variables (`SI.NewDB`, `SI.SanitizeDB`, `SI.ResolveStoredDB`), event helpers `SI.On` / `SI.OnInit`, combat queue `SI.RunSafe(key, fn)`, slash commands, addon compartment.
- `Slots.lua`: `SI.SLOTS`, `SI.SLOT_ORDER`.
- `Trackers.lua`: secure tracker buttons, groups, magnet, resize, slot key bindings (override bindings).
- `Menu.lua`: styling helpers, Ctrl+right click Track/Untrack menu on the character window, `SI.NewGridMenu`, name tips.
- `ItemTip.lua`: short item tooltip.
- `Flyout.lua`: right-click menu, bag scanning (`SI.ScanBags`, `SI.BagItem`, `SI.NumSlots`), equip and combat queue (`SI.EquipOrQueue`).
- `Favorites.lua`: favorite items. `CharacterMenu.lua`: hover menu on the character window with glow and stars.
- `Window.lua`: main window and tab API `SI.RegisterTab(id, label, def)`. Tabs: `Options.lua` (1 Settings), `Sets.lua` (2 Sets), `Profiles.lua` (3 Profiles).
- `Minimap.lua`: minimap button.
- `tests\wow_mock.lua`, `tests\showitems_test.lua`: mock-based tests (not proof of in-game behavior). `tools\`: texture generators, run from the repo root.

## Gotchas

- Settings live in `ShowItemsCharDB` (per character). `ShowItemsDB.chars[...]` is the legacy account-wide store, kept as a backup. Never write new data there.
- Tracker buttons and set key buttons are secure frames. Anything that touches them must go through `SI.RunSafe` (queued until combat ends).
- Equipment moves from insecure code are blocked in combat on this client. Only the set key button (macro `/equipslot`) can swap weapons in combat.
- Texture paths use `Interface\AddOns\ShowItems\...`, so the installed folder must be named `ShowItems`.
- Minimap button: right-click opens settings. Addon compartment: right-click toggles enable. Do not unify without asking.
- `ShowItemsLock`, `ItemRackButtons`, `ItemRackOptTabs` textures come from ItemRack (GPL-3.0).
- `ShowItems.toc` has `## Author: mybermudaislands`.
- Indentation: 4 spaces for `.lua` and `.toc` (see `.editorconfig`). No em-dashes anywhere.
- Run tests from the repo root: `lua5.1 tests\showitems_test.lua` (Lua 5.1 binary from `<workspace>\lua51`). Syntax check: `luac5.1 -p <file>`.
