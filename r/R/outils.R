# Declaration des outils MCP : les 8 outils de nemetonshiny, inchanges, plus
# ceux du lot 1. On etend le serveur existant au lieu d'en ecrire un autre.

.lecture_seule <- function() {
  ann <- tryCatch(utils::getFromNamespace("tool_annotations", "ellmer"), error = function(e) NULL)
  if (is.null(ann)) NULL else ann(read_only_hint = TRUE)
}

.outil <- function(fun, name, description, arguments, lecture = FALSE) {
  args <- list(fun, name = name, description = description, arguments = arguments)
  if (lecture && !is.null(a <- .lecture_seule())) args$annotations <- a
  do.call(ellmer::tool, args)
}

#' MCP tools of nemetonclaude
#'
#' @return A list of `ellmer::tool()` definitions: the tools of nemetonshiny
#'   (`lister_projets`, `resume_projet`, `lancer_calcul`, `etat_calcul`,
#'   `annuler_calcul`, `generer_rapport`, `exporter_gpkg`, `url_app`) and the
#'   lot 1 tools (`chercher_commune`, `parcelles_commune`, `creer_projet`,
#'   `vue_atlas`, `contexte_carto`, `detail_indicateur`).
#' @export
outils_mcp <- function() {
  t <- ellmer::type_string
  b <- ellmer::type_boolean
  num <- ellmer::type_number
  projet_arg <- t("Project id, or its name (case and accents ignored).")
  langue_arg <- t("'fr' or 'en' (default 'fr').", required = FALSE)

  # Outils de lecture de nemetonshiny annotes « lecture seule » : la vue
  # Calcul peut suivre etat_calcul (watchTool) sans confirmation a chaque
  # interrogation dans l'application Claude.
  # etat_calcul est remplace par etat_calcul_vue (memes entrees, durees en
  # plus), declare plus bas.
  existants <- lapply(.ns("mcp_tools")(), function(o) {
    a <- .lecture_seule()
    if (o@name %in% c("lister_projets", "resume_projet", "url_app") && !is.null(a)) {
      o@annotations <- a
    }
    o
  })
  existants <- Filter(function(o) !o@name %in% c("etat_calcul", "exporter_gpkg"), existants)
  nouveaux <- list(
    .outil(etat_calcul_vue, "etat_calcul",
      "State of a project's background computation: status (lancement, en_cours, termine, echec, annule, aucun), progress, indicators done and total, current task, elapsed seconds (ecoule_s, computed by the server), error and log tail on failure.",
      list(projet = projet_arg),
      lecture = TRUE),
    .outil(exporter_gpkg_vue, "exporter_gpkg",
      "Write the GeoPackage of a computed project's results (one feature per management unit) and return the file path. With zip = true, also return the GeoPackage zipped and base64 encoded (zip_base64, zip_nom, zip_taille) so a view can offer it as a download; above 15 MB only zip_trop_gros is set.",
      list(projet = projet_arg,
           zip = b("Also return the zipped GeoPackage inline (default false).", required = FALSE))),
    .outil(chercher_commune, "chercher_commune",
      "Find the INSEE code of a French commune from its department (code or name) and its name. Several matches (homonyms, delegated communes): returns candidates with choix_requis = true; ask the user, never pick for them. Use insee_cadastre for the cadastre.",
      list(departement = t("Department code ('21', '2A', '974') or name ('Cote-d'Or')."),
           nom = t("Commune name as the user says it."),
           limite = ellmer::type_integer("Maximum number of candidates (default 10).", required = FALSE)),
      lecture = TRUE),
    .outil(parcelles_commune_vue, "parcelles_commune",
      "Cadastral parcels of a commune (Etalab cadastre, WGS84) written as GeoJSON files for the Selection view: parcels (idu, section, numero, contenance in m2, foret), commune outline, section limits. Returns counts, area, bbox and file paths to join to the artifact; above 5 MB, one file per section (mode par_section).",
      list(insee = t("INSEE code (5 characters); insee_cadastre of chercher_commune."),
           section = t("Only this cadastral section (large communes).", required = FALSE),
           tolerance_m = num("Simplification tolerance in metres (default 0.5).", required = FALSE),
           foret = b("Mark parcels covered by the BD Foret (default true).", required = FALSE),
           inclure_geojson = b("Also return the GeoJSON inline when under 2 MB (default false).", required = FALSE)),
      lecture = TRUE),
    .outil(creer_projet, "creer_projet",
      "Create a Nemeton project from the parcels the user picked (IDU list) in a commune. Returns the project id; then call lancer_calcul.",
      list(nom = t("Project name."),
           insee = t("INSEE code of the commune (insee_cadastre)."),
           parcelles = ellmer::type_array(t("Parcel id (IDU, 14 characters)."), description = "Parcel ids (IDU)."),
           description = t("Optional description.", required = FALSE))),
    .outil(vue_atlas, "vue_atlas",
      "Data of the Atlas view of a computed project: GeoJSON file (one feature per management unit, 12 famille_* indices, indicateur_*_norm scores, .<code>_status) with a 'nemeton' header (project, global score, NDP, confidence, family catalogue). Join the file to the artifact as atlas.geojson.",
      list(projet = projet_arg, langue = langue_arg,
           tolerance_m = num("Simplification tolerance in metres (default 1).", required = FALSE),
           bruts = b("Also include raw indicator values (default false).", required = FALSE),
           inclure_geojson = b("Also return the GeoJSON inline when under 2 MB (default false).", required = FALSE)),
      lecture = TRUE),
    .outil(contexte_carto, "contexte_carto",
      "Vector map context of a project (BD TOPO roads, rivers, water bodies) clipped to the project, as contexte.geojson to join to the artifact (external tiles are blocked in artifacts).",
      list(projet = projet_arg,
           marge_m = num("Margin around the project in metres (default 300).", required = FALSE)),
      lecture = TRUE),
    .outil(detail_indicateur, "detail_indicateur",
      "Detail of one sub-indicator for one management unit: raw value, 0-100 score, status explaining a missing value, label, help text, family.",
      list(projet = projet_arg,
           ug = t("Management unit id (ug_id) or label."),
           code = t("Indicator code, e.g. 'B1', 'A5'."),
           langue = langue_arg),
      lecture = TRUE),
    .outil(plan_actions, "plan_actions",
      "Action plan of a project (the one nemetonshiny edits): actions with calendar year (annee), unit label, status, priority, quantities, origin; recent history; allowed types, statuses, priorities and transitions; peut_ecrire for this account. Writes plan.geojson (management units with family scores) for the Plan view.",
      list(projet = projet_arg, langue = langue_arg,
           geojson = b("Also write plan.geojson (default true; false for a quick refresh).", required = FALSE),
           historique = ellmer::type_integer("Number of recent history entries (default 300).", required = FALSE),
           inclure_geojson = b("Also return the GeoJSON inline when under 2 MB (default false).", required = FALSE)),
      lecture = TRUE),
    .outil(ajouter_action, "ajouter_action",
      "Add an action to a project's plan. Default status 'proposee': a suggestion by Claude must carry source = {origine: 'claude'} and stay 'proposee' until a person validates it. Unknown unit, type or out-of-horizon year: error nemetonclaude_action_invalide.",
      list(projet = projet_arg, action = .type_action(required = TRUE))),
    .outil(modifier_action, "modifier_action",
      "Change fields of one action (status, year, priority, quantities, comment...). Pass attendu = the action's version as last read (plan_actions): if someone changed it since, nothing is written and the error nemetonclaude_conflit carries the current action.",
      list(projet = projet_arg,
           action_id = t("Action id (act_...)."),
           modifications = .type_action(required = TRUE),
           attendu = t("version of the action as last read (plan_actions).", required = FALSE))),
    .outil(supprimer_action, "supprimer_action",
      "Remove one action from a project's plan (kept in the plan's history). Prefer status 'abandonnee' to keep a trace on the board.",
      list(projet = projet_arg, action_id = t("Action id (act_...)."))),
    .outil(profils_experts, "profils_experts",
      "Expert profiles (forest manager, local elected official, owner, naturalist...): key, label and the instructions that set the point of view of an answer.",
      list(langue = langue_arg),
      lecture = TRUE),
    .outil(exporter_marculus, "exporter_marculus",
      "Write the Marculus field bundle of a project (zip: one GeoPackage per marking action - thinning, clear-cut, respacing, observation - and the .marsync of their contexts) into its exports folder. The plan is not changed.",
      list(projet = projet_arg))
  )
  c(existants, nouveaux)
}

