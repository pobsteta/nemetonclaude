# Extracted from test-fonctions-pures.R:161

# prequel ----------------------------------------------------------------------
brut <- list(
  list(nom = "Velars-sur-Ouche", code = "21661", codesPostaux = list("21370"),
       population = 1800L, type = "commune-actuelle"),
  list(nom = "Velars", code = "21999", codesPostaux = list("21000"),
       population = 10L, type = "commune-deleguee", chefLieu = "21500")
)

# test -------------------------------------------------------------------------
dossier <- withr::local_tempdir()
f <- file.path(dossier, "resultats_p1.gpkg")
writeBin(as.raw(1:100), f)
reponse <- .json(list(ok = TRUE, projet = "p1", fichier = f))
local_mocked_bindings(.ns = function(nom) function(projet) {
    if (projet == "inconnu") .json(list(ok = FALSE, erreur = "introuvable")) else reponse
  })
