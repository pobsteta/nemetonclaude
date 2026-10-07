---
name: nemeton-vues
description: Créer un projet nemeton et publier ses vues interactives dans Claude (Sélection des parcelles, Calcul en cours, Atlas du projet, Plan d'actions partagé) à partir du connecteur MCP nemeton, local ou distant. À utiliser dès qu'un utilisateur parle de diagnostiquer une forêt, de créer un projet nemeton, de choisir des parcelles cadastrales, de lancer ou suivre un calcul, de voir, explorer ou partager les résultats d'un projet (familles, indicateurs, carte, radar), ou de planifier des actions sylvicoles (éclaircie, plantation, martelage Marculus).
---

# Vues nemeton dans Claude

Le connecteur MCP **nemeton** calcule ; les artéfacts Claude affichent. Le
connecteur est le seul à parler à nemeton : Claude appelle ses outils, publie
une vue avec les fichiers qu'ils écrivent, et la vue relit le connecteur en
direct quand elle le peut (capacité `mcp`).

Le connecteur existe sous deux formes, avec les mêmes outils :

| Forme | Dans cette session | Dans le manifeste d'une vue | Qui la vue peut appeler |
| --- | --- | --- | --- |
| **Locale** (stdio, plugin) | outils `mcp__nemeton__*` | `host:nemeton` | le propriétaire de l'artéfact, dans l'app Claude de bureau |
| **Distante** (HTTP + Keycloak, connecteur claude.ai) | outils `mcp__<segment>__*` d'un connecteur claude.ai nemeton | le segment `<segment>` (résolu en nom affiché à la publication) | tout lecteur qui a ajouté ce connecteur avec son compte Keycloak, sur le web, le mobile ou le bureau |

Déclarer dans le manifeste **les serveurs nemeton présents dans cette
session** (l'un, l'autre ou les deux) ; la vue choisit seule celui qui répond,
le distant d'abord (`NV.connecter`).

Référence : `specs/BRIEF-visualisation-nemeton-claude.md`.

## Quand ouvrir quelle vue

| L'utilisateur… | Vue | Outils |
| --- | --- | --- |
| veut créer un projet, nomme une commune ou sa forêt | **Sélection** (`vues/selection/`) | `chercher_commune` → `parcelles_commune` → (vue) `creer_projet` |
| veut voir, explorer ou partager les résultats d'un projet calculé | **Atlas** (`vues/atlas/`) | `vue_atlas`, `contexte_carto` (facultatif), `detail_indicateur` (depuis la vue) |
| lance ou attend un calcul | **Calcul** (`vues/calcul/`) | `lancer_calcul`, `etat_calcul` (suivi depuis la vue), `annuler_calcul` |
| veut planifier, valider ou partager des actions sylvicoles | **Plan d'actions** (`vues/plan/`) | `plan_actions`, `ajouter_action`, `modifier_action`, `supprimer_action`, `profils_experts`, `exporter_marculus` |
| veut un rapport, un GeoPackage | conversation | `generer_rapport` (pièce officielle, PDF), `exporter_gpkg` (connecteur distant : lien `urls` ; avec `zip = true`, le GeoPackage zippé en base64, que la vue Atlas propose au téléchargement comme le CSV) |
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
   - Capacités : `{"mcp": {"servers": [{"server": <serveur nemeton>, "tools": ["creer_projet", "lancer_calcul"]}]}}`,
     une entrée par serveur nemeton de la session (voir plus haut).
5. L'utilisateur clique ses parcelles et valide :
   - **dans l'app de bureau** avec le serveur nemeton : la vue appelle
     `creer_projet` elle-même et affiche l'identifiant ;
   - **ailleurs** (navigateur, mobile, lien partagé) : la vue affiche la liste
     des IDU à copier ; quand elle arrive dans la conversation, appeler
     `creer_projet(nom, insee, parcelles)` avec cette liste.
6. Enchaîner sur le parcours « Calcul ».

## Parcours « Calcul »

1. `lancer_calcul(projet)` (si la vue Sélection ne l'a pas déjà fait), puis
   un premier `etat_calcul(projet)`.
2. Écrire dans le dossier de travail un `calcul.json` :
   `{"projet": <id>, "nom": <nom du projet>, "etat": <réponse d'etat_calcul>}`.
3. Publier la vue Calcul avec `calcul.json` et les capacités
   `{"mcp": {"servers": [{"server": <serveur nemeton>, "tools": ["etat_calcul", "annuler_calcul", "lancer_calcul"]}]}}`.
   La vue suit `etat_calcul` (environ toutes les 30 s), propose Annuler
   (avec confirmation) et Relancer, affiche le journal en cas d'échec, et
   invite à demander l'Atlas une fois le calcul terminé.
4. Sans connecteur joignable pour le lecteur, la vue montre l'état figé de
   `calcul.json` : suivre alors `etat_calcul` dans la conversation à la
   demande de l'utilisateur, sans boucle d'attente.
5. Quand l'utilisateur revient avec « ouvre l'Atlas de … », enchaîner sur le
   parcours « Atlas ».

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
   - Capacités : `{"mcp": {"servers": [{"server": <serveur nemeton>, "tools": ["detail_indicateur", "exporter_gpkg", "profils_experts"]}]}, "sample": {}, "downloads": true}`.
4. Résumer en deux ou trois phrases ce que montre l'Atlas (score global,
   familles les plus fortes et les plus faibles, valeurs manquantes) et donner
   le lien.

## Parcours « Plan d'actions »

Le plan est celui du projet nemeton, le même que dans nemetonshiny (avec son
historique) : la vue le lit et l'écrit par le connecteur, il n'y a pas de
seconde copie.

1. `plan_actions(projet)` : écrit `plan.geojson` (les unités de gestion, avec
   leurs scores de familles) et rend le plan. Écrire sa réponse telle quelle
   dans le dossier de travail sous le nom `plan.json`.
2. Facultatif : `contexte_carto(projet)` pour les routes et l'hydrographie.
3. Publier la vue Plan avec `plan.json`, `plan.geojson` (← `fichier`) et
   `contexte.geojson`, et les capacités
   `{"mcp": {"servers": [{"server": <serveur nemeton>, "tools": ["plan_actions", "ajouter_action", "modifier_action", "supprimer_action", "profils_experts", "exporter_marculus"]}]}, "sample": {}, "downloads": true, "comments": {"composer_only": true}}`.
4. La vue suit le plan (environ 30 s) : calendrier en vue simple ; tableau,
   kanban des statuts, quantités et historique en vue experte (bascule
   mémorisée par lecteur). Les rôles `gestionnaire` et `admin` modifient,
   `lecteur` consulte et commente (commentaires claude.ai ancrés sur une
   action).

**Claude propose, une personne valide.** Une action suggérée par Claude,
depuis la vue (bouton « Proposer des actions avec Claude ») ou dans la
conversation, entre au plan en statut `proposee` avec
`source = {origine: "claude", extrait_texte: <justification>}`. Elle
s'affiche en ambre jusqu'à ce qu'une personne la valide (`validee`) ou
l'écarte (`abandonnee`). Ne jamais valider, planifier ou réaliser une action
à la place de l'utilisateur.

Dans la conversation :
- lire le plan avec `plan_actions(projet, geojson = false)` ;
- passer les années civiles (`annee: 2030`), pas les décalages ;
- pour modifier, passer `attendu = <version>` lue dans `plan_actions` :
  l'erreur `nemetonclaude_conflit` signale que quelqu'un a modifié l'action
  entre-temps et porte sa version actuelle dans `candidats` ;
- préférer le statut `abandonnee` à `supprimer_action` pour garder la trace
  au tableau.

`exporter_marculus(projet)` produit le paquet terrain (un GeoPackage par
action de martelage et le `.marsync`), à télécharger par le lien `urls` ;
le plan ne change pas. Le retour du martelage s'importe dans nemetonshiny.

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
- Les fichiers de données ne transitent jamais par la conversation.
  - **Connecteur local** : passer les chemins rendus par les outils.
  - **Connecteur distant** : les chemins sont ceux du serveur. Chaque réponse
    qui en contient porte `urls` (chemin → lien signé, valable
    `urls_expirent_dans_s` secondes, une heure par défaut). Télécharger chaque
    fichier utile dans le dossier de travail (`curl -fsSL -o <fichier> <lien>`)
    et publier ces copies. Un lien expiré : rappeler l'outil.
  - Taille : moins de 5 Mo par GeoJSON (les outils simplifient et découpent
    d'eux-mêmes).
- Rapport et GeoPackage du connecteur distant : donner à l'utilisateur le lien
  de `urls` (téléchargement direct, une heure) plutôt que le chemin.
- Dire à l'utilisateur, à la publication, qui pourra utiliser les fonctions
  vivantes de la vue :
  - `host:nemeton` : seulement le propriétaire de l'artéfact, dans l'app Claude
    de bureau où le serveur est installé ;
  - connecteur distant : tout lecteur qui a ajouté le connecteur nemeton à son
    compte claude.ai et dont le compte Keycloak a un rôle nemeton (`lecteur`
    pour lire, `gestionnaire` ou `admin` pour créer un projet, lancer ou
    annuler un calcul, écrire un export).
  La vue reste pleinement lisible sans (repli : liste d'IDU, état figé du
  calcul, pas de valeur brute à la demande, pas d'export GeoPackage).

## Contrat de données de l'Atlas

Propriétés de chaque entité : `ug_id`, `label`, `groupe`, `surface_ha`,
`label_cadastre`, `label_par_defaut`, `parcelles`, `n_parcelles` ; les
12 `famille_*` (0–100 : `famille_carbone`, `famille_biodiversite`,
`famille_eau`, `famille_air`, `famille_sol`, `famille_paysage`,
`famille_temporel`, `famille_risque`, `famille_social`, `famille_production`,
`famille_energie`, `famille_naturalite`) ; les `indicateur_<code>_<slug>_norm`
(0–100) ; les `.<code>_status` qui expliquent une valeur manquante.

`label` est le nom affiché de l'unité de gestion (UGF). nemetonshiny crée
une UGF par parcelle et lui donne pour nom sa référence cadastrale : tant que
ce nom n'a pas été changé dans l'application, `label` vaut « UGF <n> »
(`label_par_defaut = true`, nom stocké dans `label_cadastre`) et `parcelles`
donne les parcelles en clair (« A 15, A 16 »). Dans la conversation, nommer
les unités comme les vues (« UGF 3, parcelle A 13 ») ; `detail_indicateur`
accepte `ug_id`, le nom stocké ou le nom affiché. Pour de vrais noms, les UGF
se regroupent et se renomment dans nemetonshiny (onglet Unités de gestion).

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

Les profils YAML de nemetonshiny (`inst/experts/`, plus les profils
utilisateur) restent la seule source : `profils_experts(langue)` les sert
(`cle`, `libelle`, `consigne`). L'Atlas et le Plan d'actions les proposent à
côté de « Demander à Claude » et placent la consigne du profil choisi en tête
de la demande. Dans la conversation, quand l'utilisateur annonce son point de
vue (« profil élu local »), lire sa consigne avec `profils_experts` et s'y
tenir.

## Rapport

Le PDF de `generer_rapport` reste la pièce officielle, signée et archivable.
Pour le travail collectif (synthèse commentée, plan d'actions discuté),
proposer en plus un document Claude, sans valeur officielle, qui renvoie au
PDF.

## Erreurs du connecteur

Les outils rendent `{"ok": false, "erreur", "classe", "candidats"}` :

| Classe | Réponse |
| --- | --- |
| `nemetonclaude_departement_ambigu`, `nemetonshiny_projet_ambigu` | proposer les `candidats` |
| `nemetonclaude_commune_introuvable` | vérifier l'orthographe avec l'utilisateur, ou demander une commune voisine |
| `nemetonshiny_parcelles_introuvables` | signaler les IDU manquants (copie incomplète, autre commune) |
| `nemetonshiny_sans_indicateurs` | proposer `lancer_calcul` |
| `nemetonshiny_projet_ancien` | le projet date d'avant nemetonshiny 1.0 : proposer de le recréer avec les mêmes parcelles |
| `nemetonshiny_calcul_en_cours`, `nemetonshiny_projet_verrouille` | attendre, ou suivre `etat_calcul` ; pour le plan d'actions : le projet est ouvert dans nemetonshiny, réessayer quand il sera fermé |
| `nemetonclaude_action_invalide` | relire le message (unité inconnue, type, année hors horizon) et corriger |
| `nemetonclaude_conflit` | montrer à l'utilisateur la version actuelle (`candidats`) avant de réécrire |
| `nemetonclaude_marculus_vide` | aucune action de martelage dans le plan : rien à exporter |

Connecteur distant : un outil d'écriture refusé (« réservé aux rôles … ») vient
du rôle Keycloak du compte, pas de nemeton ; le dire à l'utilisateur et
l'orienter vers l'administrateur du realm.
