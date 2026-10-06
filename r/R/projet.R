# Outil `creer_projet(nom, insee, parcelles)` : appele par la vue Selection
# (bouton « Creer le projet », capacite `mcp`) ou par Claude a partir de la
# liste d'IDU copiee dans la conversation.

# Les IDU arrivent d'une vue (tableau JSON), d'une chaine collee dans la
# conversation (« 21661000AB0012, 21661000AB0013 ») ou d'un vecteur R.
.normaliser_idu <- function(parcelles) {
  x <- unlist(parcelles, use.names = FALSE)
  x <- unlist(strsplit(as.character(x), "[,;[:space:]]+"))
  x <- toupper(trimws(x))
  unique(x[nzchar(x)])
}

#' Create a project from the parcels picked in the Selection view
#'
#' @param nom Project name (100 characters max).
#' @param insee INSEE code of the commune (the `insee_cadastre` of
#'   [chercher_commune()]).
#' @param parcelles Parcel ids (IDU), as a vector or a comma separated string.
#' @param description Optional text.
#' @return JSON: `projet` (id), `nom`, `n_parcelles`, `surface_ha`, `suite`.
#'   Unknown ids: error of class `nemetonshiny_parcelles_introuvables`.
#' @export
creer_projet <- function(nom, insee, parcelles, description = "") {
  .mcp_call({
    nom <- trimws(as.character(nom %||% ""))
    if (!nzchar(nom)) .abort("Nom de projet non précisé.", "nemetonclaude_nom_manquant")
    if (nchar(nom) > 100) nom <- substr(nom, 1, 100)
    ids <- .normaliser_idu(parcelles)
    if (!length(ids)) .abort("Aucune parcelle sélectionnée.", "nemetonclaude_selection_vide")
    insee <- toupper(trimws(as.character(insee)))

    p <- nemetonshiny::parcelles_commune(insee, ids = ids)
    id <- nemetonshiny::projet_creer(nom, p, description = description %||% "")
    # Contour communal : repere des vues, comme dans l'application.
    tryCatch({
      g <- .ns("get_commune_geometry")(insee)
      if (!is.null(g)) .ns("save_commune_geometry")(id, g)
    }, error = function(e) NULL)

    list(projet = id, nom = nom, insee = insee, n_parcelles = nrow(p),
         surface_ha = round(sum(as.numeric(p$contenance), na.rm = TRUE) / 1e4, 2),
         suite = "lancer_calcul")
  })
}

# Resolution d'un projet par id ou nom approche : celle du serveur MCP de
# nemetonshiny (homonymes -> candidats, jamais de choix silencieux).
.resoudre_projet <- function(projet) .ns(".mcp_resolve_project")(projet)

# projet_lire() reconstruit tout le projet ; la vue Atlas et
# detail_indicateur l'appellent coup sur coup. Cache memoire par projet,
# invalide des que les indicateurs changent sur disque.
.cache_lecture <- new.env(parent = emptyenv())

.lire_projet <- function(id, langue = "fr") {
  chemin <- .ns("get_project_path")(id)
  ind <- file.path(chemin %||% "", "data", "indicators.parquet")
  cle <- paste(id, langue, if (file.exists(ind)) as.numeric(file.mtime(ind)) else 0, sep = "|")
  if (!is.null(.cache_lecture[[cle]])) return(.cache_lecture[[cle]])
  for (k in grep(paste0("^", id, "\\|"), ls(.cache_lecture), value = TRUE)) rm(list = k, envir = .cache_lecture)
  lu <- nemetonshiny::projet_lire(id, langue = langue)
  .cache_lecture[[cle]] <- lu
  lu
}
