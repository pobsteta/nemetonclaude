// Assemble une vue comme elle sera publiée : page + moteur + données, dans un
// dossier prêt à servir (aperçu local) ou à publier fichier par fichier.
// Usage : node outils/assembler-vue.mjs <selection|atlas> <dossier de données> <sortie>
// La page publiée n'a ni <html> ni <body> (l'artéfact les ajoute) ; pour
// l'aperçu local, on l'enveloppe dans le même squelette minimal.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const ici = dirname(fileURLToPath(import.meta.url));
const [vue, donnees, sortie] = process.argv.slice(2);
if (!vue || !donnees || !sortie) {
  console.error("Usage : node outils/assembler-vue.mjs <selection|atlas> <données> <sortie>");
  process.exit(1);
}
mkdirSync(sortie, { recursive: true });
const page = readFileSync(join(ici, "../vues", vue, "index.html"), "utf8");
writeFileSync(join(sortie, "index.html"),
  '<!doctype html><html lang="fr"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' +
  "<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}" +
  "body{margin:0;font:14px system-ui;background:#fafaf7}img{max-width:100%}[hidden]{display:none!important}</style>" +
  "</head><body>" + page + "</body></html>");
for (const f of ["nemeton-view.js", "nemeton-view.css"]) copyFileSync(join(ici, "../vues/moteur", f), join(sortie, f));
(function copier(d) {
  for (const n of readdirSync(d)) {
    const p = join(d, n);
    if (statSync(p).isDirectory()) { copier(p); continue; }
    const cible = join(sortie, relative(donnees, p));
    mkdirSync(dirname(cible), { recursive: true });
    copyFileSync(p, cible);
  }
})(donnees);
console.log(`Vue ${vue} assemblée dans ${sortie}`);
