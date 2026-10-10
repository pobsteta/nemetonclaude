# Connecteur distant : jetons Keycloak (cle RSA de test, sans reseau), liens
# signes, droits par role et routage HTTP. Le protocole MCP est simule.

cle <- openssl::rsa_keygen(2048)
autre_cle <- openssl::rsa_keygen(2048)
jwk <- function(k, kid) {
  j <- jsonlite::fromJSON(jose::write_jwk(k$pubkey), simplifyVector = FALSE)
  c(j, list(kid = kid, use = "sig", alg = "RS256"))
}
jwks <- function(forcer = FALSE) list(jwk(cle, "k1"))

config_test <- function(...) {
  racine <- withr::local_tempdir(.local_envir = parent.frame(2))
  dir.create(file.path(racine, "projets"))
  dir.create(file.path(racine, "vues"))
  c(config_distant(url = "https://nemeton.test", issuer = "https://auth.test/realms/nemeton",
                   audience = "nemeton-claude", secret = "secret-de-test",
                   roles_lecture = c("lecteur", "gestionnaire", "admin"),
                   roles_ecriture = c("gestionnaire", "admin"), ...),
    list(racine_projets = file.path(racine, "projets"), racine_vues = file.path(racine, "vues")))
}

jeton <- function(..., roles = "gestionnaire", k = cle, kid = "k1") {
  claims <- utils::modifyList(list(
    iss = "https://auth.test/realms/nemeton", aud = list("nemeton-claude", "account"),
    sub = "u-123", preferred_username = "demo", exp = as.numeric(Sys.time()) + 300), list(...))
  claims$realm_access <- list(roles = as.list(roles))
  # jose::jwt_claim() n'accepte qu'une audience ; Keycloak en met plusieurs.
  aud <- claims$aud
  claims$aud <- NULL
  claim <- do.call(jose::jwt_claim, claims)
  claim$aud <- aud
  jose::jwt_encode_sig(claim, k, header = list(kid = kid))
}

test_that("le verificateur accepte un jeton valide et rend l'utilisateur", {
  v <- .verificateur_jwt(config_test(), cles = jwks)
  u <- v(jeton())
  expect_equal(u$sub, "u-123")
  expect_equal(u$nom, "demo")
  expect_equal(u$roles, "gestionnaire")
})

test_that("le verificateur refuse signature, emetteur, audience, expiration et forme", {
  v <- .verificateur_jwt(config_test(), cles = jwks)
  refuse <- function(j) expect_error(v(j), class = "nemetonclaude_jeton_refuse")
  refuse(jeton(k = autre_cle))
  refuse(jeton(iss = "https://ailleurs.test/realms/x"))
  refuse(jeton(aud = "account"))
  refuse(jeton(exp = as.numeric(Sys.time()) - 600))
  refuse(jeton(nbf = as.numeric(Sys.time()) + 600))
  refuse(jeton(kid = "inconnue"))
  refuse("pas.un.jeton")
  refuse("deux.parties")
  # alg « none » : jamais accepte.
  entete <- jose::base64url_encode(charToRaw('{"alg":"none","kid":"k1"}'))
  corps <- strsplit(jeton(), ".", fixed = TRUE)[[1]][2]
  refuse(paste(entete, corps, "", sep = "."))
})

test_that("une cle inconnue fait relire le JWKS une fois (rotation)", {
  lectures <- 0
  cles <- function(forcer = FALSE) {
    lectures <<- lectures + 1
    if (forcer) list(jwk(cle, "k1"), jwk(autre_cle, "k2")) else list(jwk(cle, "k1"))
  }
  v <- .verificateur_jwt(config_test(), cles = cles)
  expect_equal(v(jeton(k = autre_cle, kid = "k2"))$sub, "u-123")
  expect_equal(lectures, 2)
})

test_that("les droits suivent les roles", {
  cfg <- config_test()
  expect_setequal(.outils_permis("lecteur", cfg), .OUTILS_LECTURE)
  expect_setequal(.outils_permis("gestionnaire", cfg), c(.OUTILS_LECTURE, .OUTILS_ECRITURE))
  expect_length(.outils_permis(c("offline_access", "uma_authorization"), cfg), 0)
})

test_that("chaque outil du connecteur est classe en lecture ou en ecriture", {
  # Un outil ajoute par nemetonshiny et oublie ici serait refuse a tous a
  # distance : le test le signale au lieu de le laisser passer inapercu.
  noms <- vapply(outils_mcp(), function(o) o@name, "")
  expect_setequal(noms, c(.OUTILS_LECTURE, .OUTILS_ECRITURE))
  expect_true(all(c("appliquer_ugf", "croiser_onf") %in% .OUTILS_ECRITURE))
})

