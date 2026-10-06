# Fonctions geometriques de la vue Selection, sur des parcelles synthetiques.

parcelles_test <- function() {
  carre <- function(x, y) sf::st_polygon(list(rbind(c(x, y), c(x + 0.001, y), c(x + 0.001, y + 0.001),
                                                    c(x, y + 0.001), c(x, y))))
  sf::st_sf(
    id = c("99999000AB0002", "99999000AB0010", "99999000AC0001"),
    section = c("AB", "AB", "AC"), numero = c("2", "10", "1"),
    contenance = c(7600, 7612.4, 7590), code_insee = "99999",
    geometry = sf::st_sfc(carre(4.9, 47.3), carre(4.901, 47.3), carre(4.9, 47.301), crs = 4326)
  )
}

test_that(".parcelles_pour_vue suit le contrat et trie par section puis numero", {
  p <- .parcelles_pour_vue(parcelles_test())
  expect_equal(names(sf::st_drop_geometry(p)), c("idu", "section", "numero", "contenance"))
  expect_equal(p$numero, c("2", "10", "1"))
  expect_equal(p$contenance, c(7600, 7612, 7590))
})

test_that(".resume_sections compte et somme en hectares", {
  s <- .resume_sections(.parcelles_pour_vue(parcelles_test()))
  expect_equal(s$section, c("AB", "AC"))
  expect_equal(s$n, c(2L, 1L))
  expect_equal(s$surface_ha, c(1.52, 0.76))
})

test_that(".simplifier_wgs84 garde les parcelles et rend du WGS84", {
  p <- .simplifier_wgs84(.parcelles_pour_vue(parcelles_test()), 0.5, 2154)
  expect_equal(nrow(p), 3)
  expect_equal(sf::st_crs(p)$epsg, 4326L)
  expect_equal(length(.emprise(p)), 4)
})
