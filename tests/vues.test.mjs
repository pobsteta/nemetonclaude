// Tests de bout en bout des vues sur les données fictives (Chromium headless).
// Leaflet est servi depuis node_modules à la place de cdnjs ; les polices
// Google sont coupées (repli système). Lancer : npm test
import { createServer } from "node:http";
import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync } from "node:fs";
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
for (const v of ["selection", "atlas", "calcul", "plan"]) {
  execFileSync("node", [join(racine, "outils/assembler-vue.mjs"), v, join(racine, "vues/exemples", v), join(dist, v)]);
}
// Vue Calcul branchée sur un connecteur simulé : un vrai projet (pas un exemple).
const direct = join(dist, "_donnees-calcul-direct");
mkdirSync(direct, { recursive: true });
writeFileSync(join(direct, "calcul.json"), JSON.stringify({ projet: "p-test", nom: "Forêt de test" }));
execFileSync("node", [join(racine, "outils/assembler-vue.mjs"), "calcul", direct, join(dist, "calcul-direct")]);
// Vue Plan branchée sur un connecteur simulé, avec droit d'écriture.
const planDirect = join(dist, "_donnees-plan-direct");
mkdirSync(planDirect, { recursive: true });
const planExemple = JSON.parse(readFileSync(join(racine, "vues/exemples/plan/plan.json"), "utf8"));
writeFileSync(join(planDirect, "plan.json"), JSON.stringify({ ...planExemple, exemple: false, peut_ecrire: true }));
for (const f of ["plan.geojson", "contexte.geojson"]) writeFileSync(join(planDirect, f), readFileSync(join(racine, "vues/exemples/plan", f)));
execFileSync("node", [join(racine, "outils/assembler-vue.mjs"), "plan", planDirect, join(dist, "plan-direct")]);

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
  if (options.claude) await page.addInitScript(options.claude);
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
  try { await fn(); console.log("ok  " + nom); } catch (e) { echecs++; console.log("ÉCHEC " + nom + "\n     " + e.message + (process.env.PILE ? "\n" + e.stack : "")); }
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
  // Une UGF d'une seule parcelle porte le nom « UGF n » ; sa référence cadastrale reste cherchable.
  await page.fill("#filtre", "UGF 4");
  assert.equal(await page.textContent("#lignes tr:first-child td:first-child"), "UGF 4");
  await page.fill("#filtre", "");
  // Clic sur une ligne : fiche avec radar 12 axes.
  await page.click("#lignes tr:first-child");
  assert.equal(await page.isVisible("#fiche"), true);
  assert.match(await page.textContent("#fiche-surface"), / ha · parcelles? [A-Z]+ \d+/);
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

await test("Atlas : profils experts servis par le connecteur et passés à Claude", async () => {
  const simule = () => {
    const mcp = {
      listTools: () => Promise.resolve({ servers: [{ server: "nemeton", tools: [{ name: "profils_experts" }] }] }),
      callTool: (server, tool) => Promise.resolve({ payload: tool === "profils_experts"
        ? { ok: true, profils: [{ cle: "generalist", libelle: "Généraliste", consigne: "Tu es généraliste." }, { cle: "naturaliste", libelle: "Naturaliste", consigne: "Tu es naturaliste, attentif aux habitats." }] }
        : { ok: false, erreur: "non simulé" } })
    };
    const sample = (consigne) => { window.__consigne = consigne; return Promise.resolve({ text: "Réponse simulée." }); };
    window.claude = { use: (nom) => Promise.resolve(nom === "mcp" ? mcp : nom === "sample" ? sample : null) };
  };
  const { ctx, page } = await ouvrir("/atlas/", { claude: simule });
  await page.waitForFunction(() => Array.from(document.querySelectorAll("#profil option")).some((o) => o.textContent === "Naturaliste"));
  // Le bloc « Demander à Claude » vit dans la fiche d'une unité.
  await page.locator("#carte path.leaflet-interactive").nth(10).click({ force: true });
  await page.waitForSelector("#profil", { state: "visible" });
  await page.selectOption("#profil", "naturaliste");
  await page.fill("#question", "Que faire pour la biodiversité ?");
  await page.click("#btn-demander");
  await page.waitForFunction(() => window.__consigne);
  const consigne = await page.evaluate(() => window.__consigne);
  assert.match(consigne, /^Tu es naturaliste, attentif aux habitats\./);
  assert.match(consigne, /Reader profile: Naturaliste/);
  await page.waitForFunction(() => /Réponse simulée/.test(document.getElementById("reponse-texte").textContent));
  await ctx.close();
});

