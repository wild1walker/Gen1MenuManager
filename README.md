<p align="center">
  <img src="docs/banner.png" alt="Gen1Wild" width="400">
</p>

<h1 align="center">Gen1MenuManager</h1>

<p align="center">
  <b>Your menus, in the order you want them</b>
</p>

Rearrange the START menu and the Pokémon Center PC menu: reorder the rows,
hide the ones you never touch, and pin field items and moves so they get a row
of their own once you own them.

Requires no permissions. The mod manager shows it with a clean permission
list, because nothing here reaches into engine internals.

## Using it

Three ways in, and no arrangement can close all of them:

- press **SELECT** with the START menu or a PC menu open
- pick **MENU MGR**, the row on either menu
- pick **MENU MANAGER** on the OPTION screen

SELECT is free in both menus — the START menu's watched-key mask is
`PAD_DOWN | PAD_UP | PAD_START | PAD_B | PAD_A` and the shared menu widget
reads up, down, A, B and START only — so the shortcut takes nothing away from
the vanilla controls.

Each menu keeps its own arrangement. Open the editor from the START menu and
you are editing the START menu; open it from a PC and you are editing that.

| Button | Does |
| --- | --- |
| Up / Down | move the cursor |
| A | grab the row, then A again to drop it |
| Up / Down while grabbed | move the row |
| SELECT | show / hide a row, or switch a pin on and off |
| B | leave |

The right-hand column reads `ON`, `OFF`, `PIN`, `LOCK` (a row that cannot be
hidden), or `----` for a pin you have not unlocked yet.

## What can be pinned

| Pin | Appears once |
| --- | --- |
| TOWN MAP | the TOWN MAP is in the bag |
| BICYCLE | the BICYCLE is in the bag |
| OLD / GOOD / SUPER ROD | that rod is in the bag |
| FLY | a party member knows FLY and you hold the THUNDERBADGE |
| CUT, SURF, STRENGTH, FLASH | a party member knows it and you hold its badge |
| DIG, TELEPORT | a party member knows it |

ITEMFINDER and the POKé FLUTE are deliberately absent. Their behavior lives
inside the bag's own result dispatch, which is file-local and exported
nowhere; pinning them would mean duplicating engine logic that can drift out
of step. They stay in the bag.

## Options

Both live under the mod's entry in the mod manager.

- **SELECT OPENS** — SELECT opens the editor from either menu. On by default,
  and while it is on the MENU MGR row is an ordinary row you can hide like any
  other. Turn it off and that row locks (`LOCK`), because it becomes the only
  route left.
- **MENU ROW** — show MENU MGR on the START menu.
- **PC ROW** — show MENU MGR on the PC menu.
- **HIDE UNUSABLE** — drop a pin whose action cannot run right now (the
  BICYCLE indoors, SURF facing dry land) instead of showing a row that
  refuses. On by default.

## Notes

- **Other mods' rows are arrangeable too.** The hook runs outermost, so QUESTS,
  ACHIEVEMENTS, NG PLUS and anything else appended by another mod can be moved
  and hidden like a vanilla row.
- **New rows are never lost.** A row the saved order does not mention — a mod
  installed since, or one that only appears with a party — is appended in
  engine order rather than dropped.
- **Layouts follow the save,** and seed from an installation-wide template, so
  a new file starts from your last arrangement instead of from scratch. The
  two menus are stored separately.
- **The PC's exit is never at risk.** The engine appends LOG OFF *after* the
  hook this mod uses, so it cannot be reordered or hidden by anything.
- **Editing a PC menu takes effect immediately.** The PC session stays open
  underneath, so the menu is rebuilt and its box resized when you leave the
  editor.
- **Rows are keyed by label** — except three cases. Rows that carry a stable
  id are keyed by that instead (Gold's PC rows do); the START menu's
  trainer-card row and the PC's `<name>'s PC` row are matched against your
  player name.
- **A renamed row loses its place once.** Two labels change during a
  playthrough: the box PC becomes BILL'S PC when you meet Bill, and a
  translation mod rewrites everything. A key that no longer matches falls to
  the end of the menu, where you can put it back. Nothing is ever dropped.

## Tests

From the root of a gen1recomp checkout, with this mod at
`mods/Gen1MenuManager/`. The suite drives the engine's own Loader, so it does
not run from a bare clone of this repository.

```sh
luajit mods/Gen1MenuManager/tests/Gen1MenuManager_test.lua
```

It runs against the ROM-free fixture dataset, so a checkout with no ROM
imported is fine.
