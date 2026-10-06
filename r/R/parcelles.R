# Outil `parcelles_commune(insee)` : les parcelles d'une commune pour la vue
# Selection. Source : cadastre Etalab en GeoJSON par commune (deja en WGS84),
# repli sur happign, tous deux via nemetonshiny::parcelles_commune().
#
# Les fichiers ecrits (parcelles, contour communal, limites de sections) sont
# joints tels quels a l'artefact : ils ne transitent pas par la conversation.

SEUIL_GEOJSON <- 5e6  # octets ; au-dela, la vue charge les sections une a une

# Colonnes utiles a la vue, renommees selon le contrat (IDU, section,
# numero, contenance en m2).
.parcelles_pour_vue <- function(p) {
  out <- sf::st_sf(
    idu = as.character(p$id),
    section = as.character(p$section),
    numero = as.character(p$numero),
    contenance = round(as.numeric(p$contenance)),
    geometry = sf::st_geometry(p)
  )
  out[order(out$section, suppressWarnings(as.integer(out$numero)), out$numero), ]
}

# Resume par section : nombre de parcelles et surface en hectares.
.resume_sections <- function(p) {
  if (!nrow(p)) return(data.frame(section = character(), n = integer(), surface_ha = numeric()))
  s <- split(p$contenance, p$section)
  data.frame(section = names(s),
             n = vapply(s, length, 1L),
             surface_ha = round(vapply(s, function(v) sum(v, na.rm = TRUE), 1) / 1e4, 2),
             row.names = NULL, stringsAsFactors = FALSE)
}

# Aide au reperage : parcelles dont le point interieur tombe dans la BD Foret.
# Au mieux : sans happign ou sans reseau, la propriete est simplement absente.
.marquer_foret <- function(p, crs_m) {
  if (!requireNamespace("happign", quietly = TRUE)) return(p)
  foret <- tryCatch({
    zone <- sf::st_as_sfc(sf::st_bbox(sf::st_transform(p, 2154)))
    happign::get_wfs(x = zone, layer = "LANDCOVER.FORESTINVENTORY.V2:formation_vegetale",
                     predicate = happign::intersects())
  }, error = function(e) {
    cli::cli_warn("BD For\u00eat indisponible : {conditionMessage(e)}")
    NULL
  })
  if (is.null(foret) || !nrow(foret)) return(p)
  pts <- sf::st_point_on_surface(sf::st_geometry(sf::st_transform(p, crs_m)))
  foret <- sf::st_union(sf::st_make_valid(sf::st_transform(sf::st_geometry(foret), crs_m)))
  p$foret <- as.integer(lengths(sf::st_intersects(pts, foret)) > 0)
  p
}

