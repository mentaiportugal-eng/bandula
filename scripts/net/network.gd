extends Node
## Bandula — Network (autoload "Network"). Multijogador online por WebSocket
## (funciona no browser). Um servidor dedicado (Godot headless) reencaminha:
##   • presença: posição, direção, animação, carro e interior de cada jogador (15×/s)
##   • conversa: chat de texto (histórico no HUD + balão sobre o avatar)
## Cada jogador mantém o seu próprio império (economia/lotes/estrelas são locais).
##
## Servidor:  godot4 --headless --path godot/bandula res://scenes/server.tscn -- --port=9080
## Cliente:   ecrã inicial «Jogar online» (ou ...index.html?online=1&nome=Ana)

signal connection_changed(online: bool, status: String)
signal peer_joined(id: int, name: String, look: int)
signal peer_left(id: int, name: String)
signal state_received(id: int, state: Dictionary)
signal chat_received(id: int, name: String, text: String)

const DEFAULT_PORT := 9080
const SEND_RATE := 15.0
const MAX_NAME := 20
const MAX_CHAT := 160
const HANDSHAKE_TIMEOUT := 20.0   # s — telemóveis lentos / separadores em segundo plano (Godot usa 3 s)
## Aparências disponíveis (o índice viaja na rede).
const LOOKS := [
	"res://scenes/characters/governante.scn", "res://scenes/characters/kianda.scn",
	"res://scenes/characters/zeca.scn", "res://scenes/characters/nzinga.scn",
	"res://scenes/characters/mateus.scn", "res://scenes/characters/rosa.scn",
	"res://scenes/characters/sr_antonio.scn", "res://scenes/characters/luena.scn",
]
const LOOK_NAMES := ["Governante", "Kianda", "Zeca", "Nzinga", "Mateus", "Rosa", "Sr. António", "Luena"]
const VEHICLE_KINDS := ["", "buggy", "candongueiro", "guarda"]

var player_name := "Governante"
var look := 0
var peers := {}                 # id → { "name", "look" }
var is_server := false
var _send_t := 0.0
var _last_chat := {}            # (servidor) id → ms da última mensagem
var last_state := {}            # (servidor) id → último estado validado (voz por proximidade)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _drop("Não foi possível ligar ao servidor."))
	multiplayer.server_disconnected.connect(func(): _drop("A ligação ao servidor caiu."))
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		start_server(_port_arg(args))


