//// The cartography sheet: the 11x11 map as inline SVG with coordinate labels,
//// terrain linework, ruins overlays, legal-anchor hints, and the ghost preview
//// of the piece currently being positioned.

import game/model.{type Coord, type Grid, type Piece, type Terrain}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/svg
import lustre/event
import ui/theme

fn f(i: Int) -> String {
  int.to_string(i)
}

fn attr(name: String, value: String) -> a.Attribute(msg) {
  a.attribute(name, value)
}

pub const offset = 26

pub type Ghost {
  Ghost(piece: Piece, anchor: Coord, terrain: Terrain, legal: Bool)
}

pub fn render(
  grid: Grid,
  hover: Option(Coord),
  ghost: Option(Ghost),
  highlights: List(Coord),
  on_hover: fn(Coord) -> msg,
  on_leave: msg,
  on_click: fn(Coord) -> msg,
) -> Element(msg) {
  let size = list.length(grid)
  let side = size * theme.cell
  let total = side + offset * 2
  let cells =
    list.flat_map(model.ints(0, size - 1), fn(r) {
      list.map(model.ints(0, size - 1), fn(c) {
        cell_elements(grid, r, c, on_hover, on_click)
      })
    })
  svg.svg(
    [
      attr("viewBox", "0 0 " <> f(total) <> " " <> f(total)),
      attr("class", "board"),
      event.on_mouse_leave(on_leave),
    ],
    [
      sheet_background(total),
      svg.g([], labels(size)),
      svg.g([], list.flatten(cells)),
      svg.g([], highlight_elements(highlights)),
      svg.g([], ghost_elements(ghost)),
      sheet_frame(total, side),
      svg.g([], hover_elements(hover)),
    ],
  )
}

fn sheet_background(total: Int) -> Element(msg) {
  svg.rect([
    attr("x", "0"),
    attr("y", "0"),
    attr("width", f(total)),
    attr("height", f(total)),
    attr("rx", "6"),
    attr("fill", theme.parchment),
  ])
}

fn sheet_frame(total: Int, side: Int) -> Element(msg) {
  svg.g([], [
    svg.rect([
      attr("x", f(offset)),
      attr("y", f(offset)),
      attr("width", f(side)),
      attr("height", f(side)),
      attr("fill", "none"),
      attr("stroke", theme.ink),
      attr("stroke-width", "2"),
    ]),
    svg.rect([
      attr("x", "4"),
      attr("y", "4"),
      attr("width", f(total - 8)),
      attr("height", f(total - 8)),
      attr("rx", "5"),
      attr("fill", "none"),
      attr("stroke", theme.parchment_dark),
      attr("stroke-width", "2"),
    ]),
  ])
}

fn labels(size: Int) -> List(Element(msg)) {
  let rows =
    list.map(model.ints(0, size - 1), fn(r) {
      svg.text(
        [
          attr("x", f(offset - 14)),
          attr("y", f(offset + r * theme.cell + 27)),
          attr("class", "coord-label"),
          attr("text-anchor", "middle"),
        ],
        row_letter(r),
      )
    })
  let cols =
    list.map(model.ints(0, size - 1), fn(c) {
      svg.text(
        [
          attr("x", f(offset + c * theme.cell + 20)),
          attr("y", f(offset - 10)),
          attr("class", "coord-label"),
          attr("text-anchor", "middle"),
        ],
        f(c + 1),
      )
    })
  list.append(rows, cols)
}

pub fn row_letter(r: Int) -> String {
  case r {
    0 -> "A"
    1 -> "B"
    2 -> "C"
    3 -> "D"
    4 -> "E"
    5 -> "F"
    6 -> "G"
    7 -> "H"
    8 -> "I"
    9 -> "J"
    10 -> "K"
    _ -> "?"
  }
}

