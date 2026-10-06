// Tests unitaires de outils/version.mjs (calcul de version, notes de NEWS.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { suivante, notes } from "../../outils/version.mjs";

test("suivante monte le bon numéro et remet les suivants à zéro", () => {
  assert.equal(suivante("0.4.7", "correctif"), "0.4.8");
  assert.equal(suivante("0.4.7", "mineure"), "0.5.0");
  assert.equal(suivante("0.4.7", "majeure"), "1.0.0");
  assert.equal(suivante("0.4.7", "2.3.4"), "2.3.4");
});

test("notes extrait la section d'une version, sans attraper un numéro plus long", () => {
  const news = [
    "# nemetonclaude 0.1.10 (2026-11-01)", "", "- Dix.", "",
    "# nemetonclaude 0.1.1 (2026-10-07)", "", "- Un.", "- Deux.", "",
    "# nemetonclaude 0.1.0 (2026-10-06)", "", "- Zéro."
  ].join("\n");
  assert.equal(notes(news, "0.1.1"), "- Un.\n- Deux.");
  assert.equal(notes(news, "0.1.0"), "- Zéro.");
  assert.equal(notes(news, "0.2.0"), "");
});
