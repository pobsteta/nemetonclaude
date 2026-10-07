# nemetonclaude 0.4.0 (2026-10-07)

- Propose le GeoPackage au téléchargement dans l'Atlas, comme le CSV (#10)

# nemetonclaude 0.3.1 (2026-10-07)

- Affiche « UGF n » pour les UGF qui gardent leur nom cadastral (#7)

# nemetonclaude 0.3.0 (2026-10-07)

- Lot 3 : plan d'actions partagé (#6)

# nemetonclaude 0.2.0 (2026-10-06)

- Lot 2 : connecteur distant (HTTP, Keycloak) et vue Calcul (#5)
- Passe les actions GitHub en Node.js 24 et fixe Ubuntu 24.04 (#4)

# nemetonclaude 0.1.0 (2026-10-06)

Première version : lot 1 du brief `specs/BRIEF-visualisation-nemeton-claude.md`.

- Connecteur MCP étendu : les 8 outils de nemetonshiny, plus
  `chercher_commune`, `parcelles_commune`, `creer_projet`, `vue_atlas`,
  `contexte_carto` et `detail_indicateur`.
- Moteur commun des vues (`nemeton-view.js`, `nemeton-view.css`), vue
  Sélection des parcelles et vue Atlas du projet.
- Skill du plugin `nemeton-vues`.
- `outils/essayer.sh` pour tout essayer d'un coup.
- Intégration continue (tests R, `R CMD check`, tests unitaires et de bout en
  bout des vues, couverture), versions alignées et publication automatique des
  versions.
