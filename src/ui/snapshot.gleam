//// Save/load support: serializes a full in-progress Game (including the RNG
//// state) plus the personal records (best run, history) to/from JSON so a
//// solo expedition survives closing the browser tab.

import game/cards.{type EdictCard}
import game/deck.{type EdictLetter}
import game/game.{
  type Game, type GameResult, type SeasonScore, GameResult, SeasonScore,
  Choosing, Placing, AmbushShown, SeasonEnd, GameOver,
}
import game/maps
import game/model.{type Cell, type Coord, type Grid, type Terrain} as model
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

pub type RunLog {
  RunLog(seed: Int, score: Int, rating: Int, title: String)
}

pub type SavedData {
  SavedData(best: Option(RunLog), runs: List(RunLog), active: Option(Game))
}

pub const empty_save = SavedData(best: None, runs: [], active: None)

/// How many completed runs we remember for the title screen.
const max_runs = 12

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

pub fn encode_save(data: SavedData) -> String {
  json.object([
    #("v", json.int(1)),
    #("best", json.nullable(data.best, encode_run)),
    #("runs", json.array(data.runs, encode_run)),
    #(
      "active",
      json.nullable(data.active, fn(g) {
        json.object(snapshot_fields(g))
      }),
    ),
  ])
  |> json.to_string
}

fn encode_run(run: RunLog) -> json.Json {
  json.object([
    #("seed", json.int(run.seed)),
    #("score", json.int(run.score)),
    #("rating", json.int(run.rating)),
    #("title", json.string(run.title)),
  ])
}

fn snapshot_fields(g: Game) -> List(#(String, json.Json)) {
  let core = g.core
  [
    #("seed", json.int(g.seed_int)),
    #("size", json.int(g.map.size)),
    #("grid", json.string(encode_grid(core.grid))),
    #("coins", json.int(core.coins)),
    #("season", json.int(core.season_index)),
    #("time", json.int(core.time_total)),
    #("deck", json.array(core.deck, fn(e) { json.string(cards.entry_id(e)) })),
    #(
      "ambush_pile",
      json.array(core.ambush_pile, fn(a) { json.string(a.id) }),
    ),
    #(
      "edicts",
      json.array(core.edicts, fn(p) {
        json.object([
          #("l", json.string(deck.letter_id(p.0))),
          #("id", json.string(cards.edict_kind_id(p.1.kind))),
        ])
      }),
    ),
    #("ruins_pending", json.bool(core.ruins_pending)),
    #("phase", json.string(encode_phase(core))),
    #("scores", json.array(list.reverse(core.season_scores), encode_score)),
    #("monster_loss", json.int(core.monster_loss)),
    #("rng", json.int(core.rng)),
  ]
}

fn encode_score(s: SeasonScore) -> json.Json {
  json.object([
    #("season", json.string(s.season_name)),
    #("e1l", json.string(deck.letter_id(s.edict1.0))),
    #("e1id", json.string(cards.edict_kind_id(s.edict1.1.kind))),
    #("e1s", json.int(s.edict1.2)),
    #("e2l", json.string(deck.letter_id(s.edict2.0))),
    #("e2id", json.string(cards.edict_kind_id(s.edict2.1.kind))),
    #("e2s", json.int(s.edict2.2)),
    #("coins", json.int(s.coins)),
    #("monster", json.int(s.monster)),
    #("total", json.int(s.total)),
  ])
}

fn encode_phase(core: game.Core) -> String {
  case core.phase {
    Choosing(card) -> "choosing:" <> card.id
    Placing(draft) -> "choosing:" <> draft.card.id
    AmbushShown(_, _) -> "advance"
    SeasonEnd(_) -> "season-end"
    GameOver(_) -> "over"
  }
}

// grid serialization ---------------------------------------------------------

fn terrain_char(t: Terrain) -> String {
  case t {
    model.Forest -> "f"
    model.Village -> "v"
    model.Farm -> "a"
    model.Water -> "w"
    model.Monster -> "m"
    model.Mountain -> "#"
  }
}

