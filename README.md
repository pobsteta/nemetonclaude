# nemetonClaude

Visualisation de [nemeton](https://github.com/pobsteta/nemeton) dans Claude,
sous forme de plugin : un **connecteur MCP** qui calcule, et des
**artéfacts Claude** (pages web publiées, partageables par lien) qui affichent.
L'application [nemetonshiny](https://github.com/pobsteta/nemetonshiny) reste la
référence fonctionnelle.

Le brief qui cadre le projet est dans
[`specs/BRIEF-visualisation-nemeton-claude.md`](specs/BRIEF-visualisation-nemeton-claude.md).

## Contenu (lot 1 : Sélection et Atlas en local)

| Dossier | Rôle |
| --- | --- |
| `r/` | Paquet R **nemetonclaude** : étend le serveur MCP de nemetonshiny (8 outils existants) avec `chercher_commune`, `parcelles_commune`, `creer_projet`, `vue_atlas`, `contexte_carto`, `detail_indicateur` |
| `vues/moteur/` | Moteur commun des vues : `nemeton-view.js` (carte Leaflet sans tuiles, palettes, radar, i18n FR/EN, appels au connecteur) et `nemeton-view.css` (charte, thème clair et sombre, styles Leaflet inlinés) |
| `vues/selection/` | **Vue 0 — Sélection des parcelles** : carte de la commune, clic pour ajouter ou retirer, recherche « AB 12 », sélection au rectangle, surface totale, BD Forêt en repère, « Créer le projet » via le connecteur ou liste d'IDU à copier |
| `vues/atlas/` | **Vue 1 — Atlas du projet** : rail des 12 familles, carte choroplèthe ou bivariée 5 × 5, tableau lié à la carte, fiche d'UG avec radar 12 axes et sous-indicateurs, valeurs manquantes hachurées avec leur raison, comparaison de deux UG, « Demander à Claude », exports CSV et GeoPackage |
| `vues/exemples/` | Données **fictives** pour essayer les vues sans nemeton, et catalogue des familles du cœur |
| `skills/nemeton-vues/` | Skill du plugin : quand ouvrir quelle vue, comment la publier, contrat de données, charte |
| `.claude-plugin/`, `.mcp.json` | Manifeste du plugin et déclaration du serveur MCP `nemeton` |
| `outils/`, `tests/` | Fabrication (CSS, données d'exemple, assemblage d'une vue) et tests de bout en bout |

## Installation

### Connecteur R

Le serveur MCP tourne en local (stdio), sur la machine qui a vos projets
nemeton.

```r
# install.packages("remotes")
remotes::install_github("pobsteta/nemetonshiny")
remotes::install_github("pobsteta/nemetonclaude", subdir = "r")
install.packages(c("mcptools", "happign"))  # happign : repli cadastre, BD Forêt, BD TOPO
```

Le serveur se lance par `Rscript -e "nemetonclaude::serveur_mcp()"` (déjà
déclaré dans `.mcp.json`). Variables utiles : `NEMETON_PROJECT_DIR` (dossier
des projets, comme nemetonshiny) et `NEMETON_CLAUDE_VUES_DIR` (dossier des
fichiers GeoJSON écrits pour les vues, par défaut le cache utilisateur R). Le
serveur doit tourner dans une locale UTF-8.

### Plugin Claude Code

```bash
claude --plugin-dir <chemin de ce dépôt>   # charge le plugin pour la session
```

Le plugin apporte le serveur MCP `nemeton` et le skill `nemeton-vues`.

## Tout essayer d'un coup

```bash
outils/essayer.sh          # connecteur R (installe nemetonshiny >= 1.0.0 si besoin),
                           # tests des vues, puis aperçu sur http://localhost:8765
outils/essayer.sh claude   # Claude Code avec le plugin chargé
```

Étapes séparées : `outils/essayer.sh r`, `vues`, `apercu` (`--help` pour le
détail).

## Essayer les vues sans nemeton

```bash
npm install
npm run exemples              # régénère vues/exemples/ (données fictives)
node outils/assembler-vue.mjs atlas vues/exemples/atlas .apercu/atlas
npx serve .apercu             # puis ouvrir /atlas/ et /selection/
npm test                      # tests de bout en bout (Chromium)
```

Côté R :

```bash
cd r && Rscript -e 'devtools::test()'
```

## Limites connues

- La capacité `mcp` d'un artéfact vers `host:nemeton` ne répond que dans
  l'application Claude de bureau où le serveur est installé, et pour le
  propriétaire de l'artéfact. Ailleurs, les vues restent lisibles et passent
  par la conversation (liste d'IDU à copier, pas de valeur brute à la demande).
  Le partage complet demande le connecteur distant (lot 2).
- Le cœur nemeton déclare aujourd'hui 41 sous-indicateurs, et non 31 comme
  dans le brief. Les vues lisent le catalogue joint aux données et s'adaptent
  au nombre réel.
- Lots suivants : vue Calcul et connecteur distant (lot 2), plan d'actions
  partagé (lot 3), rasters pré-rendus (lot 4).