await test("Atlas : GeoPackage zippé proposé comme le CSV, sinon lien du connecteur", async () => {
  // « PK » + octets : le contenu importe peu, la vue ne fait que le relayer.
  const simule = () => {
    window.__appels = [];
    window.__saves = [];
    const mcp = {
      listTools: () => Promise.resolve({ servers: [{ server: "nemeton", tools: [{ name: "exporter_gpkg" }] }] }),
      callTool: (server, tool, input) => {
        window.__appels.push({ tool, input });
        if (tool !== "exporter_gpkg") return Promise.resolve({ payload: { ok: false, erreur: "non simulé" } });
        return Promise.resolve({ payload: window.__sansZip
          ? { ok: true, fichier: "/srv/p/resultats.gpkg", urls: { "/srv/p/resultats.gpkg": "https://exemple.test/telechargement/abc/resultats.gpkg" } }
          : { ok: true, fichier: "/srv/p/resultats.gpkg", zip_nom: "resultats.zip", zip_taille: 4, zip_base64: btoa("PK\u0003\u0004") } });
      }
    };
    const downloads = { save: (r) => { window.__saves.push(r); return Promise.resolve({ status: "saved" }); } };
    window.claude = { use: (nom) => Promise.resolve(nom === "mcp" ? mcp : nom === "downloads" ? downloads : null) };
  };
  const { ctx, page } = await ouvrir("/atlas/", { claude: simule });
  await page.waitForSelector("#btn-gpkg", { state: "visible" });
  await page.click("#btn-gpkg");
  await page.waitForFunction(() => window.__saves.length === 1);
  const save = await page.evaluate(async () => {
    const s = window.__saves[0];
    return { filename: s.filename, octets: Array.from(new Uint8Array(await s.data.arrayBuffer())), entree: window.__appels.find((a) => a.tool === "exporter_gpkg").input };
  });
  assert.equal(save.filename, "resultats.zip");
  assert.deepEqual(save.octets, [0x50, 0x4b, 3, 4]);
  assert.equal(save.entree.zip, true);
  await page.waitForFunction(() => /zip/.test(document.getElementById("statut-export").textContent));
  // Sans contenu (ancien connecteur) : le lien temporaire du connecteur distant.
  await page.evaluate(() => { window.__sansZip = true; });
  await page.click("#btn-gpkg");
  const lien = await page.waitForSelector("#statut-export a");
  assert.equal(await lien.getAttribute("href"), "https://exemple.test/telechargement/abc/resultats.gpkg");
  await ctx.close();
});

/* ------------------------------------------------------------ Calcul */
// Capacité mcp simulée : un connecteur distant « nemeton », un suivi
// (watchTool) piloté par le test via window.__emettre, et le journal des
// appels dans window.__appels.
function claudeSimule() {
  const etats = [];
  window.__appels = [];
  window.__watch = null;
  window.__emettre = (ev) => { if (window.__watch) window.__watch(ev); };
  const mcp = {
    listTools: () => Promise.resolve({ servers: [{ server: "nemeton", tools: [{ name: "etat_calcul" }, { name: "annuler_calcul" }, { name: "lancer_calcul" }] }] }),
    watchTool: (server, tool, input, handler, opts) => {
      window.__appels.push({ type: "watch", server, tool, input, opts });
      window.__watch = handler;
      return () => { window.__appels.push({ type: "fin_watch" }); window.__watch = null; };
    },
    callTool: (server, tool, input) => {
      window.__appels.push({ type: "call", server, tool, input });
      if (tool === "etat_calcul") return Promise.resolve({ payload: window.__etat || { ok: true, statut: "aucun" } });
      return Promise.resolve({ payload: { ok: true, projet: input.projet } });
    }
  };
  window.claude = { use: (nom) => Promise.resolve(nom === "mcp" ? mcp : null) };
  void etats;
}
const etat = (statut, plus = {}) => ({ type: "data", result: { payload: JSON.stringify({ ok: true, projet: "p-test", statut, ...plus }) } });

