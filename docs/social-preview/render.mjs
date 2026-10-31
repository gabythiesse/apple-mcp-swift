// Renders banner.html to banner.png (1280x640), or <name>.html to <name>.png when a name is given.
// Run from the repo root:  npx -y playwright@1.64.1 --version >/dev/null && node docs/social-preview/render.mjs [banner-apps]
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

function findPlaywright() {
  try { return createRequire(import.meta.url).resolve("playwright"); } catch {}
  const npx = path.join(process.env.HOME, ".npm/_npx");
  for (const d of fs.readdirSync(npx)) {
    const p = path.join(npx, d, "node_modules/playwright");
    if (fs.existsSync(p)) return p;
  }
  throw new Error("playwright not found: run `npx -y playwright@1.64.1 install chromium` first");
}
const { chromium } = createRequire(import.meta.url)(findPlaywright());
const dir = path.dirname(fileURLToPath(import.meta.url));
const name = process.argv[2] || "banner";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: 1 });
await page.goto("file://" + path.join(dir, name + ".html"));
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(dir, name + ".png"), clip: { x: 0, y: 0, width: 1280, height: 640 } });
await browser.close();
console.log("ok");
