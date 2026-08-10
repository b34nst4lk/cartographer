import game/model.{type Piece, type Terrain, Forest, Farm, Water, Village, Monster} as model
import gleam/list

// ---------------------------------------------------------------------------
// Explore cards
// ---------------------------------------------------------------------------

/// One way to resolve an explore card: draw this shape, fill it with this
/// terrain, and if `coin` is True, fill in one coin symbol.
pub type Variant {
  Variant(piece: Piece, terrain: Terrain, coin: Bool)
}

pub type ExploreCard {
  ExploreCard(id: String, name: String, time: Int, variants: List(Variant))
}

fn v(rows: List(String), terrain: Terrain, coin: Bool) -> Variant {
  Variant(model.piece(rows), terrain, coin)
}

/// The 11 explore cards of the base game (the two ruins cards are separate).
pub fn explore_cards() -> List(ExploreCard) {
  [
    ExploreCard("hinterland-stream", "Hinterland Stream", 2, [
      v(["###", "#..", "#.."], Farm, False),
      v(["###", "#..", "#.."], Water, False),
    ]),
    ExploreCard("homestead", "Homestead", 2, [
      v(["#.", "##", "#."], Village, False),
      v(["#.", "##", "#."], Farm, False),
    ]),
    ExploreCard("orchard", "Orchard", 2, [
      v(["###", "..#"], Forest, False),
      v(["###", "..#"], Farm, False),
    ]),
    ExploreCard("treetop-village", "Treetop Village", 2, [
      v(["..##", "###."], Forest, False),
      v(["..##", "###."], Village, False),
    ]),
    ExploreCard("marshlands", "Marshlands", 2, [
      v(["#..", "###", "#.."], Forest, False),
      v(["#..", "###", "#.."], Water, False),
    ]),
    ExploreCard("fishing-village", "Fishing Village", 2, [
      v(["####"], Village, False),
      v(["####"], Water, False),
    ]),
    ExploreCard("great-river", "Great River", 1, [
      v(["..#", ".##", "##."], Water, False),
      v(["#", "#", "#"], Water, True),
    ]),
    ExploreCard("farmland", "Farmland", 1, [
      v([".#.", "###", ".#."], Farm, False),
      v(["#", "#"], Farm, True),
    ]),
    ExploreCard("forgotten-forest", "Forgotten Forest", 1, [
      v(["#.", "##", ".#"], Forest, False),
      v(["#.", ".#"], Forest, True),
    ]),
    ExploreCard("hamlet", "Hamlet", 1, [
      v(["###", "##."], Village, False),
      v(["##"], Village, True),
    ]),
    ExploreCard("rift-lands", "Rift Lands", 0, [
      v(["#"], Forest, False),
      v(["#"], Village, False),
      v(["#"], Farm, False),
      v(["#"], Water, False),
      v(["#"], Monster, False),
    ]),
  ]
}

// ---------------------------------------------------------------------------
// Ruins cards
// ---------------------------------------------------------------------------

pub type RuinsCard {
  RuinsCard(id: String, name: String)
}

// NOTE: verify official English names of the two ruins cards.
pub fn ruins_cards() -> List(RuinsCard) {
  [
    RuinsCard("outpost-ruins", "Outpost Ruins"),
    RuinsCard("temple-ruins", "Temple Ruins"),
  ]
}

// ---------------------------------------------------------------------------
// Ambush cards
// ---------------------------------------------------------------------------

pub type Corner {
  TopLeft
  TopRight
  BottomLeft
  BottomRight
}

pub type Direction {
  Clockwise
  CounterClockwise
}

/// `corner` + `direction` drive the solo placement algorithm (upper-right
/// icon on the physical card).
pub type AmbushCard {
  AmbushCard(
    id: String,
    name: String,
    shape: Piece,
    corner: Corner,
    direction: Direction,
  )
}