test_that("un lien signe sert son fichier, et seulement lui", {
  cfg <- config_test()
  f <- file.path(cfg$racine_vues, "atlas.geojson")
  writeLines('{"type":"FeatureCollection","features":[]}', f)
  url <- .lien(f, cfg)
  expect_match(url, "^https://nemeton.test/telechargement/[^/]+/atlas.geojson$")
  j <- strsplit(sub("^.*/telechargement/", "", url), "/")[[1]][1]
  expect_equal(.fichier_du_jeton(j, cfg), normalizePath(f))

  # Signature alteree, autre secret, expire, hors racine : refuses.
  p <- strsplit(j, ".", fixed = TRUE)[[1]]
  expect_null(.fichier_du_jeton(paste0(p[1], ".", substr(p[2], 2, 99), "A"), cfg))
  expect_null(.fichier_du_jeton(j, utils::modifyList(cfg, list(secret = "autre"))))
  vieux <- strsplit(sub("^.*/telechargement/", "", .lien(f, cfg, Sys.time() - 7200)), "/")[[1]][1]
  expect_null(.fichier_du_jeton(vieux, cfg))
  dehors <- withr::local_tempfile(fileext = ".txt")
  writeLines("x", dehors)
  expect_error(.lien(dehors, cfg), class = "nemetonclaude_lien_refuse")
  # Un jeton correctement signe qui remonte hors de la racine est refuse.
  charge <- jose::base64url_encode(charToRaw(.json(list(r = 2, f = "../../../etc/passwd", e = 4e9))))
  expect_null(.fichier_du_jeton(paste0(charge, ".", .signer(charge, cfg$secret)), cfg))
  # Le jeton ne montre pas le chemin du serveur.
  expect_false(grepl(basename(cfg$racine_vues), rawToChar(jose::base64url_decode(p[1])), fixed = TRUE))
  expect_null(.fichier_du_jeton("n.importe.quoi", cfg))
})

test_that(".ajouter_urls ajoute un lien par fichier servi sans toucher au reste", {
  cfg <- config_test()
  f <- file.path(cfg$racine_projets, "p1", "exports", "resultats.gpkg")
  dir.create(dirname(f), recursive = TRUE)
  writeBin(as.raw(1:10), f)
  texte <- .json(list(ok = TRUE, projet = "p1", fichier = normalizePath(f),
                      autres = list(absent = "/nulle/part.gpkg")))
  x <- jsonlite::fromJSON(.ajouter_urls(texte, cfg), simplifyVector = FALSE)
  expect_equal(x$fichier, normalizePath(f))
  expect_length(x$urls, 1)
  expect_match(x$urls[[normalizePath(f)]], "/resultats.gpkg$")
  expect_equal(x$urls_expirent_dans_s, 3600)
  # Erreur d'outil ou texte non JSON : inchanges.
  expect_equal(.ajouter_urls('{"ok":false,"erreur":"x"}', cfg), '{"ok":false,"erreur":"x"}')
  expect_equal(.ajouter_urls("texte", cfg), "texte")
})

# ------------------------------------------------------------- routage HTTP

requete <- function(chemin, methode = "GET", corps = NULL, jeton = NULL) {
  brut <- if (is.null(corps)) raw() else charToRaw(.json(corps))
  r <- list(PATH_INFO = chemin, REQUEST_METHOD = methode,
            rook.input = list(read = function(...) brut))
  if (!is.null(jeton)) r$HTTP_AUTHORIZATION <- paste("Bearer", jeton)
  r
}

# Faux mcptools : rend la liste de tous les outils, ou le resultat d'un
# outil qui ecrit un fichier, en notant le dossier de projets vu.
faux_mcp <- function(cfg, vu = new.env()) {
  function(req) {
    m <- jsonlite::fromJSON(rawToChar(req$rook.input$read()), simplifyVector = FALSE)
    vu$projet_dir <- getOption("nemeton.app_options")$project_dir
    vu$vues <- getOption("nemetonclaude.dossier_vues")
    res <- if (identical(m$method, "tools/list")) {
      list(tools = lapply(c(.OUTILS_LECTURE, .OUTILS_ECRITURE, "outil_inconnu"), function(n) list(name = n)))
    } else {
      f <- file.path(cfg$racine_vues, "atlas.geojson")
      writeLines("{}", f)
      list(content = list(list(type = "text", text = .json(list(ok = TRUE, fichier = normalizePath(f))))))
    }
    list(status = 200L, headers = list(`Content-Type` = "application/json"),
         body = .json(list(jsonrpc = "2.0", id = m$id, result = res)))
  }
}

corps_json <- function(r) jsonlite::fromJSON(r$body, simplifyVector = FALSE)

