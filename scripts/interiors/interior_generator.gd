extends RefCounted
## Gerador de interiores com tamanhos e divisões (casas, comércios do jogador e o
## Fortaleza Shopping). Devolve uma raiz com interior.gd, compatível com o
## InteriorManager, NPCs, cadeiras e balcões:
##
## Interior (Node3D) [interior.gd]
## ├── Sala (MeshInstance3D) · Colisao (StaticBody3D) · Luz (OmniLight3D ×n)
## ├── Divisao_<nome> (Label3D)       placa de cada divisão
## ├── Entrada (Marker3D) · Saida (Area3D) [building_portal.gd, is_exit]
## ├── Mobilia (Node3D)               peças do jogador (modo Decoração) ou do shopping
## ├── Assentos (Node3D) · Clientes (Node3D)
##
## spec: { kind: "casa"|"comercio"|"shopping", size: "p"|"m"|"g", business, name,
##         plot_id (prédios do jogador → mobília guardada no GameManager) }

const Kit = preload("res://scripts/interiors/interior_kit.gd")
const Catalog = preload("res://scripts/interiors/furniture_catalog.gd")
const DOOR := 1.1
const OUTER_DOOR := 1.8

## [largura, profundidade, fundo da zona da frente, [divisões de trás], [pesos], [divisões da frente], [pesos]]
const LAYOUTS := {
	"casa": {
		"p": [8.0, 7.0, 4.4, ["Quarto", "Casa de banho"], [0.6, 0.4], ["Sala e cozinha"], [1.0]],
		"m": [12.0, 9.0, 5.0, ["Quarto", "Cozinha", "Casa de banho"], [0.4, 0.35, 0.25], ["Sala"], [1.0]],
		"g": [16.0, 11.0, 5.5, ["Quarto", "Quarto 2", "Casa de banho"], [0.38, 0.38, 0.24], ["Sala", "Cozinha"], [0.68, 0.32]],
	},
	"comercio": {
		"p": [9.0, 8.0, 5.4, ["Armazém", "Copa"], [0.6, 0.4], ["Salão"], [1.0]],
		"m": [13.0, 10.0, 6.5, ["Armazém", "Cozinha"], [0.5, 0.5], ["Salão"], [1.0]],
		"g": [17.0, 12.0, 7.5, ["Armazém", "Cozinha", "Escritório"], [0.34, 0.33, 0.33], ["Salão"], [1.0]],
	},
	"esquadra": {
		"m": [14.0, 10.0, 6.0, ["Celas", "Gabinete"], [0.6, 0.4], ["Receção"], [1.0]],
	},
}
const ROOM_FLOOR := {
	"Sala": "#e8c08c", "Sala e cozinha": "#e8c08c", "Quarto": "#d9b48a", "Quarto 2": "#d9b48a",
	"Cozinha": "#d6eadf", "Casa de banho": "#cfe8f5", "Copa": "#d6eadf", "Armazém": "#d8d2e6",
	"Escritório": "#e6d9c4", "Salão": "#f3d9b1", "Receção": "#e4ecff", "Celas": "#c9cbd8", "Gabinete": "#e6d9c4",
}
const BUSINESS_STYLE := {
	"restaurante": ["#ffe1c4", "#e2725b"], "cantina": ["#fff4c2", "#3fa7e0"], "loja": ["#e9f6ff", "#7ed957"],
	"boutique": ["#ffe0ec", "#a77bff"], "cafe": ["#f6e7c9", "#8a5a3c"], "casa": ["#fff1d6", "#2fbfb0"],
	"escritorio": ["#eef2fb", "#3fa7e0"], "esquadra": ["#eef2ff", "#2f3b8f"],
}
const MALL_UNITS := [
	["Muamba Express", "restaurante"], ["Café Ginga", "cafe"], ["Moda Luanda", "boutique"],
	["Kianda Tech", "eletronica"], ["Hiper Kianda", "loja"], ["Grelhados do Mussulo", "restaurante"],
]

