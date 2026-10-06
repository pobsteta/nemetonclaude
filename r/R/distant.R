# Connecteur distant (lot 2) : le meme serveur MCP, servi en HTTP
# (Streamable HTTP) derriere une authentification OAuth 2.1 deleguee a
# Keycloak, pour qu'une vue partagee sur claude.ai puisse appeler nemeton
# avec les droits de son lecteur (capacite `mcp`, connecteur claude.ai).
#
# Le serveur est une ressource protegee au sens de la specification MCP
# (autorisation, RFC 9728) : il publie ses metadonnees, refuse toute requete
# sans jeton d'acces valide (401 + WWW-Authenticate) et laisse Keycloak
# delivrer les jetons. Il ne connait aucun mot de passe.
#
# Le protocole MCP lui-meme reste celui de mcptools : une requete autorisee
# lui est passee telle quelle. Les fichiers ecrits par les outils (GeoJSON
# des vues, rapport PDF, GeoPackage) sont servis par des liens signes et
# temporaires, ajoutes a la reponse sous `urls`.

# ---------------------------------------------------------------- configuration

.liste_env <- function(nom, defaut) {
  x <- Sys.getenv(nom, defaut)
  x <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
  x[nzchar(x)]
}

#' Configuration of the remote connector
#'
#' Read from environment variables, each one overridable by an argument.
#'
#' @param url Public base URL of the server, as Claude reaches it
#'   (`NEMETON_CLAUDE_URL`, e.g. `https://nemeton.example.org`). The MCP
#'   endpoint is `<url>/mcp`.
#' @param issuer Keycloak realm URL (`NEMETON_KEYCLOAK_URL`, the same
#'   variable as nemetonshiny, e.g. `https://auth.example.org/realms/nemeton`).
#' @param audience Expected `aud` of access tokens
#'   (`NEMETON_CLAUDE_AUDIENCE`, default `nemeton-claude`).
#' @param roles_lecture,roles_ecriture Keycloak realm roles allowed to read
#'   (list projects, open views) and to write (create a project, start a
#'   computation, write an export). `NEMETON_CLAUDE_ROLES_LECTURE`
#'   (default `lecteur,gestionnaire,admin`) and `NEMETON_CLAUDE_ROLES_ECRITURE`
#'   (default `gestionnaire,admin`).
#' @param isolation `"collectif"` (default): every user of the instance sees
#'   the same projects, as in nemetonshiny. `"utilisateur"`: each user has
#'   their own project folder under the root (`NEMETON_CLAUDE_ISOLATION`).
#' @param secret Key signing download links (`NEMETON_CLAUDE_SECRET`). Without
#'   it, a random key is drawn at start-up and links die with the process.
#' @param duree_lien Lifetime of a download link in seconds (default 3600).
#' @return A list.
#' @export
config_distant <- function(url = Sys.getenv("NEMETON_CLAUDE_URL"),
                           issuer = Sys.getenv("NEMETON_KEYCLOAK_URL"),
                           audience = Sys.getenv("NEMETON_CLAUDE_AUDIENCE", "nemeton-claude"),
                           roles_lecture = .liste_env("NEMETON_CLAUDE_ROLES_LECTURE", "lecteur,gestionnaire,admin"),
                           roles_ecriture = .liste_env("NEMETON_CLAUDE_ROLES_ECRITURE", "gestionnaire,admin"),
                           isolation = Sys.getenv("NEMETON_CLAUDE_ISOLATION", "collectif"),
                           secret = Sys.getenv("NEMETON_CLAUDE_SECRET"),
                           duree_lien = 3600) {
  url <- sub("/+$", "", url)
  issuer <- sub("/+$", "", issuer)
  if (!nzchar(url)) .abort("NEMETON_CLAUDE_URL manquante (URL publique du serveur).", "nemetonclaude_config")
  if (!nzchar(issuer)) .abort("NEMETON_KEYCLOAK_URL manquante (URL du realm Keycloak).", "nemetonclaude_config")
  isolation <- match.arg(isolation, c("collectif", "utilisateur"))
  if (!nzchar(secret)) {
    secret <- paste(openssl::rand_bytes(32), collapse = "")
    cli::cli_inform("NEMETON_CLAUDE_SECRET absente : liens de t\u00e9l\u00e9chargement valables jusqu'\u00e0 l'arr\u00eat du serveur.")
  }
  list(url = url, ressource = paste0(url, "/mcp"), issuer = issuer, audience = audience,
       roles_lecture = roles_lecture, roles_ecriture = unique(roles_ecriture),
       isolation = isolation, secret = secret, duree_lien = as.numeric(duree_lien))
}

