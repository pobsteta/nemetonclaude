// Génère les données FICTIVES des vues (aucune donnée réelle) :
//   vues/exemples/selection/{selection.json, commune.geojson, sections.geojson, parcelles.geojson}
//   vues/exemples/atlas/{atlas.geojson, contexte.geojson}
//   vues/exemples/calcul/calcul.json
//   vues/exemples/plan/{plan.json, plan.geojson, contexte.geojson}
// Le catalogue des familles (vues/exemples/catalogue.json) est celui du cœur
// nemeton (R/indicator-config.R) ; les valeurs, elles, sont tirées au hasard.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ici = dirname(fileURLToPath(import.meta.url));
const ex = join(ici, "../vues/exemples");

let graine = 20261006;
const alea = () => ((graine = (graine * 1664525 + 1013904223) >>> 0) / 4294967296);
const r6 = (x) => Math.round(x * 1e6) / 1e6;

// Réseau de sommets légèrement déformé : les parcelles voisines partagent leurs bords.
const LON0 = 4.895, LAT0 = 47.300, NX = 24, NY = 16, DX = 0.0024, DY = 0.0016;
const sommets = [];
for (let j = 0; j <= NY; j++) {
  sommets.push([]);
  for (let i = 0; i <= NX; i++) {
    const bord = i === 0 || j === 0 || i === NX || j === NY;
    sommets[j].push([
      r6(LON0 + i * DX + (bord ? 0 : (alea() - 0.5) * DX * 0.55)),
      r6(LAT0 + j * DY + (bord ? 0 : (alea() - 0.5) * DY * 0.55))
    ]);
  }
}
const M_PAR_DEG_LAT = 111320, M_PAR_DEG_LON = 111320 * Math.cos((LAT0 * Math.PI) / 180);
function aire(anneau) {
  let s = 0;
  for (let k = 0; k < anneau.length - 1; k++) {
    s += anneau[k][0] * M_PAR_DEG_LON * anneau[k + 1][1] * M_PAR_DEG_LAT -
         anneau[k + 1][0] * M_PAR_DEG_LON * anneau[k][1] * M_PAR_DEG_LAT;
  }
  return Math.abs(s / 2);
}

const section = (i, j) => (j < NY / 2 ? (i < NX / 2 ? "A" : "B") : (i < NX / 2 ? "C" : "D"));
// Massif boisé : une tache elliptique à cheval sur B et D.
const enForet = (i, j) => ((i - 17) / 6.5) ** 2 + ((j - 8.5) / 5.5) ** 2 < 1;

const INSEE = "99999";
const compteurs = {};
const parcelles = [];
for (let j = 0; j < NY; j++) {
  for (let i = 0; i < NX; i++) {
    const s = section(i, j);
    compteurs[s] = (compteurs[s] || 0) + 1;
    const anneau = [sommets[j][i], sommets[j][i + 1], sommets[j + 1][i + 1], sommets[j + 1][i], sommets[j][i]];
    const numero = String(compteurs[s]);
    parcelles.push({
      type: "Feature",
      properties: {
        idu: INSEE + "000" + s.padStart(2, "0") + numero.padStart(4, "0"),
        section: s, numero, contenance: Math.round(aire(anneau)),
        foret: enForet(i, j) ? 1 : 0
      },
      geometry: { type: "Polygon", coordinates: [anneau] },
      _ij: [i, j]
    });
  }
}

const fc = (features) => ({ type: "FeatureCollection", features });
const contour = (i0, j0, i1, j1) => {
  const a = [];
  for (let i = i0; i <= i1; i++) a.push(sommets[j0][i]);
  for (let j = j0 + 1; j <= j1; j++) a.push(sommets[j][i1]);
  for (let i = i1 - 1; i >= i0; i--) a.push(sommets[j1][i]);
  for (let j = j1 - 1; j >= j0; j--) a.push(sommets[j][i0]);
  return [a];
};
const H = NX / 2, V = NY / 2;
const sections = fc([
  ["A", 0, 0, H, V], ["B", H, 0, NX, V], ["C", 0, V, H, NY], ["D", H, V, NX, NY]
].map(([s, i0, j0, i1, j1]) => ({ type: "Feature", properties: { section: s },
  geometry: { type: "Polygon", coordinates: contour(i0, j0, i1, j1) } })));
const commune = fc([{ type: "Feature", properties: { nom: "Commune fictive" },
  geometry: { type: "Polygon", coordinates: contour(0, 0, NX, NY) } }]);

