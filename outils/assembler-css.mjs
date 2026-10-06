// Assemble vues/moteur/nemeton-view.css : styles de Leaflet (inlinés, les
// feuilles de style externes étant bloquées dans un artéfact) + charte nemeton.
// Usage : node outils/assembler-css.mjs <chemin vers leaflet/dist/leaflet.css>
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ici = dirname(fileURLToPath(import.meta.url));
const source = process.argv[2];
if (!source) { console.error("Chemin de leaflet.css requis."); process.exit(1); }
const leaflet = readFileSync(source, "utf8")
  // Ni marqueurs ni contrôle de couches : on retire les images référencées.
  .replace(/^[^{}]*\{[^{}]*url\(images\/[^)]*\)[^{}]*\}\s*/gm, "")
  .replace(/\n{3,}/g, "\n\n");
const base = readFileSync(join(ici, "../vues/moteur/nemeton-view.base.css"), "utf8");
writeFileSync(join(ici, "../vues/moteur/nemeton-view.css"),
  "/* Leaflet 1.9.4 — leaflet.css (BSD-2-Clause, © Volodymyr Agafonkin, CloudMade) */\n" +
  leaflet.trim() + "\n\n" + base);
console.log("vues/moteur/nemeton-view.css écrit.");
