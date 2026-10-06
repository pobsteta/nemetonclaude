# Outil `contexte_carto(projet)` : fond vectoriel leger, puisque les tuiles
# externes sont bloquees dans un artefact. Routes et hydrographie BD TOPO
# (IGN, via happign), decoupees a l'emprise du projet plus une marge.

COUCHES_CONTEXTE <- list(
  route     = list(couche = "BDTOPO_V3:troncon_de_route",       nom = "nom_1_gauche"),
  cours_eau = list(couche = "BDTOPO_V3:troncon_hydrographique", nom = "cpx_toponyme_de_cours_d_eau"),
  plan_eau  = list(couche = "BDTOPO_V3:surface_hydrographique", nom = "nom_1_gauche")
)

# Ne garde que les colonnes utiles : `couche`, `nature`, `importance`, `nom`.
.normaliser_contexte <- function(x, type, col_nom = NULL) {
  noms <- tolower(names(x))
  pick <- function(motif) {
    j <- which(noms == motif)
    if (length(j)) as.character(x[[j[1]]]) else rep(NA_character_, nrow(x))
  }
  sf::st_sf(
    couche = rep(type, nrow(x)),
    nature = pick("nature"),
    importance = pick("importance"),
    nom = if (is.null(col_nom)) NA_character_ else pick(col_nom),
    geometry = sf::st_geometry(x)
  )
}

#' Vector map context of a project (roads, rivers, water bodies)
#'
#' @param projet Project id or name.
#' @param marge_m Margin around the project, in metres.
#' @return JSON: `fichier` (`contexte.geojson`, property `couche` among
#'   `route`, `cours_eau`, `plan_eau`) and the state of each layer.
#' @export
contexte_carto <- function(projet, marge_m = 300) {
  .mcp_call({
    if (!requireNamespace("happign", quietly = TRUE)) {
      .abort("Le paquet {.pkg happign} est requis pour la BD TOPO.", "nemetonclaude_dependance_manquante")
    }
    id <- .resoudre_projet(projet)
    parcelles <- .ns("load_parcels")(id)
    if (is.null(parcelles) || !nrow(parcelles)) {
      .abort("Projet {.val {id}} sans parcelles.", "nemetonshiny_projet_introuvable")
    }
    crs_m <- .crs_metrique(as.character(parcelles$code_insee[1] %||% ""))
    zone <- sf::st_as_sfc(sf::st_bbox(sf::st_buffer(
      sf::st_union(sf::st_transform(parcelles, crs_m)), marge_m)))

    etats <- list()
    morceaux <- list()
    for (type in names(COUCHES_CONTEXTE)) {
      def <- COUCHES_CONTEXTE[[type]]
      x <- tryCatch(
        happign::get_wfs(x = sf::st_transform(zone, 2154), layer = def$couche,
                         spatial_filter = "intersects"),
        error = function(e) e)
      if (inherits(x, "error") || is.null(x)) {
        etats[[type]] <- list(ok = FALSE, erreur = if (inherits(x, "error")) conditionMessage(x) else "vide")
        next
      }
      if (!nrow(x)) { etats[[type]] <- list(ok = TRUE, n = 0L); next }
      x <- suppressWarnings(sf::st_intersection(sf::st_transform(x, crs_m), zone))
      x <- .normaliser_contexte(x, type, def$nom)
      morceaux[[type]] <- .simplifier_wgs84(x, 2, crs_m)
      etats[[type]] <- list(ok = TRUE, n = nrow(x))
    }
    fichier <- NULL
    if (length(morceaux)) {
      tout <- do.call(rbind, unname(morceaux))
      fichier <- .ecrire_geojson(tout, file.path(.dossier_vues("projets", id), "contexte.geojson"))
    }
    list(projet = id, fichier = fichier,
         taille_octets = if (!is.null(fichier)) .taille(fichier),
         couches = etats, source = "IGN BD TOPO (Géoplateforme, via happign)")
  })
}
