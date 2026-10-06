// Tests unitaires du moteur nemeton-view.js : fonctions pures (langue,
// formats, couleurs, bivarié, erreurs du connecteur), sans navigateur.
// Le moteur s'attache à `window` : on lui donne un global minimal, puis on
// l'importe comme un module pour que la couverture de code le compte.
// Lancer : npm run test:unitaires
import { test } from "node:test";
import assert from "node:assert/strict";

const stockage = new Map();
globalThis.window = globalThis;
globalThis.document = {
  documentElement: { lang: "fr" },
  querySelectorAll: () => [],
  querySelector: () => null
};
globalThis.localStorage = {
  getItem: (k) => (stockage.has(k) ? stockage.get(k) : null),
  setItem: (k, v) => stockage.set(k, String(v)),
  removeItem: (k) => stockage.delete(k)
};
await import("../../vues/moteur/nemeton-view.js");
const NV = globalThis.NV;

const hex = /^#[0-9a-f]{6}$/;

test("t traduit, remplace les variables et retombe sur le français puis la clé", () => {
  NV.textes({ fr: { salut: "Bonjour {nom}", seul_fr: "Seul" }, en: { salut: "Hello {nom}" } });
  NV.lang = "fr";
  assert.equal(NV.t("salut", { nom: "Velars" }), "Bonjour Velars");
  NV.lang = "en";
  assert.equal(NV.t("salut", { nom: "Velars" }), "Hello Velars");
  assert.equal(NV.t("seul_fr"), "Seul");
  assert.equal(NV.t("cle_absente"), "cle_absente");
  assert.equal(NV.t("salut"), "Hello ");
  NV.lang = "fr";
});

test("changerLangue n'accepte que fr et en, et mémorise le choix", () => {
  NV.changerLangue("en");
  assert.equal(NV.lang, "en");
  assert.equal(NV.stockage.lire("nemeton-langue"), "en");
  NV.changerLangue("de");
  assert.equal(NV.lang, "fr");
});

test("nombre et hectares formatent selon la langue, tiret si la valeur manque", () => {
  NV.lang = "fr";
  assert.equal(NV.nombre(1234.567, 1).replace(/\s/g, " "), "1 234,6");
  assert.equal(NV.nombre(null), "—");
  assert.equal(NV.nombre(""), "—");
  assert.equal(NV.nombre(Infinity), "—");
  assert.equal(NV.hectares(15200).replace(/\s/g, " "), "1,52 ha");
  assert.equal(NV.hectares(null), "— ha");
  NV.lang = "en";
  assert.equal(NV.nombre(1234.567, 1), "1,234.6");
  NV.lang = "fr";
});

test("date lit l'ISO avec ou sans T, rend le texte brut s'il est illisible", () => {
  NV.lang = "fr";
  assert.equal(NV.date("2026-10-06 12:00:00"), "6 octobre 2026");
  assert.equal(NV.date(""), "—");
  assert.equal(NV.date("pas une date"), "pas une date");
});

test("echapper neutralise le HTML", () => {
  assert.equal(NV.echapper(`<b a="1">'&'</b>`), "&lt;b a=&quot;1&quot;&gt;&#39;&amp;&#39;&lt;/b&gt;");
  assert.equal(NV.echapper(null), "");
});

test("stockage rend la valeur par défaut si absente, illisible ou refusée", () => {
  NV.stockage.ecrire("sel", ["a", "b"]);
  assert.deepEqual(NV.stockage.lire("sel", []), ["a", "b"]);
  NV.stockage.effacer("sel");
  assert.deepEqual(NV.stockage.lire("sel", []), []);
  stockage.set("casse", "{pas du json");
  assert.equal(NV.stockage.lire("casse", 0), 0);
  const ls = globalThis.localStorage;
  globalThis.localStorage = { getItem() { throw new Error("refusé"); }, setItem() { throw new Error("refusé"); } };
  assert.equal(NV.stockage.lire("x", "défaut"), "défaut");
  assert.doesNotThrow(() => NV.stockage.ecrire("x", 1));
  globalThis.localStorage = ls;
});

test("couleurScore suit viridis aux bornes et rend null si la valeur manque", () => {
  assert.equal(NV.couleurScore(0), NV.palettes.viridis[0]);
  assert.equal(NV.couleurScore(100), NV.palettes.viridis.at(-1));
  assert.equal(NV.couleurScore(150), NV.palettes.viridis.at(-1));
  assert.equal(NV.couleurScore(-5), NV.palettes.viridis[0]);
  assert.match(NV.couleurScore(42), hex);
  assert.equal(NV.couleurScore(0, "divergente"), NV.palettes.divergente[0]);
  for (const v of [null, undefined, "", NaN]) assert.equal(NV.couleurScore(v), null);
});

