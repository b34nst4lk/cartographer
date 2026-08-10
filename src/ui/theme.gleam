//// Palette, terrain colours and the minimal linework glyphs drawn inside map
//// cells. One flat fill + one darker ink glyph per terrain — the stripped-down
//// look, staying friendly to the original game without copying its art.

import game/model.{type Terrain} as model
import lustre/attribute as a
import lustre/element/svg
import lustre/element.{type Element}
import gleam/int

pub const ink = "#46351f"

pub const ink_faint = "#8a764f"

pub const parchment = "#f3ead2"

pub const parchment_dark = "#e4d6b4"

pub const cell_fill = "#f8f2df"

pub const grid_line = "#c4b088"

pub const danger = "#a4372a"

pub const coin = "#d9a92f"

pub const monster_fill = "#6a5578"

pub const monster_ink = "#453555"

pub fn terrain_fill(t: Terrain) -> String {
  case t {
    model.Forest -> "#88a86f"
    model.Village -> "#c0664a"
    model.Farm -> "#d8b452"
    model.Water -> "#82a7ba"
    model.Monster -> monster_fill
    model.Mountain -> "#c9bfae"
  }
}

pub fn terrain_ink(t: Terrain) -> String {
  case t {
    model.Forest -> "#4f6a3e"
    model.Village -> "#7d3d26"
    model.Farm -> "#96721c"
    model.Water -> "#44687c"
    model.Monster -> monster_ink
    model.Mountain -> "#6d6154"
  }
}

pub fn terrain_label(t: Terrain) -> String {
  case t {
    model.Forest -> "Forest"
    model.Village -> "Village"
    model.Farm -> "Farm"
    model.Water -> "Water"
    model.Monster -> "Monster"
    model.Mountain -> "Mountain"
  }
}

// --- little helpers ---------------------------------------------------------

fn f(i: Int) -> String {
  int.to_string(i)
}

fn attr(name: String, value: String) -> a.Attribute(msg) {
  a.attribute(name, value)
}

pub fn path(d: String, fill: String, extra: List(a.Attribute(msg))) -> Element(msg) {
  svg.path([attr("d", d), attr("fill", fill), ..extra])
}

pub fn stroke_path(d: String, color: String, width: Int) -> Element(msg) {
  svg.path([
    attr("d", d),
    attr("fill", "none"),
    attr("stroke", color),
    attr("stroke-width", f(width)),
    attr("stroke-linecap", "round"),
  ])
}

// --- cell glyphs (drawn inside a CELL x CELL square at origin x,y) ----------

pub const cell = 40

/// Ink linework for a terrain inside the cell at absolute (x, y).
pub fn glyph(t: Terrain, x: Int, y: Int) -> List(Element(msg)) {
  let ink = terrain_ink(t)
  case t {
    model.Forest -> [
      path(
        "M"
          <> f(x + 20)
          <> " "
          <> f(y + 9)
          <> " L"
          <> f(x + 30)
          <> " "
          <> f(y + 27)
          <> " L"
          <> f(x + 23)
          <> " "
          <> f(y + 27)
          <> " L"
          <> f(x + 23)
          <> " "
          <> f(y + 33)
          <> " L"
          <> f(x + 17)
          <> " "
          <> f(y + 33)
          <> " L"
          <> f(x + 17)
          <> " "
          <> f(y + 27)
          <> " L"
          <> f(x + 10)
          <> " "
          <> f(y + 27)
          <> " Z",
        ink,
        [],
      ),
    ]
    model.Village -> [
      path(
        "M"
          <> f(x + 12)
          <> " "
          <> f(y + 23)
          <> " L"
          <> f(x + 20)
          <> " "
          <> f(y + 13)
          <> " L"
          <> f(x + 28)
          <> " "
          <> f(y + 23)
          <> " L"
          <> f(x + 28)
          <> " "
          <> f(y + 31)
          <> " L"
          <> f(x + 12)
          <> " "
          <> f(y + 31)
          <> " Z",
        ink,
        [],
      ),
    ]
    model.Farm -> [
      stroke_path(
        "M"
          <> f(x + 14)
          <> " "
          <> f(y + 14)
          <> " L"
          <> f(x + 12)
          <> " "
          <> f(y + 29)
          <> " M"
          <> f(x + 20)
          <> " "
          <> f(y + 13)
          <> " L"
          <> f(x + 19)
          <> " "
          <> f(y + 30)
          <> " M"
          <> f(x + 26)
          <> " "
          <> f(y + 14)
          <> " L"
          <> f(x + 27)
          <> " "
          <> f(y + 29),
        ink,
        2,
      ),
    ]
    model.Water -> [
      stroke_path(
        "M"
          <> f(x + 10)
          <> " "
          <> f(y + 18)
          <> " q5 -6 10 0 t10 0"
          <> " M"
          <> f(x + 10)
          <> " "
          <> f(y + 26)
          <> " q5 -6 10 0 t10 0",
        ink,
        2,
      ),
    ]
    model.Monster -> [
      stroke_path(
        "M"
          <> f(x + 13)
          <> " "
          <> f(y + 14)
          <> " L"
          <> f(x + 27)
          <> " "
          <> f(y + 30)
          <> " M"
          <> f(x + 27)
          <> " "
          <> f(y + 14)
          <> " L"
          <> f(x + 13)
          <> " "
          <> f(y + 30),
        ink,
        3,
      ),
    ]
    model.Mountain -> [
      stroke_path(
        "M"
          <> f(x + 20)
          <> " "
          <> f(y + 10)
          <> " L"
          <> f(x + 32)
          <> " "
          <> f(y + 30)
          <> " L"
          <> f(x + 8)
          <> " "
          <> f(y + 30)
          <> " Z",
        ink,
        2,
      ),
      stroke_path(
        "M"
          <> f(x + 16)
          <> " "
          <> f(y + 17)
          <> " L"
          <> f(x + 20)
          <> " "
          <> f(y + 10)
          <> " L"
          <> f(x + 24)
          <> " "
          <> f(y + 17),
        ink,
        1,
      ),
    ]
  }
}

/// Dashed amber overlay marking open ruins (drawn over whatever is in the cell).
pub fn ruins_overlay(x: Int, y: Int) -> Element(msg) {
  svg.g([attr("class", "ruins")], [
    svg.rect([
      attr("x", f(x + 5)),
      attr("y", f(y + 5)),
      attr("width", "30"),
      attr("height", "30"),
      attr("fill", "none"),
      attr("stroke", "#946c26"),
      attr("stroke-width", "2"),
      attr("stroke-dasharray", "5 4"),
    ]),
    stroke_path(
      "M"
        <> f(x + 15)
        <> " "
        <> f(y + 12)
        <> " L"
        <> f(x + 21)
        <> " "
        <> f(y + 21)
        <> " L"
        <> f(x + 16)
        <> " "
        <> f(y + 29),
      "#946c26",
      2,
    ),
  ])
}
