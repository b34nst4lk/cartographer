import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// Board cell coordinates, 0-indexed: #(row, col), row 0 = top edge.
pub type Coord =
  #(Int, Int)

pub type Terrain {
  Forest
  Village
  Farm
  Water
  Monster
  Mountain
}

/// `ruins` marks the six pre-printed ruins spaces. A ruins space counts as
/// empty until the player draws over it (then it keeps the flag for e.g.
/// The Golden Granary scoring).
pub type Cell {
  Empty(ruins: Bool)
  Filled(terrain: Terrain, ruins: Bool)
}

/// A polyomino-ish shape as a list of cell offsets, normalized so that
/// min row = min col = 0. Cells do not need to be connected (ambush cards).
pub type Piece =
  List(Coord)

/// Row-major grid: grid is a list of rows.
pub type Grid =
  List(List(Cell))

// ---------------------------------------------------------------------------
// List micro-helpers
// ---------------------------------------------------------------------------

/// Inclusive ascending integer list: ``ints(1, 3) == [1, 2, 3]``.
pub fn ints(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..ints(from + 1, to)]
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

fn list_set(l: List(a), i: Int, value: a) -> List(a) {
  case l {
    [] -> []
    [x, ..rest] ->
      case i <= 0 {
        True -> [value, ..rest]
        False -> [x, ..list_set(rest, i - 1, value)]
      }
  }
}

// ---------------------------------------------------------------------------
// Cell helpers
// ---------------------------------------------------------------------------

pub fn is_filled(cell: Cell) -> Bool {
  case cell {
    Empty(_) -> False
    Filled(_, _) -> True
  }
}

/// Open (unclaimed) ruins space.
pub fn is_open_ruins(cell: Cell) -> Bool {
  case cell {
    Empty(True) -> True
    _ -> False
  }
}

/// Pre-printed ruins space, claimed or not.
pub fn on_ruins(cell: Cell) -> Bool {
  case cell {
    Empty(r) -> r
    Filled(_, r) -> r
  }
}

pub fn cell_terrain(cell: Cell) -> Option(Terrain) {
  case cell {
    Filled(t, _) -> Some(t)
    _ -> None
  }
}

// ---------------------------------------------------------------------------
// Grid helpers
// ---------------------------------------------------------------------------

pub fn grid_size(grid: Grid) -> Int {
  list.length(grid)
}

pub fn grid_at(grid: Grid, row: Int, col: Int) -> Result(Cell, Nil) {
  case list_at(grid, row) {
    Ok(r) -> list_at(r, col)
    Error(Nil) -> Error(Nil)
  }
}

pub fn set_cell(grid: Grid, row: Int, col: Int, cell: Cell) -> Grid {
  case list_at(grid, row) {
    Ok(r) -> list_set(grid, row, list_set(r, col, cell))
    Error(Nil) -> grid
  }
}

pub fn all_coords(size: Int) -> List(Coord) {
  use r <- list.flat_map(ints(0, size - 1))
  use c <- list.map(ints(0, size - 1))
  #(r, c)
}

/// Orthogonal neighbors that are inside the board.
pub fn neighbors4(size: Int, coord: Coord) -> List(Coord) {
  [
    #(coord.0 - 1, coord.1),
    #(coord.0 + 1, coord.1),
    #(coord.0, coord.1 - 1),
    #(coord.0, coord.1 + 1),
  ]
  |> list.filter(fn(p) { p.0 >= 0 && p.1 >= 0 && p.0 < size && p.1 < size })
}

pub fn is_edge(size: Int, coord: Coord) -> Bool {
  coord.0 == 0 || coord.1 == 0 || coord.0 == size - 1 || coord.1 == size - 1
}

/// True if every orthogonal neighbor of `coord` is either off the map or a
/// filled space ("surrounded on all four sides by filled spaces or the edge").
pub fn surrounded_by_filled_or_edge(grid: Grid, coord: Coord) -> Bool {
  let size = grid_size(grid)
  use n <- list.all(neighbors4(size, coord))
  case grid_at(grid, n.0, n.1) {
    Ok(cell) -> is_filled(cell)
    Error(Nil) -> True
  }
}

/// All coordinates filled with the given terrain.
pub fn coords_with(grid: Grid, terrain: Terrain) -> List(Coord) {
  let size = grid_size(grid)
  use c <- list.filter(all_coords(size))
  case grid_at(grid, c.0, c.1) {
    Ok(Filled(t, _)) -> t == terrain
    _ -> False
  }
}