test("bivarié : classes 0 à 4 et coins de la légende 5 × 5", () => {
  const b = NV.bivarie;
  assert.deepEqual([0, 19.9, 20, 59, 80, 100].map(b.classe), [0, 0, 1, 2, 4, 4]);
  assert.equal(b.classe(null), null);
  assert.equal(b.couleur(0, 0), b.coins.bb);
  assert.equal(b.couleur(4, 0), b.coins.ah);
  assert.equal(b.couleur(0, 4), b.coins.bh);
  assert.equal(b.couleur(4, 4), b.coins.hh);
  assert.match(b.couleur(2, 3), hex);
  assert.equal(b.couleur(null, 2), null);
});

test("contraste choisit un texte sombre sur fond clair et blanc sur fond sombre", () => {
  assert.equal(NV.contraste("#fde725"), "#14201a");
  assert.equal(NV.contraste("#440154"), "#ffffff");
});

test("messageMcp traduit les codes de la capacité mcp", () => {
  NV.lang = "fr";
  assert.match(NV.messageMcp({ code: "server_not_connected" }), /application Claude de bureau/);
  assert.match(NV.messageMcp({ code: "not_granted" }), /Autorisations/);
  assert.match(NV.messageMcp({ code: "tool_error", message: "boum" }), /boum/);
  assert.match(NV.messageMcp({ code: "inconnu" }), /\(inconnu\)/);
  assert.match(NV.messageMcp(undefined), /\(\?\)/);
  assert.equal(NV.messageMcp({ nemeton: true, message: "Projet introuvable" }), "Projet introuvable");
});

test("appeler rend le JSON de l'outil et rejette une réponse ok:false", async () => {
  const appels = [];
  const mcp = (payload) => ({
    callTool: (serveur, outil, entree) => {
      appels.push([serveur, outil, entree]);
      return Promise.resolve({ payload });
    }
  });
  assert.deepEqual(await NV.appeler(mcp('{"ok":true,"projet":"p1"}'), "creer_projet", { nom: "x" }),
    { ok: true, projet: "p1" });
  assert.deepEqual(appels[0], ["host:nemeton", "creer_projet", { nom: "x" }]);
  assert.deepEqual(await NV.appeler(mcp({ ok: true, n: 2 }), "vue_atlas", {}), { ok: true, n: 2 });
  assert.equal(await NV.appeler(mcp("texte brut"), "x", {}), "texte brut");
  await assert.rejects(
    NV.appeler(mcp('{"ok":false,"erreur":"Ambigu","classe":"nemetonshiny_projet_ambigu","candidats":["a","b"]}'), "x", {}),
    (e) => e.nemeton === true && e.message === "Ambigu" &&
      e.classe === "nemetonshiny_projet_ambigu" && e.candidats.length === 2
  );
});

test("capacite rend null hors de claude.ai et quand la capacité est refusée", async () => {
  assert.equal(await NV.capacite("mcp"), null);
  globalThis.claude = { use: () => Promise.reject(new Error("non déclarée")) };
  assert.equal(await NV.capacite("mcp"), null);
  globalThis.claude = { use: (nom) => Promise.resolve({ nom }) };
  assert.deepEqual(await NV.capacite("mcp"), { nom: "mcp" });
  delete globalThis.claude;
});

test("annoncer écrit puis efface le message", async () => {
  const el = { textContent: "" };
  NV.annoncer(el, "Copié", 10);
  assert.equal(el.textContent, "Copié");
  await new Promise((r) => setTimeout(r, 30));
  assert.equal(el.textContent, "");
  NV.annoncer(el, "Reste", 0);
  assert.equal(el.textContent, "Reste");
  assert.doesNotThrow(() => NV.annoncer(null, "x"));
});

test("connecter préfère le connecteur distant, puis le serveur local", async () => {
  const mcp = (servers) => ({ listTools: () => Promise.resolve({ servers }) });
  const outils = [{ name: "etat_calcul" }];
  assert.equal(await NV.connecter(mcp([{ server: "host:nemeton", tools: outils }, { server: "nemeton ONF", tools: outils }])), "nemeton ONF");
  assert.equal(NV.SERVEUR, "nemeton ONF");
  assert.equal(await NV.connecter(mcp([{ server: "host:nemeton", tools: outils }])), "host:nemeton");
  // Un connecteur listé sans outils (pas encore choisi) ou un serveur de l'artéfact ne compte pas.
  assert.equal(await NV.connecter(mcp([{ server: "nemeton", tools: [] }, { server: "artifacts_data", kind: "artifact", tools: outils }])), null);
  assert.equal(await NV.connecter({ listTools: () => Promise.reject({ code: "not_granted" }) }), null);
  assert.equal(await NV.connecter(null), null);
});

test("messageMcp oriente vers le bon réglage selon le serveur", () => {
  NV.lang = "fr";
  NV.SERVEUR = "nemeton ONF";
  assert.match(NV.messageMcp({ code: "server_not_connected" }), /« nemeton ONF » dans Réglages/);
  NV.SERVEUR = "host:nemeton";
  assert.match(NV.messageMcp({ code: "server_not_connected" }), /application Claude de bureau/);
});
