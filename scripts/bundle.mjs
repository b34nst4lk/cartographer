#!/usr/bin/env node
// Inline the compiled JS bundle and the stylesheet into one self-contained
// HTML file: dist/cartographers-solo.html (also copied to dist/index.html).
import { readFileSync, writeFileSync } from "node:fs";

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
