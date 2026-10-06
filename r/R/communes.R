# Outil `chercher_commune(departement, nom)` : du nom que connait
# l'utilisateur au code INSEE qu'attend nemeton. Jamais de choix silencieux :
# homonymes, communes deleguees ou nom approchant rendent des candidats.

.GEO_API <- "https://geo.api.gouv.fr"

#' Resolve a department from its code or its name
#'
#' @param departement Code (`"21"`, `"2A"`, `"974"`) or name, accents and
#'   case ignored (`"Cote d'Or"`).
#' @return The department code. Error of class
#'   `nemetonclaude_departement_ambigu` (with `candidats`) or
#'   `nemetonclaude_departement_introuvable`.
#' @noRd
.resoudre_departement <- function(departement, liste = NULL) {
  d <- trimws(as.character(departement %||% ""))
  if (!nzchar(d)) .abort("Département non précisé.", "nemetonclaude_departement_introuvable")
  liste <- liste %||% .ns("get_departments")()
  codes <- unname(liste)
  if (toupper(d) %in% codes) return(toupper(d))
  if (grepl("^[0-9]$", d) && paste0("0", d) %in% codes) return(paste0("0", d))

  noms <- .normaliser(sub("^[0-9AB]+ - ", "", names(liste)))
  cible <- .normaliser(d)
  idx <- which(noms == cible)
  if (!length(idx)) idx <- which(grepl(cible, noms, fixed = TRUE))
  if (length(idx) == 1L) return(codes[idx])
  if (!length(idx)) {
    .abort("Aucun département ne correspond à {.val {d}}.",
           "nemetonclaude_departement_introuvable")
  }
  candidats <- names(liste)[idx]
  .abort(c("Plusieurs départements correspondent à {.val {d}}.", i = "{candidats}"),
         "nemetonclaude_departement_ambigu", candidats = candidats)
}

# Interroge geo.api.gouv.fr. Communes actuelles, deleguees et associees :
# l'utilisateur d'une commune nouvelle connait souvent l'ancien nom.
.requete_communes <- function(code_dep, nom, limite) {
  resp <- httr2::request(.GEO_API) |>
    httr2::req_url_path_append("communes") |>
    httr2::req_url_query(
      nom = nom, codeDepartement = code_dep,
      type = "commune-actuelle,commune-deleguee,commune-associee",
      fields = "nom,code,codesPostaux,population,type,chefLieu",
      boost = "population", limit = limite
    ) |>
    httr2::req_timeout(15) |>
    httr2::req_retry(max_tries = 3, backoff = ~ 2) |>
    httr2::req_perform()
  httr2::resp_body_json(resp)
}

# Reponse geo.api -> data.frame de candidats.
.candidats_communes <- function(brut) {
  if (!length(brut)) {
    return(data.frame(nom = character(), insee = character(), code_postal = character(),
                      type = character(), insee_cadastre = character(),
                      population = integer(), stringsAsFactors = FALSE))
  }
  val <- function(x, champ, defaut = NA_character_) {
    v <- x[[champ]]
    if (is.null(v) || !length(v)) defaut else as.character(v[[1]])
  }
  type <- vapply(brut, val, "", champ = "type", defaut = "commune-actuelle")
  code <- vapply(brut, val, "", champ = "code")
  chef <- vapply(brut, val, "", champ = "chefLieu")
  data.frame(
    nom = vapply(brut, val, "", champ = "nom"),
    insee = code,
    code_postal = vapply(brut, function(x) paste(unlist(x$codesPostaux), collapse = ", "), ""),
    type = type,
    # Le cadastre Etalab est publie par commune ACTUELLE : une commune
    # deleguee se cherche sous le code de sa commune nouvelle.
    insee_cadastre = ifelse(type == "commune-actuelle" | is.na(chef), code, chef),
    population = vapply(brut, function(x) as.integer(x$population %||% NA_integer_), 1L),
    stringsAsFactors = FALSE
  )
}

#' Decide between candidates, never silently
#'
#' @return `list(commune = <row or NULL>, choix_requis = logical)`. A commune
#'   is retained only when exactly one current commune carries exactly the
#'   requested name (accents, case, hyphens and « St » ignored) and no other
#'   candidate carries it.
#' @noRd
.choisir_commune <- function(cand, nom) {
  if (!nrow(cand)) return(list(commune = NULL, choix_requis = FALSE))
  exact <- which(.normaliser(cand$nom) == .normaliser(nom))
  if (length(exact) == 1L && cand$type[exact] == "commune-actuelle") {
    return(list(commune = as.list(cand[exact, , drop = FALSE]), choix_requis = FALSE))
  }
  list(commune = NULL, choix_requis = TRUE)
}

#' Find a commune's INSEE code
#'
#' @param departement Department code or name.
#' @param nom Commune name, as the user says it.
#' @param limite Maximum number of candidates.
#' @return JSON: `departement`, `commune` (when unambiguous), `choix_requis`,
#'   `candidats` (name, INSEE code, postcode, type, `insee_cadastre`).
#' @export
chercher_commune <- function(departement, nom, limite = 10) {
  .mcp_call({
    if (!is.character(nom) || !nzchar(trimws(nom))) {
      .abort("Nom de commune non précisé.", "nemetonclaude_commune_introuvable")
    }
    dep <- .resoudre_departement(departement)
    cand <- .candidats_communes(.requete_communes(dep, trimws(nom), as.integer(limite %||% 10)))
    if (!nrow(cand)) {
      .abort("Aucune commune {.val {nom}} dans le département {.val {dep}}.",
             "nemetonclaude_commune_introuvable")
    }
    choix <- .choisir_commune(cand, nom)
    list(departement = dep,
         commune = choix$commune,
         choix_requis = choix$choix_requis,
         candidats = cand,
         consigne = if (choix$choix_requis)
           "Proposer les candidats à l'utilisateur ; ne pas choisir à sa place.")
  })
}