# Outils qui ecrivent : reserves aux roles d'ecriture. Tout outil absent de
# cette liste et de .OUTILS_LECTURE est refuse a tous (garde-fou si
# nemetonshiny ajoute un outil).
.OUTILS_ECRITURE <- c("creer_projet", "lancer_calcul", "annuler_calcul",
                      "generer_rapport", "exporter_gpkg")
.OUTILS_LECTURE <- c("lister_projets", "resume_projet", "etat_calcul", "url_app",
                     "chercher_commune", "parcelles_commune", "vue_atlas",
                     "contexte_carto", "detail_indicateur")

.outils_permis <- function(roles, config) {
  c(if (length(intersect(roles, c(config$roles_lecture, config$roles_ecriture)))) .OUTILS_LECTURE,
    if (length(intersect(roles, config$roles_ecriture))) .OUTILS_ECRITURE)
}

# ---------------------------------------------------------------- jetons

.b64url_json <- function(x) {
  jsonlite::fromJSON(rawToChar(jose::base64url_decode(x)), simplifyVector = FALSE)
}

.refus <- function(message, raison = "invalid_token") {
  rlang::abort(message, class = "nemetonclaude_jeton_refuse", raison = raison)
}

# Cles publiques du realm (JWKS), relues au plus une fois par minute quand
# un jeton arrive avec une cle inconnue (rotation des cles Keycloak).
.jwks_keycloak <- function(issuer) {
  cache <- new.env(parent = emptyenv())
  function(forcer = FALSE) {
    if (!forcer && !is.null(cache$cles) && difftime(Sys.time(), cache$lu, units = "secs") < 3600) {
      return(cache$cles)
    }
    if (forcer && !is.null(cache$lu) && difftime(Sys.time(), cache$lu, units = "secs") < 60) {
      return(cache$cles)
    }
    conf <- httr2::resp_body_json(httr2::req_perform(httr2::req_timeout(
      httr2::request(paste0(issuer, "/.well-known/openid-configuration")), 10)))
    jwks <- httr2::resp_body_json(httr2::req_perform(httr2::req_timeout(
      httr2::request(conf$jwks_uri), 10)))
    cache$cles <- jwks$keys
    cache$lu <- Sys.time()
    cache$cles
  }
}

#' Access token verifier
#'
#' @param config [config_distant()].
#' @param cles Function `cles(forcer = FALSE)` returning the realm's JWKS
#'   keys (list of JWK); by default read from Keycloak.
#' @param marge Clock leeway in seconds.
#' @return A function `verifier(jeton)` returning the user (`sub`, `nom`,
#'   `email`, `roles`) or raising an error of class
#'   `nemetonclaude_jeton_refuse`.
#' @noRd
.verificateur_jwt <- function(config, cles = .jwks_keycloak(config$issuer), marge = 60) {
  function(jeton) {
    parties <- strsplit(jeton, ".", fixed = TRUE)[[1]]
    if (length(parties) != 3L) .refus("Jeton mal form\u00e9.")
    entete <- tryCatch(.b64url_json(parties[1]), error = function(e) .refus("Jeton mal form\u00e9."))
    if (!isTRUE(entete$alg %in% c("RS256", "RS384", "RS512", "ES256", "ES384", "ES512"))) {
      .refus("Algorithme de signature refus\u00e9.")
    }
    trouver <- function(jeu) {
      for (k in jeu) if (identical(k$kid, entete$kid) && !identical(k$use, "enc")) return(k)
      NULL
    }
    cle <- trouver(cles())
    if (is.null(cle)) cle <- trouver(cles(forcer = TRUE))
    if (is.null(cle)) .refus("Cl\u00e9 de signature inconnue.")
    pub <- jose::read_jwk(.json(cle))
    claims <- tryCatch(jose::jwt_decode_sig(jeton, pub),
                       error = function(e) .refus(paste("Jeton refus\u00e9 :", conditionMessage(e))))
    maintenant <- as.numeric(Sys.time())
    if (is.null(claims$exp) || claims$exp < maintenant - marge) .refus("Jeton expir\u00e9.")
    if (!is.null(claims$nbf) && claims$nbf > maintenant + marge) .refus("Jeton pas encore valide.")
    if (!identical(claims$iss, config$issuer)) .refus("\u00c9metteur du jeton inattendu.")
    if (!config$audience %in% unlist(claims$aud)) .refus("Jeton destin\u00e9 \u00e0 un autre service (aud).")
    if (is.null(claims$sub) || !nzchar(claims$sub)) .refus("Jeton sans sujet.")
    list(sub = claims$sub,
         nom = claims$preferred_username %||% claims$name %||% claims$sub,
         email = claims$email,
         roles = as.character(unlist(claims$realm_access$roles)))
  }
}