# Schema d'une action du plan, pour ajouter_action et modifier_action : tous
# les champs sont facultatifs dans une modification.
.type_action <- function(required = TRUE) {
  t <- ellmer::type_string
  n <- ellmer::type_number
  ellmer::type_object(
    "Action fields (as in nemetonshiny's action plan).",
    ug_id = t("Management unit id.", required = FALSE),
    type = t("coupe_rase, eclaircie, depressage, plantation, regeneration, cloisonnement, desserte, observation, protection, entretien or autre.", required = FALSE),
    type_libre = t("Free label when type is 'autre'.", required = FALSE),
    intensite = t("e.g. faible, moderee, forte.", required = FALSE),
    annee = ellmer::type_integer("Calendar year (e.g. 2028).", required = FALSE),
    duree = ellmer::type_integer("Duration in years.", required = FALSE),
    priorite = t("haute, moyenne or basse.", required = FALSE),
    statut = t("proposee, validee, planifiee, realisee or abandonnee.", required = FALSE),
    objectifs_lies = ellmer::type_array(t("Family code: C, B, W, A, F, L, T, R, S, P, E, N."), "Families the action serves.", required = FALSE),
    quantite = ellmer::type_object("Quantities.",
      volume_m3 = n("Volume (m3).", required = FALSE), surface_ha = n("Area (ha).", required = FALSE),
      nb_tiges = ellmer::type_integer("Stems.", required = FALSE), rdi = n("RDI.", required = FALSE),
      cout_eur = n("Cost (EUR).", required = FALSE), revenu_eur = n("Revenue (EUR).", required = FALSE),
      .required = FALSE),
    source = ellmer::type_object("Origin of the action.",
      origine = t("'claude' for a suggestion by Claude, 'vue' when typed in a view.", required = FALSE),
      extrait_texte = t("Short justification.", required = FALSE),
      .required = FALSE),
    commentaire = t("Short note.", required = FALSE),
    .required = required)
}