/// Every coordinate whose cell satisfies `pred`.
pub fn coords_matching(grid: Grid, pred: fn(Cell) -> Bool) -> List(Coord) {
  let size = grid_size(grid)
  use c <- list.filter(all_coords(size))
  case grid_at(grid, c.0, c.1) {
    Ok(cell) -> pred(cell)
    Error(Nil) -> False
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

pub fn normalize(piece: Piece) -> Piece {
  let min_r = list.fold(list.map(piece, fn(c) { c.0 }), 999, int.min)
  let min_c = list.fold(list.map(piece, fn(c) { c.1 }), 999, int.min)
  list.map(piece, fn(c) { #(c.0 - min_r, c.1 - min_c) })
}

pub fn rotate_cw(piece: Piece) -> Piece {
  list.map(piece, fn(c) { #(c.1, 0 - c.0) }) |> normalize
}

pub fn flip_horizontal(piece: Piece) -> Piece {
  list.map(piece, fn(c) { #(c.0, 0 - c.1) }) |> normalize
}

/// #(height, width) of the piece's bounding box (piece should be normalized).
pub fn bounding(piece: Piece) -> #(Int, Int) {
  let max_r = list.fold(list.map(piece, fn(c) { c.0 }), 0, int.max)
  let max_c = list.fold(list.map(piece, fn(c) { c.1 }), 0, int.max)
  #(max_r + 1, max_c + 1)
}

pub fn piece_at(piece: Piece, anchor: Coord) -> Piece {
  list.map(piece, fn(c) { #(c.0 + anchor.0, c.1 + anchor.1) })
}

/// Build a piece from ASCII art rows, ``#`` marks a cell.
pub fn piece(rows: List(String)) -> Piece {
  rows
  |> list.index_map(fn(row, r) {
    row
    |> string_to_cells(r)
  })
  |> list.flatten
  |> normalize
}

fn string_to_cells(row: String, r: Int) -> Piece {
  row
  |> string_characters
  |> list.index_map(fn(ch, c) { #(ch == "#", #(r, c)) })
  |> list.filter(fn(p) { p.0 })
  |> list.map(fn(p) { p.1 })
}

// String helpers (avoid importing gleam/string in every caller)
import gleam/string

fn string_characters(s: String) -> List(String) {
  string.to_graphemes(s)
}

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------

/// The shape cannot overlap filled spaces or leave the map. Open ruins count
/// as empty and may be covered.
pub fn can_place(grid: Grid, piece: Piece, anchor: Coord) -> Bool {
  use c <- list.all(piece_at(piece, anchor))
  case grid_at(grid, c.0, c.1) {
    Ok(cell) -> !is_filled(cell)
    Error(Nil) -> False
  }
}

pub fn legal_anchors(grid: Grid, piece: Piece) -> List(Coord) {
  let size = grid_size(grid)
  use a <- list.filter(all_coords(size))
  can_place(grid, piece, a)
}

pub fn place(
  grid: Grid,
  piece: Piece,
  anchor: Coord,
  terrain: Terrain,
) -> Grid {
  use g, c <- list.fold(piece_at(piece, anchor), grid)
  case grid_at(g, c.0, c.1) {
    Ok(cell) -> set_cell(g, c.0, c.1, Filled(terrain, on_ruins(cell)))
    Error(Nil) -> g
  }
}

/// True if placing `piece` at `anchor` would cover at least one open ruins space.
pub fn covers_open_ruins(grid: Grid, piece: Piece, anchor: Coord) -> Bool {
  use c <- list.any(piece_at(piece, anchor))
  case grid_at(grid, c.0, c.1) {
    Ok(cell) -> is_open_ruins(cell)
    Error(Nil) -> False
  }
}

pub fn open_ruins_count(grid: Grid) -> Int {
  grid
  |> coords_matching(is_open_ruins)
  |> list.length
}

/// Number of mountain spaces whose four adjacent spaces are all filled.
pub fn claimed_mountains(grid: Grid) -> Int {
  let size = grid_size(grid)
  use m <- list.count(coords_with(grid, Mountain))
  use n <- list.all(neighbors4(size, m))
  case grid_at(grid, n.0, n.1) {
    Ok(cell) -> is_filled(cell)
    Error(Nil) -> True
  }
}