fn cell_elements(
  grid: Grid,
  r: Int,
  c: Int,
  on_hover: fn(Coord) -> msg,
  on_click: fn(Coord) -> msg,
) -> List(Element(msg)) {
  let x = offset + c * theme.cell
  let y = offset + r * theme.cell
  let coord = #(r, c)
  let base =
    svg.rect([
      attr("x", f(x)),
      attr("y", f(y)),
      attr("width", f(theme.cell)),
      attr("height", f(theme.cell)),
      attr("fill", theme.cell_fill),
      attr("stroke", theme.grid_line),
      attr("stroke-width", "1"),
      a.class("cell-rect"),
      event.on_mouse_enter(on_hover(coord)),
      event.on_click(on_click(coord)),
    ])
  let content = case model.grid_at(grid, r, c) {
    Error(Nil) -> []
    Ok(model.Empty(_)) -> []
    Ok(model.Filled(t, _)) -> [
      svg.rect([
        attr("x", f(x + 1)),
        attr("y", f(y + 1)),
        attr("width", f(theme.cell - 2)),
        attr("height", f(theme.cell - 2)),
        attr("fill", theme.terrain_fill(t)),
        attr("class", "terrain-fill"),
      ]),
      ..theme.glyph(t, x, y)
    ]
  }
  let ruins = case model.grid_at(grid, r, c) {
    Ok(model.Empty(True)) | Ok(model.Filled(_, True)) -> [
      theme.ruins_overlay(x, y),
    ]
    _ -> []
  }
  [base, ..list.append(list.append(content, ruins), [])]
}

fn highlight_elements(highlights: List(Coord)) -> List(Element(msg)) {
  list.map(highlights, fn(coord) {
    let #(r, c) = coord
    svg.circle([
      attr("cx", f(offset + c * theme.cell + 20)),
      attr("cy", f(offset + r * theme.cell + 20)),
      attr("r", "4"),
      attr("class", "anchor-dot"),
    ])
  })
}

fn ghost_elements(ghost: Option(Ghost)) -> List(Element(msg)) {
  case ghost {
    None -> []
    Some(g) -> {
      let cls = case g.legal {
        True -> "ghost-ok"
        False -> "ghost-bad"
      }
      list.map(g.piece, fn(cell) {
        let #(dr, dc) = cell
        let r = g.anchor.0 + dr
        let c = g.anchor.1 + dc
        svg.rect([
          attr("x", f(offset + c * theme.cell + 1)),
          attr("y", f(offset + r * theme.cell + 1)),
          attr("width", f(theme.cell - 2)),
          attr("height", f(theme.cell - 2)),
          attr("fill", theme.terrain_fill(g.terrain)),
          attr("class", cls),
        ])
      })
    }
  }
}

fn hover_elements(hover: Option(Coord)) -> List(Element(msg)) {
  case hover {
    None -> []
    Some(#(r, c)) -> [
      svg.rect([
        attr("x", f(offset + c * theme.cell)),
        attr("y", f(offset + r * theme.cell)),
        attr("width", f(theme.cell)),
        attr("height", f(theme.cell)),
        attr("class", "hover-cell"),
      ]),
    ]
  }
}

// ---------------------------------------------------------------------------
// Mini shape thumbnails (card variants, ambush previews)
// ---------------------------------------------------------------------------

/// A small SVG rendering of a piece in a terrain's colours.
pub fn shape_thumb(
  piece: Piece,
  terrain: Terrain,
  cell_px: Int,
  ghostly: Bool,
) -> Element(msg) {
  let #(h, w) = model.bounding(piece)
  let wpx = w * cell_px
  let hpx = h * cell_px
  let cells =
    list.map(piece, fn(cell) {
      let #(r, c) = cell
      svg.rect([
        attr("x", f(c * cell_px + 1)),
        attr("y", f(r * cell_px + 1)),
        attr("width", f(cell_px - 2)),
        attr("height", f(cell_px - 2)),
        attr("rx", "2"),
        attr("fill", case ghostly {
          True -> "#9a8a66"
          False -> theme.terrain_fill(terrain)
        }),
      ])
    })
  let frame =
    svg.rect([
      attr("x", "0"),
      attr("y", "0"),
      attr("width", f(wpx)),
      attr("height", f(hpx)),
      attr("fill", "none"),
      attr("stroke", theme.parchment_dark),
      attr("stroke-width", "1"),
    ])
  svg.svg(
    [
      attr("viewBox", "0 0 " <> f(wpx) <> " " <> f(hpx)),
      attr("width", f(wpx)),
      attr("height", f(hpx)),
      attr("class", "shape-thumb"),
    ],
    [frame, ..cells],
  )
}

/// Compact coin badge used on card variants.
pub fn coin_badge(px: Int) -> Element(msg) {
  svg.svg(
    [
      attr("viewBox", "0 0 " <> f(px) <> " " <> f(px)),
      attr("width", f(px)),
      attr("height", f(px)),
      attr("class", "coin-badge"),
    ],
    [
      svg.circle([
        attr("cx", f(px / 2)),
        attr("cy", f(px / 2)),
        attr("r", f(px / 2 - 1)),
        attr("fill", theme.coin),
        attr("stroke", "#9a7116"),
        attr("stroke-width", "1"),
      ]),
    ],
  )
}