pub fn ambush_cards() -> List(AmbushCard) {
  [
    AmbushCard(
      "goblin-onslaught",
      "Goblin Onslaught",
      model.piece(["#..", ".#.", "..#"]),
      BottomRight,
      CounterClockwise,
    ),
    AmbushCard(
      "bugbear-assault",
      "Bugbear Assault",
      model.piece(["#.#", "#.#"]),
      TopRight,
      Clockwise,
    ),
    AmbushCard(
      "gnoll-attack",
      "Gnoll Attack",
      model.piece(["##", "#.", "##"]),
      TopLeft,
      CounterClockwise,
    ),
    AmbushCard(
      "kobold-raid",
      "Kobold Raid",
      model.piece(["#.", "##", "#."]),
      BottomLeft,
      Clockwise,
    ),
  ]
}

// ---------------------------------------------------------------------------
// Deck entries
// ---------------------------------------------------------------------------

pub type DeckEntry {
  Explore(ExploreCard)
  Ruins(RuinsCard)
  Ambush(AmbushCard)
}

/// Time an entry adds to the season clock (ruins and ambushes are instant).
pub fn entry_time(entry: DeckEntry) -> Int {
  case entry {
    Explore(card) -> card.time
    Ruins(_) -> 0
    Ambush(_) -> 0
  }
}

// ---------------------------------------------------------------------------
// Scoring cards (edicts)
// ---------------------------------------------------------------------------

/// The four scoring-card stacks (colors on the card backs):
/// forest group (green), hamlet group (yellow), river & farmlands (blue),
/// arrangement group (red).
pub type EdictGroup {
  ForestGroup
  HamletGroup
  WaterFarmGroup
  ArrangementGroup
}

pub type EdictKind {
  SentinelWood
  Greenbough
  Treetower
  StonesideForest
  CanalLake
  GoldenGranary
  MagesValley
  ShoresideExpanse
  Wildholds
  GreatCity
  Shieldgate
  GreengoldPlains
  Borderlands
  BrokenRoad
  LostBarony
  Cauldrons
}

/// `corner` is the number printed in the lower right corner, subtracted from
/// the player's score in solo mode.
pub type EdictCard {
  EdictCard(
    kind: EdictKind,
    name: String,
    group: EdictGroup,
    corner: Int,
    text: String,
  )
}

pub fn all_edicts() -> List(EdictCard) {
  [
    EdictCard(SentinelWood, "Sentinel Wood", ForestGroup, 25,
      "Earn one reputation star for each forest space adjacent to the edge of the map."),
    EdictCard(Greenbough, "Greenbough", ForestGroup, 22,
      "Earn one reputation star for each row and column with at least one forest space. The same forest space may be scored in a row and a column."),
    EdictCard(Treetower, "Treetower", ForestGroup, 17,
      "Earn one reputation star for each forest space surrounded on all four sides by filled spaces or the edge of the map."),
    EdictCard(StonesideForest, "Stoneside Forest", ForestGroup, 18,
      "Earn three reputation stars for each mountain space connected to another mountain space by a cluster of forest spaces."),
    EdictCard(CanalLake, "Canal Lake", WaterFarmGroup, 24,
      "Earn one reputation star for each water space adjacent to at least one farm space. Earn one reputation star for each farm space adjacent to at least one water space."),
    EdictCard(GoldenGranary, "The Golden Granary", WaterFarmGroup, 20,
      "Earn one reputation star for each water space adjacent to a ruins space. Earn three reputation stars for each farm space on a ruins space."),
    EdictCard(MagesValley, "Mages Valley", WaterFarmGroup, 22,
      "Earn two reputation stars for each water space adjacent to a mountain space. Earn one reputation star for each farm space adjacent to a mountain space."),
    EdictCard(ShoresideExpanse, "Shoreside Expanse", WaterFarmGroup, 27,
      "Earn three reputation stars for each cluster of farm spaces not adjacent to a water space or the edge of the map. Earn three reputation stars for each cluster of water spaces not adjacent to a farm space or the edge of the map."),
    EdictCard(Wildholds, "Wildholds", HamletGroup, 16,
      "Earn eight reputation stars for each cluster of six or more village spaces."),
    EdictCard(GreatCity, "Great City", HamletGroup, 16,
      "Earn one reputation star for each village space in the largest cluster of village spaces that is not adjacent to a mountain space."),
    EdictCard(Shieldgate, "Shieldgate", HamletGroup, 20,
      "Earn two reputation stars for each village space in the second largest cluster of village spaces. If there are multiple largest clusters, score one of the largest."),
    EdictCard(GreengoldPlains, "Greengold Plains", HamletGroup, 21,
      "Earn three reputation stars for each cluster of villages spaces that is adjacent to three or more different terrain types."),
    EdictCard(Borderlands, "Borderlands", ArrangementGroup, 24,
      "Earn six reputation stars for each complete row or complete column of filled spaces."),
    EdictCard(BrokenRoad, "The Broken Road", ArrangementGroup, 24,
      "Earn three reputation stars for each complete diagonal line of filled spaces that touches the left and bottom edges of the map."),
    EdictCard(LostBarony, "The Lost Barony", ArrangementGroup, 24,
      "Earn three reputation stars for each space along one edge of the largest square of filled spaces."),
    EdictCard(Cauldrons, "The Cauldrons", ArrangementGroup, 20,
      "Earn one reputation star for each empty space surrounded on all four sides by filled spaces or the edge of the map."),
  ]
}

