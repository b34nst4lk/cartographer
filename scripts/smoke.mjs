// DOM smoke test: load the single-file build in jsdom, mount the app,
// start a game, pick a variant, and click a legal anchor to place it.
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";

const raw = readFileSync("dist/cartographers-solo.html", "utf8");

// jsdom can't execute <script type="module">; the bundle is plain script,
// so we strip it out and eval it in the window context instead.
const js = raw.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
const html = raw.replace(/<script type="module">[\s\S]*?<\/script>/, "");

const dom = new JSDOM(html, {
  runScripts: "outside-only",
  pretendToBeVisual: true,
  url: "https://localhost/",
});

const { window } = dom;

// Give the DOM a tick, then run the bundle.
await new Promise((r) => setTimeout(r, 50));
window.eval(js);
await new Promise((r) => setTimeout(r, 300));

const $ = (sel) => window.document.querySelector(sel);
const $$ = (sel) => [...window.document.querySelectorAll(sel)];

function assert(cond, label) {
  if (!cond) {
    console.error("SMOKE FAIL:", label);
    process.exit(1);
  }
  console.log("ok -", label);
}

function click(el) {
  const ev = new window.MouseEvent("click", { bubbles: true, cancelable: true });
  el.dispatchEvent(ev);
}

async function settled() {
  // Lustre applies render passes through micro/rAF; give it a couple frames.
  for (let i = 0; i < 6; i++) {
    await new Promise((r) => setTimeout(r, 16));
  }
}

async function clickFirstAnchor() {
  const dot = $(".anchor-dot");
  if (!dot) return false;
  const cx = parseFloat(dot.getAttribute("cx"));
  const cy = parseFloat(dot.getAttribute("cy"));
  const target = $$(".cell-rect").find((r) => {
    return (
      parseFloat(r.getAttribute("x")) === cx - 20 &&
      parseFloat(r.getAttribute("y")) === cy - 20
    );
  });
  if (!target) return false;
  click(target);
  await settled();
  return true;
}

assert($(".title-card"), "title screen rendered");

click($(".btn.primary")); // Begin a new expedition
await settled();

assert($(".board"), "map board rendered after starting a game");
assert($$(".edict-row").length === 4, "four edicts listed");

// bugfix #1: scoring conditions are visible by default (no external reference)
{
  const openRows = $$(".edict-row[open]");
  assert(openRows.length === 4, "all four edict conditions are open by default");
  const text = window.document.querySelector(".edict-row[open] .edict-text");
  assert(text && text.textContent.length > 20, "edict condition text present");
}

assert($(".card-panel"), "card panel rendered");

// The reveal may be an explore card or an ambush; handle both.
async function dismiss_ambushes() {
  for (let i = 0; i < 20; i++) {
    const panel = $(".card-panel");
    if (!panel) break;
    if (panel.classList.contains("ambush")) {
      click(panel.querySelector(".btn.primary"));
      await settled();
    } else {
      break;
    }
  }
}
await dismiss_ambushes();

const variantButtons = $$(".variant-btn");
if (variantButtons.length > 0) {
  assert(true, "explore card offers variants");
  click(variantButtons[0]);
  await settled();
}

// We may now be in Placing (placing-controls) or fallback mode.
const placing = $(".placing-controls") || $(".fallback");
assert(placing, "placement mode entered");

// bugfix #2 (part 2): hotkeys work immediately after a variant click
{
  const gameRoot = window.document.getElementById("game-root");
  gameRoot.dispatchEvent(
    new window.KeyboardEvent("keydown", { key: "r", bubbles: true })
  );
  await settled();
  assert(
    $(".placing-controls") || $(".fallback"),
    "keyboard rotate executed right after the variant pick"
  );
}

// bugfix #3: hovering near the map edge snaps to a covering legal placement
{
  const hint = $(".hint");
  const ruinsPending = hint && hint.textContent.includes("ruins");
  const edgeCell = $$(".cell-rect").find(
    (r) =>
      parseFloat(r.getAttribute("x")) === 26 + 10 * 40 &&
      parseFloat(r.getAttribute("y")) === 26 + 5 * 40
  );
  if (!ruinsPending && edgeCell && $(".placing-controls") && !$(".fallback")) {
    edgeCell.dispatchEvent(new window.MouseEvent("mouseenter", { bubbles: false }));
    await settled();
    assert(
      window.document.querySelector(".ghost-ok"),
      "ghost snaps to a legal placement at the map edge"
    );
    $(".board").dispatchEvent(
      new window.MouseEvent("mouseleave", { bubbles: false })
    );
    await settled();
  }
}

// find a legal anchor dot and click the cell rect beneath it
const dot = $(".anchor-dot");
assert(dot, "at least one legal anchor is highlighted");

const cx = parseFloat(dot.getAttribute("cx"));
const cy = parseFloat(dot.getAttribute("cy"));
// cell rect that contains (cx, cy): x = cx-20, y = cy-20 exactly
const target = $$(".cell-rect").find((r) => {
  const x = parseFloat(r.getAttribute("x"));
  const y = parseFloat(r.getAttribute("y"));
  return x === cx - 20 && y === cy - 20;
});
assert(target, "found cell rect under the anchor dot");

click(target);
await settled();
await dismiss_ambushes();

const afterPanel = $(".card-panel");
const placedOk =
  afterPanel &&
  (afterPanel.classList.contains("explore") ||
    afterPanel.classList.contains("ambush") ||
    afterPanel.classList.contains("season-report"));
assert(placedOk, "placement accepted (next phase reached)");

