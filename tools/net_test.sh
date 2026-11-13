#!/usr/bin/env bash
# Teste do multijogador: servidor + 2 clientes headless (Ana e Zeca) na porta 9181.
cd "$(dirname "$0")/.."
G="${GODOT:-$HOME/.local/bin/godot4}"
LOG="${TMPDIR:-/tmp}/bandula_net"; mkdir -p "$LOG"
"$G" --headless --path . res://scenes/server.tscn -- --port=9181 > "$LOG/server.log" 2>&1 & SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
sleep 3
"$G" --headless --fixed-fps 60 --path . --script res://tests/net_client.gd -- --role=A --port=9181 > "$LOG/a.log" 2>&1 & CA=$!
"$G" --headless --fixed-fps 60 --path . --script res://tests/net_client.gd -- --role=B --port=9181 > "$LOG/b.log" 2>&1; RB=$?
wait $CA; RA=$?
grep -h "^\[[AB]\]" "$LOG/a.log" "$LOG/b.log" | grep -v "chat recebido"
[ $RA -eq 0 ] && [ $RB -eq 0 ] && echo "multijogador: OK" || { echo "multijogador: FALHOU (logs em $LOG)"; exit 1; }
