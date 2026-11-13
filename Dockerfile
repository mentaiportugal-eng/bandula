# Servidor multijogador do Bandula (Godot headless, WebSocket).
# Render / Fly.io / Railway: a plataforma define PORT e trata do HTTPS → os jogadores
# ligam-se a wss://<serviço> (sem porta).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /var/lib/apt/lists/*

WORKDIR /app
COPY . .
# Importa os recursos uma vez (cria .godot/), para o arranque ser rápido.
RUN godot --headless --path . --import 2>&1 | tail -5; test -d .godot/imported

ENV PORT=9080
EXPOSE 9080
CMD ["godot", "--headless", "--path", ".", "res://scenes/server.tscn"]