const sel = join(ex, "selection");
mkdirSync(sel, { recursive: true });
const propres = parcelles.map(({ _ij, ...f }) => f);
writeFileSync(join(sel, "parcelles.geojson"), JSON.stringify(fc(propres)));
writeFileSync(join(sel, "sections.geojson"), JSON.stringify(sections));
writeFileSync(join(sel, "commune.geojson"), JSON.stringify(commune));
const resume = {};
for (const p of propres) {
  const r = (resume[p.properties.section] ||= { section: p.properties.section, n: 0, surface_ha: 0 });
  r.n++; r.surface_ha += p.properties.contenance / 1e4;
}
writeFileSync(join(sel, "selection.json"), JSON.stringify({
  exemple: true,
  insee: INSEE, commune: "Commune fictive", departement: "99",
  n: propres.length,
  surface_ha: Math.round(propres.reduce((s, p) => s + p.properties.contenance, 0) / 100) / 100,
  mode: "complet", bd_foret: true,
  sections: Object.values(resume).map((r) => ({ ...r, surface_ha: Math.round(r.surface_ha * 100) / 100 })),
  nom_projet: "Forêt exemple",
  source: "Données fictives générées par outils/generer-exemples.mjs"
}, null, 1));

// ---------------------------------------------------------------- Atlas
// Une UG par paire de parcelles boisées voisines (horizontalement).
const catalogue = JSON.parse(readFileSync(join(ex, "catalogue.json"), "utf8"));
const boisees = parcelles.filter((p) => enForet(...p._ij));
const parIj = new Map(boisees.map((p) => [p._ij.join(","), p]));
const pris = new Set();
const ugs = [];
for (const p of boisees) {
  const [i, j] = p._ij;
  if (pris.has(p)) continue;
  const voisin = parIj.get(i + 1 + "," + j);
  const membres = voisin && !pris.has(voisin) ? [p, voisin] : [p];
  membres.forEach((m) => pris.add(m));
  const i1 = i + membres.length;
  ugs.push({ membres, i, j, anneau: contour(i, j, i1, j + 1) });
}

const groupes = ["Futaie régulière", "Futaie irrégulière", "Taillis sous futaie", "Îlot de sénescence"];
const borne = (x) => Math.max(0, Math.min(100, x));
const features = ugs.map((u, k) => {
  // Comme le connecteur : une UGF d'une seule parcelle garde le nom par
  // défaut de nemetonshiny (sa référence cadastrale) et s'affiche « UGF n » ;
  // les autres portent un nom choisi.
  const refs = u.membres.map((m) => m.properties.idu);
  const courte = (idu) => idu.slice(8, 10).replace(/^0+/, "") + " " + Number(idu.slice(10));
  const defaut = refs.length === 1;
  const props = {
    ug_id: "ug_" + (k + 1),
    label: defaut ? "UGF " + (k + 1) : "UG " + (k + 1),
    groupe: groupes[(u.i + u.j) % groupes.length],
    surface_ha: Math.round(u.membres.reduce((s, m) => s + m.properties.contenance, 0) / 100) / 100,
    label_cadastre: defaut ? refs[0] : "UG " + (k + 1),
    label_par_defaut: defaut,
    parcelles: refs.map(courte).join(", "),
    n_parcelles: refs.length
  };
  // Gradients spatiaux pour que les cartes racontent quelque chose.
  const x = (u.i - 11) / 12, y = (u.j - 3) / 11;
  for (const fam of catalogue) {
    const notes = [];
    for (const ind of fam.indicateurs) {
      let v = borne(50 + 30 * Math.sin(3 * x + fam.code.charCodeAt(0)) * Math.cos(2 * y) + (alea() - 0.5) * 30);
      let statut = null;
      if (ind.code === "A5") { v = null; statut = "hors_zone_urbaine"; }
      if (ind.code === "R5" && alea() < 0.6) { v = null; statut = "hors_zone_validite"; }
      if (ind.code === "R7" && alea() < 0.15) { v = null; statut = "donnee_climat_absente"; }
      props[ind.colonne_norm] = v == null ? null : Math.round(v * 10) / 10;
      if (statut) props[ind.statut] = statut;
      if (v != null) notes.push(v);
    }
    const col = { C: "famille_carbone", B: "famille_biodiversite", W: "famille_eau", A: "famille_air",
      F: "famille_sol", L: "famille_paysage", T: "famille_temporel", R: "famille_risque",
      S: "famille_social", P: "famille_production", E: "famille_energie", N: "famille_naturalite" }[fam.code];
    fam.colonne = col;
    props[col] = notes.length ? Math.round((notes.reduce((a, b) => a + b, 0) / notes.length) * 10) / 10 : null;
  }
  // Production et biodiversité s'opposent : de quoi montrer la carte bivariée.
  props.famille_production = Math.round(borne(30 + 60 * (x + 1) / 2 + (alea() - 0.5) * 20) * 10) / 10;
  props.famille_biodiversite = Math.round(borne(100 - props.famille_production + (alea() - 0.5) * 25) * 10) / 10;
  return { type: "Feature", properties: props, geometry: { type: "Polygon", coordinates: u.anneau } };
});