#' Cadastral parcels of a commune, ready for the Selection view
#'
#' @param insee INSEE code (5 characters). For a delegated commune, use the
#'   `insee_cadastre` returned by [chercher_commune()].
#' @param section Optional section code: only that section is written (the
#'   view loads a large commune section by section).
#' @param tolerance_m Simplification tolerance in metres (default 0.5).
#' @param foret Mark parcels covered by the BD Foret (best effort).
#' @param inclure_geojson Also return the GeoJSON inline when it stays under
#'   2 MB (for a view that calls the tool through the `mcp` capability).
#' @return JSON: counts, total area, bounding box, files to join to the
#'   artifact (`fichiers`), per-section summary and, past 5 MB, one file per
#'   section (`mode = "par_section"`).
#' @export
parcelles_commune_vue <- function(insee, section = NULL, tolerance_m = 0.5,
                                  foret = TRUE, inclure_geojson = FALSE) {
  .mcp_call({
    insee <- toupper(trimws(as.character(insee %||% "")))
    if (!grepl("^[0-9][0-9AB][0-9]{3}$", insee)) {
      .abort("Code INSEE invalide : {.val {insee}}.", "nemetonclaude_commune_introuvable")
    }
    crs_m <- .crs_metrique(insee)
    brut <- nemetonshiny::parcelles_commune(insee)
    p <- .parcelles_pour_vue(brut)
    sections <- .resume_sections(p)
    if (!is.null(section) && nzchar(section)) {
      section <- toupper(trimws(section))
      if (!section %in% p$section) {
        .abort("Section {.val {section}} absente de la commune {.val {insee}}.",
               "nemetonclaude_section_introuvable", candidats = sections$section)
      }
      p <- p[p$section == section, ]
    }
    if (isTRUE(foret)) p <- .marquer_foret(p, crs_m)
    p <- .simplifier_wgs84(p, tolerance_m, crs_m)

    dossier <- .dossier_vues("communes", insee)
    fichiers <- list()

    # Reperes : contour de commune et limites de sections (pas de tuiles).
    contour <- tryCatch(.ns("get_commune_geometry")(insee), error = function(e) NULL)
    if (!is.null(contour)) {
      contour <- .simplifier_wgs84(sf::st_sf(nom = contour$nom %||% NA_character_,
                                             geometry = sf::st_geometry(contour)), 2, crs_m)
      fichiers$commune <- .ecrire_geojson(contour, file.path(dossier, "commune.geojson"))
    }
    if (is.null(section)) {
      geom_m <- sf::st_geometry(sf::st_transform(p, crs_m))
      codes <- sort(unique(p$section))
      lim_geom <- do.call(c, lapply(codes, function(s) sf::st_union(geom_m[p$section == s])))
      lim <- .simplifier_wgs84(sf::st_sf(section = codes, geometry = lim_geom), 2, crs_m)
      fichiers$sections <- .ecrire_geojson(lim, file.path(dossier, "sections.geojson"))
    }

    nom_fichier <- if (is.null(section)) "parcelles.geojson" else sprintf("parcelles_%s.geojson", section)
    fichiers$parcelles <- .ecrire_geojson(p, file.path(dossier, nom_fichier))
    mode <- "complet"
    if (is.null(section) && .taille(fichiers$parcelles) > SEUIL_GEOJSON) {
      # Trop lourd pour une page : un fichier par section, la vue les charge
      # a la demande (clic sur une section).
      mode <- "par_section"
      unlink(fichiers$parcelles)
      fichiers$parcelles <- NULL
      dir.create(file.path(dossier, "sections"), showWarnings = FALSE)
      sections$fichier <- vapply(sections$section, function(s) {
        .ecrire_geojson(p[p$section == s, ], file.path(dossier, "sections", paste0(s, ".geojson")))
      }, "")
    }

    commune <- if (!is.null(brut$commune)) as.character(brut$commune[1]) else contour$nom %||% NULL
    # Metadonnees lues par la vue (selection.json) : pas de chemins locaux.
    meta <- list(
      insee = insee,
      commune = commune,
      departement = substr(insee, 1, if (substr(insee, 1, 2) == "97") 3 else 2),
      n = nrow(p),
      surface_ha = round(sum(p$contenance, na.rm = TRUE) / 1e4, 2),
      emprise = .emprise(p),
      mode = mode,
      bd_foret = "foret" %in% names(p),
      sections = sections[, c("section", "n", "surface_ha")],
      nom_projet = if (!is.null(commune)) paste("For\u00eat de", commune),
      source = "cadastre.data.gouv.fr (Etalab, DGFiP), repli happign"
    )
    fichiers$selection <- file.path(dossier, "selection.json")
    writeLines(.json(Filter(Negate(is.null), meta)), fichiers$selection, useBytes = TRUE)

    c(meta, list(
      dossier = dossier,
      fichiers = fichiers,
      taille_octets = if (!is.null(fichiers$parcelles)) .taille(fichiers$parcelles),
      sections_fichiers = if (mode == "par_section") sections$fichier,
      geojson = if (isTRUE(inclure_geojson)) .geojson_en_ligne(fichiers$parcelles)
    ))
  })
}
