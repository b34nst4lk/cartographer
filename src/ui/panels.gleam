//// Everything around the map: title screen, season header, the current card
//// panel (choose / place / ambush / season report / game over), the edicts
//// strip, the time track and the event log.

import game/cards.{type AmbushCard, type EdictCard, type ExploreCard, type Variant}
import game/deck.{type EdictLetter, type SeasonInfo}
import game/game.{
  type Core, type GameResult, type SeasonScore,
  Choosing, Placing, AmbushShown, SeasonEnd, GameOver,
}
import game/model as model
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import ui/board
import ui/msgs.{
  type Msg, type Model, type UiGame, BoardClicked, ChooseFallbackTerrain,
  ClearRecords, ConfirmAmbush, ConfirmSeason, Flip, LeftBoard, PickVariant,
  QuitToTitle, ResumeSavedGame, Rotate, SeedInputChanged, StartNewGame, Undo,
  Hovered,
}
import ui/snapshot.{type RunLog}
import ui/theme

fn f(i: Int) -> String {
  int.to_string(i)
}

fn t(txt: String) -> Element(Msg) {
  html.text(txt)
}

// ---------------------------------------------------------------------------
// Title screen
// ---------------------------------------------------------------------------

pub fn title_screen(model: Model) -> Element(Msg) {
  html.div([a.class("title-screen")], [
    html.div([a.class("title-card")], [
      html.div([a.class("title-compass")], [t("✦")]),
      html.h1([a.class("title-heading")], [t("CARTOGRAPHERS")]),
      html.p([a.class("title-sub")], [
        t("A solo expedition through the wilds, four seasons of ink and wilderland."),
      ]),
      best_block(model.save.best),
      html.hr([a.class("rule")]),
      html.div([a.class("title-actions")], [
        html.input([
          a.class("seed-input"),
          a.placeholder("Seed (blank = random)"),
          a.value(model.seed_input),
          event.on_input(SeedInputChanged),
        ]),
        html.button([a.class("btn primary"), event.on_click(StartNewGame)], [
          t("Begin a new expedition"),
        ]),
        case model.save.active {
          Some(_) ->
            html.button([a.class("btn"), event.on_click(ResumeSavedGame)], [
              t("Continue your last map"),
            ])
          None -> html.span([], [])
        },
      ]),
      history_block(model.save.runs, model.save.best != None || model.save.runs != []),
    ]),
  ])
}

fn best_block(best: option.Option(RunLog)) -> Element(Msg) {
  case best {
    None ->
      html.p([a.class("best none")], [t("No completed expeditions yet.")])
    Some(run) ->
      html.p([a.class("best")], [
        html.strong([], [t("Personal best: " <> f(run.score))]),
        t(" — " <> run.title <> " (rating " <> signed(run.rating) <> ", seed " <> f(run.seed) <> ")"),
      ])
  }
}

fn history_block(runs: List(RunLog), any: Bool) -> Element(Msg) {
  case any {
    False -> html.span([], [])
    True ->
      html.div([a.class("history")], [
        html.h2([a.class("history-heading")], [t("Past expeditions")]),
        html.ul(
          [a.class("history-list")],
          list.map(list.take(runs, 8), fn(run) {
            html.li([], [
              t(
                f(run.score)
                  <> " — "
                  <> run.title
                  <> "  ·  rating "
                  <> signed(run.rating)
                  <> "  ·  seed "
                  <> f(run.seed),
              ),
            ])
          }),
        ),
        html.button([a.class("btn subtle"), event.on_click(ClearRecords)], [
          t("Clear records"),
        ]),
      ])
  }
}

fn signed(i: Int) -> String {
  case i >= 0 {
    True -> "+" <> f(i)
    False -> f(i)
  }
}

// ---------------------------------------------------------------------------
// Game screen frame
// ---------------------------------------------------------------------------

