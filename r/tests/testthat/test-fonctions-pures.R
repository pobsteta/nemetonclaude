# Fonctions pures : aucun reseau, aucun projet sur disque.

test_that(".normaliser ignore accents, casse, tirets et developpe St/Ste", {
  expect_equal(.normaliser("Velars-sur-Ouche"), "velars sur ouche")
  expect_equal(.normaliser("Côte-d'Or"), "cote d or")
  expect_equal(.normaliser("St-Jean"), "saint jean")
  expect_equal(.normaliser("Ste Marie"), "sainte marie")
})

test_that(".resoudre_departement accepte code et nom, refuse l'ambigu", {
  liste <- c("21 - Côte-d'Or" = "21", "22 - Côtes-d'Armor" = "22",
             "2A - Corse-du-Sud" = "2A", "01 - Ain" = "01", "974 - La Réunion" = "974")
  expect_equal(.resoudre_departement("21", liste), "21")
  expect_equal(.resoudre_departement("2a", liste), "2A")
  expect_equal(.resoudre_departement("1", liste), "01")
  expect_equal(.resoudre_departement("cote d'or", liste), "21")
  expect_equal(.resoudre_departement("Réunion", liste), "974")
  err <- expect_error(.resoudre_departement("cote", liste),
                      class = "nemetonclaude_departement_ambigu")
  expect_length(err$candidats, 2)
  expect_error(.resoudre_departement("Atlantide", liste),
               class = "nemetonclaude_departement_introuvable")
})

brut <- list(
  list(nom = "Velars-sur-Ouche", code = "21661", codesPostaux = list("21370"),
       population = 1800L, type = "commune-actuelle"),
  list(nom = "Velars", code = "21999", codesPostaux = list("21000"),
       population = 10L, type = "commune-deleguee", chefLieu = "21500")
)

test_that(".candidats_communes rend le code cadastre de la commune nouvelle", {
  cand <- .candidats_communes(brut)
  expect_equal(cand$insee, c("21661", "21999"))
  expect_equal(cand$insee_cadastre, c("21661", "21500"))
  expect_equal(cand$code_postal[1], "21370")
  expect_equal(nrow(.candidats_communes(list())), 0)
})

test_that(".choisir_commune ne choisit qu'en cas de correspondance unique", {
  cand <- .candidats_communes(brut)
  ok <- .choisir_commune(cand, "velars sur ouche")
  expect_false(ok$choix_requis)
  expect_equal(ok$commune$insee, "21661")
  # Nom d'une commune deleguee : on demande.
  expect_true(.choisir_commune(cand, "Velars")$choix_requis)
  # Homonymes : on demande.
  homo <- rbind(cand[1, ], transform(cand[1, ], insee = "21662", insee_cadastre = "21662"))
  expect_true(.choisir_commune(homo, "Velars-sur-Ouche")$choix_requis)
  # Nom approchant seulement : on demande.
  expect_true(.choisir_commune(cand, "Vela")$choix_requis)
})

test_that(".normaliser_idu accepte tableau, chaine et doublons", {
  expect_equal(.normaliser_idu(list("21661000ab0012", "21661000AB0013")),
               c("21661000AB0012", "21661000AB0013"))
  expect_equal(.normaliser_idu("21661000AB0012, 21661000AB0013;21661000AB0012"),
               c("21661000AB0012", "21661000AB0013"))
  expect_length(.normaliser_idu(character()), 0)
})

test_that(".proprietes_atlas suit le contrat de donnees", {
  df <- data.frame(
    ug_id = c("u1", "u2"), label = c("UG 1", "UG 2"), groupe = c("A", "B"),
    surface_m2 = c(12345, 67890),
    famille_carbone = c(61.234, NA), famille_eau = c(40, 55.55),
    indicateur_c1_biomasse = c(120.5, 80),
    indicateur_c1_biomasse_norm = c(70.04, 45),
    indicateur_a5_bruit_norm = c(NA, NA),
    .a5_status = c("hors_zone_urbaine", "hors_zone_urbaine"),
    autre = 1:2, check.names = FALSE, stringsAsFactors = FALSE
  )
  p <- .proprietes_atlas(df)
  expect_equal(names(p)[1:4], c("ug_id", "label", "groupe", "surface_ha"))
  expect_equal(p$surface_ha, c(1.23, 6.79))
  expect_equal(p$famille_carbone, c(61.2, NA))
  expect_equal(p$indicateur_c1_biomasse_norm, c(70, 45))
  expect_true(all(is.na(p$indicateur_a5_bruit_norm)))
  expect_equal(p$.a5_status, c("hors_zone_urbaine", "hors_zone_urbaine"))
  expect_false("indicateur_c1_biomasse" %in% names(p))
  expect_false("autre" %in% names(p))
  expect_equal(.proprietes_atlas(df, bruts = TRUE)$indicateur_c1_biomasse, c(120.5, 80))
})

