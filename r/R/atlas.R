# Outils `vue_atlas(projet)` et `detail_indicateur(projet, ug, code)` :
# donnees de la vue Atlas (remplace Synthese + 12 Familles).
#
# Contrat (specs/BRIEF-visualisation-nemeton-claude.md, « Contrat de donnees
# de l'Atlas ») : un FeatureCollection WGS84, une entite par UGF, avec en
# membre etranger `nemeton` l'en-tete du projet et le catalogue des familles.

.arrondir <- function(x, n = 1) {
  x <- suppressWarnings(as.numeric(x))
  x[!is.finite(x)] <- NA_real_
  round(x, n)
}

# Catalogue des 12 familles et de leurs sous-indicateurs, lu du coeur via
# nemetonshiny (libelles et aides FR/EN). Il voyage avec les donnees : la vue
# n'a aucune liste d'indicateurs codee en dur.
.catalogue_familles <- function() {
  fams <- .ns("INDICATOR_FAMILIES")
  lapply(unname(fams), function(f) {
    ind <- lapply(seq_along(f$indicators), function(i) {
      code <- f$indicators[i]
      col <- f$column_names[i]
      lab <- f$indicator_labels[[code]] %||% list()
      aide <- f$indicator_tooltips[[code]] %||% list()
      list(code = code, colonne = col, colonne_norm = paste0(col, "_norm"),
           statut = paste0(".", tolower(code), "_status"),
           label_fr = lab$fr %||% code, label_en = lab$en %||% code,
           aide_fr = aide$fr %||% NULL, aide_en = aide$en %||% NULL)
    })
    list(code = f$code, colonne = nemeton::get_famille_col(f$code),
         nom_fr = f$name_fr, nom_en = f$name_en, couleur = f$color,
         indicateurs = ind)
  })
}

#' Properties of the Atlas features (pure function, tested)
#'
#' @param df data.frame without geometry, one row per management unit.
#' @param bruts Also keep raw indicator values.
#' @return data.frame: `ug_id`, `label`, `groupe`, `surface_ha`, the
#'   `famille_*` indices, the `indicateur_*_norm` scores, the `.<code>_status`
#'   columns (and raw `indicateur_*` when `bruts`).
#' @noRd
.proprietes_atlas <- function(df, bruts = FALSE) {
  n <- nrow(df)
  col <- function(noms, defaut = rep(NA_character_, n)) {
    for (x in noms) if (x %in% names(df)) return(df[[x]])
    defaut
  }
  ug_id <- as.character(col(c("ug_id", "ugf_id", "id"), as.character(seq_len(n))))
  surface <- col(c("surface_m2", "surface_sig_m2"), NULL)
  out <- data.frame(
    ug_id = ug_id,
    label = as.character(col(c("label", "nom"), ug_id)),
    groupe = as.character(col(c("groupe", "group"))),
    surface_ha = if (is.null(surface)) NA_real_ else .arrondir(as.numeric(surface) / 1e4, 2),
    stringsAsFactors = FALSE
  )
  fam <- grep("^famille_", names(df), value = TRUE)
  norm <- grep("^indicateur_.*_norm$", names(df), value = TRUE)
  statut <- grep("^\\.[a-z][0-9]+_status$", names(df), value = TRUE)
  for (x in fam) out[[x]] <- .arrondir(df[[x]], 1)
  for (x in norm) out[[x]] <- .arrondir(df[[x]], 1)
  for (x in statut) out[[x]] <- as.character(df[[x]])
  if (isTRUE(bruts)) {
    for (x in setdiff(grep("^indicateur_", names(df), value = TRUE), norm)) {
      out[[x]] <- signif(suppressWarnings(as.numeric(df[[x]])), 4)
    }
  }
  out
}

.entete_atlas <- function(id, s, langue) {
  list(
    project_id = id,
    name = s$name,
    global_score = .arrondir(s$global_score, 1),
    ndp_level = s$ndp_level,
    ndp_name = s$ndp_name,
    confidence = s$confidence,
    updated_at = s$updated_at,
    langue = langue,
    n_ugf = s$n_ugf,
    n_parcelles = s$n_parcels,
    familles = if (!is.null(s$families)) lapply(seq_len(nrow(s$families)), function(i) {
      list(code = s$families$code[i], nom = s$families$famille[i],
           score = .arrondir(s$families$score[i], 1))
    }),
    genere_a = .maintenant()
  )
}