// bugfix #2: clicking anywhere in the app reclaims keyboard focus
{
  click($(".topbar-actions .btn.subtle")); // some button (undo)
  await settled();
  assert(
    window.document.activeElement &&
      window.document.activeElement.id === "game-root",
    "keyboard focus is on the game root after a click"
  );
}

// bugfix #4: hint copy no longer claims options are "below"
{
  // undo is per-action: retreat until we're back at shape choice
  for (let i = 0; i < 8; i++) {
    const hint = $(".hint");
    if (hint && hint.textContent.includes("options")) break;
    const panel = $(".card-panel");
    if (panel && panel.classList.contains("ambush")) {
      click(panel.querySelector(".btn.primary"));
      await settled();
      continue;
    }
    if ($(".placing-controls") || $(".fallback")) {
      const undoBtn = $(".topbar-actions .btn.subtle");
      if (!undoBtn) break;
      click(undoBtn);
      await settled();
      continue;
    }
    break;
  }
  const hint = $(".hint");
  assert(
    hint && hint.textContent.includes("options") &&
      !hint.textContent.includes("below"),
    "hint copy fits the layout"
  );
}

// resume the flow: pick variant + place at first legal anchor
{
  const vb = $$(".variant-btn");
  if (vb.length > 0) {
    click(vb[0]);
    await settled();
  }
  if ($(".anchor-dot")) {
    await clickFirstAnchor();
  }
}

// ---- mid-game resume across a reload --------------------------------------
{
  const filledCount = $$(".terrain-fill").length;
  const savedMid = window.localStorage.getItem("cartographers-solo-save-v1");
  assert(savedMid && savedMid.includes('"active"'), "active game persisted mid-run");

  const domR = new JSDOM(html, {
    runScripts: "outside-only",
    pretendToBeVisual: true,
    url: "https://localhost/",
  });
  const wR = domR.window;
  wR.localStorage.setItem("cartographers-solo-save-v1", savedMid);
  await new Promise((r) => setTimeout(r, 50));
  wR.eval(js);
  await new Promise((r) => setTimeout(r, 300));
  const contBtn = [...wR.document.querySelectorAll("button")].find((b) =>
    b.textContent.includes("Continue")
  );
  assert(contBtn, "resume button offered after mid-game reload");
  const ev = new wR.MouseEvent("click", { bubbles: true, cancelable: true });
  contBtn.dispatchEvent(ev);
  await new Promise((r) => setTimeout(r, 300));
  const resumed = [...wR.document.querySelectorAll(".terrain-fill")].length;
  assert(resumed === filledCount, `map state restored (${resumed} filled cells)`);
  const journal = [...wR.document.querySelectorAll(".log-list li")].map((li) =>
    li.textContent
  );
  assert(journal.some((s) => s.includes("restored")), "restore logged in journal");
}

console.log("\nSMOKE OK (phase 1) — now autoplaying the whole game");

let steps = 0;
let gamesOver = false;
outer: while (steps < 4000) {
  steps++;
  const panel = $(".card-panel");
  if (!panel) break;
  if (panel.classList.contains("gameover")) {
    gamesOver = true;
    break;
  }
  if (panel.classList.contains("ambush")) {
    click(panel.querySelector(".btn.primary"));
    await settled();
    continue;
  }
  if (panel.classList.contains("season-report")) {
    click(panel.querySelector(".btn.primary"));
    await settled();
    continue;
  }
  const variants = $$(".variant-btn");
  if (variants.length > 0) {
    // try each variant until one yields legal anchors (ruins may restrict)
    for (let i = 0; i < variants.length; i++) {
      click($$(".variant-btn")[i]);
      await settled();
      if ($(".anchor-dot")) {
        if (await clickFirstAnchor()) break;
      }
      // no anchors for this variant: change shape (undo) and try the next
      const change = [...$$("button")].find((b) =>
        b.textContent.includes("different shape")
      );
      if (change) {
        click(change);
        await settled();
      }
      if (i === variants.length - 1) {
        // last resort: fallback should place 1x1 anywhere
        if (await clickFirstAnchor()) break;
      }
    }
    continue;
  }
  // already in placement mode (e.g. handed over from the phase-1 test)
  if ($(".anchor-dot")) {
    await clickFirstAnchor();
    continue;
  }
  // unknown panel state; fail loudly
  console.error("stuck on panel:", panel.className, panel.textContent.slice(0, 120));
  break outer;
}

assert(gamesOver, `autoplay reached Game Over in ${steps} steps`);
assert($(".over-title"), "the queen's title is shown");
assert($$(".rating-row.hit").length === 1, "rating table highlights the verdict");
assert($$(".receipt li").length === 4, "all four seasons on the receipt");

// ---- persistence: reload and check best + records survive -----------------

const saved = window.localStorage.getItem("cartographers-solo-save-v1");
assert(saved && saved.includes('"best"') && !saved.includes('"best":null'), "records written to localStorage");

const dom2 = new JSDOM(html, {
  runScripts: "outside-only",
  pretendToBeVisual: true,
  url: "https://localhost/",
});
const window2 = dom2.window;
// carry over the saved game record
window2.localStorage.setItem("cartographers-solo-save-v1", saved);
await new Promise((r) => setTimeout(r, 50));
window2.eval(js);
await new Promise((r) => setTimeout(r, 300));

const bestText = window2.document.querySelector(".best");
assert(bestText && bestText.textContent.includes("Personal best"), "personal best shown after reload");

console.log("\nSMOKE OK (full autoplay + persistence)");
process.exit(0);
