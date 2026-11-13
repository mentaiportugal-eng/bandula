extends SceneTree
## Teste de fumo do Bandula (corre o jogo real, sem janela):
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/smoke_test.gd

var main: Node3D
var player: CharacterBody3D
var gm: Node
var frame := 0
var step := 0
var t0 := 0
var mark := {}
var results := []
var busted_fine := -1
var escaped_ok := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	gm = root.get_node("GameManager")
	gm.busted.connect(func(f): busted_fine = f)
	gm.escaped.connect(func(): escaped_ok = true)


func ok(name: String, cond: bool, info := "") -> void:
	results.append([name, cond, info])
	print(("  ✔ " if cond else "  ✘ ") + name + ("  (" + info + ")" if info != "" else ""))


func buggy() -> VehicleBody3D:
	for v in main.get_node("Traffic").get_children():
		if v is VehicleBody3D and v.display_name == "Buggy Urbano" and v.ai_mode == "parked":
			return v
	return null


func _process(_delta: float) -> bool:
	frame += 1
	var f := frame - t0
	match step:
		0:   # assentar
			if f == 60:
				ok("jogador no chão", player.is_on_floor(), "y=%.2f" % player.global_position.y)
				ok("avatar com AnimationTree", player.avatar.anim_tree != null)
				ok("lotes registados", gm.plots.size() > 100, str(gm.plots.size()))
				mark.p = player.global_position
				Input.action_press("move_forward")
				_next()
		1:   # andar 1 s
			if f == 60:
				Input.action_release("move_forward")
				ok("anda para a frente", player.global_position.distance_to(mark.p) > 2.5, "%.1f m" % player.global_position.distance_to(mark.p))
				mark.y = player.global_position.y
				mark.min_sy = 1.0
				Input.action_press("jump")
				_next()
		2:   # saltar e aterrar
			if f == 2:
				Input.action_release("jump")
			mark.min_sy = minf(mark.min_sy, player.visual.scale.y)
			if f == 18:
				mark.top = player.global_position.y
			if f == 70:
				ok("salta", mark.top > mark.y + 0.6, "+%.2f m" % (mark.top - mark.y))
				ok("squash ao aterrar", mark.min_sy < 0.9, "escala y min %.2f" % mark.min_sy)
				var b := buggy()
				ok("buggy estacionado", b != null)
				player.global_position = b.global_position + b.global_basis.x * 2.0
				_next()
		3:
			if f == 5:
				var b := buggy()
				player.enter_vehicle(b)
				mark.v = b
				mark.p = b.global_position
				mark.yaw = atan2(b.global_basis.z.x, b.global_basis.z.z)
				ok("entra no veículo", player.vehicle == b and player.visual.get_parent() == b.seat)
				Input.action_press("move_forward")
			if f == 185:
				var b: VehicleBody3D = mark.v
				var moved: Vector3 = b.global_position - mark.p
				ok("acelera (3 s)", b.speed_kmh() > 40.0, "%.0f km/h" % b.speed_kmh())
				ok("anda para a frente do modelo (+Z)", moved.dot(b.global_basis.z) > 5.0, "forward_sign=%s · desloc. %.1f m" % [b.forward_sign, moved.dot(b.global_basis.z)])
				Input.action_press("move_left")
				mark.yaw = atan2(b.global_basis.z.x, b.global_basis.z.z)
			if f == 215:
				Input.action_release("move_left")
				var b: VehicleBody3D = mark.v
				var yaw := atan2(b.global_basis.z.x, b.global_basis.z.z)
				ok("vira à esquerda com A", wrapf(yaw - mark.yaw, -PI, PI) > 0.15, "Δyaw %.2f" % wrapf(yaw - mark.yaw, -PI, PI))
				Input.action_press("handbrake")
				Input.action_press("move_right")
				mark.drift = 0.0
			if f > 215 and f < 260:
				var b: VehicleBody3D = mark.v
				mark.drift = maxf(mark.drift, absf(b.linear_velocity.dot(b.global_basis.x)))
			if f == 260:
				Input.action_release("handbrake")
				Input.action_release("move_right")
				Input.action_release("move_forward")
				ok("drift com travão de mão", mark.drift > 2.0, "lateral %.1f m/s" % mark.drift)
				Input.action_press("move_back")
				mark.min_kmh = 999.0
			if f > 260 and f < 400:
				mark.min_kmh = minf(mark.min_kmh, (mark.v as VehicleBody3D).speed_kmh())
			if f == 400:
				Input.action_release("move_back")
				var b: VehicleBody3D = mark.v
				ok("trava até parar (S)", mark.min_kmh < 3.0, "mín. %.0f km/h · depois marcha-atrás %.0f km/h" % [mark.min_kmh, b.speed_kmh()])
				player.exit_vehicle()
				ok("sai do veículo", player.vehicle == null and player.visual.get_parent() == player)
				b.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), b.global_position + Vector3(0, 2.5, 0))
				_next()
		4:   # auto-desvirar
			if f == 200:
				var b: VehicleBody3D = mark.v
				ok("auto-desvirar", b.global_basis.y.y > 0.8, "up.y %.2f" % b.global_basis.y.y)
				# economia
				var free_id := ""
				for id in gm.plots:
					if gm.plots[id].owner == "" and gm.plots[id].district == "centro":
						free_id = id
						break
				var t: float = gm.treasury
				var r: Dictionary = gm.buy_plot(free_id)
				ok("compra lote na Baixa", r.ok and gm.treasury < t, "%s · Kz %d" % [free_id, gm.treasury])
				r = gm.build_on_plot(free_id, "comercio")
				ok("constrói comércio", r.ok and gm.plots[free_id].node._building != null)
				mark.tr = gm.treasury
				gm._new_day()
				ok("rendimento diário", gm.treasury > mark.tr, "saldo %+.0f" % gm.last_report.net)
				var ilha := ""
				for id in gm.plots:
					if gm.plots[id].district == "ilha":
						ilha = id
				ok("lotes na Ilha de Luanda", ilha != "" and gm.plots[ilha].area == "Ilha de Luanda")
				# procurado
				gm.report_offense("police_carjack")
				gm.report_offense("police_carjack")
				ok("estrelas de procurado", gm.wanted_level >= 2, "%d estrelas" % gm.wanted_level)
				_next()
		5:   # a Guarda aparece e persegue
			if f == 400:
				var cops := get_nodes_in_group("police").filter(func(c): return c.ai_mode == "chase")
				ok("viaturas da Guarda em perseguição", cops.size() >= 1, "%d viaturas" % cops.size())
				ok("sirene ligada", cops.size() > 0 and cops[0].siren.visible)
				if cops.size() > 0:
					var c: VehicleBody3D = cops[0]
					c.global_position = player.global_position + Vector3(4, 1, 0)
					c.linear_velocity = Vector3.ZERO
					c.start_ai("parked")
					c.driver = "npc"
				_next()
		6:   # detido
			if busted_fine >= 0 or f > 400:
				var door: Vector3 = main.get_node("Luanda/Spawns/PortaEsquadra").global_position
				ok("DETIDO (multa)", busted_fine > 0, "Kz %d" % busted_fine)
				ok("levado à esquadra", player.global_position.distance_to(door) < 3.0)
				ok("estrelas limpas", gm.wanted_level == 0)
				gm.report_offense("police_carjack")
				for c in get_nodes_in_group("police"):
					c.global_position += Vector3(0, 0, 400)
				_next()
		7:   # escapar
			if escaped_ok or f > 1200:
				ok("ESCAPOU", escaped_ok, "%d frames" % f)
				var fails := results.filter(func(r): return not r[1]).size()
				print("\nRESULTADO: %d/%d ok" % [results.size() - fails, results.size()])
				quit(1 if fails > 0 else 0)
	return false


func _next() -> void:
	step += 1
	t0 = frame
