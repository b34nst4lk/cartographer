import game/cards.{type AmbushCard, type DeckEntry, Ambush, Explore, Ruins}
import game/rng.{type Rng}
import gleam/int
import gleam/list

/// Edicts are the four fixed letters in the play area; one scoring card is
/// randomly placed below each at setup.
pub type EdictLetter {
  A
  B
  C
  D
}

pub fn letter_name(letter: EdictLetter) -> String {
  case letter {
    A -> "A"
    B -> "B"
    C -> "C"
    D -> "D"
  }
}

pub fn letter_id(letter: EdictLetter) -> String {
  letter_name(letter)
}

pub fn letter_from_id(id: String) -> Result(EdictLetter, Nil) {
  case id {
    "A" -> Ok(A)
    "B" -> Ok(B)
    "C" -> Ok(C)
    "D" -> Ok(D)
    _ -> Error(Nil)
  }
}

fn letter_index(letter: EdictLetter) -> Int {
  case letter {
    A -> 0
    B -> 1
    C -> 2
    D -> 3
  }
}

pub type SeasonInfo {
  SeasonInfo(name: String, threshold: Int, edicts: #(EdictLetter, EdictLetter))
}

pub fn season_info(index: Int) -> SeasonInfo {
  case index {
    0 -> SeasonInfo("Spring", 8, #(A, B))
    1 -> SeasonInfo("Summer", 8, #(B, C))
    2 -> SeasonInfo("Fall", 7, #(C, D))
    _ -> SeasonInfo("Winter", 6, #(D, A))
  }
}

pub const season_count = 4

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

fn first_of_shuffled(l: List(a), s: Rng) -> #(a, Rng) {
  let #(shuffled, s2) = rng.shuffle(s, l)
  let assert [x, ..] = shuffled
  #(x, s2)
}

/// Draw one scoring card from each of the four stacks and place them in
/// random order below edicts A–D. Returned list is sorted by letter.
pub fn draw_edicts(s: Rng) -> #(List(#(EdictLetter, cards.EdictCard)), Rng) {
  let #(picked, s1) =
    list.fold(cards.edict_groups(), #([], s), fn(acc, group) {
      let #(card, seed2) =
        first_of_shuffled(cards.edicts_in_group(group), acc.1)
      #([card, ..acc.0], seed2)
    })
  let #(letters, s2) = rng.shuffle(s1, [A, B, C, D])
  let pairs = list.zip(letters, picked)
  let sorted =
    list.sort(pairs, fn(p, q) {
      int.compare(letter_index(p.0), letter_index(q.0))
    })
  #(sorted, s2)
}

/// Shuffle the four ambush cards into a face-down pile.
pub fn new_ambush_pile(s: Rng) -> #(List(AmbushCard), Rng) {
  rng.shuffle(s, cards.ambush_cards())
}

/// The 13 explore-deck cards: 11 explore + 2 ruins.
fn explore_entries() -> List(DeckEntry) {
  list.map(cards.explore_cards(), Explore)
  |> list.append(list.map(cards.ruins_cards(), Ruins))
}

/// Build one season's deck: all explore cards plus the ambushes currently in
/// play (carried over undrawn from previous seasons, if any) plus the top
/// card of the ambush pile, shuffled without revealing it.
/// Returns: new deck, remaining ambush pile, ambushes now in the deck, seed.
pub fn build_season_deck(
  s: Rng,
  carried: List(AmbushCard),
  pile: List(AmbushCard),
) -> #(List(DeckEntry), List(AmbushCard), List(AmbushCard), Rng) {
  let #(top, pile2) = case pile {
    [t, ..rest] -> #(Ok(t), rest)
    [] -> #(Error(Nil), pile)
  }
  let carried2 = case top {
    Ok(a) -> [a, ..carried]
    Error(Nil) -> carried
  }
  let entries = list.append(explore_entries(), list.map(carried2, cards.Ambush))
  let #(shuffled, s2) = rng.shuffle(s, entries)
  #(shuffled, pile2, carried2, s2)
}

/// Ambush cards that were in the season deck but never got revealed carry
/// over to the next season (drawn ambushes are removed from the game).
pub fn undrawn_ambushes(deck: List(DeckEntry)) -> List(AmbushCard) {
  use entry <- list.filter_map(deck)
  case entry {
    Ambush(a) -> Ok(a)
    _ -> Error(Nil)
  }
}