pub fn game_screen(ui: UiGame) -> Element(Msg) {
  let core = ui.game.core
  let phase = core.phase
  let over = case phase {
    GameOver(_) -> True
    _ -> False
  }
  html.div([a.classes([#("game-screen", True), #("is-over", over)])], [
    header_bar(ui),
    html.main([a.class("layout")], [
      html.aside([a.class("sidebar left")], [card_panel(ui)]),
      html.section([a.class("map-area")], [
        board.render(
          core.grid,
          ui.hover,
          ghost_for(ui),
          anchors_for(ui),
          Hovered,
          LeftBoard,
          BoardClicked,
        ),
        hints_row(ui),
      ]),
      html.aside([a.class("sidebar right")], [
        edicts_panel(core),
        track_panel(core),
        log_panel(core),
      ]),
    ]),
  ])
}

fn header_bar(ui: UiGame) -> Element(Msg) {
  let core = ui.game.core
  let info = deck.season_info(core.season_index)
  html.header([a.class("topbar")], [
    html.div([a.class("brand")], [
      t("CARTOGRAPHERS"),
      html.span([a.class("solo-tag")], [t("solo")]),
    ]),
    html.div([a.class("topbar-mid")], [
      html.span([a.class("season-chip")], [t(info.name)]),
      html.span([a.class("score-chip")], [
        t("Score " <> f(game_score(ui))),
      ]),
      html.span([a.class("coin-chip")], [
        board.coin_badge(14),
        t(" " <> f(core.coins)),
      ]),
      html.span([a.class("seed-chip")], [t("seed " <> f(ui.game.seed_int))]),
    ]),
    html.div([a.class("topbar-actions")], [
      html.button(
        [
          a.class("btn subtle"),
          event.on_click(Undo),
          a.disabled(list.is_empty(ui.game.undo_stack)),
        ],
        [t("Undo")],
      ),
      html.button([a.class("btn subtle"), event.on_click(QuitToTitle)], [
        t("Menu"),
      ]),
    ]),
  ])
}

fn game_score(ui: UiGame) -> Int {
  case ui.game.core.phase {
    GameOver(result) -> result.total
    _ -> game_score_running(ui)
  }
}

fn game_score_running(ui: UiGame) -> Int {
  game.score_so_far(ui.game.core)
}


fn hints_row(ui: UiGame) -> Element(Msg) {
  let hint = case ui.game.core.phase {
    Choosing(_) -> "Choose a shape from the card's options."
    Placing(draft) ->
      case draft.is_fallback {
        True ->
          "Nothing fits — draw a single square of any terrain anywhere on the map."
        False ->
          case ui.game.core.ruins_pending {
            True ->
              "The ruins decree a drawing must overlap a ruins space. Click a marked space."
            False -> "Position the shape, then click a space to draw it. R rotates, F mirrors."
          }
      }
    AmbushShown(_, _) -> ""
    SeasonEnd(_) -> ""
    GameOver(_) -> ""
  }
  html.p([a.class("hint")], [t(hint)])
}

// ---------------------------------------------------------------------------
// Left panel: the revealed card
// ---------------------------------------------------------------------------

fn card_panel(ui: UiGame) -> Element(Msg) {
  case ui.game.core.phase {
    Choosing(card) -> explore_choosing(ui, card)
    Placing(draft) -> explore_placing(ui, draft)
    AmbushShown(card, placed) -> ambush_panel(card, placed)
    SeasonEnd(score) -> season_panel(ui, score)
    GameOver(result) -> over_panel(ui, result)
  }
}

fn explore_choosing(ui: UiGame, card: ExploreCard) -> Element(Msg) {
  let core = ui.game.core
  html.div([a.class("card-panel explore")], [
    ruins_banner(core.ruins_pending),
    card_header(card.name, card.time, "explore"),
    case card_has_coin(card) {
      True -> html.p([a.class("coinnote")], [board.coin_badge(14), t(" This card offers a coin option.")])
      False -> html.span([], [])
    },
    html.div(
      [a.class("variant-list")],
      list.index_map(card.variants, fn(v, i) { variant_button(card, v, i) }),
    ),
  ])
}

fn card_has_coin(card: ExploreCard) -> Bool {
  list.any(card.variants, fn(v) { v.coin })
}

fn variant_button(_card: ExploreCard, v: Variant, i: Int) -> Element(Msg) {
  html.button(
    [
      a.classes([#("variant-btn", True), #("with-coin", v.coin)]),
      event.on_click(PickVariant(i)),
    ],
    [
      board.shape_thumb(v.piece, v.terrain, 18, False),
      html.span([a.class("variant-terrain")], [
        t(theme.terrain_label(v.terrain)),
      ]),
      case v.coin {
        True -> board.coin_badge(16)
        False -> html.span([], [])
      },
    ],
  )
}

fn explore_placing(ui: UiGame, draft: game.Draft) -> Element(Msg) {
  html.div([a.class("card-panel placing")], [
    ruins_banner(ui.game.core.ruins_pending),
    card_header(draft.card.name, draft.card.time, "explore"),
    case draft.is_fallback {
      True -> fallback_controls(ui)
      False ->
        html.div([a.class("placing-controls")], [
          html.div([a.class("placing-shape")], [
            board.shape_thumb(draft.piece, draft.variant.terrain, 26, False),
            html.span([a.class("variant-terrain")], [
              t(theme.terrain_label(draft.variant.terrain)),
            ]),
            case draft.variant.coin {
              True -> board.coin_badge(16)
              False -> html.span([], [])
            },
          ]),
          html.div([a.class("btn-row")], [
            html.button([a.class("btn"), event.on_click(Rotate)], [t("Rotate ⟳")]),
            html.button([a.class("btn"), event.on_click(Flip)], [t("Mirror ⇋")]),
          ]),
          html.button([a.class("btn subtle"), event.on_click(Undo)], [
            t("Pick a different shape"),
          ]),
        ])
    },
  ])
}

fn fallback_controls(ui: UiGame) -> Element(Msg) {
  let terrains = [model.Forest, model.Village, model.Farm, model.Water]
  html.div([a.class("fallback")], [
    html.p([a.class("fallback-note")], [
      t("None of the offered shapes fit. Draw a single space instead — pick its terrain:"),
    ]),
    html.div(
      [a.class("btn-row wrap")],
      list.map(terrains, fn(t_) {
        html.button(
          [
            a.classes([
              #("btn", True),
              #("terrain-pick", True),
              #("active", ui.fallback_terrain == t_),
            ]),
            event.on_click(ChooseFallbackTerrain(t_)),
          ],
          [board.shape_thumb([#(0, 0)], t_, 14, False), t(theme.terrain_label(t_))],
        )
      }),
    ),
  ])
}

fn ambush_panel(card: AmbushCard, placed: option.Option(model.Coord)) -> Element(Msg) {
  html.div([a.class("card-panel ambush")], [
    card_header(card.name, 0, "ambush"),
    html.div([a.class("ambush-body")], [
      board.shape_thumb(card.shape, model.Monster, 22, False),
      html.p([a.class("ambush-scan")], [t(scan_description(card))]),
    ]),
    html.p([a.class("ambush-outcome " <> outcome_class(placed))], [
      t(case placed {
        Some(#(r, c)) ->
          "Monsters pour in at "
            <> board.row_letter(r)
            <> f(c + 1)
            <> "."
        None -> "No room for an invasion — the card is disregarded."
      }),
    ]),
    html.button([a.class("btn primary"), event.on_click(ConfirmAmbush)], [
      t("Continue"),
    ]),
  ])
}

fn outcome_class(placed: option.Option(model.Coord)) -> String {
  case placed {
    Some(_) -> "bad"
    None -> "good"
  }
}

fn scan_description(card: AmbushCard) -> String {
  let corner = case card.corner {
    cards.TopLeft -> "top-left"
    cards.TopRight -> "top-right"
    cards.BottomLeft -> "bottom-left"
    cards.BottomRight -> "bottom-right"
  }
  let dir = case card.direction {
    cards.Clockwise -> "clockwise"
    cards.CounterClockwise -> "counter-clockwise"
  }
  "Raid from the " <> corner <> " corner, " <> dir <> " along the edge."
}

fn season_panel(ui: UiGame, s: SeasonScore) -> Element(Msg) {
  html.div([a.class("card-panel season-report")], [
    html.h2([a.class("card-title")], [t(s.season_name <> " scored")]),
    score_row(s.edict1.0, s.edict1.1, s.edict1.2),
    score_row(s.edict2.0, s.edict2.1, s.edict2.2),
    html.p([a.class("score-line")], [
      t("Coins  "),
      html.strong([], [t("+" <> f(s.coins))]),
    ]),
    html.p([a.class("score-line monster")], [
      t("Monster spaces  "),
      html.strong([], [t("−" <> f(s.monster))]),
    ]),
    html.hr([a.class("rule")]),
    html.p([a.class("score-total")], [
      t(s.season_name <> " total  "),
      html.strong([], [t(signed(s.total))]),
    ]),
    html.button([a.class("btn primary"), event.on_click(ConfirmSeason)], [
      t(case ui.game.core.season_index >= deck.season_count - 1 {
        True -> "Conclude the expedition"
        False -> "Draw " <> next_season_name(ui)
      }),
    ]),
  ])
}

fn next_season_name(ui: UiGame) -> String {
  deck.season_info(ui.game.core.season_index + 1).name
}

fn score_row(letter: EdictLetter, card: EdictCard, pts: Int) -> Element(Msg) {
  html.p([a.class("score-line")], [
    edict_badge(letter, card),
    t(" " <> card.name <> "  "),
    html.strong([], [t("+" <> f(pts))]),
  ])
}

fn over_panel(ui: UiGame, result: GameResult) -> Element(Msg) {
  html.div([a.class("card-panel gameover")], [
    html.p([a.class("over-title")], [t(result.title)]),
    html.h2([a.class("card-title")], [t("Final score " <> f(result.total))]),
    html.p([a.class("score-line")], [
      t("The queen's numbers sum to " <> f(result.corner_sum) <> "."),
    ]),
    html.p([a.class("score-line")], [
      t("Rating: " <> f(result.total) <> " − " <> f(result.corner_sum) <> " = "),
      html.strong([], [t(signed(result.rating))]),
    ]),
    rating_table(result.rating),
    html.hr([a.class("rule")]),
    season_receipt(ui),
    html.div([a.class("btn-row wrap")], [
      html.button([a.class("btn primary"), event.on_click(QuitToTitle)], [
        t("Back to the drafting table"),
      ]),
    ]),
  ])
}

fn season_receipt(ui: UiGame) -> Element(Msg) {
  let scores = list.reverse(ui.game.core.season_scores)
  html.ul(
    [a.class("receipt")],
    list.map(scores, fn(s) {
      html.li([], [
        t(s.season_name <> " " <> signed(s.total) <> "  (monsters −" <> f(s.monster) <> ")"),
      ])
    }),
  )
}

fn rating_table(rating: Int) -> Element(Msg) {
  let rows = [
    #(30, "Legendary Cartographer"),
    #(20, "Master Mapsmith"),
    #(10, "Journeyman Topographer"),
    #(0, "Apprentice Surveyor"),
    #(-5, "Amateur Assessor"),
    #(-10, "Inept Assistant"),
    #(-20, "Dimwitted Doodler"),
    #(-30, "Oblivious Inkdrinker"),
  ]
  html.div([a.class("rating-table")], [
    html.p([a.class("rating-caption")], [t("The queen's verdicts:")]),
    ..list.map(rows, fn(row) {
      let #(threshold, name) = row
      let hit = name == game.title_for(rating)
      html.p([a.classes([#("rating-row", True), #("hit", hit)])], [
        t(signed(threshold) <> " · " <> name),
      ])
    })
  ])
}

fn card_header(name: String, time: Int, kind: String) -> Element(Msg) {
  html.div([a.class("card-head " <> kind)], [
    html.span([a.class("card-kind")], [t(kind)]),
    html.h2([a.class("card-title")], [t(name)]),
    case time > 0 {
      True -> html.span([a.class("card-time")], [t("⌛ " <> f(time))])
      False -> html.span([], [])
    },
  ])
}

fn ruins_banner(pending: Bool) -> Element(Msg) {
  case pending {
    False -> html.span([], [])
    True ->
      html.p([a.class("ruins-banner")], [
        t("Ruins revealed — your next shape must overlap a ruins space."),
      ])
  }
}

// ---------------------------------------------------------------------------
// Right panel: edicts, time track, log
// ---------------------------------------------------------------------------

fn edicts_panel(core: Core) -> Element(Msg) {
  let info = deck.season_info(core.season_index)
  let #(l1, l2) = info.edicts
  html.div([a.class("panel edicts")], [
    html.h3([a.class("panel-title")], [t("The queen's decrees")]),
    ..list.map(core.edicts, fn(p) {
      let #(letter, card) = p
      let active = letter == l1 || letter == l2
      html.details(
        [
          a.classes([
            #("edict-row", True),
            #("active", active),
            #("group-" <> group_class(card.group), True),
          ]),
          // open by default so the scoring conditions are always visible;
          // the player can still collapse a row and it stays collapsed
          a.attribute("open", ""),
        ],
        [
          html.summary([a.class("edict-summary")], [
            html.span([a.class("edict-letter")], [t(deck.letter_id(letter))]),
            html.span([a.class("edict-name")], [t(card.name)]),
            html.span(
              [a.class("edict-corner"), a.title("the number to beat")],
              [t(f(card.corner))],
            ),
          ]),
          html.p([a.class("edict-text")], [t(card.text)]),
        ],
      )
    })
  ])
}

fn group_class(g: cards.EdictGroup) -> String {
  case g {
    cards.ForestGroup -> "green"
    cards.HamletGroup -> "yellow"
    cards.WaterFarmGroup -> "blue"
    cards.ArrangementGroup -> "red"
  }
}

fn edict_badge(letter: EdictLetter, _card: EdictCard) -> Element(Msg) {
  html.span([a.class("edict-letter inline")], [t(deck.letter_id(letter))])
}

fn track_panel(core: Core) -> Element(Msg) {
  let info: SeasonInfo = deck.season_info(core.season_index)
  let spent = int.min(core.time_total, info.threshold)
  let pips =
    list.map(model.ints(1, info.threshold), fn(i) {
      html.span(
        [a.classes([#("pip", True), #("spent", i <= spent)])],
        [],
      )
    })
  let overflow = core.time_total - info.threshold
  html.div([a.class("panel track")], [
    html.h3([a.class("panel-title")], [
      t(info.name <> " — time " <> f(spent) <> "/" <> f(info.threshold)),
    ]),
    html.div([a.class("track-pips")], pips),
    case overflow > 0 {
      True ->
        html.p([a.class("overflow-note")], [
          t("(" <> f(core.time_total) <> " spent; season ends)"),
        ])
      False -> html.span([], [])
    },
  ])
}

fn log_panel(core: Core) -> Element(Msg) {
  html.div([a.class("panel log")], [
    html.h3([a.class("panel-title")], [t("Journal")]),
    html.ul(
      [a.class("log-list")],
      list.map(list.take(core.log, 8), fn(line) {
        html.li([], [t(line)])
      }),
    ),
  ])
}

// ---------------------------------------------------------------------------
// Ghost/anchor helpers shared with the board
// ---------------------------------------------------------------------------

fn ghost_for(ui: UiGame) -> option.Option(board.Ghost) {
  case ui.game.core.phase, ui.hover {
    Placing(draft), Some(coord) -> {
      let terrain = case draft.is_fallback {
        True -> ui.fallback_terrain
        False -> draft.variant.terrain
      }
      let legal = game.draft_anchors(ui.game)
      // Snap: if the shape doesn't fit anchored at the hovered cell, try the
      // nearest legal anchor that still covers the hovered cell. Only show
      // red when no covering placement exists at all.
      case game.click_anchor(legal, draft.piece, coord) {
        Some(anchor) ->
          Some(board.Ghost(
            piece: draft.piece,
            anchor: anchor,
            terrain: terrain,
            legal: True,
          ))
        None ->
          Some(board.Ghost(
            piece: draft.piece,
            anchor: coord,
            terrain: terrain,
            legal: False,
          ))
      }
    }
    _, _ -> None
  }
}

fn anchors_for(ui: UiGame) -> List(model.Coord) {
  case ui.game.core.phase {
    Placing(_) -> game.draft_anchors(ui.game)
    _ -> []
  }
}
