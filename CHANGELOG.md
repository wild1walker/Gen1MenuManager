# Changelog

## 0.5.0

- **Runs on Gold, Silver and Crystal.** The manifest already said `all`; now
  the code means it. The editor arranges the same two menus there.

- **The START menu comes back once, not twice.** Red's `Menu` pops itself
  before running a row's `onSelect`, so the editor opens with the START menu
  already off the stack. Gold's `StartMenu:choose` does not pop, so the editor
  sits on top of a live one and re-opening built a *second* menu behind it —
  two identical menus stacked, which reads exactly as "I can't close it". The
  stale one is dropped first, and popped rather than reused: the menu
  underneath was built from the layout you just changed.

- **`ROW HINTS`**, a new Gen 2-only row, off by default. Gold prints a line of
  help under the highlighted START row, covering the bottom tenth of the screen
  for as long as the menu is open. On does not force the hints back — it stands
  down and leaves the cart's own `MENU ACCOUNT` setting to decide, so the two
  never disagree.
