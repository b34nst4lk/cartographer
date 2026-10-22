#!/usr/bin/env node
// Bundle the compiled Gleam output with esbuild, then inline the resulting
// JS bundle and the stylesheet into one self-contained HTML file:
// dist/cartographers-solo.html (also copied to dist/index.html).
// Erlang-free: `gleam build --target javascript` produces the modules; the
// bundling step below shells out to esbuild via npx (cached after first use).
import { execSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";

writeFileSync(
  ".cartographer-entry.mjs",
  `import { main } from "./build/dev/javascript/cartographer/cartographer.mjs";
main();`,
);
execSync(
  "npx --yes esbuild .cartographer-entry.mjs --bundle --minify --charset=utf8 --format=esm --platform=browser --outfile=dist/cartographer.js",
  { stdio: "inherit" },
);
rmSync(".cartographer-entry.mjs");

const js = readFileSync("dist/cartographer.js", "utf8");
const css = readFileSync("assets/app.css", "utf8");

if (js.includes("</script")) {
  throw new Error("bundle contains </script — refusing to inline");
}

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cartographers — Solo</title>
<style>
${css}
</style>
</head>
<body>
<div id="app"></div>
<script type="module">
${js}
</script>
</body>
</html>
`;

writeFileSync("dist/cartographers-solo.html", html);
writeFileSync("dist/index.html", html);
console.log(`inlined ${(js.length / 1024).toFixed(1)}kb JS + ${(css.length / 1024).toFixed(1)}kb css -> dist/cartographers-solo.html (${(html.length / 1024).toFixed(1)}kb)`);
