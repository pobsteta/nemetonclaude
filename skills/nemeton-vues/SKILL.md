---
name: nemeton-vues
description: Créer un projet nemeton et publier ses vues interactives dans Claude (Sélection des parcelles, Atlas du projet) à partir du connecteur MCP nemeton. À utiliser dès qu'un utilisateur parle de diagnostiquer une forêt, de créer un projet nemeton, de choisir des parcelles cadastrales, ou de voir, explorer ou partager les résultats d'un projet (familles, indicateurs, carte, radar).
---

# Vues nemeton dans Claude

Le connecteur MCP **nemeton** calcule ; les artéfacts Claude affichent. Le
connecteur est le seul à parler à nemeton : Claude appelle ses outils, publie
une vue avec les fichiers qu'ils écrivent, et la vue relit le connecteur en
direct quand elle le peut (capacité `mcp`, serveur `host:nemeton`).

Référence : `specs/BRIEF-visualisation-nemeton-claude.md`.

## Quand ouvrir quelle vue

| L'utilisateur… | Vue | Outils |
| --- | --- | --- |
| veut créer un projet, nomme une commune ou sa forêt | **Sélection** (`vues/selection/`) | `chercher_commune` → `parcelles_commune` → (vue) `creer_projet` |
| veut voir, explorer ou partager les résultats d'un projet calculé | **Atlas** (`vues/atlas/`) | `vue_atlas`, `contexte_carto` (facultatif), `detail_indicateur` (depuis la vue) |
| attend un calcul | conversation (lot 2 : vue Calcul) | `lancer_calcul`, `etat_calcul`, `annuler_calcul` |
| veut un rapport, un GeoPackage | conversation | `generer_rapport`, `exporter_gpkg` |
| veut éditer les unités de gestion | application nemetonshiny | `url_app` |

## Parcours « créer son premier projet »

1. Demander le département et la commune si l'utilisateur ne les a pas donnés.
2. `chercher_commune(departement, nom)`.
   - `choix_requis = false` : la commune est dans `commune` ; continuer.
   - `choix_requis = true` : **proposer les candidats** (nom, code postal,
     type) et laisser l'utilisateur choisir. Ne jamais choisir à sa place, même
     pour un homonyme moins peuplé ou une commune déléguée.
   - Prendre ensuite `insee_cadastre` (commune nouvelle pour une commune
     déléguée), pas `insee`.
3. `parcelles_commune(insee = <insee_cadastre>)`. L'outil écrit les fichiers
   dans `dossier` et rend leurs chemins dans `fichiers`.
4. Publier la vue Sélection (voir « Publier une vue ») avec :
   - `selection.json` ← `fichiers.selection`
   - `commune.geojson` ← `fichiers.commune` (si présent)
   - `sections.geojson` ← `fichiers.sections`
   - `parcelles.geojson` ← `fichiers.parcelles` en mode `complet` ;
     en mode `par_section`, un fichier `sections/<S>.geojson` par entrée de
     `sections_fichiers` (la vue les charge au clic sur la section).
   - Capacités : `{"mcp": {"servers": [{"server": "host:nemeton", "tools": ["creer_projet", "lancer_calcul"]}]}}`.
5. L'utilisateur clique ses parcelles et valide :
   - **dans l'app de bureau** avec le serveur nemeton : la vue appelle
     `creer_projet` elle-même et affiche l'identifiant ;
   - **ailleurs** (navigateur, mobile, lien partagé) : la vue affiche la liste
     des IDU à copier ; quand elle arrive dans la conversation, appeler
     `creer_projet(nom, insee, parcelles)` avec cette liste.
6. Enchaîner : `lancer_calcul(projet)`, puis suivre `etat_calcul` jusqu'à
   `termine`, puis ouvrir l'Atlas.

## Parcours « Atlas »

1. `vue_atlas(projet, langue)` : écrit `atlas.geojson` (une entité par UG,
   en-tête `nemeton` avec score global, NDP, confiance φ et catalogue des
   familles). Erreur `nemetonshiny_sans_indicateurs` : proposer `lancer_calcul`.
   Erreur `nemetonshiny_projet_ambigu` : proposer les `candidats`.
2. Facultatif : `contexte_carto(projet)` pour les routes et l'hydrographie
   (fond vectoriel, les tuiles étant bloquées).
3. Publier la vue Atlas avec :
   - `atlas.geojson` ← `fichier` de `vue_atlas`
   - `contexte.geojson` ← `fichier` de `contexte_carto` (si présent)
   - Capacités : `{"mcp": {"servers": [{"server": "host:nemeton", "tools": ["detail_indicateur", "exporter_gpkg"]}]}, "sample": {}, "downloads": true}`.