## Porta: --port=N, senão a variável de ambiente PORT (Render, Fly.io, Railway), senão 9080.
static func _port_arg(args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--port="):
			return int(a.substr(7))
	var env := OS.get_environment("PORT")
	return int(env) if env.is_valid_int() else DEFAULT_PORT


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not is_server


## Endereço por omissão do servidor, por esta ordem:
##   1. ?servidor=wss://... no endereço da página (web)
##   2. bandula/network/server_url no project.godot (servidor de produção, p. ex. no Render)
##   3. o mesmo anfitrião da página na porta 9080 (servidor local / rede de casa)
func default_url() -> String:
	var host := "127.0.0.1"
	var secure := false
	if OS.has_feature("web"):
		var m := RegEx.create_from_string("[?&]servidor=([^&]+)").search(str(JavaScriptBridge.eval("location.search", true)))
		if m:
			return m.get_string(1).uri_decode()
		host = str(JavaScriptBridge.eval("location.hostname", true))
		secure = str(JavaScriptBridge.eval("location.protocol", true)) == "https:"
	var prod := str(ProjectSettings.get_setting("bandula/network/server_url", ""))
	var local := host in ["", "localhost", "127.0.0.1"] or host.begins_with("192.168.") or host.begins_with("10.")
	if prod != "" and not (OS.has_feature("web") and local):
		return prod
	return "%s://%s:%d" % ["wss" if secure else "ws", host if host != "" else "127.0.0.1", DEFAULT_PORT]


static func clean_name(n: String) -> String:
	var s := n.strip_edges().replace("\n", " ").substr(0, MAX_NAME)
	return s if s.length() >= 2 else "Visitante"


# ------------------------------------------------------------------ servidor

func start_server(port: int = DEFAULT_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = HANDSHAKE_TIMEOUT
	var err := peer.create_server(port)
	if err != OK:
		push_error("Bandula: não foi possível abrir o servidor na porta %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("[Bandula] servidor multijogador à escuta em ws://0.0.0.0:%d" % port)
	return OK


func _on_peer_connected(id: int) -> void:
	if is_server:
		print("[Bandula] ligação %d" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server or not peers.has(id):
		return
	var n: String = peers[id].name
	peers.erase(id)
	_last_chat.erase(id)
	last_state.erase(id)
	_peer_left.rpc(id)
	_system("%s saiu de Luanda." % n)
	print("[Bandula] %s saiu (%d online)" % [n, peers.size()])


@rpc("any_peer", "reliable")
func register(name: String, look_index: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var n := clean_name(name)
	peers[id] = {"name": n, "look": clampi(look_index, 0, LOOKS.size() - 1)}
	var list := []
	for pid in peers:
		if pid != id:
			list.append([pid, peers[pid].name, peers[pid].look])
	_peer_list.rpc_id(id, list)
	for pid in peers:
		if pid != id:
			_peer_joined.rpc_id(pid, id, n, peers[id].look)
	_system("%s chegou a Luanda." % n)
	print("[Bandula] %s entrou (%d online)" % [n, peers.size()])


@rpc("any_peer", "unreliable_ordered")
func send_state(s: Dictionary) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var clean := _clean_state(s)
	if clean.is_empty():
		return
	last_state[id] = clean
	for pid in peers:
		if pid != id:
			_peer_state.rpc_id(pid, id, clean)


@rpc("any_peer", "reliable")
func send_chat(text: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_chat.get(id, -10000)) < 600:            # anti-spam
		return
	_last_chat[id] = now
	var t := text.strip_edges().replace("\n", " ").substr(0, MAX_CHAT)
	if t != "":
		_chat.rpc(id, peers[id].name, t)


## Valida o estado recebido (tipos, limites, valores permitidos) antes de o reencaminhar.
static func _clean_state(s: Dictionary) -> Dictionary:
	var p = s.get("p")
	if not p is Vector3 or absf(p.x) > 450.0 or absf(p.z) > 450.0 or p.y < -450.0 or p.y > 120.0:
		return {}
	var st := str(s.get("st", "walk"))
	if not st in ["walk", "air", "sit", "car"]:
		st = "walk"
	var v := str(s.get("v", ""))
	if not v in VEHICLE_KINDS:
		v = ""
	return {
		"p": p, "y": wrapf(float(s.get("y", 0.0)), -PI, PI), "sp": clampf(float(s.get("sp", 0.0)), 0.0, 45.0),
		"st": st, "v": v, "r": str(s.get("r", "")).substr(0, 48),
	}


func _system(text: String) -> void:
	_chat.rpc(0, "", text)


# ------------------------------------------------------------------ cliente

func join(url: String, name: String, look_index: int) -> Error:
	player_name = clean_name(name)
	look = clampi(look_index, 0, LOOKS.size() - 1)
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = HANDSHAKE_TIMEOUT
	var err := peer.create_client(url)
	if err != OK:
		connection_changed.emit(false, "Endereço inválido: %s" % url)
		return err
	multiplayer.multiplayer_peer = peer
	connection_changed.emit(false, "A ligar a %s…" % url)
	return OK


func leave() -> void:
	_drop("Offline")


func say(text: String) -> void:
	if is_online():
		send_chat.rpc_id(1, text)


func _on_connected() -> void:
	register.rpc_id(1, player_name, look)
	connection_changed.emit(true, "Online como %s" % player_name)


func _drop(msg: String) -> void:
	for id in peers.keys():
		peer_left.emit(id, peers[id].name)
	peers.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_changed.emit(false, msg)


@rpc("authority", "reliable")
func _peer_list(list: Array) -> void:
	for e in list:
		peers[int(e[0])] = {"name": str(e[1]), "look": int(e[2])}
		peer_joined.emit(int(e[0]), str(e[1]), int(e[2]))


@rpc("authority", "reliable")
func _peer_joined(id: int, name: String, look_index: int) -> void:
	peers[id] = {"name": name, "look": look_index}
	peer_joined.emit(id, name, look_index)


@rpc("authority", "reliable")
func _peer_left(id: int) -> void:
	var n: String = peers.get(id, {}).get("name", "")
	peers.erase(id)
	peer_left.emit(id, n)


@rpc("authority", "unreliable_ordered")
func _peer_state(id: int, s: Dictionary) -> void:
	if peers.has(id):
		state_received.emit(id, s)


@rpc("authority", "reliable")
func _chat(id: int, name: String, text: String) -> void:
	chat_received.emit(id, name, text)


func _process(delta: float) -> void:
	if is_server or not is_online():
		return
	_send_t += delta
	if _send_t < 1.0 / SEND_RATE:
		return
	_send_t = 0.0
	var p = GameManager.player
	if p != null and is_instance_valid(p):
		send_state.rpc_id(1, _gather(p))


## Estado do jogador local para os outros (posição, direção, animação, carro, interior).
func _gather(p: Node) -> Dictionary:
	var s := {"p": p.global_position, "y": p.visual.global_rotation.y, "sp": p.current_speed(), "st": "walk", "v": "", "r": ""}
	if p.seat != null:
		s.st = "sit"
	elif p.vehicle != null:
		var v: Node3D = p.vehicle
		s.st = "car"
		s.p = v.global_position
		s.y = atan2(v.global_basis.z.x, v.global_basis.z.z)
		s.v = {"Buggy Urbano": "buggy", "Candongueiro": "candongueiro", "Viatura da Guarda": "guarda"}.get(v.display_name, "buggy")
	elif not p.is_on_floor():
		s.st = "air"
	if Interiors.is_inside() and Interiors.portal != null:
		s.r = str(Interiors.portal.portal_id)
	return s