# ---------------------------------------------------------------- liens signes

.signer <- function(texte, secret) {
  jose::base64url_encode(openssl::sha256(charToRaw(texte), key = secret))
}

# Dossiers d'ou un lien peut servir un fichier : la racine des projets
# nemeton et celle des fichiers de vues (sous-dossiers par utilisateur
# compris). Un lien vers un fichier hors de ces racines est refuse meme
# correctement signe.
.racines_servies <- function(config) {
  c(config$racine_projets %||% .ns("get_projects_root")(),
    config$racine_vues %||% .dossier_vues())
}

.sous <- function(fichier, racines) {
  reel <- normalizePath(fichier, winslash = "/", mustWork = FALSE)
  any(vapply(racines, function(r) {
    startsWith(reel, paste0(normalizePath(r, winslash = "/", mustWork = FALSE), "/"))
  }, logical(1)))
}

#' Signed, expiring download link for a file
#'
#' The token carries the index of a served root and the path below it, so
#' it never shows the server's directory layout.
#' @noRd
.lien <- function(fichier, config, maintenant = Sys.time(), racines = .racines_servies(config)) {
  reel <- normalizePath(fichier, winslash = "/")
  bases <- normalizePath(racines, winslash = "/", mustWork = FALSE)
  i <- which(startsWith(reel, paste0(bases, "/")))[1]
  if (is.na(i)) .abort("Fichier hors des dossiers servis.", "nemetonclaude_lien_refuse")
  charge <- jose::base64url_encode(charToRaw(.json(list(
    r = i, f = substring(reel, nchar(bases[i]) + 2L),
    e = floor(as.numeric(maintenant) + config$duree_lien)))))
  sprintf("%s/telechargement/%s.%s/%s", config$url, charge, .signer(charge, config$secret),
          utils::URLencode(basename(fichier), reserved = TRUE))
}

# Rend le chemin du fichier d'un jeton, ou NULL (signature, expiration,
# racine ou existence en defaut). Aucune raison n'est donnee au client.
.fichier_du_jeton <- function(jeton, config, racines = .racines_servies(config)) {
  p <- strsplit(jeton, ".", fixed = TRUE)[[1]]
  if (length(p) != 2L) return(NULL)
  attendu <- .signer(p[1], config$secret)
  if (nchar(attendu) != nchar(p[2]) ||
      !identical(openssl::sha256(charToRaw(attendu)), openssl::sha256(charToRaw(p[2])))) {
    return(NULL)
  }
  charge <- tryCatch(.b64url_json(p[1]), error = function(e) NULL)
  if (!is.numeric(charge$r) || !is.character(charge$f) || !is.numeric(charge$e)) return(NULL)
  if (charge$e < as.numeric(Sys.time()) || charge$r < 1 || charge$r > length(racines)) return(NULL)
  f <- file.path(racines[[charge$r]], charge$f)
  if (!file.exists(f) || dir.exists(f) || !.sous(f, racines)) return(NULL)
  normalizePath(f, winslash = "/")
}