const moyenne = (col) => {
  const v = features.map((f) => f.properties[col]).filter((x) => x != null);
  return v.length ? Math.round((v.reduce((a, b) => a + b, 0) / v.length) * 10) / 10 : null;
};
const familles = catalogue.map((f) => ({ code: f.code, nom: f.nom_fr, score: moyenne(f.colonne) }));
const atlas = {
  type: "FeatureCollection",
  nemeton: {
    exemple: true,
    project_id: "20261006_120000_demo",
    name: "Forêt exemple (données fictives)",
    global_score: Math.round((familles.reduce((s, f) => s + (f.score || 0), 0) / familles.length) * 10) / 10,
    ndp_level: 2, ndp_name: "Diagnostic intermédiaire",
    confidence: 0.72,
    updated_at: "2026-10-06T12:00:00",
    langue: "fr",
    n_ugf: features.length, n_parcelles: boisees.length,
    familles,
    genere_a: "2026-10-06T12:00:00+0200",
    catalogue
  },
  features
};
const at = join(ex, "atlas");
mkdirSync(at, { recursive: true });
writeFileSync(join(at, "atlas.geojson"), JSON.stringify(atlas));

// Contexte : une route en travers et un ruisseau sinueux.
const ligne = (f) => Array.from({ length: 40 }, (_, k) => f(k / 39)).map(([a, b]) => [r6(a), r6(b)]);
writeFileSync(join(at, "contexte.geojson"), JSON.stringify(fc([
  { type: "Feature", properties: { couche: "route", nature: "Route à 1 chaussée", importance: "3", nom: "D 905" },
    geometry: { type: "LineString", coordinates: ligne((t) => [LON0 + t * NX * DX, LAT0 + DY * (3 + 6 * t)]) } },
  { type: "Feature", properties: { couche: "cours_eau", nature: "Ruisseau", nom: "Ruisseau fictif" },
    geometry: { type: "LineString", coordinates: ligne((t) => [LON0 + DX * (14 + 3 * Math.sin(t * 7)), LAT0 + t * NY * DY]) } }
])));
// Plan d'actions : les UG de l'Atlas, et un plan type sur 20 ans.
const pl = join(ex, "plan");
mkdirSync(pl, { recursive: true });
const familleCols = ["ug_id", "label", "label_cadastre", "label_par_defaut", "parcelles", "n_parcelles", "groupe", "surface_ha", "famille_carbone", "famille_biodiversite", "famille_eau",
  "famille_air", "famille_sol", "famille_paysage", "famille_temporel", "famille_risque", "famille_social",
  "famille_production", "famille_energie", "famille_naturalite"];
