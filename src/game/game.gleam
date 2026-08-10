import game/ambush
import game/cards.{
  type AmbushCard, type DeckEntry, type EdictCard, type ExploreCard,
  type Variant, Variant, Explore, Ruins, Ambush,
}
import game/deck.{type EdictLetter}
import game/maps.{type MapSpec}
import game/model.{type Coord, type Grid, type Piece, type Terrain}
import game/scoring
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import game/rng.{type Rng}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Interactive phase of a turn.
pub type Phase {
  /// An explore card is revealed; the player picks one of its variants.
  Choosing(card: ExploreCard)
  /// A variant (or the 1x1 fallback) is being positioned on the map.
  Placing(draft: Draft)
  /// An ambush card was revealed and resolved; wait for acknowledgement.
  AmbushShown(card: AmbushCard, placed_at: Option(Coord))
  /// A season has just been scored; wait for acknowledgement.
  SeasonEnd(score: SeasonScore)
  /// Winter is over.
  GameOver(result: GameResult)
}

pub type Draft {
  Draft(
    card: ExploreCard,
    variant: Variant,
    /// Current orientation (rotation/flip applied, normalized).
    piece: Piece,
    /// Fallback mode: player could not draw any offered shape and draws a
    /// 1x1 square of any terrain anywhere instead (no coin).
    is_fallback: Bool,
  )
}

pub type SeasonScore {
  SeasonScore(
    season_name: String,
    edict1: #(EdictLetter, EdictCard, Int),
    edict2: #(EdictLetter, EdictCard, Int),
    coins: Int,
    monster: Int,
    total: Int,
  )
}

pub type GameResult {
  GameResult(total: Int, corner_sum: Int, rating: Int, title: String)
}