await test("Calcul : exemple figé sans connecteur", async () => {
  const { ctx, page } = await ouvrir("/calcul/");
  await page.waitForFunction(() => document.getElementById("statut").textContent !== "—");
  assert.equal(await page.textContent("#titre-projet"), "Forêt fictive de démonstration");
  assert.equal(await page.isVisible("#bandeau-exemple"), true);
  assert.equal(await page.textContent("#statut"), "En cours");
  assert.equal(await page.textContent("#indicateurs"), "12 sur 41");
  assert.equal(await page.textContent("#pourcent"), "29 %");
  assert.match(await page.textContent("#ecoule"), /^28 min \d+ s$/);
  assert.equal(await page.textContent("#tache"), "B2 — Diversité structurale");
  for (const b of ["#btn-annuler", "#btn-relancer", "#btn-rafraichir"]) assert.equal(await page.isVisible(b), false, b);
  assert.match(await page.textContent("#fraicheur"), /sans suivi en direct/);
  await capture(page, "calcul-exemple");
  await ctx.close();
});

await test("Calcul : suivi en direct, annulation, fin, échec et relance", async () => {
  const { ctx, page } = await ouvrir("/calcul-direct/", { claude: claudeSimule });
  await page.waitForFunction(() => window.__watch);
  const watch = (await page.evaluate(() => window.__appels))[0];
  assert.deepEqual([watch.server, watch.tool, watch.input.projet, watch.opts.refetchInterval], ["nemeton", "etat_calcul", "p-test", 30000]);

  await page.evaluate((ev) => window.__emettre(ev), etat("en_cours", { progression: 10, progression_max: 40, indicateurs_faits: 10, indicateurs_total: 41, tache: "C1 — Biomasse", ecoule_s: 3725 }));
  assert.equal(await page.textContent("#statut"), "En cours");
  assert.equal(await page.textContent("#pourcent"), "25 %");
  assert.match(await page.textContent("#ecoule"), /^1 h 2 min$/);
  assert.match(await page.textContent("#fraicheur"), /Suivi en direct/);

  // Annuler demande confirmation, puis appelle annuler_calcul ; le calcul
  // tourne encore jusqu'au prochain indicateur.
  await page.evaluate(() => { window.__etat = { ok: true, projet: "p-test", statut: "en_cours", indicateurs_faits: 11, indicateurs_total: 41 }; });
  await page.click("#btn-annuler");
  assert.equal(await page.isVisible("#confirmer"), true);
  await page.click("#btn-confirmer");
  await page.waitForFunction(() => window.__appels.some((a) => a.tool === "annuler_calcul"));
  assert.match(await page.textContent("#message"), /Annulation demandée/);

  // Fin du calcul : invitation à ouvrir l'Atlas, suivi arrêté.
  await page.evaluate((ev) => window.__emettre(ev), etat("termine", { ecoule_s: 5400 }));
  assert.equal(await page.isVisible("#suite"), true);
  assert.equal(await page.textContent("#invite"), "Ouvre l'Atlas du projet Forêt de test");
  assert.equal(await page.textContent("#pourcent"), "100 %");
  assert.equal(await page.textContent("#message"), "", "message d'annulation effacé à la fin");
  assert.equal(await page.isVisible("#bloc-tache"), false);
  assert.equal(await page.getAttribute("#btn-relancer", "class"), "nv-bouton");
  assert.ok((await page.evaluate(() => window.__appels)).some((a) => a.type === "fin_watch"));
  await capture(page, "calcul-termine");

  // Échec (relu par Rafraîchir) : journal affiché, relance possible.
  await page.evaluate(() => { window.__etat = { ok: true, projet: "p-test", statut: "echec", erreur: "Mémoire épuisée", log: ["ligne 1", "ligne 2"] }; });
  await page.click("#btn-rafraichir");
  await page.waitForSelector("#bloc-journal:not([hidden])");
  assert.equal(await page.textContent("#erreur"), "Mémoire épuisée");
  assert.equal(await page.textContent("#journal"), "ligne 1\nligne 2");
  // lancer_calcul écrit le statut « lancement » avant de rendre la main.
  await page.evaluate(() => { window.__etat = { ok: true, projet: "p-test", statut: "lancement" }; });
  await page.click("#btn-relancer");
  await page.waitForFunction(() => window.__appels.some((a) => a.tool === "lancer_calcul"));
  await page.waitForFunction(() => window.__watch);
  await page.waitForFunction(() => document.getElementById("statut").textContent === "Lancement");
  assert.equal(await page.isVisible("#bloc-journal"), false);
  await ctx.close();
});

