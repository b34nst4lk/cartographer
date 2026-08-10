//// Lustre application shell: init/update/view plus the localStorage save/load
//// plumbing. All game rules live in src/game/*; all markup in src/ui/*.

import game/game.{Choosing, Placing, AmbushShown, SeasonEnd, GameOver}
import game/maps
import game/model.{Forest, Village, Farm, Water}
import gleam/int
import gleam/option.{None, Some}
import lustre.{type App}
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import ui/msgs.{
  type Model, type Msg, Model, UiGame, TitleScreen, GameScreen,
  SaveLoaded, SeedInputChanged, StartNewGame, BeginGame, ResumeSavedGame,
  Hovered, LeftBoard, BoardClicked, PickVariant, Rotate, Flip,
  ChooseFallbackTerrain, ConfirmAmbush, ConfirmSeason, Undo, QuitToTitle,
  ClearRecords, FocusRoot, KeyPressed,
}
import ui/panels
import ui/snapshot
import ui/store

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

pub fn app() -> App(Nil, Model, Msg) {
  lustre.application(init, update, view)
}

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      screen: TitleScreen,
      save: snapshot.empty_save,
      game: None,
      seed_input: "",
    )
  #(
    model,
    effect.batch([
      effect.from(fn(dispatch) { dispatch(SaveLoaded(store.load_save())) }),
      focus_eff(),
    ]),
  )
}

fn focus_eff() -> Effect(Msg) {
  effect.from(fn(_dispatch) { store.focus_game_root() })
}

pub fn start(selector: String) -> Result(Nil, lustre.Error) {
  case lustre.start(app(), selector, Nil) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(e)
  }
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SaveLoaded(raw) -> {
      let save = snapshot.decode_save(raw)
      #(Model(..model, save: save), effect.none())
    }
    SeedInputChanged(s) -> #(Model(..model, seed_input: s), effect.none())
    StartNewGame ->
      case int.parse(model.seed_input) {
        Ok(seed) -> begin_game(model, seed)
        Error(Nil) ->
          #(
            model,
            effect.from(fn(dispatch) { dispatch(BeginGame(store.now_int())) }),
          )
      }
    BeginGame(seed) -> begin_game(model, seed)
    ResumeSavedGame ->
      case model.save.active {
        None -> #(model, effect.none())
        Some(g) -> {
          let model =
            Model(..model, screen: GameScreen, game: Some(msgs.new_uigame(g)))
          #(model, focus_eff())
        }
      }
    Hovered(coord) -> with_ui(model, fn(ui) {
      #(UiGame(..ui, hover: Some(coord)), effect.none())
    })
    LeftBoard -> with_ui(model, fn(ui) {
      #(UiGame(..ui, hover: None), effect.none())
    })
    BoardClicked(coord) ->
      with_game_ui(model, fn(ui) {
        case ui.game.core.phase {
          Placing(draft) ->
            // forgiving placement: use the nearest legal anchor whose shape
            // covers the clicked cell, not necessarily the cell itself
            case
              game.click_anchor(
                game.draft_anchors(ui.game),
                draft.piece,
                coord,
              )
            {
              Some(anchor) -> game.place_at(ui.game, anchor)
              None -> ui.game
            }
          _ -> ui.game
        }
      })
    PickVariant(i) -> with_game_ui(model, fn(ui) { game.pick_variant(ui.game, i) })
    Rotate -> with_game_ui(model, fn(ui) { game.rotate_draft(ui.game) })
    Flip -> with_game_ui(model, fn(ui) { game.flip_draft(ui.game) })
    ChooseFallbackTerrain(t) ->
      case model.game {
        None -> #(model, effect.none())
        Some(ui) -> {
          let g = game.set_fallback_terrain(ui.game, t)
          let ui2 = UiGame(..ui, game: g, fallback_terrain: t)
          #(Model(..model, game: Some(ui2)), effect.none())
        }
      }
    ConfirmAmbush -> with_game_ui(model, fn(ui) { game.confirm_ambush(ui.game) })
    ConfirmSeason -> with_game_ui(model, fn(ui) { game.confirm_season_end(ui.game) })
    Undo -> with_game_ui(model, fn(ui) { game.undo(ui.game) })
    QuitToTitle -> {
      let model = Model(..model, screen: TitleScreen)
      #(sync_records(model), persist(model))
    }
    ClearRecords -> {
      let save =
        snapshot.SavedData(
          best: None,
          runs: [],
          active: model.save.active,
        )
      let model = Model(..model, save: save)
      #(model, persist(model))
    }
    FocusRoot -> #(model, focus_eff())
    KeyPressed(key) -> handle_key(model, key)
  }
}

