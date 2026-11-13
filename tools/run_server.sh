#!/usr/bin/env bash
# Servidor multijogador do Bandula (WebSocket, sem gráficos).
#   tools/run_server.sh            → porta 9080
#   tools/run_server.sh 9500       → outra porta
# Os jogadores ligam-se a ws://<IP-deste-computador>:<porta> (menu «Jogar online»).
set -e
cd "$(dirname "$0")/.."
G="${GODOT:-$HOME/.local/bin/godot4}"
exec "$G" --headless --path . res://scenes/server.tscn -- --port="${1:-9080}"
