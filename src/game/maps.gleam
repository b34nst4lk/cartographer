import game/model.{type Coord, type Grid, Empty, Filled, Mountain}
import gleam/list

/// A map sheet layout: board size plus pre-printed terrain.
/// Coordinates are #(row, col), 0-indexed, row 0 = top edge (row "A").
pub type MapSpec {
  MapSpec(
    id: String,
    name: String,
    size: Int,
    mountains: List(Coord),
    ruins: List(Coord),
  )
}

/// Wilderness, side A of the official map sheet.
/// Mountains: B4, C9, F6, I3, J8.  Ruins: B6, C2, C10, I2, I10, J6.
pub fn wilderness_a() -> MapSpec {
  MapSpec(
    id: "wilderness-a",
    name: "Wilderness (A)",
    size: 11,
    mountains: [#(1, 3), #(2, 8), #(5, 5), #(8, 2), #(9, 7)],
    ruins: [#(1, 5), #(2, 1), #(2, 9), #(8, 1), #(8, 9), #(9, 5)],
  )
}

/// All maps known to the app. Add new layouts here.
pub fn all() -> List(MapSpec) {
  [wilderness_a()]
}

/// Build the starting grid for a map spec.
pub fn new_grid(spec: MapSpec) -> Grid {
  let base = list.repeat(list.repeat(Empty(False), spec.size), spec.size)
  let with_mountains =
    list.fold(spec.mountains, base, fn(g, c) {
      model.set_cell(g, c.0, c.1, Filled(Mountain, False))
    })
  list.fold(spec.ruins, with_mountains, fn(g, c) {
    model.set_cell(g, c.0, c.1, Empty(True))
  })
}
