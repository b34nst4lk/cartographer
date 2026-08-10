//// Thin FFI layer for browser storage and misc host services.

/// Reads the save blob from localStorage ("" when empty/unavailable).
pub fn load_save() -> String {
  do_load_save()
}

/// Persists the save blob.
pub fn store_save(json: String) -> Nil {
  do_store_save(json)
}

/// Deletes the save blob entirely.
pub fn clear_save() -> Nil {
  do_clear_save()
}

/// Milliseconds-based seed for new games.
pub fn now_int() -> Int {
  do_now_int()
}

/// Moves keyboard focus onto the game root so hotkeys work, unless the user
/// is currently typing into an input field.
pub fn focus_game_root() -> Nil {
  do_focus_game_root()
}

@external(javascript, "./store_ffi.mjs", "load_save")
fn do_load_save() -> String {
  ""
}

@external(javascript, "./store_ffi.mjs", "store_save")
fn do_store_save(_json: String) -> Nil {
  Nil
}

@external(javascript, "./store_ffi.mjs", "clear_save")
fn do_clear_save() -> Nil {
  Nil
}

@external(javascript, "./store_ffi.mjs", "now_int")
fn do_now_int() -> Int {
  0
}

@external(javascript, "./store_ffi.mjs", "focus_game_root")
fn do_focus_game_root() -> Nil {
  Nil
}
