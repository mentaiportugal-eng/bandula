extends SceneTree
## Teste de prédios: tamanhos/divisões, mobília do jogador, Fortaleza Shopping, esquadra.
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/buildings_test.gd

var main: Node3D
var player: CharacterBody3D
var gm: Node
var im: Node
var deco: Node3D
var frame := 0
var step := 0
var t0 := 0
var m := {}
var results := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	deco = main.get_node("Decorator")
	gm = root.get_node("GameManager")
	im = root.get_node("Interiors")


func ok(name: String, cond: bool, info := "") -> void:
	results.append(cond)
	print(("  ✔ " if cond else "  ✘ ") + name + ("  (" + info + ")" if info != "" else ""))


func free_plot(district: String, skip := "") -> String:
	for id in gm.plots:
		if gm.plots[id].owner == "" and gm.plots[id].district == district and id != skip:
			return id
	return ""


func portal_of(plot_id: String) -> Node:
	for p in get_nodes_in_group("portals"):
		if p.portal_id == plot_id:
			return p
	return null


func enter(p: Node) -> void:
	player.global_position = p.outside_transform().origin
	im.enter(p, player)


func rooms(interior: Node) -> Array:
	return interior.get_children().filter(func(n): return n.name.begins_with("Divisao_")).map(func(n): return n.text)


func furniture_count(interior: Node) -> int:
	var c := 0
	for n in interior.find_children("*", "", true, false):
		if n.has_meta("furniture_entry"):
			c += 1
	return c


## Põe a peça-fantasma num ponto local do interior e coloca-a.
func place(fid: String, local: Vector3, yaw := 0.0) -> bool:
	var idx := 0
	for i in gm.FURNITURE.size():
		if gm.FURNITURE[i].id == fid:
			idx = i
	deco.select(idx)
	deco.yaw = yaw
	var pos: Vector3 = im.current.to_global(local)
	deco.ghost.global_position = pos
	deco.valid = deco._fits(im.current, pos)
	var before: int = gm.plots[im.current.owner_plot_id].furniture.size()
	deco.place()
	return gm.plots[im.current.owner_plot_id].furniture.size() == before + 1