await test("Calcul : connecteur absent ou refusé, sombre, EN, téléphone 400 px", async () => {
  const { ctx, page } = await ouvrir("/calcul-direct/", { claude: claudeSimule, theme: "dark", viewport: { width: 400, height: 800 } });
  await page.waitForFunction(() => window.__watch);
  await page.evaluate((ev) => window.__emettre(ev), etat("en_cours", { indicateurs_faits: 3, indicateurs_total: 41 }));
  await page.evaluate(() => window.__emettre({ type: "error", error: { code: "server_not_connected", message: "x" } }));
  assert.match(await page.textContent("#message"), /Ajoutez le connecteur « nemeton »/);
  assert.equal(await page.textContent("#statut"), "État inconnu");
  await page.click("#lang-en");
  assert.equal(await page.textContent("#statut"), "Unknown status");
  assert.match(await page.textContent("#message"), /Add the “nemeton” connector/);
  const deborde = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert.equal(deborde, false);
  await capture(page, "calcul-mobile-sombre");
  await ctx.close();

  // Sans capacité mcp du tout : explication, pas de bouton.
  const sans = await ouvrir("/calcul-direct/");
  await sans.page.waitForSelector("#sans-connecteur:not([hidden])", { timeout: 15000 });
  assert.equal(await sans.page.isVisible("#btn-annuler"), false);
  await sans.ctx.close();
});

/* ------------------------------------------------------------ Plan */
// Connecteur simulé : tient le plan en mémoire (window.__plan), applique
// ajouter/modifier/supprimer, et note chaque appel dans window.__appels.
function planSimule(plan) {
  window.__plan = plan;
  window.__appels = [];
  window.__conflit = false;
  const rendre = (x) => Promise.resolve({ payload: x });
  const mcp = {
    listTools: () => Promise.resolve({ servers: [{ server: "nemeton", tools: [{ name: "plan_actions" }] }] }),
    watchTool: (server, tool, input, handler) => {
      window.__appels.push({ type: "watch", tool, input });
      window.__watch = handler;
      setTimeout(() => handler({ type: "data", result: { payload: JSON.parse(JSON.stringify(window.__plan)) } }), 0);
      return () => { window.__watch = null; };
    },
    callTool: (server, tool, input) => {
      window.__appels.push({ type: "call", tool, input });
      const p = window.__plan;
      if (tool === "plan_actions") return rendre(JSON.parse(JSON.stringify(p)));
      if (tool === "profils_experts") return rendre({ ok: true, profils: [{ cle: "generalist", libelle: "Généraliste", consigne: "Tu es généraliste." }, { cle: "elu_local", libelle: "Élu local", consigne: "Tu parles à un élu." }] });
      if (tool === "ajouter_action") {
        const a = { ...input.action, id: "act_nouvelle_" + p.actions.length, version: "n1", propose_par_claude: input.action.source && input.action.source.origine === "claude" };
        p.actions.push(a);
        return rendre({ ok: true, action: a });
      }
      if (tool === "modifier_action") {
        const a = p.actions.find((x) => x.id === input.action_id);
        if (window.__conflit) {
          // Un autre compte a modifié l'action entre-temps.
          Object.assign(a, { priorite: "basse", modifie_par: "alice", version: "autre" });
          return rendre({ ok: false, erreur: "L'action a été modifiée par alice pendant votre saisie.", classe: "nemetonclaude_conflit", candidats: [{ ...a }] });
        }
        if (input.attendu !== a.version) return rendre({ ok: false, erreur: "version inattendue " + input.attendu, classe: "x" });
        Object.assign(a, input.modifications, { version: a.version + "+" });
        return rendre({ ok: true, action: a });
      }
      if (tool === "supprimer_action") { p.actions = p.actions.filter((x) => x.id !== input.action_id); return rendre({ ok: true }); }
      if (tool === "exporter_marculus") return rendre({ ok: true, fichier: "/srv/p/exports/marculus.zip", chantiers: 3, urls: { "/srv/p/exports/marculus.zip": "https://nemeton.test/telechargement/x/marculus.zip" } });
      return rendre({ ok: false, erreur: "outil inconnu " + tool });
    }
  };
  const sample = { json: (consigne) => { window.__consigne = consigne; return Promise.resolve({ actions: [
    { type: "eclaircie", intensite: "moderee", annee: 2030, priorite: "haute", objectifs_lies: ["P", "B"], justification: "Production (P) élevée." },
    { type: "coupe_magique", annee: 2031, priorite: "basse" }] }); } };
  window.claude = { use: (nom) => Promise.resolve(nom === "mcp" ? mcp : nom === "sample" ? sample : null) };
}

