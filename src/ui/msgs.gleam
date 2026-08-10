//// Message and app-state types, kept in their own module so the view modules
//// and the update loop can share them without import cycles.

import game/model.{type Coord, type Terrain}
import game/game.{type Game}
import gleam/option.{type Option, None}
import ui/snapshot.{type SavedData}

pub type Msg {
  /// Browser storage contents delivered at startup.
  SaveLoaded(String)
  SeedInputChanged(String)
  StartNewGame
  /// Effect-produced seed (clock) when no seed was typed.
  BeginGame(Int)
  ResumeSavedGame
  Hovered(Coord)
  LeftBoard
  BoardClicked(Coord)
  PickVariant(Int)
  Rotate
  Flip
  ChooseFallbackTerrain(Terrain)
  ConfirmAmbush
  ConfirmSeason
  Undo
  QuitToTitle
  ClearRecords
  /// Click anywhere in the app: (re)claim keyboard focus for hotkeys.
  FocusRoot
  KeyPressed(String)
}

pub type Screen {
  TitleScreen
  GameScreen
}

pub type Model {
  Model(
    screen: Screen,
    save: SavedData,
    game: Option(UiGame),
    seed_input: String,
  )
}

pub type UiGame {
  UiGame(
    game: Game,
    hover: Option(Coord),
    fallback_terrain: Terrain,
    /// Set once the finished run has been written to the records.
    recorded: Bool,
  )
}

pub fn new_uigame(game: Game) -> UiGame {
  UiGame(
    game: game,
    hover: None,
    fallback_terrain: model.Forest,
    recorded: case game.core.phase {
      game.GameOver(_) -> True
      _ -> False
    },
  )
}
