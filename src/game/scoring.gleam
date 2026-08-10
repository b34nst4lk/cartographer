import game/cards.{
  type EdictKind, SentinelWood, Greenbough, Treetower, StonesideForest,
  CanalLake, GoldenGranary, MagesValley, ShoresideExpanse, Wildholds, GreatCity,
  Shieldgate, GreengoldPlains, Borderlands, BrokenRoad, LostBarony, Cauldrons,
}
import game/model.{type Cell, type Coord, type Grid, type Terrain} as model
import gleam/int
import gleam/list
import gleam/set.{type Set}

// ---------------------------------------------------------------------------
// Cluster machinery
// ---------------------------------------------------------------------------

fn terrain_pred(t: Terrain) -> fn(Cell) -> Bool {
  fn(cell) {
    case model.cell_terrain(cell) {
      option.Some(c) -> c == t
      option.None -> False
    }
  }
}

import gleam/option

/// Connected groups of orthogonally-adjacent cells satisfying `pred`.
pub fn clusters(grid: Grid, pred: fn(Cell) -> Bool) -> List(List(Coord)) {
  let size = model.grid_size(grid)
  let matching =
    model.all_coords(size)
    |> list.filter(fn(c) {
      case model.grid_at(grid, c.0, c.1) {
        Ok(cell) -> pred(cell)
        Error(Nil) -> False
      }
    })
  do_clusters(grid, matching, pred, [], set.new())
}

fn do_clusters(
  grid: Grid,
  remaining: List(Coord),
  pred: fn(Cell) -> Bool,
  acc: List(List(Coord)),
  visited: Set(Coord),
) -> List(List(Coord)) {
  case remaining {
    [] -> list.reverse(acc)
    [c, ..rest] ->
      case set.contains(visited, c) {
        True -> do_clusters(grid, rest, pred, acc, visited)
        False -> {
          let #(cluster, visited2) =
            flood(grid, [c], pred, [], set.insert(visited, c))
          do_clusters(grid, rest, pred, [cluster, ..acc], visited2)
        }
      }
  }
}

fn flood(
  grid: Grid,
  stack: List(Coord),
  pred: fn(Cell) -> Bool,
  cluster: List(Coord),
  visited: Set(Coord),
) -> #(List(Coord), Set(Coord)) {
  case stack {
    [] -> #(list.reverse(cluster), visited)
    [c, ..rest] -> {
      let size = model.grid_size(grid)
      let new =
        model.neighbors4(size, c)
        |> list.filter(fn(n) {
          !set.contains(visited, n)
          && case model.grid_at(grid, n.0, n.1) {
            Ok(cell) -> pred(cell)
            Error(Nil) -> False
          }
        })
      let visited2 = list.fold(new, visited, set.insert)
      flood(grid, list.append(new, rest), pred, [c, ..cluster], visited2)
    }
  }
}

fn adjacent_to_terrain(grid: Grid, coord: Coord, t: Terrain) -> Bool {
  let size = model.grid_size(grid)
  use n <- list.any(model.neighbors4(size, coord))
  case model.grid_at(grid, n.0, n.1) {
    Ok(cell) -> model.cell_terrain(cell) == option.Some(t)
    Error(Nil) -> False
  }
}

