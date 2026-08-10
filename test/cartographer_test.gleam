import game/cards
import game/deck
import game/game.{
  type Game, Choosing, Placing, AmbushShown, SeasonEnd, GameOver,
}
import game/maps
import game/model.{type Coord, type Grid, type Terrain} as model
import game/scoring
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

fn wilderness() -> Grid {
  maps.new_grid(maps.wilderness_a())
}

/// Fill cells with a terrain (preserves ruins flags, like player drawing).
fn fill(grid: Grid, coords: List(Coord), t: Terrain) -> Grid {
  list.fold(coords, grid, fn(g, c) { model.place(g, [#(0, 0)], c, t) })
}

fn fill_piece(grid: Grid, rows: List(String), anchor: Coord, t: Terrain) -> Grid {
  model.place(grid, model.piece(rows), anchor, t)
}

// ---------------------------------------------------------------------------
// model: pieces & placement
// ---------------------------------------------------------------------------

pub fn rotate_four_times_identity_test() {
  let p = model.piece(["#.", "##", "#."])
  let p4 = p |> model.rotate_cw |> model.rotate_cw |> model.rotate_cw |> model.rotate_cw
  should.equal(p4, p)
}

pub fn flip_twice_identity_test() {
  let p = model.piece(["..#", ".##", "##."])
  should.equal(p |> model.flip_horizontal |> model.flip_horizontal, p)
}

pub fn rotate_normalizes_to_origin_test() {
  let p = model.piece(["#"])
  should.equal(model.rotate_cw(p), [#(0, 0)])
  let s = model.piece(["##", ".#"])
  // min row/col are always 0 after a transform
  let r = model.rotate_cw(s)
  should.equal(0, list.fold(list.map(r, fn(c) { c.0 }), 9, int.min))
  should.equal(0, list.fold(list.map(r, fn(c) { c.1 }), 9, int.min))
}

pub fn can_place_test() {
  let g = wilderness()
  let p = model.piece(["##", "#."])
  // inside, empty
  should.be_true(model.can_place(g, p, #(0, 0)))
  // off the edge
  should.be_false(model.can_place(g, p, #(10, 10)))
  // overlapping mountain B4 (1,3)
  should.be_false(model.can_place(g, p, #(1, 3)))
  // covering open ruins B6 (1,5) counts as empty
  should.be_true(model.can_place(g, p, #(1, 5)))
}

pub fn mountain_claim_test() {
  let g = wilderness()
  should.equal(model.claimed_mountains(g), 0)
  let g2 = fill(g, [#(4, 5), #(6, 5), #(5, 4), #(5, 6)], model.Farm)
  should.equal(model.claimed_mountains(g2), 1)
}

// ---------------------------------------------------------------------------
// scoring cards
// ---------------------------------------------------------------------------

pub fn sentinel_wood_test() {
  let g =
    wilderness()
    |> fill([#(0, 0), #(0, 5), #(10, 10)], model.Forest)
    |> fill([#(5, 4)], model.Forest)
  should.equal(scoring.score(cards.SentinelWood, g), 3)
}

pub fn greenbough_test() {
  let g =
    wilderness()
    |> fill([#(0, 0), #(0, 5), #(3, 3)], model.Forest)
  // rows {0,3} = 2, cols {0,5,3} = 3
  should.equal(scoring.score(cards.Greenbough, g), 5)
}

pub fn treetower_test() {
  let g =
    wilderness()
    |> fill([#(0, 0)], model.Forest)
    |> fill([#(0, 1), #(1, 0)], model.Farm)
    |> fill([#(5, 4)], model.Forest)
  // the corner forest is surrounded by filled spaces + the map edge
  should.equal(scoring.score(cards.Treetower, g), 1)
}

pub fn stoneside_forest_test() {
  let g =
    wilderness()
    // one forest cluster touching mountains F6 (5,5) and I3 (8,2)
    |> fill(
      [#(4, 5), #(4, 4), #(5, 4), #(6, 4), #(7, 4), #(7, 3), #(7, 2)],
      model.Forest,
    )
    // a second forest cluster touching only F6
    |> fill([#(5, 6), #(4, 6)], model.Forest)
  should.equal(scoring.score(cards.StonesideForest, g), 6)
}

pub fn canal_lake_test() {
  let g =
    wilderness()
    |> fill([#(4, 4)], model.Water)
    |> fill([#(4, 5), #(7, 7)], model.Farm)
  should.equal(scoring.score(cards.CanalLake, g), 2)
}

pub fn golden_granary_test() {
  let g =
    wilderness()
    // water adjacent to the ruins at B6 (1,5)
    |> fill([#(1, 4)], model.Water)
    // farm drawn on the ruins at C2 (2,1)
    |> fill([#(2, 1)], model.Farm)
    // a farm elsewhere scores nothing
    |> fill([#(9, 9)], model.Farm)
  should.equal(scoring.score(cards.GoldenGranary, g), 4)
}

pub fn mages_valley_test() {
  let g =
    wilderness()
    |> fill([#(4, 5), #(6, 5)], model.Water)
    |> fill([#(5, 4), #(7, 7)], model.Farm)
  // two waters by the F6 mountain => 4, one farm by it => 1
  should.equal(scoring.score(cards.MagesValley, g), 5)
}

pub fn shoreside_expanse_test() {
  let g =
    wilderness()
    // interior farm cluster, no adjacent water => 3
    |> fill([#(4, 3), #(4, 4)], model.Farm)
    // interior water cluster, no adjacent farm => 3
    |> fill([#(7, 7), #(7, 8)], model.Water)
    // water on the edge never scores => 0
    |> fill([#(10, 10)], model.Water)
  should.equal(scoring.score(cards.ShoresideExpanse, g), 6)
}

pub fn wildholds_test() {
  let g =
    wilderness()
    |> fill(
      [#(3, 3), #(3, 4), #(4, 3), #(4, 4), #(3, 5), #(3, 6)],
      model.Village,
    )
    |> fill([#(8, 8), #(8, 9)], model.Village)
  should.equal(scoring.score(cards.Wildholds, g), 8)
}

pub fn great_city_test() {
  let g =
    wilderness()
    // size-5 village cluster adjacent to the F6 mountain => ineligible
    |> fill(
      [#(4, 5), #(4, 6), #(4, 7), #(3, 7), #(2, 7)],
      model.Village,
    )
    // size-3 cluster away from mountains
    |> fill([#(8, 0), #(9, 0), #(10, 0)], model.Village)
  should.equal(scoring.score(cards.GreatCity, g), 3)
}

pub fn shieldgate_test() {
  let g =
    wilderness()
    |> fill([#(0, 0), #(0, 1), #(0, 2), #(0, 3), #(0, 4), #(0, 5)], model.Village)
    |> fill([#(3, 3), #(3, 4), #(4, 3), #(4, 4)], model.Village)
    |> fill([#(8, 8), #(8, 9), #(9, 8), #(9, 9)], model.Village)
  // sizes 6, 4, 4 => second largest 4 => 8
  should.equal(scoring.score(cards.Shieldgate, g), 8)
}

pub fn shieldgate_tie_test() {
  let g =
    wilderness()
    |> fill([#(0, 0), #(0, 1), #(0, 2), #(1, 0), #(1, 1)], model.Village)
    |> fill([#(5, 7), #(5, 8), #(6, 7), #(6, 8), #(6, 9)], model.Village)
  // two tied size-5 clusters: score one of the largest => 10
  should.equal(scoring.score(cards.Shieldgate, g), 10)
}

pub fn greengold_plains_test() {
  let g =
    wilderness()
    |> fill([#(3, 3), #(3, 4)], model.Village)
    |> fill([#(3, 2)], model.Forest)
    |> fill([#(2, 3)], model.Water)
    |> fill([#(4, 3)], model.Farm)
    // isolated second village cluster => 0
    |> fill([#(8, 8)], model.Village)
  should.equal(scoring.score(cards.GreengoldPlains, g), 3)
}

pub fn borderlands_test() {
  let row3 = list.map(model.ints(0, 10), fn(c) { #(3, c) })
  let col0 = list.map(model.ints(0, 10), fn(r) { #(r, 0) })
  let g = wilderness() |> fill(row3, model.Forest) |> fill(col0, model.Water)
  should.equal(scoring.score(cards.Borderlands, g), 12)
}

pub fn broken_road_test() {
  let diagonal = list.map(model.ints(0, 10), fn(r) { #(r, r) })
  let g =
    wilderness()
    |> fill(diagonal, model.Farm)
    // incomplete d=3 diagonal scores nothing
    |> fill([#(3, 0), #(4, 1), #(5, 2)], model.Water)
  should.equal(scoring.score(cards.BrokenRoad, g), 3)
}

pub fn lost_barony_test() {
  let g =
    wilderness()
    |> fill_piece(["###", "###", "###"], #(4, 0), model.Farm)
    |> fill_piece(["##", "##"], #(7, 7), model.Forest)
  should.equal(scoring.score(cards.LostBarony, g), 9)
}

pub fn cauldrons_test() {
  let g =
    wilderness()
    // (0,0) empty in the corner: neighbours (0,1),(1,0) filled + edge
    |> fill([#(0, 1), #(1, 0)], model.Farm)
    // (4,5) empty: surrounded by villages and the F6 mountain
    |> fill([#(3, 5), #(4, 4), #(4, 6)], model.Village)
  should.equal(scoring.score(cards.Cauldrons, g), 2)
}

pub fn monster_penalty_test() {
  let g =
    wilderness()
    |> fill([#(5, 4), #(5, 6)], model.Monster)
  // (5,4) neighbours: (4,4),(6,4),(5,3) empty, (5,5) mountain
  // (5,6) neighbours: (4,6),(6,6),(5,7) empty
  should.equal(scoring.monster_penalty(g), 6)
}

pub fn title_for_test() {
  should.equal(game.title_for(35), "Legendary Cartographer")
  should.equal(game.title_for(20), "Master Mapsmith")
  should.equal(game.title_for(0), "Apprentice Surveyor")
  should.equal(game.title_for(-4), "Amateur Assessor")
  should.equal(game.title_for(-5), "Amateur Assessor")
  should.equal(game.title_for(-6), "Inept Assistant")
  should.equal(game.title_for(-100), "Oblivious Inkdrinker")
}

// ---------------------------------------------------------------------------
// ruins constraint
// ---------------------------------------------------------------------------

pub fn effective_anchors_ruins_test() {
  let g = wilderness()
  let domino = model.piece(["##"])
  let anchors = game.effective_anchors(g, domino, True)
  // (1,4) covers the ruins at (1,5)
  should.be_true(list.contains(anchors, #(1, 4)))
  // (0,0) does not cover any ruins -> illegal while ruins is pending
  should.be_false(list.contains(anchors, #(0, 0)))
  // without the pending ruins requirement anywhere legal is fine
  let free = game.effective_anchors(g, domino, False)
  should.be_true(list.contains(free, #(0, 0)))
}

// ---------------------------------------------------------------------------
// ambush solo placement
// ---------------------------------------------------------------------------

pub fn gnoll_attack_top_left_test() {
  let g = wilderness()
  let assert [gnoll, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "gnoll-attack" })
  let #(g2, anchor) = game_ambush(g, gnoll)
  should.equal(anchor, Some(#(0, 0)))
  should.equal(model.grid_at(g2, 0, 0), Ok(model.Filled(model.Monster, False)))
  // (2,1) is a pre-printed ruins space: the monster covers it (legal) and
  // the ruins flag is preserved.
  should.equal(model.grid_at(g2, 2, 1), Ok(model.Filled(model.Monster, True)))
}

pub fn gnoll_attack_slides_down_test() {
  // block (0,0): scan proceeds down the left edge -> anchor (1,0)
  let g = wilderness() |> fill([#(0, 0)], model.Forest)
  let assert [gnoll, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "gnoll-attack" })
  let #(_, anchor) = game_ambush(g, gnoll)
  should.equal(anchor, Some(#(1, 0)))
}

pub fn bugbear_assault_top_right_test() {
  let g = wilderness()
  let assert [bugbear, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "bugbear-assault" })
  let #(_, anchor) = game_ambush(g, bugbear)
  // shape is 2x3 (max_c = 8); scan starts at the top-right corner
  should.equal(anchor, Some(#(0, 8)))
}

pub fn kobold_raid_bottom_left_test() {
  let g = wilderness()
  let assert [kobold, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "kobold-raid" })
  let #(_, anchor) = game_ambush(g, kobold)
  // shape is 3x2 (max_r = 8); scan starts at the bottom-left corner
  should.equal(anchor, Some(#(8, 0)))
}

pub fn goblin_onslaught_bottom_right_test() {
  let g = wilderness()
  let assert [goblin, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "goblin-onslaught" })
  let #(_, anchor) = game_ambush(g, goblin)
  // 3x3 diagonal from the bottom-right corner; max_r = max_c = 8
  should.equal(anchor, Some(#(8, 8)))
}

pub fn ambush_disregarded_when_no_room_test() {
  // a cell on the map can't host a 3x3 diagonal anywhere if... build full grid
  let full =
    list.fold(model.all_coords(11), wilderness(), fn(g, c) {
      case model.is_filled(case_ok(model.grid_at(g, c.0, c.1))) {
        True -> g
        False -> model.place(g, [#(0, 0)], c, model.Forest)
      }
    })
  let assert [goblin, ..] =
    cards.ambush_cards() |> list.filter(fn(a) { a.id == "goblin-onslaught" })
  let #(g2, anchor) = game_ambush(full, goblin)
  should.equal(anchor, None)
  should.equal(g2, full)
}

fn case_ok(r: Result(model.Cell, Nil)) -> model.Cell {
  case r {
    Ok(c) -> c
    Error(Nil) -> model.Empty(False)
  }
}

import game/ambush

fn game_ambush(g: Grid, card: cards.AmbushCard) -> #(Grid, option.Option(Coord)) {
  ambush.resolve(g, card)
}

// ---------------------------------------------------------------------------
// deck machinery
// ---------------------------------------------------------------------------

pub fn new_game_setup_test() {
  let g = game.new_game(42, maps.wilderness_a())
  // four edicts, one per group, assigned to letters A-D
  should.equal(list.length(g.core.edicts), 4)
  let groups = list.map(g.core.edicts, fn(p) { p.1.group })
  should.equal(list.unique(groups) |> list.length, 4)
  // the first season always pauses on a card (Choosing / fallback / ambush)
  case g.core.phase {
    Choosing(_) -> Nil
    Placing(_) -> Nil
    AmbushShown(_, _) -> Nil
    SeasonEnd(_) -> should.fail()
    GameOver(_) -> should.fail()
  }
  // some time has elapsed for non-ambush/ruins reveals
  case g.core.phase {
    Choosing(_) -> should.be_true(g.core.time_total >= 1)
    Placing(_) -> should.be_true(g.core.time_total >= 1)
    _ -> Nil
  }
}

pub fn first_season_deck_size_test() {
  let #(d, pile, carried, _s) =
    deck.build_season_deck(prng_seed(1), [], first_ambush_pile())
  // 13 explore cards + 1 ambush
  should.equal(list.length(d), 14)
  should.equal(list.length(pile), 3)
  should.equal(list.length(carried), 1)
}

import game/rng
import ui/snapshot

fn prng_seed(i: Int) -> rng.Rng {
  rng.new(i)
}

fn first_ambush_pile() {
  let #(pile, _) = deck.new_ambush_pile(rng.new(1))
  pile
}
// ---------------------------------------------------------------------------
// full-game simulation: greedy autoplay until GameOver
// ---------------------------------------------------------------------------

pub fn autoplay_reaches_game_over_test() {
  let g = game.new_game(2024, maps.wilderness_a())
  let end = autoplay(g, 500)
  case end.core.phase {
    GameOver(result) -> {
      let total =
        list.fold(end.core.season_scores, 0, fn(acc, s) { acc + s.total })
      should.equal(result.total, total)
      should.equal(list.length(end.core.season_scores), 4)
      let corners =
        list.fold(end.core.edicts, 0, fn(acc, p) { acc + p.1.corner })
      should.equal(result.corner_sum, corners)
      should.equal(result.rating, result.total - result.corner_sum)
    }
    _ -> should.fail()
  }
}

fn autoplay(g: Game, fuel: Int) -> Game {
  case fuel <= 0 {
    True -> g
    False ->
      case g.core.phase {
        GameOver(_) -> g
        Choosing(card) -> {
          let idx = first_playable_variant(g, card)
          autoplay(game.pick_variant(g, idx), fuel - 1)
        }
        Placing(_) -> {
          let anchors = game.draft_anchors(g)
          case anchors {
            [] -> {
              // chosen variant doesn't fit under the ruins rule: undo to
              // variant selection and pick a different variant
              autoplay(game.undo(g), fuel - 1)
            }
            [a, ..] -> autoplay(game.place_at(g, a), fuel - 1)
          }
        }
        AmbushShown(_, _) -> autoplay(game.confirm_ambush(g), fuel - 1)
        SeasonEnd(_) -> autoplay(game.confirm_season_end(g), fuel - 1)
      }
  }
}

/// One full player action (pick/place/confirm) for the autoplay helpers.
fn step(g: Game) -> Game {
  case g.core.phase {
    GameOver(_) -> g
    Choosing(card) -> {
      let idx = first_playable_variant(g, card)
      game.pick_variant(g, idx)
    }
    Placing(_) -> {
      let anchors = game.draft_anchors(g)
      case anchors {
        [] -> game.undo(g)
        [a, ..] -> game.place_at(g, a)
      }
    }
    AmbushShown(_, _) -> game.confirm_ambush(g)
    SeasonEnd(_) -> game.confirm_season_end(g)
  }
}

/// Step through a game until a ruins card is actually drawn (ruins_pending
/// becomes True), or the game ends / fuel runs out.
fn drive_until_ruins(g: Game, fuel: Int) -> Game {
  case fuel <= 0 {
    True -> g
    False ->
      case g.core.phase {
        GameOver(_) -> g
        _ ->
          case g.core.ruins_pending {
            True -> g
            False -> drive_until_ruins(step(g), fuel - 1)
          }
      }
  }
}

pub fn ruins_card_is_drawn_and_sets_pending_test() {
  let g0 = game.new_game(2024, maps.wilderness_a())
  let g = drive_until_ruins(g0, 300)
  should.be_true(g.core.ruins_pending)
  // the next shape must overlap an open ruins space
  case g.core.phase {
    Choosing(card) -> {
      let idx = first_playable_variant(g, card)
      let g2 = game.pick_variant(g, idx)
      case g2.core.phase {
        Placing(draft) -> {
          let anchors = game.draft_anchors(g2)
          should.be_true(list.length(anchors) > 0)
          case draft.is_fallback {
            // the 1x1 fallback may go anywhere; nothing to restrict
            True -> Nil
            False ->
              should.be_true(
                list.all(anchors, fn(a) {
                  model.covers_open_ruins(g2.core.grid, draft.piece, a)
                }),
              )
          }
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// forgiving placement (anchor snapping used by the UI)
// ---------------------------------------------------------------------------

// the wilderness-A mountains/ruins live at these coordinates (row, col)

pub fn target_anchor_prefers_exact_cell_test() {
  let grid = maps.new_grid(maps.wilderness_a())
  let piece = model.piece(["##"])
  let legal = model.legal_anchors(grid, piece)
  should.equal(
    game.target_anchor(legal, piece, #(4, 1)),
    Some(#(4, 1)),
  )
}

pub fn target_anchor_snaps_inside_the_map_edge_test() {
  let grid = maps.new_grid(maps.wilderness_a())
  let piece = model.piece(["##"])
  let legal = model.legal_anchors(grid, piece)
  // hovering the rightmost column: anchoring there would fall out of bounds,
  // so the shape hugs the cursor from the left instead
  should.equal(
    game.target_anchor(legal, piece, #(7, 10)),
    Some(#(7, 9)),
  )
}

pub fn target_anchor_snaps_around_a_mountain_test() {
  let grid = maps.new_grid(maps.wilderness_a())
  let piece = model.piece(["##"])
  let legal = model.legal_anchors(grid, piece)
  // mountain at #(5, 5): anchoring at #(5, 4) would overlap it; the legal
  // placement one column left still covers the hovered cell
  should.equal(
    game.target_anchor(legal, piece, #(5, 4)),
    Some(#(5, 3)),
  )
}

pub fn target_anchor_refuses_a_mountain_cell_test() {
  let grid = maps.new_grid(maps.wilderness_a())
  let piece = model.piece(["##"])
  let legal = model.legal_anchors(grid, piece)
  should.equal(game.target_anchor(legal, piece, #(5, 5)), None)
}

pub fn click_anchor_still_accepts_empty_origin_shapes_test() {
  let grid = maps.new_grid(maps.wilderness_a())
  // a disconnected shape that does not occupy its own origin cell
  let piece = model.piece([".#", "#."])
  let legal = model.legal_anchors(grid, piece)
  // no covering anchor maps onto the dot cell...
  should.equal(game.target_anchor(legal, piece, #(0, 0)), None)
  // ...but a click there must still place at that anchor
  should.equal(
    game.click_anchor(legal, piece, #(0, 0)),
    Some(#(0, 0)),
  )
}

// ---------------------------------------------------------------------------
// save/resume roundtrip
// ---------------------------------------------------------------------------

pub fn snapshot_roundtrip_test() {
  let g0 = game.new_game(7, maps.wilderness_a())
  let g1 = autoplay(g0, 6)
  case g1.core.phase {
    GameOver(_) -> should.fail()
    _ -> Nil
  }
  let save = snapshot.with_active(snapshot.empty_save, Some(g1))
  let raw = snapshot.encode_save(save)
  let decoded = snapshot.decode_save(raw)
  case decoded.active {
    None -> should.fail()
    Some(g2) -> {
      // the restored game must re-encode to the identical snapshot
      let raw2 =
        snapshot.encode_save(snapshot.with_active(snapshot.empty_save, Some(g2)))
      should.equal(raw2, raw)
    }
  }
}

fn first_playable_variant(g: Game, card: cards.ExploreCard) -> Int {
  let idxs =
    list.index_map(card.variants, fn(v, i) {
      let anchors =
        game.effective_anchors(g.core.grid, v.piece, g.core.ruins_pending)
      #(list.length(anchors), i)
    })
  let best =
    list.fold(idxs, #(0, 0), fn(best, p) {
      case p.0 > best.0 {
        True -> p
        False -> best
      }
    })
  best.1
}
