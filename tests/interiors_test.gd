extends SceneTree
## Teste dos interiores (portas, mobiliário, lojas, NPCs):
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/interiors_test.gd

var main: Node3D
var player: CharacterBody3D
var gm: Node
var im: Node
var hud: CanvasLayer
var frame := 0
var step := 0
var t0 := 0
var m := {}
var results := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	hud = main.get_node("HUD")
	gm = root.get_node("GameManager")
	im = root.get_node("Interiors")


func ok(name: String, cond: bool, info := "") -> void:
	results.append(cond)
	print(("  ✔ " if cond else "  ✘ ") + name + ("  (" + info + ")" if info != "" else ""))


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func portal(mode: String, kind := "") -> Node:
	for p in get_nodes_in_group("portals"):
		if p.mode == mode and (kind == "" or p.interior_type == kind):
			return p
	return null


func go(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO


func _process(_d: float) -> bool:
	frame += 1
	var f := frame - t0
	match step:
		0:
			if f == 60:
				var p := portal("fade", "restaurante")
				ok("portas nos comércios da Baixa", get_nodes_in_group("portals").size() >= 5, "%d portas" % get_nodes_in_group("portals").size())
				m.portal = p
				go(p.outside_transform().origin)
				_next()
		1:
			if f == 10:
				ok("prompt à porta", player._interact_target == m.portal, player._prompt)
				press("interact")
			if f == 60:
				var it: Node3D = im.current
				ok("entra (fade)", im.is_inside() and player.interior == it and player.global_position.y < -300.0, "%s · y=%.0f" % [it.display_name if it else "-", player.global_position.y])
				var clients: Array = it.patrons()
				var seated := clients.filter(func(n): return n.state == "seated").size()
				ok("atendente + clientes sentados", clients.size() >= 2 and seated >= 1, "%d NPCs, %d sentados" % [clients.size(), seated])
				m.interior = it
				it.spawn_interval = Vector2(0.5, 0.6)                      # acelera a chegada de clientes
				var free: Array = it.free_seats()
				m.seat = free[0]
				go(m.seat.approach_position())
				_next()
		2:
			if f == 10:
				player.sit_on(m.seat)
			if f == 40:
				var sp: Vector3 = m.seat.sit_transform().origin
				var state: String = player.avatar.anim_tree.get("parameters/playback").get_current_node()
				ok("senta na cadeira", player.seat == m.seat and player.global_position.distance_to(sp) < 0.05, "anim %s" % state)
				ok("animação Sit", state == "Sit")
				ok("câmara acolhedora", player.camera_rig.profile == "seated")
				Input.action_press("move_forward")
			if f == 42:
				Input.action_release("move_forward")
				ok("W levanta", player.seat == null and m.seat.is_free())
				var counter: Node3D = m.interior.get_node("Balcao")
				go(counter.global_position + counter.global_basis.z * 1.3)
				_next()
		3:
			if f == 10:
				ok("prompt do balcão", player._interact_target != null and player._interact_target.kind == "counter", player._prompt)
				press("interact")
			if f == 15:
				ok("abre a loja", hud.shop.visible and hud.shop_items.get_child_count() == 5, hud.shop_title.text)
				gm.energy = 40.0
				m.t = gm.treasury
				var first: Button = hud.shop_items.get_child(0)
				first.pressed.emit()
			if f == 20:
				ok("compra desconta Kz e dá energia", gm.treasury == m.t - 120 and gm.energy > 80.0, "Kz %d · energia %d" % [gm.treasury, gm.energy])
				var r: Dictionary = gm.purchase("restaurante", m.interior.place_id, "socio")
				ok("torna-se sócio", r.ok and gm.investments >= 120.0, "+Kz %d/dia" % gm.investments)
				r = gm.purchase("restaurante", m.interior.place_id, "socio")
				ok("sociedade é única", not r.ok, r.get("reason", ""))
				gm._new_day()
				ok("lucro do restaurante no relatório", gm.last_report.buildings >= 120.0, "prédios+investimentos Kz %d" % gm.last_report.buildings)
				press("interact")
			if f == 25:
				ok("E fecha a loja", not hud.shop.visible)
				m.walked = false
				_next()
		4:   # um cliente entra a pé e senta-se
			for n in m.interior.patrons():
				if n.state == "walk_in":
					m.walked = true
					m.walker = n
			if m.has("walker") and is_instance_valid(m.walker) and m.walker.state == "seated":
				ok("cliente entra e senta-se", true, "%.1f s" % (f / 60.0))
				_next()
			elif f > 1500:
				ok("cliente entra e senta-se", false, "andou=%s" % m.walked)
				_next()
		5:
			if f == 1:
				go(m.interior.get_node("Saida").global_position)
			if f == 10:
				press("interact")
			if f == 60:
				ok("sai para a rua", not im.is_inside() and player.global_position.distance_to(m.portal.outside_transform().origin) < 0.5)
				var p := portal("seamless")
				m.ilha = p
				go(p.outside_transform().origin)
				_next()
		6:   # restaurante da Ilha, sem fade
			if f == 10:
				press("interact")
			if f == 12:
				var shell: Node3D = m.ilha.shell()
				var hidden := shell.find_children("*", "MeshInstance3D", true, false).all(func(mi): return not mi.visible)
				ok("entra sem fade (seamless)", im.is_inside() and player.global_position.distance_to(shell.global_position) < 8.0, im.current.display_name)
				ok("casco escondido, interior no lugar", hidden and im.current.global_position.distance_to(shell.global_position) < 0.01)
				go(im.current.get_node("Saida").global_position)
			if f == 22:
				press("interact")
			if f == 26:
				var shell: Node3D = m.ilha.shell()
				ok("sai e o edifício volta", not im.is_inside() and shell.find_children("*", "MeshInstance3D", true, false)[0].visible)
				go(m.portal.outside_transform().origin)
			if f == 36:
				press("interact")
			if f == 90:
				gm.report_offense("police_carjack")
				gm.bust()
			if f == 95:
				var door: Vector3 = main.get_node("Luanda/Spawns/PortaEsquadra").global_position
				ok("detido dentro do restaurante → esquadra", not im.is_inside() and player.global_position.distance_to(door) < 3.0)
				var fails := results.filter(func(r): return not r).size()
				print("\nRESULTADO: %d/%d ok" % [results.size() - fails, results.size()])
				quit(1 if fails > 0 else 0)
	return false


func _next() -> void:
	step += 1
	t0 = frame
