const KEY = "cartographers-solo-save-v1";

export function load_save() {
  try {
    return localStorage.getItem(KEY) ?? "";
  } catch (_e) {
    return "";
  }
}

export function store_save(json) {
  try {
    localStorage.setItem(KEY, json);
  } catch (_e) {}
}

export function clear_save() {
  try {
    localStorage.removeItem(KEY);
  } catch (_e) {}
}

export function now_int() {
  return Math.floor(Date.now() % 2147483647);
}

export function focus_game_root() {
  try {
    const active = document.activeElement;
    const tag = active && active.tagName;
    // never steal focus while the player is typing somewhere
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    document.getElementById("game-root")?.focus({ preventScroll: true });
  } catch (_e) {}
}
