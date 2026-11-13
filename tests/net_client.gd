extends SceneTree
## Cliente de teste do multijogador (2 processos + servidor):
##   godot4 --headless --path godot/bandula res://scenes/server.tscn -- --port=9181 &
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/net_client.gd -- --role=A --port=9181 &
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/net_client.gd -- --role=B --port=9181
## A («Ana») anda, fala e entra num restaurante; B («Zeca») confere o que vê.

var main: Node3D
var player: CharacterBody3D
var net: Node
var im: Node
var role := "A"
var port := 9181
var results := []
var chats := []
var t_both := -1.0
var done := {}
var spot := Vector3(15, 0.4, -19)
var voice_n := 0
var voice_rms := 0.0
var voice_at_6 := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--port="):
			port = int(a.substr(7))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	net = root.get_node("Network")
	im = root.get_node("Interiors")
	net.chat_received.connect(func(id, n, t): chats.append([id, n, t]))
	root.get_node("Voice").voice_received.connect(_on_voice)


func _on_voice(_id: int, frames: PackedVector2Array) -> void:
	voice_n += 1
	var e := 0.0
	for f in frames:
		e += f.x * f.x
	voice_rms = sqrt(e / frames.size())


## Tom de 440 Hz (amplitude 0.5) a 16 kHz — substitui o microfone nos testes headless.
func tone(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for i in int(16000 * seconds):
		a.append(0.5 * sin(TAU * 440.0 * i / 16000.0))
	return a


func ok(name: String, cond: bool, info := "") -> void:
	results.append(cond)
	print("[%s] %s %s%s" % [role, "✔" if cond else "✘", name, ("  (" + info + ")") if info != "" else ""])


## Relógio real: os dois processos partilham-no. (O tempo de jogo com --fixed-fps corre a
## velocidades diferentes em cada processo e dessincronizava o guião da Ana e do Zeca.)
func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func once(key: String, at: float) -> bool:
	if done.has(key) or now() - t_both < at:
		return false
	done[key] = true
	return true


## Verificação que deve acabar por ser verdade: tenta entre `from` e `to` s (relógio real).
func expect(key: String, from: float, to: float, name: String, cond: Callable, info := Callable()) -> void:
	if done.has(key) or now() - t_both < from:
		return
	var c: bool = cond.call()
	if c or now() - t_both >= to:
		done[key] = true
		ok(name, c, info.call() if info.is_valid() else "")


func remote() -> Node:
	var rp := main.get_node("RemotePlayers")
	return rp.avatars.values()[0] if rp.avatars.size() > 0 else null


func restaurant() -> Node:
	for p in get_nodes_in_group("portals"):
		if p.mode == "fade" and p.interior_type == "restaurante":
			return p
	return null


func _process(d: float) -> bool:
	if not done.has("join"):
		done["join"] = true                              # autoloads só estão na árvore a partir do 1.º frame
		net.join("ws://127.0.0.1:%d" % port, "Ana" if role == "A" else "Zeca", 1 if role == "A" else 2)
		return false
	if t_both < 0.0:
		if net.is_online() and net.peers.size() >= 1:
			t_both = now()                               # os dois estão ligados: começa o guião
			ok("ligado ao servidor e vê o outro jogador", true, "%s online" % str(net.peers.values().map(func(p): return p.name)))
			player.global_position = spot if role == "A" else spot + Vector3(-6, 0, 0)
		elif Time.get_ticks_msec() > 90000:
			ok("ligado ao servidor", false)
			quit(1)
		return false
	if role == "A":
		if not done.has("entra"):                        # fica no sítio (o trânsito pode empurrá-la)
			player.global_position = spot
			player.velocity = Vector3.ZERO
		if once("fala", 2.0):
			net.say("Olá, Luanda!")
		if once("voz_rua", 3.5):
			root.get_node("Voice").send_pcm(tone(0.6))    # 10 pacotes, perto do Zeca
		if once("voz_dentro", 8.5):
			root.get_node("Voice").send_pcm(tone(0.6))    # dentro do restaurante: o Zeca está na rua
		if once("entra", 7.0):
			var p := restaurant()
			player.global_position = p.outside_transform().origin
			im.enter(p, player)
		expect("chat", 3.0, 8.0, "recebeu a mensagem do Zeca", func(): return chats.any(func(c): return c[1] == "Zeca" and c[2] == "Bom dia, Ana!"))
		expect("sistema", 0.0, 8.0, "mensagens do sistema (entradas)", func(): return chats.any(func(c): return c[0] == 0 and "chegou a Luanda" in c[2]))
		expect("zeca_dentro", 11.0, 16.0, "vê o Zeca dentro do restaurante", func():
			var r := remote()
			return r != null and r.visible and r.player_name == "Zeca")
		if done.has("zeca_dentro") and once("fim", 18.0):      # fica ligada até o Zeca acabar (17 s)
			_finish()
	else:
		if once("fala", 3.0):
			net.say("Bom dia, Ana!")
		var r := remote()
		expect("nome", 1.0, 6.5, "vê a Ana com o nome por cima", func(): return r != null and r.visible and r.name_label.text == "Ana")
		expect("pos", 1.0, 6.5, "posição da Ana sincronizada", func(): return r != null and r.global_position.distance_to(spot) < 1.0,
			func(): return "%.2f m" % (r.global_position.distance_to(spot) if r else -1.0))
		expect("balao", 2.0, 6.5, "recebeu «Olá, Luanda!» com balão", func(): return r != null and r.bubble.visible and chats.any(func(c): return c[1] == "Ana" and c[2] == "Olá, Luanda!"),
			func(): return "%d msgs" % chats.size())
		expect("voz", 3.5, 6.8, "ouve a voz da Ana (microfone)", func(): return voice_n >= 8, func(): return "%d pacotes" % voice_n)
		if done.has("voz") and once("voz_det", 0.0):
			ok("voz descodificada com o volume certo", voice_rms > 0.3 and voice_rms < 0.42, "RMS %.3f (esperado 0.354)" % voice_rms)
			ok("nome da Ana fica verde a falar / som 3D no avatar", r != null and r.voice != null)
		if once("marca", 8.0):                           # a Ana já entrou (7 s); fala lá dentro aos 8,5 s
			voice_at_6 = voice_n
		expect("fora_sala", 7.0, 10.0, "a Ana entrou no restaurante: não aparece na rua", func(): return r != null and not r.visible and r.room != "",
			func(): return "sala %s" % (r.room if r else "?"))
		if once("fora", 10.0):
			ok("voz por proximidade: não ouve a Ana dentro do restaurante", voice_n == voice_at_6, "%d → %d" % [voice_at_6, voice_n])
			var p := restaurant()
			player.global_position = p.outside_transform().origin
			im.enter(p, player)
		expect("dentro", 11.0, 15.0, "no mesmo restaurante: vê a Ana", func(): return r != null and r.visible)
		if once("fim", 17.0):                            # fica ligado até a Ana terminar as verificações
			_finish()
	return false


func _finish() -> void:
	print("[%s] chat recebido: %s" % [role, str(chats)])
	var fails := results.filter(func(x): return not x).size()
	print("[%s] RESULTADO: %d/%d ok" % [role, results.size() - fails, results.size()])
	quit(1 if fails > 0 else 0)
