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

  existants <- .ns("mcp_tools")()
  nouveaux <- list(
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
      lecture = TRUE)
  )
  c(existants, nouveaux)
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