/// Everything that changes during play — this is what undo snapshots hold.
pub type Core {
  Core(
    grid: Grid,
    coins: Int,
    season_index: Int,
    time_total: Int,
    deck: List(DeckEntry),
    ambush_pile: List(AmbushCard),
    edicts: List(#(EdictLetter, EdictCard)),
    ruins_pending: Bool,
    phase: Phase,
    season_scores: List(SeasonScore),
    monster_loss: Int,
    rng: Rng,
    log: List(String),
  )
}

pub type Game {
  Game(map: MapSpec, seed_int: Int, core: Core, undo_stack: List(Core))
}

const undo_limit = 100

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

pub fn new_game(seed_int: Int, map: MapSpec) -> Game {
  let s0 = rng.new(seed_int)
  let #(edicts, s1) = deck.draw_edicts(s0)
  let #(ambush_pile, s2) = deck.new_ambush_pile(s1)
  let #(season_deck, ambush_pile2, _carried, s3) =
    deck.build_season_deck(s2, [], ambush_pile)
  let core =
    Core(
      grid: maps.new_grid(map),
      coins: 0,
      season_index: 0,
      time_total: 0,
      deck: season_deck,
      ambush_pile: ambush_pile2,
      edicts: edicts,
      ruins_pending: False,
      // Placeholder, overwritten by advance() below.
      phase: GameOver(GameResult(0, 0, 0, "")),
      season_scores: [],
      monster_loss: 0,
      rng: s3,
      log: [],
    )
  let core = log(core, "Spring begins.")
  Game(map: map, seed_int: seed_int, core: advance(core), undo_stack: [])
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

fn log(core: Core, message: String) -> Core {
  Core(..core, log: [message, ..core.log])
}

fn push(game: Game) -> Game {
  Game(..game, undo_stack: list.take([game.core, ..game.undo_stack], undo_limit))
}

pub fn undo(game: Game) -> Game {
  case game.undo_stack {
    [] -> game
    [core, ..rest] -> Game(..game, core: core, undo_stack: rest)
  }
}

pub fn season(core: Core) -> deck.SeasonInfo {
  deck.season_info(core.season_index)
}

pub fn edict_for_letter(
  core: Core,
  letter: EdictLetter,
) -> Result(EdictCard, Nil) {
  case list.find(core.edicts, fn(p) { p.0 == letter }) {
    Ok(#(_, card)) -> Ok(card)
    Error(Nil) -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Placement rules
// ---------------------------------------------------------------------------

/// Anchors where `piece` may legally be drawn, honoring the ruins
/// requirement: while a ruins card is pending and open ruins remain, the
/// shape must overlap at least one open ruins space (if that is possible).
pub fn effective_anchors(
  grid: Grid,
  piece: Piece,
  ruins_pending: Bool,
) -> List(Coord) {
  case ruins_pending && model.open_ruins_count(grid) > 0 {
    True ->
      model.legal_anchors(grid, piece)
      |> list.filter(fn(a) { model.covers_open_ruins(grid, piece, a) })
    False -> model.legal_anchors(grid, piece)
  }
}

/// Fallback is forced when no offered shape can be legally drawn (with the
/// ruins requirement active, that also covers: no open ruins are left, or no
/// shape can overlap one).
fn forced_fallback(core: Core, card: ExploreCard) -> Bool {
  list.all(card.variants, fn(v) {
    list.is_empty(effective_anchors(core.grid, v.piece, core.ruins_pending))
  })
}

// ---------------------------------------------------------------------------
// The draw pipeline
// ---------------------------------------------------------------------------

/// Reveal cards until something requires player input.
fn advance(core: Core) -> Core {
  case core.deck {
    [] -> core
    [entry, ..rest] -> {
      let core = Core(..core, deck: rest)
      case entry {
        Ruins(card) -> {
          let core = case core.ruins_pending {
            True ->
              log(
                core,
                card.name
                  <> " revealed again — the ruins requirement stays as one.",
              )
            False ->
              log(
                core,
                card.name
                  <> " revealed — the next shape must overlap a ruins space.",
              )
          }
          advance(core)
        }
        Ambush(card) -> {
          let before = model.claimed_mountains(core.grid)
          let #(grid2, anchor) = ambush.resolve(core.grid, card)
          let gained = model.claimed_mountains(grid2) - before
          let core = Core(..core, grid: grid2, coins: core.coins + gained)
          let core = case anchor {
            Some(_) -> log(core, card.name <> " — monsters raid the map!")
            None -> log(core, card.name <> " — no room; card disregarded.")
          }
          Core(..core, phase: AmbushShown(card, anchor))
        }
        Explore(card) -> {
          let core =
            Core(..core, time_total: core.time_total + card.time)
          let core = log(core, card.name <> " revealed.")
          case forced_fallback(core, card) {
            True ->
              Core(..core, phase: Placing(fallback_draft(card, core)))
            False -> Core(..core, phase: Choosing(card))
          }
        }
      }
    }
  }
}

fn fallback_draft(card: ExploreCard, _core: Core) -> Draft {
  Draft(
    card: card,
    variant: Variant(model.piece(["#"]), model.Forest, False),
    piece: model.piece(["#"]),
    is_fallback: True,
  )
}

// ---------------------------------------------------------------------------
// Player actions
// ---------------------------------------------------------------------------

/// Pick a variant of the revealed explore card and start positioning it.
pub fn pick_variant(game: Game, index: Int) -> Game {
  case game.core.phase {
    Choosing(card) ->
      case list_at(card.variants, index) {
        Error(Nil) -> game
        Ok(variant) -> {
          let game = push(game)
          let draft =
            Draft(
              card: card,
              variant: variant,
              piece: variant.piece,
              is_fallback: False,
            )
          Game(..game, core: Core(..game.core, phase: Placing(draft)))
        }
      }
    _ -> game
  }
}

fn list_at(l: List(a), i: Int) -> Result(a, Nil) {
  case l {
    [] -> Error(Nil)
    [x, ..rest] ->
      case i <= 0 {
        True -> Ok(x)
        False -> list_at(rest, i - 1)
      }
  }
}

pub fn rotate_draft(game: Game) -> Game {
  case game.core.phase {
    Placing(draft) ->
      Game(
        ..game,
        core: Core(
          ..game.core,
          phase: Placing(Draft(..draft, piece: model.rotate_cw(draft.piece))),
        ),
      )
    _ -> game
  }
}

pub fn flip_draft(game: Game) -> Game {
  case game.core.phase {
    Placing(draft) ->
      Game(
        ..game,
        core: Core(
          ..game.core,
          phase: Placing(
            Draft(..draft, piece: model.flip_horizontal(draft.piece)),
          ),
        ),
      )
    _ -> game
  }
}

/// In fallback mode the player may fill the single square with any terrain
/// type (except mountains).
pub fn set_fallback_terrain(game: Game, terrain: Terrain) -> Game {
  case game.core.phase {
    Placing(draft) ->
      case draft.is_fallback {
        False -> game
        True ->
          Game(
            ..game,
            core: Core(
              ..game.core,
              phase: Placing(
                Draft(..draft, variant: Variant(..draft.variant, terrain: terrain)),
              ),
            ),
          )
      }
    _ -> game
  }
}

/// Anchors the current draft may legally be placed at (for ghost rendering).
pub fn draft_anchors(game: Game) -> List(Coord) {
  case game.core.phase {
    Placing(draft) ->
      case draft.is_fallback {
        True -> model.legal_anchors(game.core.grid, draft.piece)
        False ->
          effective_anchors(game.core.grid, draft.piece, game.core.ruins_pending)
      }
    _ -> []
  }
}

/// Resolve which anchor to use when the player targets map cell `target`
/// with a shape: the legal anchor whose cells cover `target`, preferring the
/// exact cell, then the nearest by manhattan distance (row/column tiebreak).
/// This makes placement forgiving near map edges, mountains, and ruins — the
/// shape hugs the cursor instead of silently pinning its own first cell.
pub fn target_anchor(
  legal: List(Coord),
  piece: model.Piece,
  target: Coord,
) -> Option(Coord) {
  let covering =
    list.filter(legal, fn(a) { list.contains(model.piece_at(piece, a), target) })
  case covering {
    [] -> None
    [first, ..rest] ->
      Some(list.fold(rest, first, fn(best, a) {
        case coord_lt(coord_key(a, target), coord_key(best, target)) {
          True -> a
          False -> best
        }
      }))
  }
}

/// Where a click on map cell `target` would place the shape, if anywhere:
/// prefer the snapped covering anchor, but also accept `target` itself when
/// it is a legal anchor (some shapes don't occupy their own origin cell).
pub fn click_anchor(
  legal: List(Coord),
  piece: model.Piece,
  target: Coord,
) -> Option(Coord) {
  case target_anchor(legal, piece, target) {
    Some(a) -> Some(a)
    None ->
      case list.contains(legal, target) {
        True -> Some(target)
        False -> None
      }
  }
}

fn coord_key(a: Coord, target: Coord) -> #(Int, Int, Int) {
  let d =
    int.absolute_value(a.0 - target.0) + int.absolute_value(a.1 - target.1)
  #(d, a.0, a.1)
}

fn coord_lt(x: #(Int, Int, Int), y: #(Int, Int, Int)) -> Bool {
  x.0 < y.0
  || { x.0 == y.0 && { x.1 < y.1 || { x.1 == y.1 && x.2 < y.2 } } }
}

/// Draw the current draft shape at `anchor`.
pub fn place_at(game: Game, anchor: Coord) -> Game {
  case game.core.phase {
    Placing(draft) ->
      case list.contains(draft_anchors(game), anchor) {
        False -> game
        True -> {
          let game = push(game)
          let core = game.core
          let before = model.claimed_mountains(core.grid)
          let grid2 = model.place(core.grid, draft.piece, anchor, draft.variant.terrain)
          let mountain_coins = model.claimed_mountains(grid2) - before
          let shape_coin = case draft.variant.coin {
            True -> 1
            False -> 0
          }
          let core =
            Core(
              ..core,
              grid: grid2,
              coins: core.coins + mountain_coins + shape_coin,
              ruins_pending: False,
              log: placement_log(core, draft, mountain_coins, shape_coin),
            )
          after_turn(Game(..game, core: core))
        }
      }
    _ -> game
  }
}

fn placement_log(
  core: Core,
  draft: Draft,
  mountain_coins: Int,
  shape_coin: Int,
) -> List(String) {
  let base = case draft.is_fallback {
    True -> "No shape fit — you draw a single square of " <> terrain_name(draft.variant.terrain) <> "."
    False -> "You draw " <> draft.card.name <> " as " <> terrain_name(draft.variant.terrain) <> "."
  }
  let gains = case mountain_coins, shape_coin {
    0, 0 -> ""
    m, s -> " (+" <> int.to_string(m + s) <> " coin)"
  }
  [base <> gains, ..core.log]
}

pub fn terrain_name(t: Terrain) -> String {
  case t {
    model.Forest -> "forest"
    model.Village -> "village"
    model.Farm -> "farm"
    model.Water -> "water"
    model.Monster -> "monster"
    model.Mountain -> "mountain"
  }
}

/// After every draw phase, check whether the season's time is up.
fn after_turn(game: Game) -> Game {
  let info = season(game.core)
  case game.core.time_total >= info.threshold {
    False -> Game(..game, core: advance(game.core))
    True -> {
      let score = score_season(game.core, info)
      let core =
        Core(
          ..game.core,
          phase: SeasonEnd(score),
          season_scores: [score, ..game.core.season_scores],
          monster_loss: game.core.monster_loss + score.monster,
        )
      Game(..game, core: log(core, info.name <> " ends."))
    }
  }
}

fn score_season(core: Core, info: deck.SeasonInfo) -> SeasonScore {
  let #(l1, l2) = info.edicts
  let assert Ok(e1) = edict_for_letter(core, l1)
  let assert Ok(e2) = edict_for_letter(core, l2)
  let s1 = scoring.score(e1.kind, core.grid)
  let s2 = scoring.score(e2.kind, core.grid)
  let monster = scoring.monster_penalty(core.grid)
  SeasonScore(
    season_name: info.name,
    edict1: #(l1, e1, s1),
    edict2: #(l2, e2, s2),
    coins: core.coins,
    monster: monster,
    total: s1 + s2 + core.coins - monster,
  )
}

/// Acknowledge an ambush reveal and continue the season.
pub fn confirm_ambush(game: Game) -> Game {
  case game.core.phase {
    AmbushShown(_, _) -> {
      let game = push(game)
      Game(..game, core: advance(game.core))
    }
    _ -> game
  }
}

/// Acknowledge the end of a season and move on (or finish the game).
pub fn confirm_season_end(game: Game) -> Game {
  case game.core.phase {
    SeasonEnd(_) -> {
      let game = push(game)
      case game.core.season_index >= deck.season_count - 1 {
        True -> Game(..game, core: game_over(game.core))
        False -> Game(..game, core: next_season(game.core))
      }
    }
    _ -> game
  }
}

fn next_season(core: Core) -> Core {
  let carried = deck.undrawn_ambushes(core.deck)
  let #(season_deck, pile2, _carried, s2) =
    deck.build_season_deck(core.rng, carried, core.ambush_pile)
  let info = deck.season_info(core.season_index + 1)
  let core =
    Core(
      ..core,
      season_index: core.season_index + 1,
      time_total: 0,
      deck: season_deck,
      ambush_pile: pile2,
      ruins_pending: False,
      rng: s2,
    )
  let core = log(core, info.name <> " begins.")
  advance(core)
}

fn game_over(core: Core) -> Core {
  let total =
    list.fold(core.season_scores, 0, fn(acc, s) { acc + s.total })
  let corner_sum =
    list.fold(core.edicts, 0, fn(acc, p) { acc + p.1.corner })
  let rating = total - corner_sum
  let result = GameResult(total, corner_sum, rating, title_for(rating))
  log(
    Core(..core, phase: GameOver(result)),
    "Winter ends. Final score " <> int.to_string(total) <> ", rating "
      <> int.to_string(rating)
      <> " — "
      <> title_for(rating)
      <> ".",
  )
}

/// The queen's title for a solo rating (highest threshold met or surpassed).
pub fn title_for(rating: Int) -> String {
  case True {
    _ if rating >= 30 -> "Legendary Cartographer"
    _ if rating >= 20 -> "Master Mapsmith"
    _ if rating >= 10 -> "Journeyman Topographer"
    _ if rating >= 0 -> "Apprentice Surveyor"
    _ if rating >= -5 -> "Amateur Assessor"
    _ if rating >= -10 -> "Inept Assistant"
    _ if rating >= -20 -> "Dimwitted Doodler"
    _ -> "Oblivious Inkdrinker"
  }
}

/// Total score so far (sum of completed season totals).
pub fn score_so_far(core: Core) -> Int {
  list.fold(core.season_scores, 0, fn(acc, s) { acc + s.total })
}

// ---------------------------------------------------------------------------
// Restoring a saved game
// ---------------------------------------------------------------------------

/// What the game was waiting on when it was saved.
pub type ResumePhase {
  /// An explore card was revealed and awaiting a placement choice.
  ResumeChoosing(card_id: String)
  /// An ambush had been resolved; continue with the next draw.
  ResumeAdvance
  /// A season had just been scored; show its tally again.
  ResumeSeasonEnd
  /// The game was over.
  ResumeOver
}

/// Rebuild a Game from a fully restored Core and a phase hint.
/// The undo stack always starts empty after a reload.
pub fn rebuilt(map: MapSpec, seed_int: Int, core: Core, hint: ResumePhase) -> Game {
  let phase = case hint {
    ResumeChoosing(card_id) ->
      case cards.explore_by_id(card_id) {
        Ok(card) -> Choosing(card)
        Error(Nil) -> core.phase
      }
    ResumeAdvance -> advance(core).phase
    ResumeSeasonEnd ->
      case core.season_scores {
        [score, ..] -> SeasonEnd(score)
        [] -> core.phase
      }
    ResumeOver -> {
      let total = score_so_far(core)
      let corner_sum =
        list.fold(core.edicts, 0, fn(acc, p) { acc + p.1.corner })
      let rating = total - corner_sum
      GameOver(GameResult(total, corner_sum, rating, title_for(rating)))
    }
  }
  Game(map: map, seed_int: seed_int, core: Core(..core, phase: phase), undo_stack: [])
}
