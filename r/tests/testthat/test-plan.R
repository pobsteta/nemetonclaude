# Plan d'actions : l'API de nemetonshiny ecrit un vrai action_plan.json dans
# un projet temporaire ; seules l'unite de gestion et la resolution du projet
# sont simulees (pas de cadastre ni de calcul).

ID <- "20261006_101500_test"

projet_test <- function(env = parent.frame()) {
  racine <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(racine, ID, "data"), recursive = TRUE)
  withr::local_options(nemeton.app_options = list(project_dir = racine),
                       nemetonclaude.utilisateur = "gest", nemetonclaude.peut_ecrire = TRUE,
                       .local_envir = env)
  testthat::local_mocked_bindings(
    .resoudre_projet = function(projet) ID,
    .ug_ids_projet = function(id) list(ids = c("u1", "u2"), ug = NULL,
                                       projet = list(metadata = list(name = "Forêt test"))),
    .env = env)
  racine
}

lire <- function(json) jsonlite::fromJSON(json, simplifyVector = FALSE)

test_that(".normaliser_action garde les champs connus et convertit l'annee civile", {
  a <- .normaliser_action(list(ug_id = "u1", type = "eclaircie", annee = 2031, id = "pirate",
                               cree_par = "x", objectifs_lies = list("B", "C"), duree = "3"), 2026)
  expect_equal(a$annee_cible, 5L)
  expect_null(a$id)
  expect_null(a$cree_par)
  expect_equal(a$objectifs_lies, c("B", "C"))
  expect_identical(a$duree, 3L)
  expect_equal(.normaliser_action(list(annee_cible = 4), 2026)$annee_cible, 4L)
  expect_equal(.normaliser_action('{"type":"autre","type_libre":"Mare"}', 2026)$type_libre, "Mare")
})

test_that(".action_pour_vue ajoute l'annee civile, le libelle et l'origine Claude", {
  v <- .action_pour_vue(list(ug_id = "u1", annee_cible = 3L, source = list(origine = "claude")),
                        2026, c(u1 = "UG 1"))
  expect_equal(v$annee, 2029L)
  expect_equal(v$ug_label, "UG 1")
  expect_true(v$propose_par_claude)
  expect_null(.action_pour_vue(list(ug_id = "u9"), 2026, c(u1 = "UG 1"))$annee)
  # Une seule famille reste un tableau JSON.
  expect_match(.json(.action_pour_vue(list(objectifs_lies = "W"), 2026)), '"objectifs_lies":\\["W"\\]')
  expect_match(.json(.action_pour_vue(list(), 2026)), '"objectifs_lies":\\[\\]')
})

test_that("ajouter, lire, modifier et supprimer une action ecrivent le plan et son historique", {
  projet_test()
  r <- lire(ajouter_action("x", list(ug_id = "u1", type = "eclaircie", annee = 2030,
                                     priorite = "haute", objectifs_lies = list("B"),
                                     source = list(origine = "claude"))))
  expect_true(r$ok)
  a <- r$action
  expect_equal(a$statut, "proposee")
  expect_equal(a$cree_par, "gest")
  expect_true(a$propose_par_claude)
  expect_equal(a$annee, 2030)

  p <- lire(plan_actions("x", geojson = FALSE))
  expect_length(p$actions, 1)
  # La version rendue a l'ajout est celle que relit plan_actions().
  expect_equal(p$actions[[1]]$version, a$version)
  expect_equal(p$nom, "Forêt test")
  expect_true(p$peut_ecrire)
  expect_true("eclaircie" %in% unlist(p$catalogue$types))
  expect_equal(p$historique[[1]]$op, "create")

  m <- lire(modifier_action("x", a$id, list(statut = "validee", annee = 2031), attendu = a$version))
  expect_true(m$ok)
  expect_false(identical(m$action$version, a$version))
  expect_equal(m$action$statut, "validee")
  expect_equal(m$action$annee, 2031)
  expect_equal(m$action$modifie_par, "gest")

  # Conflit : la vue avait lu une version plus ancienne.
  k <- lire(modifier_action("x", a$id, list(priorite = "basse"), attendu = a$version))
  expect_false(k$ok)
  expect_equal(k$classe, "nemetonclaude_conflit")
  expect_equal(k$candidats[[1]]$statut, "validee")

  champs <- vapply(lire(plan_actions("x", geojson = FALSE))$historique, function(e) e$champ %||% "", "")
  expect_true(all(c("statut", "annee_cible") %in% champs))

  s <- lire(supprimer_action("x", a$id))
  expect_true(s$ok)
  p <- lire(plan_actions("x", geojson = FALSE))
  expect_length(p$actions, 0)
  expect_equal(p$historique[[1]]$op, "delete")
})

test_that("une action invalide ou un compte sans ecriture sont refuses sans rien ecrire", {
  projet_test()
  r <- lire(ajouter_action("x", list(ug_id = "u9", type = "eclaircie", annee = 2030)))
  expect_false(r$ok)
  expect_equal(r$classe, "nemetonclaude_action_invalide")
  expect_match(r$erreur, "u9")
  r <- lire(ajouter_action("x", list(ug_id = "u1", type = "coupe_magique", annee = 2030)))
  expect_equal(r$classe, "nemetonclaude_action_invalide")
  expect_equal(lire(modifier_action("x", "act_absente", list(statut = "validee")))$classe,
               "nemetonclaude_action_introuvable")
  withr::local_options(nemetonclaude.peut_ecrire = FALSE)
  expect_equal(lire(ajouter_action("x", list(ug_id = "u1", type = "eclaircie", annee = 2030)))$classe,
               "nemetonclaude_droits")
  withr::local_options(nemetonclaude.peut_ecrire = TRUE)
  expect_length(lire(plan_actions("x", geojson = FALSE))$actions, 0)
})

test_that("un projet en cours d'edition dans l'application n'est pas modifie", {
  projet_test()
  vrai_ns <- .ns
  local_mocked_bindings(.ns = function(nom) {
    if (identical(nom, "lock_status")) function(id) list(stale = FALSE, holder_label = "Alice")
    else vrai_ns(nom)
  })
  r <- lire(ajouter_action("x", list(ug_id = "u1", type = "eclaircie", annee = 2030)))
  expect_equal(r$classe, "nemetonshiny_projet_verrouille")
  expect_match(r$erreur, "Alice")
})

test_that("profils_experts sert les profils YAML de nemetonshiny", {
  r <- lire(profils_experts("fr"))
  expect_true(r$ok)
  cles <- vapply(r$profils, `[[`, "", "cle")
  expect_true("generalist" %in% cles)
  p <- r$profils[[which(cles == "generalist")]]
  expect_true(nzchar(p$libelle))
  expect_true(nzchar(p$consigne))
})