test_that(".mcp_call rend ok:true ou une erreur classee lisible", {
  ok <- jsonlite::fromJSON(.mcp_call(list(a = 1)))
  expect_true(ok$ok)
  expect_equal(ok$a, 1)
  ko <- jsonlite::fromJSON(.mcp_call(
    .abort("Ambigu.", "nemetonclaude_departement_ambigu", candidats = c("x", "y"))))
  expect_false(ko$ok)
  expect_equal(ko$classe, "nemetonclaude_departement_ambigu")
  expect_equal(ko$candidats, c("x", "y"))
})

test_that(".crs_metrique choisit la projection locale", {
  expect_equal(.crs_metrique("21661"), 2154)
  expect_equal(.crs_metrique("97411"), 2975)
  expect_equal(.crs_metrique("97302"), 2972)
})

test_that(".ecrire_geojson et .ajouter_entete produisent un FeatureCollection RFC 7946", {
  skip_if_not_installed("sf")
  x <- sf::st_sf(ug_id = "u1", geometry = sf::st_sfc(
    sf::st_polygon(list(rbind(c(4.9, 47.3), c(4.91, 47.3), c(4.91, 47.31), c(4.9, 47.3)))),
    crs = 4326))
  f <- withr::local_tempfile(fileext = ".geojson")
  .ecrire_geojson(x, f)
  .ajouter_entete(f, list(project_id = "p1", global_score = 55))
  gj <- jsonlite::read_json(f)
  expect_equal(gj$type, "FeatureCollection")
  expect_equal(gj$nemeton$project_id, "p1")
  expect_length(gj$features, 1)
  expect_equal(gj$features[[1]]$properties$ug_id, "u1")
})

test_that(".durees_calcul compte depuis le lancement, ou jusqu'a la fin", {
  t0 <- as.POSIXct("2026-10-06 10:00:00")
  expect_equal(.durees_calcul(list(lance_a = "2026-10-06T09:58:30"), t0)$ecoule_s, 90)
  expect_equal(.durees_calcul(list(lance_a = "2026-10-06T09:00:00", fin_a = "2026-10-06T09:30:00"), t0)$ecoule_s, 1800)
  expect_null(.durees_calcul(list(), t0)$ecoule_s)
  expect_null(.durees_calcul(list(lance_a = "n'importe quoi"), t0)$ecoule_s)
  expect_match(.durees_calcul(list(), t0)$maintenant, "^2026-10-06T10:00:00[+-][0-9]{4}$")
})

test_that(".identites_ug nomme UGF n les unites qui gardent leur reference cadastrale", {
  x <- .identites_ug(c("ug_1", "ug_12", "ug_3", "ug_4"),
                     c("212000000A0036", "Futaie du haut", NA, "212000000B0102"),
                     c("212000000A0036", "212000000A0015, 212000000A0016", "212000000C0007", ""))
  expect_equal(x$label, c("UGF 1", "Futaie du haut", "UGF 3", "UGF 4"))
  expect_equal(x$label_par_defaut, c(TRUE, FALSE, TRUE, TRUE))
  expect_equal(x$parcelles, c("A 36", "A 15, A 16", "C 7", ""))
  expect_equal(x$label_cadastre[1], "212000000A0036")
  # Sans numero dans l'identifiant, le nom stocke reste.
  expect_equal(.identites_ug("parcelle_x", "212000000A0036")$label, "212000000A0036")
  expect_equal(.ref_courte(c("212000000AB0007", "21200000AB0007", "libre")), c("212000000AB0007", "AB 7", "libre"))
})