4. Résumer en deux ou trois phrases ce que montre l'Atlas (score global,
   familles les plus fortes et les plus faibles, valeurs manquantes) et donner
   le lien.

## Publier une vue

Chaque vue = sa page (`vues/<vue>/index.html`) + le moteur commun
(`nemeton-view.js`, `nemeton-view.css`) + ses données.

- **Premier usage** : publier un artéfact modèle « Moteur nemeton » qui porte
  `nemeton-view.js` et `nemeton-view.css` (fichiers de `vues/moteur/`), et
  noter son URL.
- **Chaque vue** : publier `vues/<vue>/index.html` avec
  `files = {"nemeton-view.js": {artifact: <URL du modèle>, path: "nemeton-view.js"},
  "nemeton-view.css": {artifact: <URL du modèle>, path: "nemeton-view.css"},
  "atlas.geojson": "<chemin rendu par l'outil>", …}`.
  Sans modèle, publier les deux fichiers du moteur directement depuis
  `vues/moteur/`.
- Titre : le nom du projet ou de la commune (« Atlas · Forêt de Velars »,
  « Sélection · Velars-sur-Ouche »).
- Les fichiers de données ne transitent jamais par la conversation : passer
  les chemins rendus par les outils. Taille : moins de 5 Mo par GeoJSON (les
  outils simplifient et découpent d'eux-mêmes).
- La capacité `mcp` vers `host:nemeton` ne répond que dans l'app Claude de
  bureau où le serveur est installé, et seulement pour le propriétaire de
  l'artéfact. Le dire à l'utilisateur à la publication ; la vue reste
  pleinement lisible sans (repli : liste d'IDU, pas de valeur brute à la
  demande, pas d'export GeoPackage).

## Contrat de données de l'Atlas

Propriétés de chaque entité : `ug_id`, `label`, `groupe`, `surface_ha` ; les
12 `famille_*` (0–100 : `famille_carbone`, `famille_biodiversite`,
`famille_eau`, `famille_air`, `famille_sol`, `famille_paysage`,
`famille_temporel`, `famille_risque`, `famille_social`, `famille_production`,
`famille_energie`, `famille_naturalite`) ; les `indicateur_<code>_<slug>_norm`
(0–100) ; les `.<code>_status` qui expliquent une valeur manquante.

En-tête `nemeton` : `project_id`, `name`, `global_score`, `ndp_level`,
`ndp_name`, `confidence`, `updated_at`, `langue`, `n_ugf`, `familles`
(score projet par famille) et `catalogue` (familles, colonnes, libellés et
aides FR/EN des sous-indicateurs, lus du cœur nemeton). La vue n'a aucune
liste d'indicateurs codée en dur : le catalogue voyage avec les données.

Une valeur manquante n'est **jamais** un zéro : hachures sur la carte, barre
hachurée, raison tirée de `.<code>_status`.

## Charte

- Thème clair et sombre ; palettes perceptuelles (viridis pour les scores,
  bivariée 5 × 5 pour les compromis).
- Vert `#1B6B1B` réservé à l'action principale ; ambre `#E8A33D` réservé aux
  contenus générés par IA (bloc « Demander à Claude »).
- FR/EN (bascule dans chaque vue), chiffres au format de la langue
  (`68 412,50` en français), WCAG AA, lisible à 400 px.
- Français : vouvoyer l'utilisateur.

## Profils experts

Le profil (gestionnaire forestier, élu local, propriétaire, naturaliste) se
choisit une fois par projet dans l'Atlas, à côté de « Demander à Claude ».
Les profils YAML de nemetonshiny (`inst/experts/`) restent côté R pour le
moment (question ouverte du brief).

## Erreurs du connecteur

Les outils rendent `{"ok": false, "erreur", "classe", "candidats"}` :

| Classe | Réponse |
| --- | --- |
| `nemetonclaude_departement_ambigu`, `nemetonshiny_projet_ambigu` | proposer les `candidats` |
| `nemetonclaude_commune_introuvable` | vérifier l'orthographe avec l'utilisateur, ou demander une commune voisine |
| `nemetonshiny_parcelles_introuvables` | signaler les IDU manquants (copie incomplète, autre commune) |
| `nemetonshiny_sans_indicateurs` | proposer `lancer_calcul` |
| `nemetonshiny_projet_ancien` | le projet date d'avant nemetonshiny 1.0 : proposer de le recréer avec les mêmes parcelles |
| `nemetonshiny_calcul_en_cours`, `nemetonshiny_projet_verrouille` | attendre, ou suivre `etat_calcul` |