writeFileSync(join(pl, "plan.geojson"), JSON.stringify({
  type: "FeatureCollection",
  nemeton: { exemple: true, project_id: atlas.nemeton.project_id, name: atlas.nemeton.name, genere_a: "2026-10-06T12:00:00+0200" },
  features: features.map((f) => ({ type: "Feature", geometry: f.geometry,
    properties: Object.fromEntries(familleCols.map((c) => [c, f.properties[c] ?? null])) }))
}));
// Même fond de contexte que l'Atlas, écrit plus bas.
const BASE = 2026;
const modeles = [
  ["eclaircie", "moderee", 2, "haute", "planifiee", ["P", "C"], { volume_m3: 85, surface_ha: 3.1, cout_eur: 900, revenu_eur: 4200 }],
  ["depressage", null, 1, "moyenne", "validee", ["P"], { surface_ha: 2.4, cout_eur: 1800 }],
  ["cloisonnement", null, 1, "moyenne", "realisee", ["P", "F"], { surface_ha: 4, cout_eur: 1200 }],
  ["regeneration", null, 6, "moyenne", "proposee", ["B", "T"], { surface_ha: 2 }],
  ["observation", null, 3, "basse", "planifiee", ["B"], {}],
  ["coupe_rase", "forte", 14, "basse", "abandonnee", ["P"], { volume_m3: 320, revenu_eur: 19000 }],
  ["plantation", null, 15, "moyenne", "proposee", ["C", "P"], { surface_ha: 2.8, nb_tiges: 4500, cout_eur: 9800 }],
  ["protection", null, 2, "haute", "validee", ["B", "N"], { cout_eur: 650 }],
  ["eclaircie", "faible", 9, "moyenne", "proposee", ["P", "R"], { volume_m3: 60, revenu_eur: 2600 }],
  ["entretien", null, 4, "basse", "planifiee", ["S", "L"], { cout_eur: 400 }],
  ["autre", null, 5, "moyenne", "proposee", ["W", "B"], { cout_eur: 2500 }]
];
const actionsPlan = [], historique = [];
modeles.forEach((m, k) => {
  const u = features[(k * 7 + 3) % features.length].properties;
  const id = "act_20261006" + String(100000 + k) + "_demo" + k;
  const claude = m[4] === "proposee" && (k === 6 || k === 8);
  const a = { id, ug_id: u.ug_id, type: m[0], type_libre: m[0] === "autre" ? "Création d'une mare forestière" : null,
    intensite: m[1], annee_cible: m[2], annee: BASE + m[2], duree: 1, priorite: m[3], statut: m[4], objectifs_lies: m[5],
    quantite: m[6], source: { origine: claude ? "claude" : "vue", extrait_texte: claude ? "Biodiversité (B) faible et régénération lente : favoriser le mélange." : null },
    commentaire: null, cree_par: "gestionnaire", cree_le: "2026-09-1" + (k % 9) + "T09:00:00+0200",
    ug_label: u.label, propose_par_claude: claude, version: "v" + k };
  actionsPlan.push(a);
  historique.push({ ts: a.cree_le, user: "gestionnaire", action_id: id, op: "create" });
  if (m[4] !== "proposee") historique.push({ ts: "2026-10-01T14:3" + (k % 10) + ":00+0200", user: "gestionnaire", action_id: id, op: "update", champ: "statut", ancien: "proposee", nouveau: m[4] === "realisee" ? "planifiee" : m[4] });
});
writeFileSync(join(pl, "plan.json"), JSON.stringify({
  exemple: true, ok: true, projet: atlas.nemeton.project_id, nom: atlas.nemeton.name,
  horizon_annees: 20, annee_base: BASE, actions: actionsPlan, historique: historique.reverse(),
  commentaires_ug: { [features[3].properties.ug_id]: "Peuplement fragilisé par les sécheresses de 2022." },
  catalogue: {
    types: ["coupe_rase", "eclaircie", "depressage", "plantation", "regeneration", "cloisonnement", "desserte", "observation", "protection", "entretien", "autre"],
    statuts: ["proposee", "validee", "planifiee", "realisee", "abandonnee"], priorites: ["haute", "moyenne", "basse"],
    familles: ["C", "B", "W", "A", "F", "L", "T", "R", "S", "P", "E", "N"],
    transitions: { proposee: ["validee", "abandonnee"], validee: ["planifiee", "abandonnee"], planifiee: ["validee", "realisee", "abandonnee"], realisee: [], abandonnee: ["proposee"] },
    types_marculus: ["coupe_rase", "eclaircie", "depressage", "observation"]
  },
  peut_ecrire: false, genere_a: "2026-10-06T12:00:00+0200"
}, null, 1) + "\n");

// Calcul : état figé d'un calcul en cours, sans connecteur.
const cal = join(ex, "calcul");
mkdirSync(cal, { recursive: true });
writeFileSync(join(cal, "calcul.json"), JSON.stringify({
  exemple: true, projet: "20261006_101500_exmp", nom: "Forêt fictive de démonstration",
  etat: {
    ok: true, projet: "20261006_101500_exmp", statut: "en_cours", job_id: "20261006101502-abcd",
    phase: "computing", progression: 12, progression_max: 41, indicateurs_faits: 12, indicateurs_total: 41,
    tache: "B2 — Diversité structurale", ecoule_s: 1694
  }
}, null, 1) + "\n");
copyFileSync(join(at, "contexte.geojson"), join(pl, "contexte.geojson"));
console.log(`${propres.length} parcelles, ${features.length} UG d'exemple écrites dans vues/exemples/.`);
