extends SceneTree
## Todos os edifícios têm interior e deixam o jogador entrar:
##   godot4 --headless --fixed-fps 60 --path godot/bandula --script res://tests/all_buildings_test.gd

var main: Node3D
var player: CharacterBody3D
var gm: Node
var im: Node
var frame := 0
var step := 0
var t0 := 0
var results := []
var queue := []          # [portal, verificação]
var current := []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	gm = root.get_node("GameManager")
	im = root.get_node("Interiors")


func ok(name: String, cond: bool, info := "") -> void:
	results.append(cond)
	print(("  ✔ " if cond else "  ✘ ") + name + ("  (" + info + ")" if info != "" else ""))


func has_door(n: Node) -> bool:
	return n.get_node_or_null("Porta") != null


func first_portal(pred: Callable) -> Node:
	for p in get_nodes_in_group("portals"):
		if pred.call(p):
			return p
	return null


func _process(_d: float) -> bool:
	frame += 1
	var f := frame - t0
	match step:
		0:
			if f == 60:
				# cobertura: prédios dos lotes, torres, esquadra, shopping, restaurantes e quiosques da Ilha
				var lots := 0
				var lots_ok := 0
				for id in gm.plots:
					var b: Node = gm.plots[id].node._building
					if b != null:
						lots += 1
						lots_ok += 1 if has_door(b) else 0
				ok("todos os prédios dos lotes têm porta", lots > 0 and lots_ok == lots, "%d/%d" % [lots_ok, lots])
				var marcos := main.get_node("Luanda/Marcos")
				var landmarks := marcos.get_children().filter(func(n): return has_door(n))
				ok("torres, esquadra e shopping têm porta", landmarks.size() == marcos.get_child_count(), ", ".join(marcos.get_children().map(func(n): return n.name)))
				var kiosks := main.get_node("Luanda/Quiosques").get_children()
				ok("quiosques têm porta", kiosks.all(func(k): return has_door(k)), "%d quiosques" % kiosks.size())
				var shops := main.get_node("Luanda/Estabelecimentos").get_children()
				ok("restaurantes da Ilha têm porta", shops.all(func(s): return has_door(s)))
				ok("portas no mapa", get_nodes_in_group("portals").size() > 100, "%d portas" % get_nodes_in_group("portals").size())
				queue = [
					[first_portal(func(p): return p.interior_type == "casa"), "casa"],
					[first_portal(func(p): return p.interior_type == "escritorio"), "torre"],
					[first_portal(func(p): return p.interior_type == "esquadra"), "esquadra"],
					[first_portal(func(p): return p.portal_id.begins_with("quiosque")), "quiosque"],
				]
				_next()
		1:
			if f == 1:
				if queue.is_empty():
					var fails := results.filter(func(x): return not x).size()
					print("\nRESULTADO: %d/%d ok" % [results.size() - fails, results.size()])
					quit(1 if fails > 0 else 0)
					return false
				current = queue.pop_front()
				var p: Node = current[0]
				player.global_position = p.outside_transform().origin
			if f == 10:
				ok("prompt para entrar (%s)" % current[1], player._interact_target == current[0], player._prompt)
				var ev := InputEventAction.new()
				ev.action = "interact"
				ev.pressed = true
				Input.parse_input_event(ev)
				var up := InputEventAction.new()
				up.action = "interact"
				Input.parse_input_event(up)
			if f == 60:
				var it: Node3D = im.current
				var rooms: Array = it.get_children().filter(func(n): return n.name.begins_with("Divisao_")).map(func(n): return n.text)
				var furn: int = it.get_node("Mobilia").get_child_count() + it.get_node("Assentos").get_child_count()
				var people: Array = it.patrons()
				match current[1]:
					"casa":
						ok("casa de NPC: divisões mobiladas", rooms.size() >= 3 and furn >= 5, "%s · %d móveis · %s" % [", ".join(rooms), furn, it.display_name])
						ok("moradores em casa", people.filter(func(n): return n.state == "seated").size() >= 1, "%d" % people.size())
					"torre":
						ok("torre: escritório com receção", it.counters().size() == 1 and people.size() >= 1, it.display_name)
						var r: Dictionary = gm.purchase("escritorio", it.place_id, "consultoria")
						ok("contrata consultoria", r.ok and gm.investments >= 60.0)
					"esquadra":
						ok("esquadra: receção, gabinete e celas", "Celas" in rooms and "Receção" in rooms and it.counters().size() == 1, ", ".join(rooms))
						var r: Dictionary = gm.purchase("esquadra", it.place_id, "entregar")
						ok("não se entrega sem estrelas", not r.ok)
						gm.report_offense("police_carjack")
						gm.report_offense("police_carjack")
						var t: float = gm.treasury
						r = gm.purchase("esquadra", it.place_id, "entregar")
						ok("entrega-se: multa a metade, estrelas limpas", r.ok and gm.wanted_level == 0 and gm.treasury < t, "Kz %d" % r.get("fine", 0))
					"quiosque":
						ok("quiosque: café por dentro", it.counters().size() == 1 and it.counters()[0].shop_type == "cafe", it.display_name)
						gm.energy = 50.0
						ok("compra café", gm.purchase("cafe", it.place_id, "cafe").ok and gm.energy > 50.0)
				im.exit(player, true)
				t0 = frame
	return false


func _next() -> void:
	step += 1
	t0 = frame
