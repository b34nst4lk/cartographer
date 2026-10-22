//// Tiny self-contained deterministic RNG so the whole game state — including
//// the random source — can be serialized (unlike opaque library seeds).
//// Uses the classic LCG constants (Numerical Recipes): the modulus is 2^32
//// and the multiplier keeps all intermediate products below 2^53, so the
//// arithmetic is exact even on JavaScript's float64 integers.

import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/result

/// The RNG state; plain Int so it can be saved.
pub type Rng =
  Int

const modulus = 4_294_967_296

const multiplier = 1_664_525

const increment = 1_013_904_223

pub fn new(seed: Int) -> Rng {
  let abs = int.absolute_value(seed)
  result.unwrap(int.modulo(abs, modulus), 0)
}

fn step(state: Rng) -> #(Rng, Rng) {
  let next =
    result.unwrap(int.modulo(state * multiplier + increment, modulus), 0)
  #(next, next)
}

/// Uniform int in [lo, hi] (modulo bias is irrelevant at our scales).
pub fn int(state: Rng, lo: Int, hi: Int) -> #(Int, Rng) {
  let #(x, state2) = step(state)
  let span = hi - lo + 1
  #(lo + result.unwrap(int.modulo(x, span), 0), state2)
}

/// Fisher-Yates via random sort keys (order of equal keys is preserved).
pub fn shuffle(state: Rng, items: List(a)) -> #(List(a), Rng) {
  let #(keyed, state2) =
    list.fold(items, #([], state), fn(acc, item) {
      let #(pairs, s) = acc
      let #(key, s2) = step(s)
      #([#(key, item), ..pairs], s2)
    })
  let sorted = list.sort(keyed, fn(a, b) { compare(a.0, b.0) })
  #(list.map(sorted, fn(p) { p.1 }), state2)
}

fn compare(a: Int, b: Int) -> Order {
  int.compare(a, b)
}

/// Draw one element uniformly. Returns Error on empty lists.
pub fn pick(state: Rng, items: List(a)) -> Result(#(a, Rng), Nil) {
  case items {
    [] -> Error(Nil)
    _ -> {
      let #(i, s2) = int(state, 0, list.length(items) - 1)
      case get_at(items, i) {
        Ok(x) -> Ok(#(x, s2))
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

fn get_at(items: List(a), i: Int) -> Result(a, Nil) {
  case items {
    [] -> Error(Nil)
    [x, ..rest] ->
      case i <= 0 {
        True -> Ok(x)
        False -> get_at(rest, i - 1)
      }
  }
}