var root: Node3D
var kit
var body: StaticBody3D
var H := 3.4
var _bounds := Vector2(10, 9)
var _room_rects := {}             # nome da divisão → Rect2 (x, z, largura, fundo) local


static func generate(spec: Dictionary) -> Node3D:
	var g = new()
	return g._generate(spec)


func _generate(spec: Dictionary) -> Node3D:
	var kind: String = spec.get("kind", "casa")
	root = Node3D.new()
	root.name = "Interior"
	root.set_script(load("res://scripts/interiors/interior.gd"))
	kit = Kit.new()
	body = StaticBody3D.new()
	body.name = "Colisao"
	root.add_child(body)
	for g in ["Mobilia", "Assentos", "Clientes"]:
		var n := Node3D.new()
		n.name = g
		root.add_child(n)
	var depth := 0.0
	if kind == "shopping":
		depth = _shopping()
		root.set("interior_type", "shopping")
		root.set("max_patrons", 10)
	else:
		var size: String = spec.get("size", "m")
		var business: String = {"comercio": spec.get("business", "loja"), "esquadra": "esquadra"}.get(kind, "casa")
		if not LAYOUTS[kind].has(size):
			size = LAYOUTS[kind].keys()[0]
		depth = _rooms(LAYOUTS[kind][size], business)
		root.set("interior_type", business)
		root.set("max_patrons", 0 if kind in ["casa", "esquadra"] else {"p": 2, "m": 4, "g": 6}[size])
		root.set("residents", int(spec.get("residents", 0)))
		if spec.get("furnish", "") == "auto":
			_auto_furnish(business)
		var plot_id: String = spec.get("plot_id", "")
		root.set("owner_plot_id", plot_id)
		if plot_id != "":
			var p: Dictionary = GameManager.plots.get(plot_id, {})
			for e in p.get("furniture", []):
				add_furniture(root, e, business)
	root.set("display_name", spec.get("name", "Interior"))
	root.set_meta("bounds", _bounds)
	var mesh: ArrayMesh = kit.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Sala"
	mi.mesh = mesh
	root.add_child(mi)
	root.move_child(mi, 0)
	var e := Marker3D.new()
	e.name = "Entrada"
	e.position = Vector3(0, 0.05, depth / 2.0 - 1.1)
	e.rotation.y = PI
	root.add_child(e)
	var exit := Area3D.new()
	exit.name = "Saida"
	exit.set_script(load("res://scripts/interiors/building_portal.gd"))
	exit.set("is_exit", true)
	exit.position = Vector3(0, 0, depth / 2.0 - 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 2.4, 1.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.2, 0)
	exit.add_child(cs)
	root.add_child(exit)
	return root


## Peça de mobília do jogador (entrada guardada no GameManager) dentro do interior.
static func add_furniture(interior: Node3D, entry: Dictionary, business := "loja") -> Node3D:
	var accent := Color(BUSINESS_STYLE.get(business, BUSINESS_STYLE.casa)[1])
	var n: Node3D = Catalog.create(entry.id, business, accent)
	n.position = Vector3(entry.x, 0, entry.z)
	n.rotation.y = entry.yaw
	n.set_meta("furniture_entry", entry)
	var container := interior.get_node("Assentos") if n.get("kind") == "seat" else interior.get_node("Mobilia")
	container.add_child(n)
	return n


# ------------------------------------------------------------------ paredes e divisões