test_that("les metadonnees de ressource protegee pointent vers Keycloak", {
  cfg <- config_test()
  app <- .app_distant(cfg, verifier = .verificateur_jwt(cfg, cles = jwks), transmettre = faux_mcp(cfg))
  for (ch in c("/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp")) {
    r <- app$call(requete(ch))
    expect_equal(r$status, 200L)
    m <- corps_json(r)
    expect_equal(m$resource, "https://nemeton.test/mcp")
    expect_equal(m$authorization_servers[[1]], "https://auth.test/realms/nemeton")
  }
  expect_equal(app$call(requete("/sante"))$status, 200L)
  expect_equal(app$call(requete("/ailleurs"))$status, 404L)
})

test_that("/mcp sans jeton ou avec un mauvais jeton rend 401 et le defi OAuth", {
  cfg <- config_test()
  app <- .app_distant(cfg, verifier = .verificateur_jwt(cfg, cles = jwks), transmettre = faux_mcp(cfg))
  for (j in list(NULL, jeton(k = autre_cle))) {
    r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 1, method = "tools/list"), j))
    expect_equal(r$status, 401L)
    expect_match(r$headers$`WWW-Authenticate`,
                 'resource_metadata="https://nemeton.test/.well-known/oauth-protected-resource"', fixed = TRUE)
  }
  r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 1, method = "tools/list"),
                        jeton(roles = "offline_access")))
  expect_equal(r$status, 403L)
  expect_match(r$headers$`WWW-Authenticate`, "insufficient_scope")
})

test_that("un lecteur ne voit ni n'appelle les outils d'ecriture", {
  cfg <- config_test()
  app <- .app_distant(cfg, verifier = .verificateur_jwt(cfg, cles = jwks), transmettre = faux_mcp(cfg))
  lecteur <- jeton(roles = "lecteur")
  r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 2, method = "tools/list"), lecteur))
  noms <- vapply(corps_json(r)$result$tools, `[[`, "", "name")
  expect_setequal(noms, .OUTILS_LECTURE)
  r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 3, method = "tools/call",
                                             params = list(name = "lancer_calcul", arguments = list(projet = "p"))), lecteur))
  expect_match(corps_json(r)$error$message, "réservé")
  # Un outil inconnu (ajoute un jour par nemetonshiny) est refuse a tous.
  r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 4, method = "tools/call",
                                             params = list(name = "outil_inconnu")), jeton()))
  expect_false(is.null(corps_json(r)$error))
})

test_that("un appel autorise rend les liens de telechargement, servis ensuite sans jeton", {
  cfg <- config_test()
  app <- .app_distant(cfg, verifier = .verificateur_jwt(cfg, cles = jwks), transmettre = faux_mcp(cfg))
  r <- app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 5, method = "tools/call",
                                             params = list(name = "vue_atlas", arguments = list(projet = "p"))), jeton()))
  res <- jsonlite::fromJSON(corps_json(r)$result$content[[1]]$text, simplifyVector = FALSE)
  url <- res$urls[[res$fichier]]
  expect_match(url, "^https://nemeton.test/telechargement/")
  d <- app$call(requete(sub("^https://nemeton.test", "", url)))
  expect_equal(d$status, 200L)
  expect_equal(d$headers$`Content-Type`, "application/geo+json")
  expect_equal(rawToChar(d$body), "{}\n")
  expect_equal(app$call(requete("/telechargement/faux.jeton/x"))$status, 404L)
})

test_that("en mode isolation, chaque utilisateur a ses dossiers, restaures apres la requete", {
  cfg <- config_test(isolation = "utilisateur")
  vu <- new.env()
  app <- .app_distant(cfg, verifier = .verificateur_jwt(cfg, cles = jwks), transmettre = faux_mcp(cfg, vu))
  withr::local_options(nemeton.app_options = list(project_dir = "/avant"))
  app$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 6, method = "tools/list"), jeton(sub = "a/b c")))
  expect_equal(vu$projet_dir, file.path(cfg$racine_projets, "a_b_c"))
  expect_equal(vu$vues, file.path(cfg$racine_vues, "a_b_c"))
  expect_equal(getOption("nemeton.app_options")$project_dir, "/avant")
  expect_null(getOption("nemetonclaude.dossier_vues"))

  # Mode collectif : rien ne change.
  cfg2 <- config_test()
  app2 <- .app_distant(cfg2, verifier = .verificateur_jwt(cfg2, cles = jwks), transmettre = faux_mcp(cfg2, vu))
  app2$call(requete("/mcp", "POST", list(jsonrpc = "2.0", id = 7, method = "tools/list"), jeton()))
  expect_equal(vu$projet_dir, "/avant")
})

test_that("config_distant exige l'URL et le realm", {
  expect_error(config_distant(url = "", issuer = "x", secret = "s"), class = "nemetonclaude_config")
  expect_error(config_distant(url = "https://x", issuer = "", secret = "s"), class = "nemetonclaude_config")
  expect_equal(config_distant(url = "https://x/", issuer = "https://k/realms/n/", secret = "s")$ressource, "https://x/mcp")
})