fn handle_key(model: Model, key: String) -> #(Model, Effect(Msg)) {
  case model.game {
    None -> #(model, effect.none())
    Some(ui) ->
      case ui.game.core.phase {
        Placing(draft) ->
          case key {
            "r" | "R" -> update(model, Rotate)
            "f" | "F" | "m" | "M" -> update(model, Flip)
            "u" | "z" -> update(model, Undo)
            "1" | "2" | "3" | "4" ->
              case draft.is_fallback {
                False -> #(model, effect.none())
                True -> {
                  let terrain = case key {
                    "1" -> Forest
                    "2" -> Village
                    "3" -> Farm
                    _ -> Water
                  }
                  update(model, ChooseFallbackTerrain(terrain))
                }
              }
            _ -> #(model, effect.none())
          }
        Choosing(_) ->
          case key {
            "1" -> update(model, PickVariant(0))
            "2" -> update(model, PickVariant(1))
            "u" | "z" -> update(model, Undo)
            _ -> #(model, effect.none())
          }
        AmbushShown(_, _) ->
          case key {
            "Enter" | " " -> update(model, ConfirmAmbush)
            _ -> #(model, effect.none())
          }
        SeasonEnd(_) ->
          case key {
            "Enter" | " " -> update(model, ConfirmSeason)
            _ -> #(model, effect.none())
          }
        GameOver(_) -> #(model, effect.none())
      }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Run a UiGame -> UiGame transform (model-only change, no persistence).
fn with_ui(
  model: Model,
  f: fn(msgs.UiGame) -> #(msgs.UiGame, Effect(Msg)),
) -> #(Model, Effect(Msg)) {
  case model.game {
    None -> #(model, effect.none())
    Some(ui) -> {
      let #(ui2, eff) = f(ui)
      #(Model(..model, game: Some(ui2)), eff)
    }
  }
}

/// Run a Game -> Game transform, persist the new snapshot, and record the
/// run in the history the first time the game ends.
fn with_game_ui(
  model: Model,
  f: fn(msgs.UiGame) -> game.Game,
) -> #(Model, Effect(Msg)) {
  case model.game {
    None -> #(model, effect.none())
    Some(ui) -> {
      let g = f(ui)
      let #(model, g) = record_if_over(model, g, ui.recorded)
      let recorded = case g.core.phase {
        GameOver(_) -> True
        _ -> ui.recorded
      }
      let save = snapshot.with_active(model.save, active_of(g))
      let ui2 = UiGame(..ui, game: g, recorded: recorded)
      let model = Model(..model, save: save, game: Some(ui2))
      #(model, persist(model))
    }
  }
}

/// ChooseFallbackTerrain is handled directly; this section intentionally
/// keeps only the general helpers.

fn active_of(g: game.Game) -> option.Option(game.Game) {
  case g.core.phase {
    GameOver(_) -> None
    _ -> Some(g)
  }
}

/// When a finished game first reaches GameOver, append it to the records.
fn record_if_over(
  model: Model,
  g: game.Game,
  recorded: Bool,
) -> #(Model, game.Game) {
  case g.core.phase {
    GameOver(result) ->
      case recorded {
        True -> #(model, g)
        False -> {
          let save = snapshot.record_run(model.save, g.seed_int, result)
          #(Model(..model, save: save), g)
        }
      }
    _ -> #(model, g)
  }
}

fn begin_game(model: Model, seed: Int) -> #(Model, Effect(Msg)) {
  let g = game.new_game(seed, maps.wilderness_a())
  let save = snapshot.with_active(model.save, Some(g))
  let model =
    Model(
      screen: GameScreen,
      save: save,
      game: Some(msgs.new_uigame(g)),
      seed_input: "",
    )
  #(model, effect.batch([persist(model), focus_eff()]))
}

fn sync_records(model: Model) -> Model {
  case model.game {
    None -> model
    Some(ui) -> {
      let save = snapshot.with_active(model.save, active_of(ui.game))
      Model(..model, save: save)
    }
  }
}

fn persist(model: Model) -> Effect(Msg) {
  let json = snapshot.encode_save(model.save)
  effect.from(fn(_dispatch) { store.store_save(json) })
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  let body = case model.screen, model.game {
    GameScreen, Some(ui) -> panels.game_screen(ui)
    _, _ -> panels.title_screen(model)
  }
  html.div(
    [
      a.id("game-root"),
      a.tabindex(0),
      a.class("app"),
      event.on_keydown(KeyPressed),
      event.on_click(FocusRoot),
    ],
    [body],
  )
}