func _solid(size: Vector3, pos: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = pos
	body.add_child(cs)


## Parede ao longo de X (em z), de x0 a x1, com vãos [[a, b], …].
func _wall_x(z: float, x0: float, x1: float, gaps: Array, col: Color, t := 0.2) -> void:
	var cuts := [x0]
	for g in gaps:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(x1)
	for i in range(0, cuts.size(), 2):
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 0.05:
			continue
		kit.slab(Kit.at((a + b) / 2.0, 0, z), b - a, H, t, col, 0.05, 0.02)
		_solid(Vector3(b - a, H, t), Vector3((a + b) / 2.0, H / 2.0, z))
	for g in gaps:                                           # padieira sobre o vão
		kit.slab(Kit.at((g[0] + g[1]) / 2.0, 2.3, z), g[1] - g[0], H - 2.3, t, col, 0.03, 0.01)


## Parede ao longo de Z (em x), de z0 a z1, com vãos.
func _wall_z(x: float, z0: float, z1: float, gaps: Array, col: Color, t := 0.2) -> void:
	var cuts := [z0]
	for g in gaps:
		cuts.append(g[0])
		cuts.append(g[1])
	cuts.append(z1)
	for i in range(0, cuts.size(), 2):
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 0.05:
			continue
		kit.slab(Kit.at(x, 0, (a + b) / 2.0), t, H, b - a, col, 0.05, 0.02)
		_solid(Vector3(t, H, b - a), Vector3(x, H / 2.0, (a + b) / 2.0))
	for g in gaps:
		kit.slab(Kit.at(x, 2.3, (g[0] + g[1]) / 2.0), t, H - 2.3, g[1] - g[0], col, 0.03, 0.01)


func _light(pos: Vector3, energy := 1.2, rng := 6.0) -> void:
	var l := OmniLight3D.new()
	l.name = "Luz"
	l.light_color = Color("#ffd9a3")
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	root.add_child(l)


func _room_label(name: String, pos: Vector3, yaw := 0.0) -> void:
	var l := Label3D.new()
	l.name = "Divisao_" + name.replace(" ", "_")
	l.text = name
	l.font_size = 40
	l.outline_size = 8
	l.modulate = Color("#3b3355")
	l.outline_modulate = Color("#fff8ec")
	l.pixel_size = 0.004
	l.position = pos
	l.rotation.y = yaw
	root.add_child(l)


func _shell(W: float, D: float, wall: Color, band: Color, door_w: float) -> void:
	_wall_x(-D / 2.0, -W / 2.0 - 0.1, W / 2.0 + 0.1, [], wall)
	_wall_z(-W / 2.0, -D / 2.0, D / 2.0, [], wall)
	_wall_z(W / 2.0, -D / 2.0, D / 2.0, [], wall)
	_wall_x(D / 2.0, -W / 2.0 - 0.1, W / 2.0 + 0.1, [[-door_w / 2.0, door_w / 2.0]], wall)
	_solid(Vector3(door_w, 2.3, 0.2), Vector3(0, 1.15, D / 2.0 + 0.05))      # porta fechada (sai-se com E)
	kit.slab(Kit.at(0, H, 0), W + 0.4, 0.2, D + 0.4, Color("#fff8ec"), 0.1, 0.03)
	_solid(Vector3(W + 1.0, 0.2, D + 1.0), Vector3(0, H + 0.1, 0))
	_solid(Vector3(W + 1.0, 0.2, D + 1.0), Vector3(0, -0.1, 0))
	for sx in [-1.0, 1.0]:                                     # moldura da porta
		kit.slab(Kit.at(sx * (door_w / 2.0 + 0.08), 0, D / 2.0 - 0.12), 0.16, 2.45, 0.1, band, 0.04, 0.015)
	kit.slab(Kit.at(0, 2.35, D / 2.0 - 0.12), door_w + 0.32, 0.14, 0.1, band, 0.04, 0.015)


func _rooms(L: Array, business: String) -> float:
	var W: float = L[0]
	var D: float = L[1]
	var front: float = L[2]
	var style: Array = BUSINESS_STYLE.get(business, BUSINESS_STYLE.casa)
	var wall := Color(style[0])
	var band := Color(style[1])
	var zb := D / 2.0 - front                                   # fronteira entre a frente e as divisões de trás
	_bounds = Vector2(W, D)
	_shell(W, D, wall, band, OUTER_DOOR)
	# divisões de trás: paredes entre elas e a parede com portas para a frente
	var gaps := []
	var x := -W / 2.0
	var names: Array = L[3]
	var weights: Array = L[4]
	for i in names.size():
		var w: float = W * weights[i]
		var cx := x + w / 2.0
		gaps.append([cx - DOOR / 2.0, cx + DOOR / 2.0])
		kit.slab(Kit.at(cx, -0.08, (-D / 2.0 + zb) / 2.0), w - 0.05, 0.08, zb + D / 2.0 - 0.05, Color(ROOM_FLOOR.get(names[i], "#e8c08c")), 0.05, 0.01)
		_room_label(names[i], Vector3(cx, 2.6, -D / 2.0 + 0.13))
		_room_rects[names[i]] = Rect2(x + 0.1, -D / 2.0 + 0.1, w - 0.2, zb + D / 2.0 - 0.2)
		_light(Vector3(cx, H - 0.4, (-D / 2.0 + zb) / 2.0), 1.0, maxf(w, 4.0))
		if i > 0:
			_wall_z(x, -D / 2.0, zb, [], wall)
		x += w
	_wall_x(zb, -W / 2.0, W / 2.0, gaps, wall)
	# zona da frente (uma ou duas divisões)
	var fnames: Array = L[5]
	var fweights: Array = L[6]
	x = -W / 2.0
	for i in fnames.size():
		var w: float = W * fweights[i]
		var cx := x + w / 2.0
		kit.slab(Kit.at(cx, -0.08, (zb + D / 2.0) / 2.0), w - 0.05, 0.08, front - 0.05, Color(ROOM_FLOOR.get(fnames[i], "#e8c08c")), 0.05, 0.01)
		_room_label(fnames[i], Vector3(cx, 2.6, zb + 0.13))
		_room_rects[fnames[i]] = Rect2(x + 0.1, zb + 0.1, w - 0.2, front - 0.2)
		_light(Vector3(cx, H - 0.4, (zb + D / 2.0) / 2.0), 1.3, maxf(w, front) + 1.0)
		if i > 0:
			_wall_z(x, zb, D / 2.0, [[zb + front / 2.0 - DOOR / 2.0, zb + front / 2.0 + DOOR / 2.0]], wall)
		x += w
	# faixa decorativa e janelas
	kit.slab(Kit.at(0, 0, -D / 2.0 + 0.12), W - 0.2, 0.9, 0.04, band, 0.02, 0.0)
	for sx in [-1.0, 1.0]:
		kit.slab(Kit.at(sx * (W / 2.0 - 0.12), 1.3, (zb + D / 2.0) / 2.0), 0.04, 1.1, minf(front - 1.0, 2.4), Color("#cdeeff"), 0.04, 0.0)
	return D


# ------------------------------------------------------------------ Fortaleza Shopping

func _shopping() -> float:
	H = 6.0
	var W := 44.0
	var D := 26.0
	var wall := Color("#f6dfc4")
	var band := Color("#e2725b")
	_bounds = Vector2(W, D)
	_shell(W, D, wall, band, 3.2)
	# piso em mosaico grande (dois tons) e claraboias
	for ix in range(-11, 11):
		for iz in range(-6, 7):
			kit.slab(Kit.at(ix * 2.0 + 1.0, -0.1, iz * 2.0), 1.96, 0.1, 1.96, Color("#f6eadb") if (ix + iz) % 2 == 0 else Color("#e9d6c2"), 0.06, 0.01)
	for sx in [-12.0, 0.0, 12.0]:
		kit.slab(Kit.at(sx, H - 0.05, 2.0), 8.0, 0.08, 6.0, Color("#dff4ff"), 0.4, 0.02)
		_light(Vector3(sx, H - 0.8, 2.0), 0.9, 13.0)
	# lojas no fundo (montras abertas para o corredor)
	var unit_w := W / MALL_UNITS.size()
	var front_z := -6.0
	for i in MALL_UNITS.size():
		var u: Array = MALL_UNITS[i]
		var cx := -W / 2.0 + unit_w * (i + 0.5)
		if i > 0:
			_wall_z(-W / 2.0 + unit_w * i, -D / 2.0, front_z, [], wall)
		var accent := Color(["#e2725b", "#8a5a3c", "#a77bff", "#3fa7e0", "#7ed957", "#ff9f43"][i])
		kit.slab(Kit.at(cx, -0.08, (-D / 2.0 + front_z) / 2.0), unit_w - 0.25, 0.09, 7.0 - 0.2, accent.lightened(0.7), 0.05, 0.01)
		kit.slab(Kit.at(cx, 3.6, front_z), unit_w - 0.2, 0.9, 0.3, accent, 0.08, 0.02)          # fachada da loja
		var sign := Label3D.new()
		sign.name = "Loja_" + str(i)
		sign.text = u[0]
		sign.font_size = 72
		sign.outline_size = 12
		sign.modulate = Color("#fff8ec")
		sign.outline_modulate = accent.darkened(0.3)
		sign.pixel_size = 0.005
		sign.position = Vector3(cx, 4.05, front_z + 0.2)
		root.add_child(sign)
		var counter: Node3D = Catalog.create("balcao", u[1], accent)
		counter.position = Vector3(cx, 0, front_z - 2.2)
		counter.set("place_name", u[0])
		root.get_node("Mobilia").add_child(counter)
		for k in 2:
			var shelf: Node3D = Catalog.create("estante" if u[1] != "restaurante" else "frigorifico", u[1], accent)
			shelf.position = Vector3(cx - 1.6 + k * 3.2, 0, -D / 2.0 + 0.5)
			root.get_node("Mobilia").add_child(shelf)
		_light(Vector3(cx, 3.2, (-D / 2.0 + front_z) / 2.0), 0.7, 6.5)
	# praça da alimentação: mesas redondas com cadeiras (os clientes sentam-se aqui)
	for t in [Vector2(-9, -1), Vector2(0, -1), Vector2(9, -1), Vector2(-9, 4.5), Vector2(0, 4.5), Vector2(9, 4.5)]:
		var table: Node3D = Catalog.create("mesa_redonda")
		table.position = Vector3(t.x, 0, t.y)
		root.get_node("Mobilia").add_child(table)
		for a in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
			var chair: Node3D = Catalog.create("cadeira", "restaurante", Color("#ff9f43"))
			var off := Vector3(sin(a), 0, cos(a)) * 0.95
			chair.position = Vector3(t.x, 0, t.y) + off
			chair.rotation.y = atan2(-off.x, -off.z)               # virada para a mesa
			root.get_node("Assentos").add_child(chair)
	for p in [Vector3(-20, 0, 11), Vector3(20, 0, 11), Vector3(-20, 0, -4.5), Vector3(20, 0, -4.5)]:
		var plant: Node3D = Catalog.create("planta")
		plant.position = p
		plant.scale = Vector3.ONE * 1.6
		root.get_node("Mobilia").add_child(plant)
	var title := Label3D.new()
	title.name = "Letreiro"
	title.text = "FORTALEZA SHOPPING"
	title.font_size = 120
	title.outline_size = 18
	title.modulate = Color("#e2725b")
	title.outline_modulate = Color("#fff8ec")
	title.pixel_size = 0.006
	title.position = Vector3(0, 4.6, D / 2.0 - 0.15)
	title.rotation.y = PI
	root.add_child(title)
	return D


# ------------------------------------------------------------------ mobília automática (prédios de NPCs)

## Mobila cada divisão conforme o nome e o negócio (casas, escritórios, esquadra, quiosques).
func _auto_furnish(business: String) -> void:
	for name in _room_rects:
		var r: Rect2 = _room_rects[name]
		var x0 := r.position.x
		var z0 := r.position.y
		var w := r.size.x
		var d := r.size.y
		var cx := x0 + w / 2.0
		match name:
			"Sala", "Sala e cozinha":
				_put("sofa", x0 + minf(1.3, w * 0.25) + 0.3, z0 + 0.6, 0.0)
				_put("tapete", x0 + minf(1.3, w * 0.25) + 0.3, z0 + 1.9, 0.0)
				_table_set(x0 + w * 0.72, z0 + d * 0.42, "mesa_redonda")
				_put("candeeiro", x0 + 0.4, z0 + 0.4, 0.0)
				_put("planta", x0 + w - 0.45, z0 + 0.45, 0.0)
				if name == "Sala e cozinha":
					_put("frigorifico", x0 + w - 1.2, z0 + 0.5, 0.0)
			"Quarto", "Quarto 2":
				_put("cama", cx, z0 + 1.15, 0.0)
				_put("planta", x0 + 0.4, z0 + 0.4, 0.0)
			"Cozinha", "Copa":
				_put("frigorifico", x0 + 0.6, z0 + 0.5, 0.0)
				if w > 3.2 and d > 3.0:
					_table_set(cx + 0.5, z0 + d * 0.55, "mesa_redonda")
			"Casa de banho":
				_put("planta", cx, z0 + 0.45, 0.0)
			"Armazém":
				var n := maxi(1, int((w - 0.4) / 1.8))
				for i in n:
					_put("estante", x0 + 0.2 + 0.9 + i * 1.8, z0 + 0.35, 0.0, business)
			"Escritório", "Gabinete":
				_put("mesa", cx, z0 + d * 0.5, 0.0)
				_put("cadeira", cx, z0 + d * 0.5 - 0.85, 0.0)
				_put("estante", cx, z0 + 0.3, 0.0)
			"Celas":
				for i in range(int(w / 0.5)):                            # grades das celas
					kit.slab(Kit.at(x0 + 0.25 + i * 0.5, 0, z0 + d - 0.6), 0.06, 2.4, 0.06, Color("#6b6f8a"), 0.02, 0.0)
				_put("banco", x0 + 0.8, z0 + 0.6, 0.0)
				_put("banco", x0 + w - 0.8, z0 + 0.6, 0.0)
			"Receção":
				_put("balcao", cx, z0 + 0.6, 0.0, business)
				for i in 3:
					_put("banco", x0 + 0.6, z0 + d * 0.3 + i * 0.9, PI / 2.0)
				_put("planta", x0 + w - 0.5, z0 + 0.5, 0.0)
			"Salão":
				_put("balcao", cx, z0 + 0.6, 0.0, business)
				match business:
					"restaurante", "cantina", "cafe":
						for sx in [-1.0, 1.0]:
							if w > 7.0:
								_table_set(cx + sx * w * 0.3, z0 + d * 0.5, "mesa_redonda")
							else:
								_put("banco", cx + sx * 1.6, z0 + 2.0, PI)
					"loja", "boutique":
						for sx in [-1.0, 1.0]:
							_put("estante", cx + sx * (w / 2.0 - 0.3), z0 + d * 0.45, -sx * PI / 2.0, business)
					"escritorio":
						_put("sofa", x0 + 1.4, z0 + d * 0.55, PI / 2.0)
						_table_set(cx + w * 0.25, z0 + d * 0.5, "mesa")
						_put("planta", x0 + w - 0.5, z0 + 0.5, 0.0)


## Mesa com duas cadeiras viradas para ela.
func _table_set(x: float, z: float, table: String) -> void:
	_put(table, x, z, 0.0)
	var off := 0.85 if table == "mesa_redonda" else 1.25
	_put("cadeira", x - off, z, PI / 2.0)
	_put("cadeira", x + off, z, -PI / 2.0)


## Coloca uma peça (sem registo no GameManager) se couber dentro das paredes exteriores.
func _put(fid: String, x: float, z: float, yaw: float, shop_type := "loja") -> void:
	var fp := Catalog.footprint(fid)
	var half := Vector2(fp.x, fp.y).rotated(yaw).abs() / 2.0
	if absf(x) + half.x > _bounds.x / 2.0 - 0.12 or absf(z) + half.y > _bounds.y / 2.0 - 0.12:
		return
	if z + half.y > _bounds.y / 2.0 - 1.8 and absf(x) - half.x < 1.4:       # porta livre
		return
	var accent := Color(BUSINESS_STYLE.get(shop_type, BUSINESS_STYLE.casa)[1])
	var n: Node3D = Catalog.create(fid, shop_type, accent)
	n.position = Vector3(x, 0, z)
	n.rotation.y = yaw
	root.get_node("Assentos" if n.get("kind") == "seat" else "Mobilia").add_child(n)
