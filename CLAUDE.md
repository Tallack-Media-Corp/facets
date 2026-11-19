# Facets

## Read these first

- [DESIGN.md](DESIGN.md): the design system and its Shared pieces table (the design map).
- [docs/consistency.md](docs/consistency.md): the rules, the checks, and the checklist before any build.

## Short rules

- One job, one piece: build only from the pieces in the design map. If none fits, extend one or add a new one to the map, with a source rule that bans the hand-built form, and replace every copy in the same change.
- Every size, radius, timing, icon and colour comes from the tokens (`Shared/Tokens.swift`, `Facets/UI/Symbols.swift`).
- Platform and mode differences go inside the shared piece, never in a screen.
- Every bug fix searches for the same mistake elsewhere, fixes all of it, and adds the check that would have caught it.
- Check each fix on the platform it was reported on. Before any build, run the full checklist including the visual sweep (`scripts/sweep.sh`), and look at every contact sheet.
- Never take focus on the owner's computer to check something; capture in the background.
- Builds use `.build/DerivedData` only; `scripts/housekeeping.sh` clears a finished round.