/// Terrains of all filled spaces orthogonally adjacent to `coord` (deduped caller-side).
fn adjacent_terrains(grid: Grid, coord: Coord) -> List(Terrain) {
  let size = model.grid_size(grid)
  use n <- list.filter_map(model.neighbors4(size, coord))
  case model.grid_at(grid, n.0, n.1) {
    Ok(cell) ->
      case model.cell_terrain(cell) {
        option.Some(t) -> Ok(t)
        option.None -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn count_where(coords: List(Coord), pred: fn(Coord) -> Bool) -> Int {
  list.count(coords, pred)
}

// ---------------------------------------------------------------------------
// The sixteen scoring cards
// ---------------------------------------------------------------------------

pub fn score(kind: EdictKind, grid: Grid) -> Int {
  case kind {
    SentinelWood -> sentinel_wood(grid)
    Greenbough -> greenbough(grid)
    Treetower -> treetower(grid)
    StonesideForest -> stoneside_forest(grid)
    CanalLake -> canal_lake(grid)
    GoldenGranary -> golden_granary(grid)
    MagesValley -> mages_valley(grid)
    ShoresideExpanse -> shoreside_expanse(grid)
    Wildholds -> wildholds(grid)
    GreatCity -> great_city(grid)
    Shieldgate -> shieldgate(grid)
    GreengoldPlains -> greengold_plains(grid)
    Borderlands -> borderlands(grid)
    BrokenRoad -> broken_road(grid)
    LostBarony -> lost_barony(grid)
    Cauldrons -> cauldrons(grid)
  }
}

fn sentinel_wood(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  count_where(model.coords_with(grid, model.Forest), fn(c) {
    model.is_edge(size, c)
  })
}

fn greenbough(grid: Grid) -> Int {
  let forests = model.coords_with(grid, model.Forest)
  let rows = list.unique(list.map(forests, fn(c) { c.0 })) |> list.length
  let cols = list.unique(list.map(forests, fn(c) { c.1 })) |> list.length
  rows + cols
}

fn treetower(grid: Grid) -> Int {
  count_where(model.coords_with(grid, model.Forest), fn(c) {
    model.surrounded_by_filled_or_edge(grid, c)
  })
}

fn stoneside_forest(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  // Every mountain whose adjacent forest cluster also touches another
  // mountain earns 3. Each mountain scores at most once.
  let connected =
    clusters(grid, terrain_pred(model.Forest))
    |> list.flat_map(fn(cluster) {
      let touching =
        cluster
        |> list.flat_map(fn(c) { model.neighbors4(size, c) })
        |> list.filter(fn(n) {
          case model.grid_at(grid, n.0, n.1) {
            Ok(cell) -> model.cell_terrain(cell) == option.Some(model.Mountain)
            Error(Nil) -> False
          }
        })
        |> list.unique
      case list.length(touching) >= 2 {
        True -> touching
        False -> []
      }
    })
    |> list.unique
  3 * list.length(connected)
}

fn canal_lake(grid: Grid) -> Int {
  let waters =
    count_where(model.coords_with(grid, model.Water), fn(c) {
      adjacent_to_terrain(grid, c, model.Farm)
    })
  let farms =
    count_where(model.coords_with(grid, model.Farm), fn(c) {
      adjacent_to_terrain(grid, c, model.Water)
    })
  waters + farms
}

fn golden_granary(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  let waters =
    count_where(model.coords_with(grid, model.Water), fn(c) {
      use n <- list.any(model.neighbors4(size, c))
      case model.grid_at(grid, n.0, n.1) {
        Ok(cell) -> model.on_ruins(cell)
        Error(Nil) -> False
      }
    })
  let farms_on_ruins =
    model.coords_matching(grid, fn(cell) {
      model.cell_terrain(cell) == option.Some(model.Farm) && model.on_ruins(cell)
    })
    |> list.length
  waters + 3 * farms_on_ruins
}

fn mages_valley(grid: Grid) -> Int {
  let waters =
    count_where(model.coords_with(grid, model.Water), fn(c) {
      adjacent_to_terrain(grid, c, model.Mountain)
    })
  let farms =
    count_where(model.coords_with(grid, model.Farm), fn(c) {
      adjacent_to_terrain(grid, c, model.Mountain)
    })
  2 * waters + farms
}

fn shoreside_expanse(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  let farms =
    clusters(grid, terrain_pred(model.Farm))
    |> list.count(fn(cluster) {
      list.all(cluster, fn(c) {
        !model.is_edge(size, c) && !adjacent_to_terrain(grid, c, model.Water)
      })
    })
  let waters =
    clusters(grid, terrain_pred(model.Water))
    |> list.count(fn(cluster) {
      list.all(cluster, fn(c) {
        !model.is_edge(size, c) && !adjacent_to_terrain(grid, c, model.Farm)
      })
    })
  3 * farms + 3 * waters
}

fn wildholds(grid: Grid) -> Int {
  clusters(grid, terrain_pred(model.Village))
  |> list.count(fn(cluster) { list.length(cluster) >= 6 })
  |> int.multiply(8)
}

fn great_city(grid: Grid) -> Int {
  let eligible =
    clusters(grid, terrain_pred(model.Village))
    |> list.filter(fn(cluster) {
      list.all(cluster, fn(c) { !adjacent_to_terrain(grid, c, model.Mountain) })
    })
    |> list.map(list.length)
    |> list.sort(int.compare)
    |> list.reverse
  case eligible {
    [biggest, ..] -> biggest
    [] -> 0
  }
}

fn shieldgate(grid: Grid) -> Int {
  let sizes =
    clusters(grid, terrain_pred(model.Village))
    |> list.map(list.length)
    |> list.sort(int.compare)
    |> list.reverse
  case sizes {
    [_, second, ..] -> 2 * second
    // "If there are multiple largest clusters, score one of the largest" —
    // i.e. sorting desc and taking index 1 does exactly that.
    _ -> 0
  }
}

fn greengold_plains(grid: Grid) -> Int {
  clusters(grid, terrain_pred(model.Village))
  |> list.count(fn(cluster) {
    let kinds =
      cluster
      |> list.flat_map(fn(c) { adjacent_terrains(grid, c) })
      |> list.unique
      |> list.filter(fn(t) { t != model.Village })
    list.length(kinds) >= 3
  })
  |> int.multiply(3)
}

fn borderlands(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  let rows =
    list.count(model.ints(0, size - 1), fn(r) {
      list.all(model.ints(0, size - 1), fn(c) {
        case model.grid_at(grid, r, c) {
          Ok(cell) -> model.is_filled(cell)
          Error(Nil) -> False
        }
      })
    })
  let cols =
    list.count(model.ints(0, size - 1), fn(c) {
      list.all(model.ints(0, size - 1), fn(r) {
        case model.grid_at(grid, r, c) {
          Ok(cell) -> model.is_filled(cell)
          Error(Nil) -> False
        }
      })
    })
  6 * { rows + cols }
}

fn broken_road(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  // Diagonals with r - c = d, d in 0..size-1: each touches the left edge
  // (row d, col 0) and the bottom edge (row size-1, col size-1-d).
  list.count(model.ints(0, size - 1), fn(d) {
    list.all(model.ints(d, size - 1), fn(r) {
      case model.grid_at(grid, r, r - d) {
        Ok(cell) -> model.is_filled(cell)
        Error(Nil) -> False
      }
    })
  })
  |> int.multiply(3)
}

fn lost_barony(grid: Grid) -> Int {
  let size = model.grid_size(grid)
  let best =
    model.ints(1, size)
    |> list.fold(0, fn(best, k) {
      case k > best && has_filled_square(grid, size, k) {
        True -> k
        False -> best
      }
    })
  3 * best
}

fn has_filled_square(grid: Grid, size: Int, k: Int) -> Bool {
  use r <- list.any(model.ints(0, size - k))
  use c <- list.any(model.ints(0, size - k))
  use dr <- list.all(model.ints(r, r + k - 1))
  use dc <- list.all(model.ints(c, c + k - 1))
  case model.grid_at(grid, dr, dc) {
    Ok(cell) -> model.is_filled(cell)
    Error(Nil) -> False
  }
}

fn cauldrons(grid: Grid) -> Int {
  model.coords_matching(grid, fn(cell) { !model.is_filled(cell) })
  |> count_where(fn(c) { model.surrounded_by_filled_or_edge(grid, c) })
}

/// Season-end monster penalty: 1 per empty space adjacent to a monster space.
pub fn monster_penalty(grid: Grid) -> Int {
  model.coords_matching(grid, fn(cell) { !model.is_filled(cell) })
  |> count_where(fn(c) { adjacent_to_terrain(grid, c, model.Monster) })
}