#' Run the MCP server (stdio)
#'
#' Tools run in this process (`session_tools = FALSE`), as in
#' nemetonshiny's `inst/mcp/server.R`.
#' @export
serveur_mcp <- function() {
  if (!requireNamespace("mcptools", quietly = TRUE)) {
    stop("Le paquet 'mcptools' est requis : install.packages(\"mcptools\").", call. = FALSE)
  }
  mcptools::mcp_server(tools = outils_mcp(), session_tools = FALSE)
}

#' State of a project's computation, for the Calcul view
#'
#' nemetonshiny's `etat_calcul`, plus `ecoule_s` (seconds since launch, or
#' launch to end once finished) and `maintenant`. Launch and end times are
#' local server times without time zone: the view cannot read them, so the
#' server computes the duration.
#'
#' @param projet Project id or name.
#' @return JSON, as nemetonshiny's `etat_calcul`.
#' @export
etat_calcul_vue <- function(projet) {
  texte <- .ns("mcp_etat_calcul")(projet)
  x <- tryCatch(jsonlite::fromJSON(texte, simplifyVector = FALSE), error = function(e) NULL)
  if (!isTRUE(x$ok)) return(texte)
  .json(c(x, .durees_calcul(x)))
}

# exporter_gpkg de nemetonshiny, plus le GeoPackage zippe en base64 a la
# demande : les vues ne peuvent ni lire un chemin du serveur ni proposer
# un .gpkg au telechargement (le .zip est accepte).
.ZIP_MAX_OCTETS <- 15 * 1024^2

exporter_gpkg_vue <- function(projet, zip = FALSE) {
  texte <- .ns("mcp_exporter_gpkg")(projet)
  x <- tryCatch(jsonlite::fromJSON(texte, simplifyVector = FALSE), error = function(e) NULL)
  if (!isTRUE(x$ok) || !isTRUE(zip)) return(texte)
  .json(c(x, .zip_base64(x$fichier)))
}

.zip_base64 <- function(fichier, max_octets = .ZIP_MAX_OCTETS) {
  nom <- paste0(tools::file_path_sans_ext(basename(fichier)), ".zip")
  archive <- file.path(tempfile("gpkg"), nom)
  dir.create(dirname(archive))
  on.exit(unlink(dirname(archive), recursive = TRUE), add = TRUE)
  zip::zip(archive, fichier, mode = "cherry-pick")
  taille <- file.size(archive)
  if (taille > max_octets) return(list(zip_nom = nom, zip_taille = taille, zip_trop_gros = TRUE))
  list(zip_nom = nom, zip_taille = taille,
       zip_base64 = openssl::base64_encode(readBin(archive, "raw", taille), linebreaks = FALSE))
}

.durees_calcul <- function(x, maintenant = Sys.time()) {
  lire <- function(s) {
    if (is.null(s)) return(NA)
    suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S"))
  }
  debut <- lire(x$lance_a)
  fin <- lire(x$fin_a)
  ecoule <- if (is.na(debut)) NULL else max(0, round(as.numeric(difftime(
    if (is.na(fin)) maintenant else fin, debut, units = "secs"))))
  list(ecoule_s = ecoule, maintenant = format(maintenant, "%Y-%m-%dT%H:%M:%S%z"))
}
