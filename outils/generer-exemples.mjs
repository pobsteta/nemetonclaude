// Génère les données FICTIVES des vues (aucune donnée réelle) :
//   vues/exemples/selection/{selection.json, commune.geojson, sections.geojson, parcelles.geojson}
//   vues/exemples/atlas/{atlas.geojson, contexte.geojson}
// Le catalogue des familles (vues/exemples/catalogue.json) est celui du cœur
// nemeton (R/indicator-config.R) ; les valeurs, elles, sont tirées au hasard.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
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
  const props = {
    ug_id: "UG" + String(k + 1).padStart(3, "0"),
    label: "UG " + (k + 1),
    groupe: groupes[(u.i + u.j) % groupes.length],
    surface_ha: Math.round(u.membres.reduce((s, m) => s + m.properties.contenance, 0) / 100) / 100
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
console.log(`${propres.length} parcelles, ${features.length} UG d'exemple écrites dans vues/exemples/.`);