await test("Plan : exemple en lecture seule, calendrier, filtre par unité, vue experte", async () => {
  const { ctx, page } = await ouvrir("/plan/");
  await page.waitForSelector("#carte path.leaflet-interactive");
  assert.equal(await page.$$eval("#carte path.leaflet-interactive", (p) => p.length), 60);
  assert.equal(await page.textContent("#titre"), "Forêt exemple (données fictives)");
  assert.equal(await page.isVisible("#bandeau-exemple"), true);
  assert.equal(await page.isVisible("#btn-nouvelle"), false);
  assert.equal(await page.isVisible("#onglets"), false, "pas d'onglets en vue simple");
  assert.equal(await page.$$eval("#vue-calendrier .pl__action", (b) => b.length), 11);
  assert.equal(await page.$$eval("#vue-calendrier .pl__action--claude", (b) => b.length), 2);
  assert.match(await page.textContent("#resume"), /Actions\s*10/);
  // Une proposition de Claude ouvre sa fiche, en lecture seule.
  await page.click("#vue-calendrier .pl__action--claude");
  assert.equal(await page.isVisible("#fiche"), true);
  assert.match(await page.textContent("#fiche"), /Proposée par Claude/);
  assert.equal(await page.isDisabled("#f-type"), true);
  assert.match(await page.textContent("#fiche"), /Lecture seule/);
  await page.keyboard.press("Escape");
  assert.equal(await page.isVisible("#fiche"), false);
  // Vue experte : tableau trié et kanban.
  await page.click("#mode-expert");
  await page.click("#onglet-tableau");
  assert.equal(await page.$$eval("#vue-tableau tbody tr", (r) => r.length), 11);
  const annees = await page.$$eval("#vue-tableau tbody tr td:first-child", (t) => t.map((x) => Number(x.textContent)));
  assert.deepEqual(annees, [...annees].sort((a, b) => a - b));
  await page.click("#onglet-kanban");
  assert.equal(await page.$$eval("#vue-kanban .pl__colonne", (c) => c.length), 5);
  assert.match(await page.textContent("#resume"), /Coût/);
  await capture(page, "plan-expert-kanban");
  // Filtre par unité depuis la carte (préférence de vue experte mémorisée).
  await page.click("#onglet-calendrier");
  const ugAvecAction = await page.evaluate(() => document.querySelector("#vue-calendrier .pl__action-sous").textContent.split(" · ")[0]);
  await page.locator("#carte path.leaflet-interactive").nth(3).click({ force: true });
  assert.equal(await page.isVisible("#filtre-ug"), true);
  assert.equal(await page.isVisible("#bloc-ug"), true);
  assert.match(await page.textContent("#bloc-ug"), /parcelles? [A-Z]+ \d+/);
  void ugAvecAction;
  await capture(page, "plan-ug");
  await ctx.close();
});

