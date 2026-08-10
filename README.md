# Cartographers — Solo

A browser implementation of the board game **Cartographers** with the official
**solo ruleset**, written in [Gleam](https://gleam.run) +
[Lustre](https://lustre.build). Ships as a single self-contained HTML file —
no server, no backend, no network. All art is original minimal linework
(parchment, flat muted terrain colours); official card texts are transcribed
for private use.

## Play

Open **`dist/cartographers-solo.html`** in any desktop browser. Your game
auto-saves to localStorage (resume with "Continue your last map"), and the
title screen keeps your personal best and past expeditions.

### Solo rules implemented

- 11×11 wilderness map (side A), fixed mountains and ruins spaces
- 13-card explore deck: one ambush card shuffled in per season, undrawn
  ambushes carried into the deck of the next season; drawn ambushes are
  removed
- Coins from mountain rings and coin-bearing card options; −1 per empty space
  adjacent to monsters at season end
- Ruins cards: the next shape must overlap an open ruins space; if impossible
  (or none remain open), draw a 1×1 square of any terrain instead
- Solo ambush AI: each enemy raids from its printed corner along the edge in
  its arrow direction, moving one space inward per pass; unplaceable ambushes
  are disregarded
- Seasons 8/8/7/6, edict pairs AB → BC → CD → DA; Treetower and The Cauldrons
  count the map edge as filled
- Endgame: total score − the sum of the four edict corner numbers gives your
  rating on the queen's title table (Oblivious Inkdrinker → Legendary
  Cartographer)
- Undo for every turn action, keyboard shortcuts: **R** rotate, **F** mirror,
  **1/2** variant choice, **Enter** confirm, **U/Z** undo

## Develop

```sh
make test    # 35 gleeunit tests: rules, all 16 scoring cards, ambush AI, sim
make build   # gleam compile + minified bundle + single-file inliner
make open    # build, then open the file
npm run smoke  # jsdom smoke test: full autoplayed game incl. save/resume
```

### Layout

- `src/game/` — pure rules engine: `model` (grid/pieces), `cards` (all card
  data incl. solo corner numbers), `scoring` (16 edict functions), `deck`
  (seasons/ambush pile), `ambush` (solo raid algorithm), `game` (solo state
  machine with undo), `rng` (serializable LCG), `maps` (MapSpec config)
- `src/ui/` — Lustre views: `board` (map SVG + ghost), `panels` (card/edict/
  track/log views), `theme` (palette + glyphs), `snapshot` (save/resume JSON),
  `store` (localStorage FFI)
- `scripts/` — `bundle.mjs` (single-file HTML inliner), `smoke.mjs` (jsdom
  end-to-end)

The map is data-driven (`MapSpec`), so map-sheet variants are an entry each.
Scoring cards are pure functions over the grid; the 16 official edicts live
in `src/game/cards.gleam` with their texts and target numbers in one place
for easy verification against the physical cards.
