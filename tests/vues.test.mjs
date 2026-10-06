// Tests de bout en bout des vues sur les données fictives (Chromium headless).
// Leaflet est servi depuis node_modules à la place de cdnjs ; les polices
// Google sont coupées (repli système). Lancer : npm test
import { createServer } from "node:http";
import { readFileSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join, extname } from "node:path";
import { execFileSync } from "node:child_process";
import assert from "node:assert/strict";

const ici = dirname(fileURLToPath(import.meta.url));
const racine = join(ici, "..");
const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require(process.env.PLAYWRIGHT_MODULE || "/opt/node-tools/node_modules/playwright"); }
const leafletJs = (() => {
  for (const p of [join(racine, "node_modules/leaflet/dist/leaflet.js"), process.env.LEAFLET_JS || ""]) if (p && existsSync(p)) return p;
  throw new Error("leaflet.js introuvable : npm install, ou LEAFLET_JS=<chemin>");
})();

const dist = join(racine, ".apercu");
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist);
execFileSync("node", [join(racine, "outils/generer-exemples.mjs")]);
for (const v of ["selection", "atlas"]) {
  execFileSync("node", [join(racine, "outils/assembler-vue.mjs"), v, join(racine, "vues/exemples", v), join(dist, v)]);
}

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".geojson": "application/geo+json" };
const serveur = createServer((req, res) => {
  const chemin = join(dist, decodeURIComponent(req.url.split("?")[0]).replace(/\/$/, "/index.html"));
  if (!chemin.startsWith(dist) || !existsSync(chemin)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": types[extname(chemin)] || "application/octet-stream" });
  res.end(readFileSync(chemin));
}).listen(0);
const base = `http://127.0.0.1:${serveur.address().port}`;

const navigateur = await playwright.chromium.launch();
const erreurs = [];
async function ouvrir(chemin, options = {}) {
  const ctx = await navigateur.newContext({ viewport: options.viewport || { width: 1360, height: 860 }, colorScheme: options.theme || "light" });
  const page = await ctx.newPage();
  await page.route("https://cdnjs.cloudflare.com/**", (r) => r.fulfill({ path: leafletJs, contentType: "text/javascript" }));
  await page.route("https://fonts.**", (r) => r.abort());
  page.on("pageerror", (e) => erreurs.push(`${chemin}: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error" && !/fonts|ERR_FAILED/.test(m.text())) erreurs.push(`${chemin}: ${m.text()}`); });
  await page.goto(base + chemin);
  return { ctx, page };
}
const captures = process.env.CAPTURES;
if (captures) mkdirSync(captures, { recursive: true });
async function capture(page, nom) { if (captures) await page.screenshot({ path: join(captures, nom + ".png") }); }

let echecs = 0;
async function test(nom, fn) {
  try { await fn(); console.log("ok  " + nom); } catch (e) { echecs++; console.log("ÉCHEC " + nom + "\n     " + e.message); }
}

/* ------------------------------------------------------------ Sélection */
await test("Sélection : parcelles chargées, clic, recherche, total, stockage", async () => {
  const { ctx, page } = await ouvrir("/selection/");
  await page.waitForSelector("#carte path.leaflet-interactive");
  assert.equal(await page.textContent("#titre-commune"), "Commune fictive");
  assert.equal(await page.isVisible("#bandeau-exemple"), true);
  const n = await page.$$eval("#carte path.leaflet-interactive", (p) => p.length);
  assert.equal(n, 384);
  // Recherche « A 1 » puis « B 12 ».
  await page.fill("#recherche", "a 1"); await page.press("#recherche", "Enter");
  await page.fill("#recherche", "B 12"); await page.press("#recherche", "Enter");
  assert.equal(await page.textContent("#total-n"), "2");
  assert.match(await page.textContent("#statut-carte"), /B 12/);
  // Clic carte sur une parcelle : ajout.
  await page.locator("#carte path.leaflet-interactive").nth(100).click({ force: true });
  assert.equal(await page.textContent("#total-n"), "3");
  assert.match(await page.textContent("#total-ha"), /ha$/);
  // Sans capacité mcp : la liste des IDU à copier s'affiche.
  await page.waitForTimeout(300);
  assert.equal(await page.isVisible("#bloc-idu"), true);
  const idu = await page.inputValue("#idu");
  assert.equal(idu.split(", ").length, 3);
  assert.match(idu, /^99999000/);
  // Retrait depuis la liste.
  await page.locator(".sel__retirer").first().click();
  assert.equal(await page.textContent("#total-n"), "2");
  await capture(page, "selection-clair");
  // La sélection survit au rechargement.
  await page.reload();
  await page.waitForSelector("#carte path.leaflet-interactive");
  assert.equal(await page.textContent("#total-n"), "2");
  await ctx.close();
});

await test("Sélection : rectangle et langue EN", async () => {
  const { ctx, page } = await ouvrir("/selection/", { theme: "dark" });
  await page.waitForSelector("#carte path.leaflet-interactive");
  await page.click("#btn-effacer").catch(() => {});
  await page.click("#btn-rectangle");
  const b = await page.locator("#carte").boundingBox();
  await page.mouse.move(b.x + b.width * 0.45, b.y + b.height * 0.4);
  await page.mouse.down();
  await page.mouse.move(b.x + b.width * 0.55, b.y + b.height * 0.55, { steps: 5 });
  await page.mouse.up();
  const total = Number(await page.textContent("#total-n"));
  assert.ok(total >= 4, "au moins 4 parcelles au rectangle, obtenu " + total);
  await page.click("#lang-en");
  assert.equal(await page.textContent("#btn-creer"), "Create the project");
  await capture(page, "selection-sombre-en");
  await page.click("#lang-fr");
  await ctx.close();
});

await test("Sélection : téléphone 400 px sans défilement horizontal", async () => {
  const { ctx, page } = await ouvrir("/selection/", { viewport: { width: 400, height: 800 } });
  await page.waitForSelector("#carte path.leaflet-interactive");
  const deborde = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert.equal(deborde, false);
  await capture(page, "selection-mobile");
  await ctx.close();
});

/* ------------------------------------------------------------ Atlas */
await test("Atlas : rail, carte, tableau, fiche, comparaison, bivarié", async () => {
  const { ctx, page } = await ouvrir("/atlas/");
  await page.waitForSelector("#carte path.leaflet-interactive");
  assert.match(await page.textContent("#titre"), /Forêt exemple/);
  assert.equal(await page.$$eval(".at__famille", (b) => b.length), 12);
  assert.equal(await page.$$eval("#lignes tr", (t) => t.length), 60);
  // Valeur manquante : motif de hachures présent dans le SVG.
  assert.equal(await page.$$eval("#nv-hachures", (p) => p.length), 1);
  // Famille Air : A5 manquant partout -> pas de zéro, raison affichée.
  await page.click(".at__famille[data-code='A']");
  assert.equal(await page.getAttribute(".at__famille[data-code='A']", "aria-pressed"), "true");
  // Filtre du tableau.
  await page.fill("#filtre", "UG 1");
  const filtrees = await page.$$eval("#lignes tr", (t) => t.length);
  assert.ok(filtrees > 0 && filtrees < 60);
  await page.fill("#filtre", "");
  // Clic sur une ligne : fiche avec radar 12 axes.
  await page.click("#lignes tr:first-child");
  assert.equal(await page.isVisible("#fiche"), true);
  assert.equal(await page.$$eval("#radar .nv-radar__axe", (a) => a.length), 12);
  const raisons = await page.$$eval(".at__ind-raison", (r) => r.map((x) => x.textContent));
  assert.ok(raisons.some((t) => /hors zone urbaine/.test(t)), "raison A5 affichée");
  // Comparaison.
  const autre = await page.$eval("#comparer option:nth-child(3)", (o) => o.value);
  await page.selectOption("#comparer", autre);
  assert.equal(await page.$$eval("#radar .nv-radar__serie", (s) => s.length), 2);
  assert.equal(await page.isVisible("#legende-radar"), true);
  await capture(page, "atlas-fiche");
  // Carte bivariée.
  await page.click("#btn-bivarie");
  assert.equal(await page.$$eval(".at__biv span", (s) => s.length), 25);
  assert.match(await page.textContent("#titre-carte"), /×/);
  await capture(page, "atlas-bivarie");
  await ctx.close();
});

await test("Atlas : sombre, EN, téléphone 400 px", async () => {
  const { ctx, page } = await ouvrir("/atlas/", { theme: "dark", viewport: { width: 400, height: 860 } });
  await page.waitForSelector("#carte path.leaflet-interactive");
  await page.click("#lang-en");
  assert.equal(await page.textContent("#onglet-table"), "Management units");
  const deborde = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert.equal(deborde, false);
  await capture(page, "atlas-mobile-sombre");
  await ctx.close();
});

await navigateur.close();
serveur.close();
if (erreurs.length) { echecs++; console.log("Erreurs de console :\n  " + erreurs.join("\n  ")); }
console.log(echecs ? `${echecs} échec(s)` : "Tous les tests passent.");
process.exit(echecs ? 1 : 0);
