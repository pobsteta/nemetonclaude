# Utilitaires communs aux outils MCP de nemetonclaude.
#
# Meme convention de reponse que le serveur MCP de nemetonshiny
# (R/service_mcp.R) : une chaine JSON courte, `{"ok":true,...}` ou
# `{"ok":false,"erreur","classe","candidats"}`. stdout est le canal du
# protocole MCP (stdio) : rien n'y est ecrit ici, les messages partent sur
# stderr via cli.

`%||%` <- function(x, y) if (is.null(x)) y else x

.json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
                                na = "null", digits = NA))
}

# Evalue `expr` ; une erreur devient une reponse `ok = false` lisible par le
# modele (message + classe + candidats eventuels), jamais une exception de
# protocole.
.mcp_call <- function(expr) {
  res <- tryCatch(expr, error = function(e) {
    cls <- grep("^(nemetonshiny|nemetonclaude)_", class(e), value = TRUE)
    structure(list(ok = FALSE, erreur = conditionMessage(e),
                   classe = if (length(cls)) cls[1] else NULL,
                   candidats = e$candidats),
              class = "mcp_erreur")
  })
  if (inherits(res, "mcp_erreur")) res <- unclass(res)
  else res <- c(list(ok = TRUE), res)
  .json(Filter(Negate(is.null), res))
}

.abort <- function(message, class, ...) {
  cli::cli_abort(message, class = c(class, "nemetonclaude_erreur"), ...,
                 call = NULL, .envir = parent.frame())
}

# Fonction interne de nemetonshiny. Un seul point d'acces, pour que la
# dependance aux internes reste visible et facile a remplacer le jour ou
# nemetonshiny les exporte.
.ns <- function(nom) utils::getFromNamespace(nom, "nemetonshiny")

# Minuscules, sans accents ni ponctuation ; « St » et « Ste » developpes.
# Table explicite plutot qu'iconv(ASCII//TRANSLIT), qui depend de la locale
# (un serveur MCP lance en locale C perdrait les lettres accentuees).
.ACCENTS <- c(
  de = "\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e7\u00e8\u00e9\u00ea\u00eb\u00ec\u00ed\u00ee\u00ef\u00f1\u00f2\u00f3\u00f4\u00f5\u00f6\u00f9\u00fa\u00fb\u00fc\u00fd\u00ff",
  vers = "aaaaaaceeeeiiiinooooouuuuyy"
)

.normaliser <- function(x) {
  x <- tolower(enc2utf8(as.character(x)))
  x <- chartr(.ACCENTS[["de"]], .ACCENTS[["vers"]], x)
  x <- gsub("\u0153", "oe", gsub("\u00e6", "ae", x))
  x <- gsub("[^a-z0-9]+", " ", x)
  x <- gsub("\\bste\\b", "sainte", x)
  x <- gsub("\\bst\\b", "saint", x)
  trimws(gsub(" +", " ", x))
}

# Dossier ou sont ecrits les fichiers des vues (GeoJSON a joindre a un
# artefact). `NEMETON_CLAUDE_VUES_DIR` l'emporte sur le cache utilisateur.
.dossier_vues <- function(...) {
  racine <- Sys.getenv("NEMETON_CLAUDE_VUES_DIR", "")
  if (!nzchar(racine)) racine <- file.path(tools::R_user_dir("nemetonclaude", "cache"), "vues")
  d <- file.path(racine, ...)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  normalizePath(d, mustWork = TRUE)
}

# Systeme metrique adapte a la commune, pour simplifier et mesurer en metres.
.crs_metrique <- function(insee) {
  dep <- substr(as.character(insee), 1, 3)
  switch(dep,
         "971" = 5490, "972" = 5490,  # RGAF09 / UTM 20N
         "973" = 2972,                # RGFG95 / UTM 22N
         "974" = 2975,                # RGR92 / UTM 40S
         "976" = 4471,                # RGM04 / UTM 38S
         2154)                        # RGF93 / Lambert-93
}

# Simplifie en metres puis repasse en WGS84 (RFC 7946).
.simplifier_wgs84 <- function(x, tolerance_m, crs_m = 2154) {
  x <- sf::st_transform(x, crs_m)
  if (tolerance_m > 0) {
    x <- sf::st_simplify(x, preserveTopology = TRUE, dTolerance = tolerance_m)
    x <- x[!sf::st_is_empty(x), ]
  }
  sf::st_transform(x, 4326)
}

# Ecrit un GeoJSON WGS84 compact (6 decimales, ~10 cm) et rend son chemin.
.ecrire_geojson <- function(x, fichier, precision = 6L) {
  if (file.exists(fichier)) unlink(fichier)
  sf::st_write(x, fichier, driver = "GeoJSON", quiet = TRUE,
               layer_options = c(sprintf("COORDINATE_PRECISION=%d", precision),
                                 "RFC7946=YES", "WRITE_NAME=NO"))
  normalizePath(fichier)
}

# Ajoute un membre etranger (RFC 7946, 6.1) en tete d'un FeatureCollection :
# `{"type":"FeatureCollection","nemeton":{...},"features":[...]}`.
.ajouter_entete <- function(fichier, entete, membre = "nemeton") {
  gj <- jsonlite::read_json(fichier, simplifyVector = FALSE)
  out <- list(type = "FeatureCollection")
  out[[membre]] <- entete
  out$features <- gj$features
  writeLines(.json(out), fichier, useBytes = TRUE)
  invisible(fichier)
}

.emprise <- function(x) {
  b <- sf::st_bbox(sf::st_transform(x, 4326))
  round(unname(as.numeric(b)), 6)
}

.taille <- function(fichier) unname(file.size(fichier))

# Lit un GeoJSON pour l'inclure tel quel dans une reponse MCP (appel depuis
# une vue par la capacite `mcp`), seulement s'il reste leger.
.geojson_en_ligne <- function(fichier, plafond = 2e6) {
  if (is.null(fichier) || !file.exists(fichier) || .taille(fichier) > plafond) return(NULL)
  jsonlite::read_json(fichier, simplifyVector = FALSE)
}

.maintenant <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