#' Data of the Atlas view
#'
#' @param projet Project id or name.
#' @param langue `"fr"` or `"en"`.
#' @param tolerance_m Simplification tolerance in metres (raised by itself,
#'   up to three times, while the file exceeds 5 MB).
#' @param bruts Also include raw indicator values (heavier).
#' @return JSON: project header, `fichier` (GeoJSON to join to the artifact
#'   as `atlas.geojson`), size and bounding box.
#' @export
vue_atlas <- function(projet, langue = "fr", tolerance_m = 1, bruts = FALSE,
                      inclure_geojson = FALSE) {
  .mcp_call({
    id <- .resoudre_projet(projet)
    langue <- if (identical(langue, "en")) "en" else "fr"
    lu <- .lire_projet(id, langue)
    if (is.null(lu$familles) || !nrow(lu$familles)) {
      .abort(c("Projet {.val {id}} : aucun indicateur calculé.",
               i = "Lancer {.code lancer_calcul} puis suivre {.code etat_calcul}."),
             "nemetonshiny_sans_indicateurs")
    }
    fam <- lu$familles
    props <- .proprietes_atlas(sf::st_drop_geometry(fam), bruts = bruts)
    x <- sf::st_sf(props, geometry = sf::st_geometry(fam))
    insee <- tryCatch(as.character(lu$projet$parcels$code_insee[1]), error = function(e) NA)
    crs_m <- .crs_metrique(if (is.na(insee)) "" else insee)

    entete <- c(.entete_atlas(id, lu$synthese, langue),
                list(catalogue = .catalogue_familles()))
    fichier <- file.path(.dossier_vues("projets", id), "atlas.geojson")
    tol <- tolerance_m
    for (essai in 1:4) {
      .ecrire_geojson(.simplifier_wgs84(x, tol, crs_m), fichier)
      .ajouter_entete(fichier, entete)
      if (.taille(fichier) <= SEUIL_GEOJSON) break
      tol <- tol * 3
    }
    entete$catalogue <- NULL
    c(entete, list(
      fichier = normalizePath(fichier),
      taille_octets = .taille(fichier),
      tolerance_m = tol,
      emprise = .emprise(x),
      geojson = if (isTRUE(inclure_geojson)) .geojson_en_ligne(fichier)
    ))
  })
}

#' Detail of one sub-indicator for one management unit
#'
#' @param projet Project id or name.
#' @param ug Management unit id (`ug_id`) or label.
#' @param code Indicator code (`"B1"`, `"a5"`...).
#' @return JSON: raw value, 0-100 score, status (reason of a missing value),
#'   label, help text, family.
#' @export
detail_indicateur <- function(projet, ug, code, langue = "fr") {
  .mcp_call({
    id <- .resoudre_projet(projet)
    langue <- if (identical(langue, "en")) "en" else "fr"
    lu <- .lire_projet(id, langue)
    df <- lu$familles %||% lu$indicateurs
    if (is.null(df)) .abort("Projet {.val {id}} : aucun indicateur calculé.", "nemetonshiny_sans_indicateurs")
    df <- sf::st_drop_geometry(df)
    ligne <- which(as.character(df$ug_id) == as.character(ug))
    if (!length(ligne) && "label" %in% names(df)) ligne <- which(df$label == ug)
    if (length(ligne) != 1L) {
      .abort("Unité de gestion {.val {ug}} introuvable.", "nemetonclaude_ug_introuvable",
             candidats = utils::head(as.character(df$ug_id), 20))
    }
    code <- tolower(trimws(code))
    cat_ <- .catalogue_familles()
    ref <- NULL
    for (f in cat_) for (i in f$indicateurs) if (tolower(i$code) == code) ref <- c(i, list(famille = f$code))
    if (is.null(ref)) {
      .abort("Indicateur {.val {code}} inconnu.", "nemetonclaude_indicateur_inconnu",
             candidats = unlist(lapply(cat_, function(f) vapply(f$indicateurs, `[[`, "", "code"))))
    }
    val <- function(col) if (col %in% names(df)) df[[col]][ligne] else NA
    brut <- suppressWarnings(as.numeric(val(ref$colonne)))
    note <- .arrondir(val(ref$colonne_norm), 1)
    statut <- val(ref$statut)
    list(
      projet = id, ug = as.character(df$ug_id[ligne]), code = toupper(code),
      famille = ref$famille, colonne = ref$colonne,
      libelle = if (langue == "fr") ref$label_fr else ref$label_en,
      aide = if (langue == "fr") ref$aide_fr else ref$aide_en,
      valeur_brute = if (is.na(brut)) NULL else signif(brut, 4),
      note = if (is.na(note)) NULL else note,
      statut = if (is.na(statut)) NULL else as.character(statut),
      manquant = is.na(note),
      source = "nemeton (coeur R), normalisation par indicateur (normalize_indicator)"
    )
  })
}
