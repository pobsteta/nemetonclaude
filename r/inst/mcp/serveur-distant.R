# Serveur MCP nemeton distant (HTTP, authentification Keycloak), pour un
# connecteur claude.ai. Configuration par variables d'environnement : voir
# ?nemetonclaude::config_distant et deploiement/ a la racine du depot.
#
#   NEMETON_CLAUDE_URL=https://nemeton.example.org \
#   NEMETON_KEYCLOAK_URL=https://auth.example.org/realms/nemeton \
#   NEMETON_CLAUDE_SECRET=... Rscript serveur-distant.R

suppressPackageStartupMessages(loadNamespace("nemetonclaude"))
nemetonclaude::serveur_mcp_distant()
