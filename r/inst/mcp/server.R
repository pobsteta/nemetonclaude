# Serveur MCP nemeton pour Claude (stdio).
#
# Les 8 outils de nemetonshiny + les outils des vues (lot 1). Declare dans
# .mcp.json a la racine du plugin. stdout est le canal du protocole : rien ne
# doit y etre ecrit ; les messages partent sur stderr.

suppressPackageStartupMessages(loadNamespace("nemetonclaude"))
nemetonclaude::serveur_mcp()
