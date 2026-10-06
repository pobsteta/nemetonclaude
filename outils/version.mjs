// Version unique du dépôt, portée par r/DESCRIPTION et recopiée dans
// package.json, .claude-plugin/plugin.json et le premier titre de NEWS.md.
//
// Usage :
//   node outils/version.mjs                    affiche la version
//   node outils/version.mjs verifier           échoue si les fichiers divergent
//   node outils/version.mjs monter <niveau>    correctif | mineure | majeure | X.Y.Z :
//                                              écrit la version partout et ajoute
//                                              à NEWS.md la section des commits
//                                              depuis la dernière étiquette
//   node outils/version.mjs notes [X.Y.Z]      section de NEWS.md d'une version
//
// Pas de cycle de développement X.Y.Z.9000 : package.json exige du semver.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const racine = join(dirname(fileURLToPath(import.meta.url)), "..");
const chemin = (f) => join(racine, f);
const lire = (f) => readFileSync(chemin(f), "utf8");
const FICHIERS = { description: "r/DESCRIPTION", npm: "package.json", plugin: ".claude-plugin/plugin.json", news: "NEWS.md" };
const SEMVER = /^\d+\.\d+\.\d+$/;
const TITRE = /^# nemetonclaude (\d+\.\d+\.\d+)/m;

function echec(message) {
  console.error(`Erreur : ${message}`);
  process.exit(1);
}

function versions() {
  const desc = lire(FICHIERS.description).match(/^Version:\s*(\S+)/m)?.[1];
  const npm = JSON.parse(lire(FICHIERS.npm)).version;
  const plugin = JSON.parse(lire(FICHIERS.plugin)).version;
  const news = existsSync(chemin(FICHIERS.news)) ? lire(FICHIERS.news).match(TITRE)?.[1] : undefined;
  return { description: desc, npm, plugin, news };
}

export function suivante(actuelle, niveau) {
  if (SEMVER.test(niveau)) return niveau;
  const [maj, min, cor] = actuelle.split(".").map(Number);
  switch (niveau) {
    case "majeure": return `${maj + 1}.0.0`;
    case "mineure": return `${maj}.${min + 1}.0`;
    case "correctif": return `${maj}.${min}.${cor + 1}`;
    default: echec(`niveau inconnu : ${niveau} (correctif, mineure, majeure ou X.Y.Z)`);
  }
}

function git(...args) {
  try { return execFileSync("git", args, { cwd: racine, encoding: "utf8" }).trim(); } catch { return ""; }
}

// Sujets des commits depuis la dernière étiquette vX.Y.Z, sans les commits de
// version eux-mêmes : avec la fusion « squash », un sujet = une PR.
function nouveautes() {
  const derniere = git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*");
  const plage = derniere ? `${derniere}..HEAD` : "HEAD";
  return git("log", plage, "--no-merges", "--format=%s")
    .split("\n").map((s) => s.trim())
    .filter((s) => s && !/^Version \d+\.\d+\.\d+/.test(s));
}

function ecrireVersion(v) {
  const desc = lire(FICHIERS.description).replace(/^Version:\s*\S+/m, `Version: ${v}`);
  writeFileSync(chemin(FICHIERS.description), desc);
  // Remplacement ciblé plutôt que JSON.stringify : la mise en forme reste.
  for (const f of [FICHIERS.npm, FICHIERS.plugin]) {
    const texte = lire(f).replace(/^(\s*"version":\s*")[^"]*(")/m, `$1${v}$2`);
    if (JSON.parse(texte).version !== v) echec(`version introuvable dans ${f}`);
    writeFileSync(chemin(f), texte);
  }
}

function ajouterSection(v, lignes) {
  const date = new Date().toISOString().slice(0, 10);
  const corps = lignes.length ? lignes.map((l) => `- ${l}`).join("\n") : "- Maintenance.";
  const avant = existsSync(chemin(FICHIERS.news)) ? lire(FICHIERS.news) : "";
  writeFileSync(chemin(FICHIERS.news), `# nemetonclaude ${v} (${date})\n\n${corps}\n\n${avant}`.trimEnd() + "\n");
}

export function notes(texte, v) {
  const lignes = texte.split("\n");
  const debut = lignes.findIndex((l) => l.startsWith(`# nemetonclaude ${v} `) || l === `# nemetonclaude ${v}`);
  if (debut < 0) return "";
  const fin = lignes.findIndex((l, i) => i > debut && l.startsWith("# nemetonclaude "));
  return lignes.slice(debut + 1, fin < 0 ? undefined : fin).join("\n").trim();
}

const [commande, arg] = process.argv.slice(2);
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const v = versions();
  switch (commande) {
    case undefined:
      console.log(v.description);
      break;
    case "verifier": {
      const valeurs = Object.entries(v);
      for (const [f, x] of valeurs) console.log(`${FICHIERS[f].padEnd(27)} ${x ?? "(absente)"}`);
      if (!SEMVER.test(v.description ?? "")) echec(`version de r/DESCRIPTION non conforme X.Y.Z : ${v.description}`);
      if (valeurs.some(([, x]) => x !== v.description)) echec("versions désalignées");
      console.log(`Versions alignées : ${v.description}`);
      break;
    }
    case "monter": {
      if (!arg) echec("niveau manquant : correctif, mineure, majeure ou X.Y.Z");
      const n = suivante(v.description, arg);
      ecrireVersion(n);
      ajouterSection(n, nouveautes());
      console.log(n);
      break;
    }
    case "notes":
      console.log(notes(existsSync(chemin(FICHIERS.news)) ? lire(FICHIERS.news) : "", arg ?? v.description));
      break;
    default:
      echec(`commande inconnue : ${commande} (verifier, monter, notes)`);
  }
}
