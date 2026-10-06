#!/usr/bin/env bash
# Essaie nemetonClaude de bout en bout sur cette machine.
#
# Usage : outils/essayer.sh [tout|r|vues|apercu|claude]   (défaut : tout)
#
#   r       installe nemetonshiny (>= 1.0.0) si besoin, teste puis installe le
#           paquet R du connecteur (r/)
#   vues    tests de bout en bout des vues (Chromium) et assemblage des
#           aperçus sur données fictives dans .apercu/
#   apercu  sert .apercu/ en local (Ctrl-C pour arrêter)
#   claude  lance Claude Code avec le plugin chargé pour cette session
#   tout    r, vues, puis apercu
#
# Variables : NEMETONSHINY_DIR (défaut ../nemetonshiny), PORT (défaut 8765).

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nemetonshiny_dir="${NEMETONSHINY_DIR:-$racine/../nemetonshiny}"
port="${PORT:-8765}"

etape() { printf '\n\033[1;32m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
echec() { printf '\033[1;31mErreur : %s\033[0m\n' "$*" >&2; exit 1; }

exiger() { command -v "$1" >/dev/null 2>&1 || echec "$1 introuvable dans le PATH."; }

etape_r() {
  exiger Rscript
  etape "Connecteur R"
  local version
  version="$(Rscript -e 'cat(tryCatch(as.character(packageVersion("nemetonshiny")), error = function(e) "0"))')"
  if Rscript -e 'quit(status = !(package_version(commandArgs(TRUE)) >= "1.0.0"))' "$version"; then
    info "nemetonshiny $version déjà installé."
  else
    [ -d "$nemetonshiny_dir" ] || echec "nemetonshiny $version < 1.0.0 et dépôt introuvable : $nemetonshiny_dir (définir NEMETONSHINY_DIR)."
    info "nemetonshiny $version < 1.0.0 : installation depuis $nemetonshiny_dir"
    R CMD INSTALL --no-test-load "$nemetonshiny_dir"
  fi

  info "Paquets suggérés (mcptools, happign, devtools)"
  Rscript -e 'manque <- setdiff(c("mcptools", "happign", "devtools"), rownames(installed.packages()))
              if (length(manque)) install.packages(manque, repos = "https://cloud.r-project.org")'

  info "Tests du paquet"
  (cd "$racine/r" && Rscript -e 'res <- as.data.frame(devtools::test(stop_on_failure = TRUE))')

  info "Installation de nemetonclaude"
  R CMD INSTALL "$racine/r"
}

etape_vues() {
  exiger node
  exiger npm
  etape "Vues"
  cd "$racine"
  [ -d node_modules/playwright ] || npm install --no-audit --no-fund
  npx playwright install chromium >/dev/null
  npm test
  for vue in selection atlas calcul; do
    node outils/assembler-vue.mjs "$vue" "vues/exemples/$vue" ".apercu/$vue"
  done
}

etape_apercu() {
  [ -d "$racine/.apercu/atlas" ] || etape_vues
  etape "Aperçu des vues (données fictives)"
  info "Sélection : http://localhost:$port/selection/"
  info "Atlas     : http://localhost:$port/atlas/"
  info "Calcul    : http://localhost:$port/calcul/"
  info "Ctrl-C pour arrêter."
  cd "$racine/.apercu"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$port" --bind 127.0.0.1
  else
    npx --yes serve -l "$port"
  fi
}

etape_claude() {
  exiger claude
  Rscript -e 'quit(status = !requireNamespace("nemetonclaude", quietly = TRUE))' \
    || echec "paquet R nemetonclaude absent : lancer d'abord outils/essayer.sh r"
  etape "Claude Code avec le plugin nemeton"
  info "Essayer : « Côte-d'Or, Velars-sur-Ouche, je veux créer un projet »"
  info "ou, sur un projet calculé : « ouvre l'Atlas de <projet> »"
  exec claude --plugin-dir "$racine"
}

case "${1:-tout}" in
  r) etape_r ;;
  vues) etape_vues ;;
  apercu) etape_apercu ;;
  claude) etape_claude ;;
  tout)
    etape_r
    etape_vues
    printf '\n   Pour le parcours dans Claude : outils/essayer.sh claude\n'
    etape_apercu
    ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echec "commande inconnue : $1 (tout, r, vues, apercu, claude)" ;;
esac