await test("Plan : transitions, édition, conflit, nouvelle action, propositions de Claude, Marculus", async () => {
  const plan = JSON.parse(readFileSync(join(dist, "plan-direct", "plan.json"), "utf8"));
  const { ctx, page } = await ouvrir("/plan-direct/", { claude: `(${planSimule.toString()})(${JSON.stringify(plan)})` });
  await page.waitForFunction(() => window.__watch && document.querySelectorAll("#vue-calendrier .pl__action").length === 11);
  assert.equal(await page.isVisible("#btn-nouvelle"), true);
  const appels = () => page.evaluate(() => window.__appels.filter((a) => a.type === "call" && a.tool !== "plan_actions" && a.tool !== "profils_experts"));

  // Kanban : valider une proposition de Claude.
  await page.click("#mode-expert");
  await page.click("#onglet-kanban");
  const carteClaude = page.locator(".pl__carte-k--claude").first();
  const idClaude = await carteClaude.getAttribute("data-carte");
  await carteClaude.locator("[data-transition='validee']").click();
  await page.waitForFunction(() => window.__appels.some((a) => a.tool === "modifier_action"));
  let c = (await appels()).at(-1);
  assert.deepEqual([c.input.action_id, c.input.modifications.statut, c.input.attendu], [idClaude, "validee", plan.actions.find((a) => a.id === idClaude).version]);
  await page.waitForFunction((id) => !document.querySelector(".pl__carte-k--claude[data-carte='" + id + "']"), idClaude);

  // Fiche : seuls les champs changés partent, avec la version lue.
  await page.click("#onglet-tableau");
  await page.locator("#vue-tableau tbody tr").first().click();
  await page.selectOption("#f-priorite", "basse");
  await page.fill("#f-commentaire", "Attendre la fin de la nidification.");
  await page.click("#btn-enregistrer");
  await page.waitForFunction(() => window.__appels.filter((a) => a.tool === "modifier_action").length === 2);
  c = (await appels()).at(-1);
  assert.deepEqual(Object.keys(c.input.modifications).sort(), ["commentaire", "priorite"]);
  await page.waitForFunction(() => /enregistrée/.test(document.getElementById("message").textContent));

  // Conflit : la fiche montre la version actuelle et le dit.
  await page.evaluate(() => { window.__conflit = true; });
  await page.fill("#f-commentaire", "Autre note");
  await page.click("#btn-enregistrer");
  await page.waitForFunction(() => /alice/.test(document.getElementById("message-fiche").textContent));
  assert.equal(await page.inputValue("#f-priorite"), "basse");
  await page.evaluate(() => { window.__conflit = false; });
  await page.click("#btn-fermer");

  // Nouvelle action, saisie dans la vue.
  await page.click("#btn-nouvelle");
  await page.selectOption("#f-type", "autre");
  assert.equal(await page.isVisible("#f-type-libre"), true);
  await page.fill("#f-type-libre", "Mare");
  await page.fill("#f-annee", "2029");
  await page.click("#btn-enregistrer");
  await page.waitForFunction(() => window.__appels.some((a) => a.tool === "ajouter_action"));
  c = (await appels()).at(-1);
  assert.equal(c.input.action.type_libre, "Mare");
  assert.equal(c.input.action.annee, 2029);
  assert.equal(c.input.action.source.origine, "vue");
  await page.click("#btn-fermer");

  // Propositions de Claude pour une unité : profil servi par le connecteur, une proposition hors règles écartée.
  await page.locator("#carte path.leaflet-interactive").nth(5).click({ force: true });
  await page.waitForSelector("#btn-claude");
  assert.ok((await page.$$eval("#profil option", (o) => o.map((x) => x.textContent))).includes("Élu local"));
  await page.selectOption("#profil", "elu_local");
  await page.click("#btn-claude");
  await page.waitForSelector(".pl__suggestion");
  assert.equal(await page.$$eval(".pl__suggestion", (s) => s.length), 1);
  assert.match(await page.textContent("#suggestions"), /1 proposition\(s\) hors des règles/);
  assert.match(await page.evaluate(() => window.__consigne), /Tu parles à un élu/);
  await capture(page, "plan-suggestions");
  await page.click("[data-ajout]");
  await page.waitForFunction(() => window.__appels.filter((a) => a.tool === "ajouter_action").length === 2);
  c = (await appels()).at(-1);
  assert.equal(c.input.action.source.origine, "claude");
  assert.equal(c.input.action.statut, "proposee");
  assert.equal(c.input.action.annee, 2030);

  // Suppression avec confirmation.
  await page.click("#btn-sans-filtre");
  await page.locator("#vue-tableau tbody tr").first().click();
  await page.click("#btn-supprimer");
  await page.click("#btn-oui-suppr");
  await page.waitForFunction(() => window.__appels.some((a) => a.tool === "supprimer_action"));

  // Paquet Marculus : lien de téléchargement.
  await page.click("#btn-marculus");
  await page.waitForSelector("#message a[href='https://nemeton.test/telechargement/x/marculus.zip']");
  await ctx.close();
});

await test("Plan : sombre, EN, téléphone 400 px, fiche en panneau bas", async () => {
  const { ctx, page } = await ouvrir("/plan/", { theme: "dark", viewport: { width: 400, height: 860 } });
  await page.waitForSelector("#carte path.leaflet-interactive");
  await page.click("#lang-en");
  assert.equal(await page.textContent("#mode-expert"), "Expert view");
  await page.locator("#vue-calendrier .pl__action").first().click();
  assert.equal(await page.isVisible("#fiche"), true);
  const deborde = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  assert.equal(deborde, false);
  await capture(page, "plan-mobile-sombre");
  await ctx.close();
});

await navigateur.close();
serveur.close();
if (erreurs.length) { echecs++; console.log("Erreurs de console :\n  " + erreurs.join("\n  ")); }
console.log(echecs ? `${echecs} échec(s)` : "Tous les tests passent.");
process.exit(echecs ? 1 : 0);