fn encode_grid(grid: Grid) -> String {
  // Two 121-char channels concatenated: terrains then open-ruins flags.
  let size = list.length(grid)
  let coords = model.ints(0, size - 1)
  let terrains =
    list.map(coords, fn(r) {
      list.map(coords, fn(c) {
        case model.grid_at(grid, r, c) {
          Ok(model.Empty(_)) -> "."
          Ok(model.Filled(t, _)) -> terrain_char(t)
          Error(Nil) -> "."
        }
      })
      |> string.join("")
    })
    |> string.join("")
  let ruins =
    list.map(coords, fn(r) {
      list.map(coords, fn(c) {
        case model.grid_at(grid, r, c) {
          Ok(model.Empty(True)) | Ok(model.Filled(_, True)) -> "1"
          _ -> "0"
        }
      })
      |> string.join("")
    })
    |> string.join("")
  terrains <> ruins
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

pub fn decode_save(raw: String) -> SavedData {
  case raw {
    "" -> empty_save
    _ -> result.unwrap(json.parse(raw, saved_decoder()), empty_save)
  }
}

fn saved_decoder() -> decode.Decoder(SavedData) {
  use best <- decode.field("best", decode.optional(run_decoder()))
  use runs <- decode.field("runs", decode.list(run_decoder()))
  use active <- decode.field("active", decode.optional(game_decoder()))
  let active_game = case active {
    Some(Ok(g)) -> Some(g)
    _ -> None
  }
  decode.success(SavedData(best: best, runs: list.take(runs, max_runs), active: active_game))
}

fn run_decoder() -> decode.Decoder(RunLog) {
  use seed <- decode.field("seed", decode.int)
  use score <- decode.field("score", decode.int)
  use rating <- decode.field("rating", decode.int)
  use title <- decode.field("title", decode.string)
  decode.success(RunLog(seed, score, rating, title))
}

/// A game snapshot either fully decodes or is dropped (decode.success can't
/// fail, so we wrap in a Result layer).
fn game_decoder() -> decode.Decoder(Result(Game, Nil)) {
  use seed <- decode.field("seed", decode.int)
  use size <- decode.field("size", decode.int)
  use grid_str <- decode.field("grid", decode.string)
  use coins <- decode.field("coins", decode.int)
  use season <- decode.field("season", decode.int)
  use time <- decode.field("time", decode.int)
  use deck_ids <- decode.field("deck", decode.list(decode.string))
  use pile_ids <- decode.field("ambush_pile", decode.list(decode.string))
  use edict_pairs <- decode.field("edicts", decode.list(edict_pair_decoder()))
  use ruins_pending <- decode.field("ruins_pending", decode.bool)
  use phase_str <- decode.field("phase", decode.string)
  use scores <- decode.field("scores", decode.list(score_decoder()))
  use monster_loss <- decode.field("monster_loss", decode.int)
  use rng_state <- decode.field("rng", decode.int)
  decode.success(rebuild_game(
    seed,
    size,
    grid_str,
    coins,
    season,
    time,
    deck_ids,
    pile_ids,
    edict_pairs,
    ruins_pending,
    phase_str,
    scores,
    monster_loss,
    rng_state,
  ))
}

fn edict_pair_decoder() -> decode.Decoder(#(String, String)) {
  use l <- decode.field("l", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(#(l, id))
}

fn score_decoder() -> decode.Decoder(
  #(String, String, String, Int, String, String, Int, Int, Int, Int),
) {
  use season <- decode.field("season", decode.string)
  use e1l <- decode.field("e1l", decode.string)
  use e1id <- decode.field("e1id", decode.string)
  use e1s <- decode.field("e1s", decode.int)
  use e2l <- decode.field("e2l", decode.string)
  use e2id <- decode.field("e2id", decode.string)
  use e2s <- decode.field("e2s", decode.int)
  use coins <- decode.field("coins", decode.int)
  use monster <- decode.field("monster", decode.int)
  use total <- decode.field("total", decode.int)
  decode.success(#(season, e1l, e1id, e1s, e2l, e2id, e2s, coins, monster, total))
}

// ---------------------------------------------------------------------------
// Rebuild
// ---------------------------------------------------------------------------

fn rebuild_game(
  seed: Int,
  size: Int,
  grid_str: String,
  coins: Int,
  season: Int,
  time: Int,
  deck_ids: List(String),
  pile_ids: List(String),
  edict_pairs: List(#(String, String)),
  ruins_pending: Bool,
  phase_str: String,
  scores: List(
    #(String, String, String, Int, String, String, Int, Int, Int, Int),
  ),
  monster_loss: Int,
  rng_state: Int,
) -> Result(Game, Nil) {
  use map <- result.try(case maps.wilderness_a() {
    m if m.size == size -> Ok(m)
    _ -> Error(Nil)
  })
  use grid <- result.try(decode_grid(grid_str, map))
  use season_deck <- result.try(map_try(deck_ids, cards.entry_by_id))
  use ambush_pile <- result.try(map_try(pile_ids, cards.ambush_by_id))
  use edicts <- result.try(map_try(edict_pairs, decode_edict_pair))
  use season_scores <- result.try(map_try(scores, decode_score))
  use hint <- result.try(decode_phase_hint(phase_str))
  let core =
    game.Core(
      grid: grid,
      coins: coins,
      season_index: clamp(season, 0, deck.season_count - 1),
      time_total: time,
      deck: season_deck,
      ambush_pile: ambush_pile,
      edicts: edicts,
      ruins_pending: ruins_pending,
      phase: GameOver(GameResult(0, 0, 0, "")),
      // scores are stored oldest-first; the core keeps newest-first
      season_scores: list.reverse(season_scores),
      monster_loss: monster_loss,
      rng: rng_state,
      log: ["Game restored."],
    )
  Ok(game.rebuilt(map, seed, core, hint))
}

fn clamp(x: Int, lo: Int, hi: Int) -> Int {
  int.max(lo, int.min(hi, x))
}

fn map_try(l: List(a), f: fn(a) -> Result(b, Nil)) -> Result(List(b), Nil) {
  case l {
    [] -> Ok([])
    [x, ..rest] ->
      case f(x) {
        Error(Nil) -> Error(Nil)
        Ok(y) ->
          case map_try(rest, f) {
            Error(Nil) -> Error(Nil)
            Ok(ys) -> Ok([y, ..ys])
          }
      }
  }
}

fn decode_edict_pair(pair: #(String, String)) -> Result(
  #(EdictLetter, EdictCard),
  Nil,
) {
  use l <- result.try(deck.letter_from_id(pair.0))
  use card <- result.try(cards.edict_by_id(pair.1))
  Ok(#(l, card))
}

fn decode_score(
  s: #(String, String, String, Int, String, String, Int, Int, Int, Int),
) -> Result(SeasonScore, Nil) {
  let #(season, e1l, e1id, e1s, e2l, e2id, e2s, coins, monster, total) = s
  use l1 <- result.try(deck.letter_from_id(e1l))
  use c1 <- result.try(cards.edict_by_id(e1id))
  use l2 <- result.try(deck.letter_from_id(e2l))
  use c2 <- result.try(cards.edict_by_id(e2id))
  Ok(SeasonScore(
    season_name: season,
    edict1: #(l1, c1, e1s),
    edict2: #(l2, c2, e2s),
    coins: coins,
    monster: monster,
    total: total,
  ))
}

fn decode_phase_hint(s: String) -> Result(game.ResumePhase, Nil) {
  case s {
    "advance" -> Ok(game.ResumeAdvance)
    "season-end" -> Ok(game.ResumeSeasonEnd)
    "over" -> Ok(game.ResumeOver)
    "choosing:" <> card_id -> Ok(game.ResumeChoosing(card_id))
    _ -> Error(Nil)
  }
}

fn decode_grid(s: String, map: maps.MapSpec) -> Result(Grid, Nil) {
  let size = map.size
  let expected = size * size
  case string.length(s) == expected * 2 {
    False -> Error(Nil)
    True -> {
      let terrains = string.slice(s, 0, expected)
      let ruins = string.slice(s, expected, expected)
      let tchars = string.to_graphemes(terrains)
      let rchars = string.to_graphemes(ruins)
      let cells =
        list.index_map(tchars, fn(tch, i) {
          let ruin = list_nth(rchars, i) == "1"
          case terrain_from_char(tch) {
            Error(Nil) -> Error(Nil)
            Ok(model.Empty(_)) -> Ok(model.Empty(ruin))
            Ok(model.Filled(t, _)) -> Ok(model.Filled(t, ruin))
          }
        })
      use parsed <- result.try(all_ok(cells, []))
      // sanity: preprinted map features must still be present (mountains
      // can't be overwritten; ruins flags persist under drawn shapes)
      let mountains_ok =
        list.all(preprinted_mountains(map), fn(c) {
          case list_nth_cells(parsed, c.0, c.1, size) {
            model.Filled(model.Mountain, _) -> True
            _ -> False
          }
        })
      let ruins_ok =
        list.all(map.ruins, fn(c) {
          case list_nth_cells(parsed, c.0, c.1, size) {
            model.Empty(True) | model.Filled(_, True) -> True
            _ -> False
          }
        })
      case mountains_ok && ruins_ok {
        False -> Error(Nil)
        True -> Ok(to_rows(parsed, size))
      }
    }
  }
}

fn all_ok(l: List(Result(a, Nil)), acc: List(a)) -> Result(List(a), Nil) {
  case l {
    [] -> Ok(list.reverse(acc))
    [Ok(x), ..rest] -> all_ok(rest, [x, ..acc])
    [Error(Nil), ..] -> Error(Nil)
  }
}

fn list_nth(l: List(String), i: Int) -> String {
  case l {
    [] -> ""
    [x, ..rest] ->
      case i <= 0 {
        True -> x
        False -> list_nth(rest, i - 1)
      }
  }
}

fn list_nth_cells(l: List(Cell), r: Int, c: Int, size: Int) -> Cell {
  let idx = r * size + c
  case nth_cell(l, idx) {
    Some(cell) -> cell
    None -> model.Empty(False)
  }
}

/// Chunk a flat row-major cell list back into rows.
fn to_rows(cells: List(Cell), size: Int) -> Grid {
  case cells {
    [] -> []
    _ -> [list.take(cells, size), ..to_rows(list.drop(cells, size), size)]
  }
}

fn nth_cell(l: List(Cell), i: Int) -> Option(Cell) {
  case l {
    [] -> None
    [x, ..rest] ->
      case i <= 0 {
        True -> Some(x)
        False -> nth_cell(rest, i - 1)
      }
  }
}

fn preprinted_mountains(map: maps.MapSpec) -> List(Coord) {
  map.mountains
}

fn terrain_from_char(ch: String) -> Result(Cell, Nil) {
  case ch {
    "." -> Ok(model.Empty(False))
    "f" -> Ok(model.Filled(model.Forest, False))
    "v" -> Ok(model.Filled(model.Village, False))
    "a" -> Ok(model.Filled(model.Farm, False))
    "w" -> Ok(model.Filled(model.Water, False))
    "m" -> Ok(model.Filled(model.Monster, False))
    "#" -> Ok(model.Filled(model.Mountain, False))
    _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Records bookkeeping
// ---------------------------------------------------------------------------

/// A finished game becomes a RunLog entry; returns the updated records and
/// the new run (newest first, capped).
pub fn record_run(
  data: SavedData,
  seed: Int,
  result: GameResult,
) -> SavedData {
  let run = RunLog(seed, result.total, result.rating, result.title)
  let better = case data.best {
    None -> Some(run)
    Some(b) ->
      case run.score > b.score {
        True -> Some(run)
        False -> data.best
      }
  }
  SavedData(best: better, runs: list.take([run, ..data.runs], max_runs), active: None)
}

pub fn with_active(data: SavedData, game: Option(Game)) -> SavedData {
  SavedData(..data, active: game)
}

// ---------------------------------------------------------------------------
// Debug helpers (used by tests when a decode fails)
// ---------------------------------------------------------------------------

/// Human-readable failure stage when decoding an active game, for tests.
pub fn debug_active_stage(raw: String) -> String {
  case json.parse(raw, decode.optional(game_decoder()) |> fn(d) {
    decode.field("active", d, decode.success)
  }) {
    Error(e) -> "json/decoder error: " <> string.inspect(e)
    Ok(None) -> "active == None"
    Ok(Some(Error(Nil))) -> "rebuild failed"
    Ok(Some(Ok(_))) -> "ok"
  }
}