pub fn edicts_in_group(group: EdictGroup) -> List(EdictCard) {
  list.filter(all_edicts(), fn(e: EdictCard) { e.group == group })
}

// ---------------------------------------------------------------------------
// Card lookup helpers (used e.g. when restoring a saved game)
// ---------------------------------------------------------------------------

pub fn explore_by_id(id: String) -> Result(ExploreCard, Nil) {
  list.find(explore_cards(), fn(c) { c.id == id })
}

pub fn ruins_by_id(id: String) -> Result(RuinsCard, Nil) {
  list.find(ruins_cards(), fn(c) { c.id == id })
}

pub fn ambush_by_id(id: String) -> Result(AmbushCard, Nil) {
  list.find(ambush_cards(), fn(c) { c.id == id })
}

pub fn edict_kind_id(kind: EdictKind) -> String {
  case kind {
    SentinelWood -> "sentinel-wood"
    Greenbough -> "greenbough"
    Treetower -> "treetower"
    StonesideForest -> "stoneside-forest"
    CanalLake -> "canal-lake"
    GoldenGranary -> "golden-granary"
    MagesValley -> "mages-valley"
    ShoresideExpanse -> "shoreside-expanse"
    Wildholds -> "wildholds"
    GreatCity -> "great-city"
    Shieldgate -> "shieldgate"
    GreengoldPlains -> "greengold-plains"
    Borderlands -> "borderlands"
    BrokenRoad -> "broken-road"
    LostBarony -> "lost-barony"
    Cauldrons -> "cauldrons"
  }
}

pub fn edict_by_id(id: String) -> Result(EdictCard, Nil) {
  list.find(all_edicts(), fn(c) { edict_kind_id(c.kind) == id })
}

pub fn entry_id(entry: DeckEntry) -> String {
  case entry {
    Explore(c) -> "e:" <> c.id
    Ruins(c) -> "r:" <> c.id
    Ambush(c) -> "a:" <> c.id
  }
}

pub fn entry_by_id(id: String) -> Result(DeckEntry, Nil) {
  case id {
    "e:" <> rest ->
      case explore_by_id(rest) {
        Ok(c) -> Ok(Explore(c))
        Error(Nil) -> Error(Nil)
      }
    "r:" <> rest ->
      case ruins_by_id(rest) {
        Ok(c) -> Ok(Ruins(c))
        Error(Nil) -> Error(Nil)
      }
    "a:" <> rest ->
      case ambush_by_id(rest) {
        Ok(c) -> Ok(Ambush(c))
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// The four stacks in drawing order.
pub fn edict_groups() -> List(EdictGroup) {
  [ForestGroup, HamletGroup, WaterFarmGroup, ArrangementGroup]
}

pub fn group_name(group: EdictGroup) -> String {
  case group {
    ForestGroup -> "forest"
    HamletGroup -> "hamlet"
    WaterFarmGroup -> "river & farmlands"
    ArrangementGroup -> "arrangement"
  }
}