func _process(_d: float) -> bool:
	frame += 1
	var f := frame - t0
	match step:
		0:
			if f == 60:
				var st := main.get_node_or_null("Luanda/Marcos/EsquadraIngombota")
				ok("Esquadra da Ingombota na cidade", st != null, "viaturas: %d" % st.find_children("*", "VehicleBody3D", true, false).size())
				ok("Fortaleza Shopping no morro", main.get_node_or_null("Luanda/Marcos/FortalezaShopping") != null)
				enter(portal_of("fortaleza-shopping"))
				_next()
		1:
			if f == 60:
				var it: Node3D = im.current
				var counters: Array = it.counters()
				var names: Array = counters.map(func(c): return c.place_name)
				ok("entra no Fortaleza Shopping", it != null and it.display_name == "Fortaleza Shopping")
				ok("6 lojas com balcão", counters.size() == 6, ", ".join(names))
				ok("praça da alimentação", it.seats().size() >= 18, "%d lugares" % it.seats().size())
				var clerks: int = it.patrons().filter(func(n): return n.mode == "clerk").size()
				ok("atendentes nas lojas", clerks == 6)
				var t: float = gm.treasury
				var r: Dictionary = gm.purchase("boutique", it.place_id + ":Moda Luanda", "camisa")
				ok("compra na boutique Moda Luanda", r.ok and gm.treasury == t - 350)
				im.exit(player, true)
				# constrói um restaurante grande
				gm.treasury = 20000.0
				m.shop = free_plot("centro")
				gm.buy_plot(m.shop)
				r = gm.build_on_plot(m.shop, "comercio", "g", "restaurante")
				ok("constrói restaurante grande", r.ok and gm.plots[m.shop].size == "g")
				_next()
		2:
			if f == 5:
				var b: Node = gm.plots[m.shop].node._building
				ok("exterior do tamanho escolhido", b.name == "comercio_g" or b.scene_file_path.ends_with("comercio_g.scn"), b.scene_file_path.get_file())
				var p := portal_of(m.shop)
				ok("porta do negócio do jogador", p != null and p.generated)
				enter(p)
			if f == 60:
				var it: Node3D = im.current
				ok("interior com divisões", rooms(it).size() >= 4, ", ".join(rooms(it)))
				ok("fechado sem balcão (sem clientes)", it.patrons().is_empty() and gm.plot_income(gm.plots[m.shop]).income == 0.0)
				deco.start()
				ok("modo Decoração", deco.active)
				var b: Vector2 = it.get_meta("bounds")
				var placed := place("balcao", Vector3(0, 0, -0.5))          # encostado à parede do salão
				ok("coloca balcão", placed, "Kz %d" % gm.treasury)
				var n := 0
				for x in [-3.0, -1.5, 1.5, 3.0]:
					if place("cadeira", Vector3(x, 0, 1.5), PI):
						n += 1
				place("mesa_redonda", Vector3(0, 0, 1.5))
				ok("coloca cadeiras e mesa", n == 4)
				ok("não cabe dentro da parede", not place("estante", Vector3(b.x / 2.0, 0, 0)))
				var inc: Dictionary = gm.plot_income(gm.plots[m.shop])
				ok("rendimento com o recheio", inc.income > gm.building_info(gm.plots[m.shop]).income, "Kz %d/dia · %s" % [inc.income, inc.note])
				deco.stop()
				im.exit(player, true)
				_next()
		3:
			if f == 5:
				enter(portal_of(m.shop))
			if f == 60:
				var it: Node3D = im.current
				ok("mobília guardada ao voltar", furniture_count(it) == 6, "%d peças" % furniture_count(it))
				ok("atendente no balcão do jogador", it.patrons().filter(func(c): return c.mode == "clerk").size() == 1)
				it.spawn_interval = Vector2(0.3, 0.4)
				m.wait = 0
			if f > 60:
				var it: Node3D = im.current
				var seated: int = it.patrons().filter(func(c): return c.mode == "patron" and c.state == "seated").size()
				if seated >= 1 or f > 1500:
					ok("clientes sentam-se nas cadeiras do jogador", seated >= 1, "%d sentados" % seated)
					var t: float = gm.treasury
					var entry: Dictionary = gm.plots[m.shop].furniture[0]
					gm.remove_furniture(m.shop, entry)
					ok("retirar devolve metade", is_equal_approx(gm.treasury - t, gm.furniture_def(entry.id).price * 0.5))
					im.exit(player, true)
					m.house = free_plot("residencial")
					gm.buy_plot(m.house)
					gm.build_on_plot(m.house, "casa", "g")
					_next()
		4:
			if f == 5:
				enter(portal_of(m.house))
			if f == 60:
				var it: Node3D = im.current
				var r: Array = rooms(it)
				ok("casa grande com 5 divisões", r.size() == 5, ", ".join(r))
				deco.start()
				ok("coloca cama no quarto", place("cama", Vector3(-4.5, 0, -2.6)))
				ok("coloca sofá na sala", place("sofa", Vector3(-3.0, 0, 3.0), PI))
				var sofa: Node = null
				for s in it.seats():
					sofa = s
				player.sit_on(sofa)
				ok("senta no sofá", player.seat == sofa)
				player.stand_up()
				ok("casa sem clientes", it.patrons().is_empty())
				ok("conforto da casa", gm.plot_income(gm.plots[m.house]).get("comfort", 0.0) > 1.0)
				deco.stop()
				var fails := results.filter(func(x): return not x).size()
				print("\nRESULTADO: %d/%d ok" % [results.size() - fails, results.size()])
				quit(1 if fails > 0 else 0)
	return false


func _next() -> void:
	step += 1
	t0 = frame
