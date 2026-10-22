import game/cards.{
  type AmbushCard, BottomLeft, BottomRight, Clockwise, CounterClockwise, TopLeft,
  TopRight,
}
import game/model.{type Coord, type Grid, Monster}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Solo mode ambush resolution: starting in the corner shown on the card and
/// proceeding along the edge in the arrow's direction, attempt to legally
/// draw the monster shape (never rotated or flipped). If no position along
/// the edge works, move one space in and try again from the same corner.
/// If the shape cannot be legally drawn at all, the card is disregarded.
///
/// `anchors_in_scan_order` enumerates every candidate anchor (the top-left of
/// the shape's bounding box) in the order the scan tries them.
pub fn anchors_in_scan_order(size: Int, card: AmbushCard) -> List(Coord) {
  let #(h, w) = model.bounding(card.shape)
  let max_r = size - h
  let max_c = size - w
  let rows = model.ints(0, max_r)
  let cols = model.ints(0, max_c)
  case card.corner, card.direction {
    // Down the left edge from the top-left corner; then one column inward.
    TopLeft, CounterClockwise ->
      list.flat_map(cols, fn(d) { list.map(rows, fn(r) { #(r, d) }) })
    // Right along the top edge from the top-left corner; then one row inward.
    TopLeft, Clockwise ->
      list.flat_map(rows, fn(d) { list.map(cols, fn(c) { #(d, c) }) })
    // Down the right edge from the top-right corner; then one column inward.
    TopRight, Clockwise ->
      list.flat_map(cols, fn(d) { list.map(rows, fn(r) { #(r, max_c - d) }) })
    // Left along the top edge from the top-right corner; then one row inward.
    TopRight, CounterClockwise ->
      list.flat_map(rows, fn(d) { list.map(cols, fn(c) { #(d, max_c - c) }) })
    // Up the left edge from the bottom-left corner; then one column inward.
    BottomLeft, Clockwise ->
      list.flat_map(cols, fn(d) { list.map(rows, fn(r) { #(max_r - r, d) }) })
    // Right along the bottom edge from the bottom-left corner; then one row inward.
    BottomLeft, CounterClockwise ->
      list.flat_map(rows, fn(d) { list.map(cols, fn(c) { #(max_r - d, c) }) })
    // Left along the bottom edge from the bottom-right corner; then one row inward.
    BottomRight, Clockwise ->
      list.flat_map(rows, fn(d) {
        list.map(cols, fn(c) { #(max_r - d, max_c - c) })
      })
    // Up the right edge from the bottom-right corner; then one column inward.
    BottomRight, CounterClockwise ->
      list.flat_map(cols, fn(d) {
        list.map(rows, fn(r) { #(max_r - r, max_c - d) })
      })
  }
}

/// Resolve an ambush card against the grid. Returns the (possibly unchanged)
/// grid and the anchor where monsters were placed, or None if the card had
/// to be disregarded. Open ruins count as empty for monster placement.
pub fn resolve(grid: Grid, card: AmbushCard) -> #(Grid, Option(Coord)) {
  let size = model.grid_size(grid)
  let anchors = anchors_in_scan_order(size, card)
  case list.find(anchors, fn(a) { model.can_place(grid, card.shape, a) }) {
    Ok(a) -> #(model.place(grid, card.shape, a, Monster), Some(a))
    Error(Nil) -> #(grid, None)
  }
}