# Ajoute `urls` (chemin -> lien signe) a la reponse JSON d'un outil, pour
# chaque chaine qui designe un fichier existant sous une racine servie.
# La structure de la reponse ne change pas : Claude lit `urls[[fichier]]`.
.ajouter_urls <- function(texte, config, racines = .racines_servies(config)) {
  x <- tryCatch(jsonlite::fromJSON(texte, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(x) || !isTRUE(x$ok)) return(texte)
  chemins <- character()
  parcourir <- function(v) {
    if (is.list(v)) for (e in v) parcourir(e)
    else if (is.character(v) && length(v) == 1L && startsWith(v, "/") &&
             file.exists(v) && !dir.exists(v) && .sous(v, racines)) chemins <<- c(chemins, v)
  }
  parcourir(x)
  if (!length(chemins)) return(texte)
  chemins <- unique(chemins)
  x$urls <- stats::setNames(lapply(chemins, .lien, config = config, racines = racines), chemins)
  x$urls_expirent_dans_s <- config$duree_lien
  .json(x)
}

# ---------------------------------------------------------------- HTTP

.reponse <- function(status, corps, entetes = list()) {
  list(status = as.integer(status),
       headers = c(list(`Content-Type` = "application/json", `Cache-Control` = "no-store"), entetes),
       body = if (is.character(corps)) corps else .json(corps))
}

.metadonnees_ressource <- function(config) {
  list(resource = config$ressource,
       authorization_servers = list(config$issuer),
       bearer_methods_supported = list("header"),
       scopes_supported = list("openid", "profile", "email"),
       resource_name = "nemeton",
       resource_documentation = "https://github.com/pobsteta/nemetonclaude")
}

.non_autorise <- function(config, description, raison = "invalid_token", status = 401L) {
  defi <- sprintf('Bearer resource_metadata="%s/.well-known/oauth-protected-resource", error="%s", error_description="%s"',
                  config$url, raison, gsub('"', "'", description))
  .reponse(status, list(error = raison, error_description = description),
           list(`WWW-Authenticate` = defi))
}

# Requete Rook dont le corps a deja ete lu : on la rejoue a mcptools.
.rejouer <- function(req, corps) {
  req$rook.input <- list(read = function(...) corps, rewind = function() invisible(), close = function() invisible())
  req
}

.erreur_jsonrpc <- function(id, message, code = -32001L) {
  .reponse(200L, list(jsonrpc = "2.0", id = id, error = list(code = code, message = message)))
}

# Contexte d'une requete authentifiee : dossiers propres a l'utilisateur en
# mode isolation. Rend une fonction qui restaure l'etat precedent.
.entrer_contexte <- function(utilisateur, config) {
  if (!identical(config$isolation, "utilisateur")) return(function() invisible())
  dossier <- gsub("[^A-Za-z0-9_-]", "_", utilisateur$sub)
  avant <- options(
    nemeton.app_options = utils::modifyList(getOption("nemeton.app_options", list()) %||% list(),
                                            list(project_dir = file.path(config$racine_projets, dossier))),
    nemetonclaude.dossier_vues = file.path(config$racine_vues, dossier))
  function() options(avant)
}

.traiter_mcp <- function(req, config, verifier, transmettre) {
  auth <- req$HTTP_AUTHORIZATION %||% ""
  if (!grepl("^Bearer\\s+\\S+", auth, ignore.case = TRUE)) {
    return(.non_autorise(config, "Jeton d'acc\u00e8s requis."))
  }
  utilisateur <- tryCatch(verifier(sub("^Bearer\\s+", "", auth, ignore.case = TRUE)),
                          nemetonclaude_jeton_refuse = function(e) e)
  if (inherits(utilisateur, "condition")) return(.non_autorise(config, conditionMessage(utilisateur), utilisateur$raison))
  permis <- .outils_permis(utilisateur$roles, config)
  if (!length(permis)) {
    return(.non_autorise(config, "Aucun r\u00f4le nemeton pour ce compte.", "insufficient_scope", 403L))
  }

  corps <- if (identical(req$REQUEST_METHOD, "POST")) req$rook.input$read() else raw()
  message <- if (length(corps)) tryCatch(jsonlite::fromJSON(rawToChar(corps), simplifyVector = FALSE),
                                         error = function(e) NULL)
  methode <- message$method %||% ""
  outil <- message$params$name %||% ""
  if (identical(methode, "tools/call") && !outil %in% permis) {
    roles <- paste(config$roles_ecriture, collapse = ", ")
    return(.erreur_jsonrpc(message$id, sprintf(
      "Outil %s r\u00e9serv\u00e9 aux r\u00f4les : %s.", outil, roles)))
  }

  restaurer <- .entrer_contexte(utilisateur, config)
  on.exit(restaurer(), add = TRUE)
  rep <- transmettre(.rejouer(req, corps))

  if (identical(rep$status, 200L) && is.character(rep$body) && nzchar(rep$body)) {
    if (identical(methode, "tools/list")) rep$body <- .filtrer_liste(rep$body, permis)
    if (identical(methode, "tools/call")) rep$body <- .urls_resultat(rep$body, config)
  }
  rep
}

.filtrer_liste <- function(corps, permis) {
  x <- jsonlite::fromJSON(corps, simplifyVector = FALSE)
  if (!is.null(x$result$tools)) {
    x$result$tools <- Filter(function(t) t$name %in% permis, x$result$tools)
  }
  .json(x)
}

.urls_resultat <- function(corps, config) {
  x <- jsonlite::fromJSON(corps, simplifyVector = FALSE)
  contenu <- x$result$content
  if (length(contenu) && identical(contenu[[1]]$type, "text")) {
    x$result$content[[1]]$text <- .ajouter_urls(contenu[[1]]$text, config)
    .json(x)
  } else corps
}

.TYPES <- c(geojson = "application/geo+json", json = "application/json",
            pdf = "application/pdf", gpkg = "application/geopackage+sqlite3",
            csv = "text/csv", png = "image/png", zip = "application/zip")

.servir_fichier <- function(jeton, config) {
  f <- .fichier_du_jeton(jeton, config)
  if (is.null(f)) return(.reponse(404L, list(error = "Lien invalide ou expir\u00e9.")))
  ext <- tolower(tools::file_ext(f))
  list(status = 200L,
       headers = list(`Content-Type` = unname(.TYPES[ext]) %||% "application/octet-stream",
                      `Content-Disposition` = sprintf('attachment; filename="%s"', gsub('"', "", basename(f))),
                      `Cache-Control` = "private, no-store",
                      `X-Content-Type-Options` = "nosniff"),
       body = readBin(f, "raw", file.size(f)))
}

#' Rook application of the remote connector
#'
#' Routes: `GET /sante`, the OAuth protected resource metadata
#' (`/.well-known/oauth-protected-resource`), `POST /mcp` (authenticated
#' MCP), `GET /telechargement/<signed token>/<name>`.
#'
#' @param config [config_distant()].
#' @param verifier Token verifier, see `.verificateur_jwt()`.
#' @param transmettre Function handling an authorized MCP request (by
#'   default mcptools' HTTP handler).
#' @return A list with a `call` function, for `httpuv::startServer()`.
#' @noRd
.app_distant <- function(config, verifier = .verificateur_jwt(config),
                         transmettre = .mcptools("handle_http_request")) {
  list(call = function(req) {
    chemin <- req$PATH_INFO %||% "/"
    methode <- req$REQUEST_METHOD %||% "GET"
    tryCatch({
      if (chemin %in% c("/.well-known/oauth-protected-resource",
                        "/.well-known/oauth-protected-resource/mcp")) {
        return(.reponse(200L, .metadonnees_ressource(config), list(`Access-Control-Allow-Origin` = "*")))
      }
      if (identical(chemin, "/sante")) return(.reponse(200L, list(ok = TRUE)))
      if (identical(chemin, "/mcp")) return(.traiter_mcp(req, config, verifier, transmettre))
      if (startsWith(chemin, "/telechargement/") && methode %in% c("GET", "HEAD")) {
        jeton <- strsplit(sub("^/telechargement/", "", chemin), "/", fixed = TRUE)[[1]][1]
        return(.servir_fichier(jeton, config))
      }
      .reponse(404L, list(error = "Introuvable."))
    }, error = function(e) {
      cli::cli_warn("Requ\u00eate {methode} {chemin} en \u00e9chec : {conditionMessage(e)}")
      .reponse(500L, list(error = "Erreur interne."))
    })
  })
}

# Internes de mcptools : un seul point d'acces, comme .ns() pour nemetonshiny.
.mcptools <- function(nom) {
  if (!requireNamespace("mcptools", quietly = TRUE)) {
    stop("Le paquet 'mcptools' est requis : install.packages(\"mcptools\").", call. = FALSE)
  }
  utils::getFromNamespace(nom, "mcptools")
}

#' Run the remote MCP server (HTTP, Keycloak authentication)
#'
#' Serves the tools of [outils_mcp()] over Streamable HTTP at `<url>/mcp`,
#' for a claude.ai custom connector. Put it behind an HTTPS reverse proxy:
#' the server itself listens in plain HTTP on `host:port`. See
#' `deploiement/` and the README for Keycloak and proxy configuration.
#'
#' @param host,port Listening address (default `127.0.0.1:8765`, behind the
#'   proxy; `NEMETON_CLAUDE_PORT`).
#' @param config [config_distant()].
#' @export
serveur_mcp_distant <- function(host = "127.0.0.1",
                                port = as.integer(Sys.getenv("NEMETON_CLAUDE_PORT", "8765")),
                                config = config_distant()) {
  the <- .mcptools("the")
  the$sessions_enabled <- FALSE
  .mcptools("set_server_tools")(outils_mcp(), session_tools = FALSE)
  config$racine_projets <- .ns("get_projects_root")()
  config$racine_vues <- .dossier_vues()
  app <- .app_distant(config)
  serveur <- httpuv::startServer(host, port, app)
  on.exit(httpuv::stopServer(serveur), add = TRUE)
  cli::cli_inform(c("Connecteur nemeton distant : {config$ressource}",
                    i = "\u00c9coute sur http://{host}:{port} ; jetons \u00e9mis par {config$issuer} (aud {config$audience}).",
                    i = "Isolation : {config$isolation}."))
  httpuv::service(Inf)
}
