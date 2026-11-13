extends RefCounted
## Constrói as cenas de interior do Bandula (scenes/interiors/*.tscn):
##   restaurante · cantina · loja (mini-mercado)
## Sala 10 × 9 m (x −5…5, z −4.5…4.5, pé-direito 3.6), porta em +Z.
##
## <Tipo> (Node3D) [interior.gd]
## ├── Sala (MeshInstance3D)       pavimento, paredes, balcão, prateleiras, decoração
## ├── Colisao (StaticBody3D)      pavimento, paredes, teto, móveis fixos, porta
## ├── Luzes (OmniLight3D…)        candeeiros quentes
## ├── Letreiro / Menu (Label3D)
## ├── Entrada (Marker3D)          onde o jogador e os clientes aparecem
## ├── Saida (Area3D) [building_portal.gd, is_exit]
## ├── Balcao (Area3D) [interactable_furniture.gd, counter] └ Atendente (Marker3D)
## ├── Assentos (Node3D) └ Cadeira_N (Area3D) [interactable_furniture.gd, seat]
## │                        ├ Malha · Colisao · SitPoint · Approach
## └── Clientes (Node3D)           NPCs (criados em jogo)

const Kit = preload("res://scripts/interiors/interior_kit.gd")
const W := 10.0
const D := 9.0
const H := 3.6
const DOOR := 1.8

const STYLE := {
	"restaurante": {"name": "Restaurante Kitanda", "floor": ["#f3d9b1", "#e8c08c"], "wall": "#ffe1c4", "band": "#e2725b", "accent": "#2fbfb0", "counter": "#c9925f",
		"menu": "MENU DA KITANDA\nMuamba de galinha · Kz 120\nCalulu de peixe · Kz 150\nMufete da Ilha · Kz 180"},
	"cantina": {"name": "Cantina da Mamã Rosa", "floor": ["#d6eadf", "#bcdccb"], "wall": "#fff4c2", "band": "#3fa7e0", "accent": "#ff8fab", "counter": "#a96f40",
		"menu": "PRATO DO DIA\nFunge com feijão · Kz 60\nSumo de múcua · Kz 40\nGasosa gelada · Kz 25"},
	"loja": {"name": "Mini-Mercado Kianda", "floor": ["#eef0f7", "#dfe3ee"], "wall": "#e9f6ff", "band": "#7ed957", "accent": "#ffd166", "counter": "#8fa2f0",
		"menu": "MINI-MERCADO KIANDA\nÁgua · bolinhos · banana-pão\nAberto todos os dias"},
}

var root: Node3D
var kit
var body: StaticBody3D
var style: Dictionary


static func build(kind: String) -> Node3D:
	var b = new()
	return b._build(kind)


static func chair_mesh(stool := false) -> ArrayMesh:
	var path := "res://scenes/interiors/%s.res" % ("banco" if stool else "cadeira")
	if ResourceLoader.exists(path):
		return load(path)
	var k = Kit.new()
	var wood := Color("#c9925f")
	for p in [[-0.19, -0.19], [0.19, -0.19], [-0.19, 0.19], [0.19, 0.19]]:
		k.lathe(Kit.at(p[0], 0, p[1]), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.025, 0.44), Vector2(0.0, 0.44)], wood, 8)
	k.slab(Kit.at(0, 0.42, 0), 0.48, 0.07, 0.48, Color("#e2725b"), 0.08, 0.02)
	if not stool:
		k.slab(Kit.at(0, 0.48, -0.21), 0.46, 0.5, 0.06, wood, 0.03, 0.015)
		k.slab(Kit.at(0, 0.88, -0.21), 0.5, 0.08, 0.08, Color("#e2725b"), 0.03, 0.015)
	var mesh: ArrayMesh = k.commit()
	ResourceSaver.save(mesh, path)
	mesh.take_over_path(path)
	return mesh


func _build(kind: String) -> Node3D:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/interiors"))
	style = STYLE[kind]
	root = Node3D.new()
	root.name = kind.capitalize()
	root.set_script(load("res://scripts/interiors/interior.gd"))
	root.set("interior_type", kind)
	root.set("display_name", style.name)
	kit = Kit.new()
	body = StaticBody3D.new()
	body.name = "Colisao"
	body.collision_layer = 1
	_own(body, root)
	_room()
	for g in ["Assentos", "Clientes"]:
		var n := Node3D.new()
		n.name = g
		_own(n, root)
	match kind:
		"restaurante":
			_restaurante()
		"cantina":
			_cantina()
		"loja":
			_loja()
	var mesh: ArrayMesh = kit.commit()
	var path := "res://scenes/interiors/sala_%s.res" % kind
	ResourceSaver.save(mesh, path)
	mesh.take_over_path(path)
	var mi := MeshInstance3D.new()
	mi.name = "Sala"
	mi.mesh = mesh
	_own(mi, root)
	root.move_child(mi, 0)
	var e := Marker3D.new()
	e.name = "Entrada"
	e.position = Vector3(0, 0.05, 3.4)
	e.rotation.y = PI                           # entra a olhar para o fundo da sala (−Z)
	_own(e, root)
	var exit := Area3D.new()
	exit.name = "Saida"
	exit.set_script(load("res://scripts/interiors/building_portal.gd"))
	exit.set("is_exit", true)
	exit.position = Vector3(0, 0, 4.0)
	_own(exit, root)
	_shape(exit, Vector3(2.4, 2.4, 1.6), Vector3(0, 1.2, 0))
	return root


# ------------------------------------------------------------------ utilidades

func _own(n: Node, parent: Node) -> void:
	parent.add_child(n)
	n.owner = root


func _shape(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = pos
	_own(cs, parent)


func _solid(size: Vector3, pos: Vector3) -> void:
	_shape(body, size, pos)


func _light(pos: Vector3, energy := 1.4, rng := 5.5) -> void:
	var l := OmniLight3D.new()
	l.name = "Luz"
	l.light_color = Color("#ffd9a3")
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	_own(l, root)


func _label(name: String, text: String, pos: Vector3, size := 48, color := Color("#3b3355")) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color("#fff8ec")
	l.position = pos
	l.pixel_size = 0.004
	_own(l, root)
	return l


# ------------------------------------------------------------------ sala

func _room() -> void:
	var c0 := Color(style.floor[0])
	var c1 := Color(style.floor[1])
	for ix in range(-5, 5):
		for iz in range(-5, 4):
			kit.slab(Kit.at(ix + 0.5, -0.1, iz + 1.0), 0.97, 0.1, 0.97, c0 if (ix + iz) % 2 == 0 else c1, 0.05, 0.01)
	var wall := Color(style.wall)
	var band := Color(style.band)
	kit.slab(Kit.at(0, 0, -D / 2.0 - 0.15), W + 0.6, H, 0.3, wall, 0.1, 0.03)
	for sx in [-1.0, 1.0]:
		kit.slab(Kit.at(sx * (W / 2.0 + 0.15), 0, 0), 0.3, H, D, wall, 0.1, 0.03)
		var seg_w := W / 2.0 + 0.3 - DOOR / 2.0                     # troços da parede da frente, ao lado da porta
		kit.slab(Kit.at(sx * (DOOR / 2.0 + seg_w / 2.0), 0, D / 2.0 + 0.15), seg_w, H, 0.3, wall, 0.1, 0.03)
	kit.slab(Kit.at(0, 2.45, D / 2.0 + 0.15), DOOR + 0.1, H - 2.45, 0.3, wall, 0.05, 0.02)
	# rodapé decorativo (faixa de cor) e cornija
	kit.slab(Kit.at(0, 0, -D / 2.0 + 0.02), W - 0.1, 1.05, 0.06, band, 0.02, 0.01)
	kit.slab(Kit.at(0, 1.05, -D / 2.0 + 0.04), W - 0.1, 0.08, 0.1, Color("#fff8ec"), 0.02, 0.01)
	for sx in [-1.0, 1.0]:
		kit.slab(Kit.at(sx * (W / 2.0 - 0.02), 0, 0), 0.06, 1.05, D - 0.1, band, 0.02, 0.01)
		kit.slab(Kit.at(sx * (W / 2.0 - 0.04), 1.05, 0), 0.1, 0.08, D - 0.1, Color("#fff8ec"), 0.02, 0.01)
		# janelas luminosas nas paredes laterais
		for z in [-2.0, 1.5]:
			kit.slab(Kit.at(sx * (W / 2.0 - 0.03), 1.4, z), 0.05, 1.2, 1.3, Color("#cdeeff"), 0.04, 0.01)
			kit.slab(Kit.at(sx * (W / 2.0 - 0.05), 1.32, z), 0.12, 0.1, 1.5, Color("#fff8ec"), 0.02, 0.01)
	kit.slab(Kit.at(0, H - 0.18, 0), W + 0.6, 0.25, D + 0.6, Color("#fff8ec"), 0.1, 0.03)
	# moldura da porta
	for sx in [-1.0, 1.0]:
		kit.slab(Kit.at(sx * (DOOR / 2.0 + 0.08), 0, D / 2.0 - 0.02), 0.16, 2.5, 0.12, Color(style.accent), 0.04, 0.015)
	kit.slab(Kit.at(0, 2.42, D / 2.0 - 0.02), DOOR + 0.32, 0.16, 0.12, Color(style.accent), 0.04, 0.015)
	# colisão: pavimento, teto, paredes e a porta fechada (sai-se com E)
	_solid(Vector3(W + 1.0, 0.2, D + 1.0), Vector3(0, -0.1, 0))
	_solid(Vector3(W + 1.0, 0.2, D + 1.0), Vector3(0, H + 0.1, 0))
	_solid(Vector3(W + 1.0, H, 0.3), Vector3(0, H / 2.0, -D / 2.0 - 0.15))
	_solid(Vector3(0.3, H, D + 1.0), Vector3(-W / 2.0 - 0.15, H / 2.0, 0))
	_solid(Vector3(0.3, H, D + 1.0), Vector3(W / 2.0 + 0.15, H / 2.0, 0))
	_solid(Vector3(W + 1.0, H, 0.3), Vector3(0, H / 2.0, D / 2.0 + 0.15))
	# plantas nos cantos da frente
	for sx in [-1.0, 1.0]:
		var x: float = sx * (W / 2.0 - 0.6)
		kit.lathe(Kit.at(x, 0, D / 2.0 - 0.6), [Vector2(0, 0), Vector2(0.22, 0), Vector2(0.3, 0.5), Vector2(0.27, 0.55), Vector2(0, 0.55)], Color("#e2725b"))
		kit.lathe(Kit.at(x, 0.5, D / 2.0 - 0.6), [Vector2(0, 0), Vector2(0.35, 0.15), Vector2(0.45, 0.55), Vector2(0.3, 0.95), Vector2(0, 1.05)], Color("#5fcf7a"))
		_solid(Vector3(0.6, 1.4, 0.6), Vector3(x, 0.7, D / 2.0 - 0.6))
	_light(Vector3(0, H - 0.5, 0), 1.2, 9.0)


func _counter(center: Vector3, length: float, shop_type: String, yaw := 0.0) -> void:
	var xf := Kit.at(center.x, 0, center.z, yaw)
	kit.slab(xf, length, 1.0, 0.75, Color(style.counter), 0.08, 0.03)
	kit.slab(xf * Transform3D(Basis(), Vector3(0, 1.0, 0)), length + 0.15, 0.08, 0.9, Color("#fff8ec"), 0.06, 0.02)
	kit.slab(xf * Transform3D(Basis(), Vector3(0, 0.25, 0.39)), length - 0.2, 0.5, 0.04, Color(style.accent), 0.04, 0.01)
	_solid_rot(Vector3(length + 0.15, 1.1, 0.9), center + Vector3(0, 0.55, 0), yaw)
	var area := Area3D.new()
	area.name = "Balcao"
	area.set_script(load("res://scripts/interiors/interactable_furniture.gd"))
	area.set("kind", "counter")
	area.set("shop_type", shop_type)
	area.set("label", "Balcão")
	area.position = center
	area.rotation.y = yaw
	_own(area, root)
	_shape(area, Vector3(length, 2.0, 1.6), Vector3(0, 1.0, 1.2))
	var clerk := Marker3D.new()
	clerk.name = "Atendente"
	clerk.position = Vector3(0, 0, -0.85)
	_own(clerk, area)


func _solid_rot(size: Vector3, pos: Vector3, yaw: float) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = pos
	cs.rotation.y = yaw
	_own(cs, body)


func _seat(pos: Vector3, yaw: float, stool := false) -> void:
	var seats := root.get_node("Assentos")
	var n := seats.get_child_count() + 1
	var a := Area3D.new()
	a.name = "%s_%02d" % ["Banco" if stool else "Cadeira", n]
	a.set_script(load("res://scripts/interiors/interactable_furniture.gd"))
	a.set("kind", "seat")
	a.set("label", "Banco" if stool else "Cadeira")
	a.position = pos
	a.rotation.y = yaw
	_own(a, seats)
	var sh := SphereShape3D.new()
	sh.radius = 1.25
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position = Vector3(0, 0.8, 0)
	_own(cs, a)
	var mi := MeshInstance3D.new()
	mi.name = "Malha"
	mi.mesh = chair_mesh(stool)
	_own(mi, a)
	var sb := StaticBody3D.new()
	sb.name = "Colisao"
	_own(sb, a)
	var b := BoxShape3D.new()
	b.size = Vector3(0.5, 0.5, 0.5)
	var bcs := CollisionShape3D.new()
	bcs.shape = b
	bcs.position = Vector3(0, 0.25, 0)
	_own(bcs, sb)
	for m in [["SitPoint", Vector3(0, 0.05, 0.22)], ["Approach", Vector3(0, 0.05, -0.85)]]:
		var mk := Marker3D.new()
		mk.name = m[0]
		mk.position = m[1]
		_own(mk, a)


func _table_round(x: float, z: float) -> void:
	kit.lathe(Kit.at(x, 0, z), [Vector2(0, 0), Vector2(0.32, 0), Vector2(0.3, 0.05), Vector2(0.07, 0.1), Vector2(0.06, 0.7), Vector2(0, 0.7)], Color("#8a5a3c"))
	kit.lathe(Kit.at(x, 0.7, z), [Vector2(0, 0), Vector2(0.58, 0), Vector2(0.6, 0.03), Vector2(0.58, 0.06), Vector2(0, 0.06)], Color("#f6e7c9"), 24)
	kit.lathe(Kit.at(x, 0.76, z), [Vector2(0, 0), Vector2(0.12, 0), Vector2(0.1, 0.04), Vector2(0, 0.04)], Color(style.accent), 12)   # prato
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 0.8
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = Vector3(x, 0.4, z)
	_own(cs, body)
	# candeeiro pendente sobre a mesa
	kit.lathe(Kit.at(x, H - 1.0, z), [Vector2(0, 0), Vector2(0.32, 0), Vector2(0.18, 0.28), Vector2(0.02, 0.35), Vector2(0.02, 0.82), Vector2(0, 0.82)], Color(style.accent))
	_light(Vector3(x, H - 1.15, z), 1.3, 4.0)


func _table_long(x: float, z: float, length: float) -> void:
	kit.slab(Kit.at(x, 0.7, z), 1.0, 0.07, length, Color("#f6e7c9"), 0.12, 0.02)
	for dz in [-length / 2.0 + 0.2, length / 2.0 - 0.2]:
		kit.slab(Kit.at(x, 0, z + dz), 0.8, 0.7, 0.08, Color("#a96f40"), 0.03, 0.01)
	var b := BoxShape3D.new()
	b.size = Vector3(1.0, 0.8, length)
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = Vector3(x, 0.4, z)
	_own(cs, body)
	for dz in [-0.7, 0.7]:
		kit.lathe(Kit.at(x, 0.77, z + dz), [Vector2(0, 0), Vector2(0.13, 0), Vector2(0.11, 0.04), Vector2(0, 0.04)], Color(style.accent), 12)
	_light(Vector3(x, H - 0.9, z), 1.2, 4.5)
	kit.lathe(Kit.at(x, H - 0.75, z), [Vector2(0, 0), Vector2(0.28, 0), Vector2(0.15, 0.25), Vector2(0.02, 0.3), Vector2(0.02, 0.6), Vector2(0, 0.6)], Color(style.accent))


func _shelf_wall(x: float, length: float) -> void:
	var cols := ["#ff6f6f", "#ffd166", "#4fd1c5", "#a77bff", "#7ed957", "#5aaeff"]
	for k in range(2):
		var y := 1.45 + k * 0.6
		kit.slab(Kit.at(x, y, -D / 2.0 + 0.25), length, 0.06, 0.4, Color("#c9925f"), 0.03, 0.01)
		var i := 0
		var px := x - length / 2.0 + 0.25
		while px < x + length / 2.0 - 0.2:
			kit.lathe(Kit.at(px, y + 0.06, -D / 2.0 + 0.25), [Vector2(0, 0), Vector2(0.06, 0), Vector2(0.06, 0.18), Vector2(0.025, 0.26), Vector2(0.02, 0.32), Vector2(0, 0.32)], Color(cols[(i + k) % cols.size()]), 8)
			px += 0.22
			i += 1


# ------------------------------------------------------------------ layouts

func _restaurante() -> void:
	_counter(Vector3(0.8, 0, -3.55), 5.0, "restaurante")
	_shelf_wall(0.8, 4.6)
	_label("Menu", style.menu, Vector3(-3.3, 2.3, -D / 2.0 + 0.08), 40)
	_label("Letreiro", style.name, Vector3(0.8, 3.0, -D / 2.0 + 0.08), 64, Color(style.band))
	kit.slab(Kit.at(0, 0, 1.4), 3.4, 0.02, 2.4, Color("#ff9f80"), 0.4, 0.0)   # tapete
	for t in [[-3.0, 0.0, true], [0.0, 1.4, false], [3.0, 0.0, true]]:
		_table_round(t[0], t[1])
		_seat(Vector3(t[0] - 0.85, 0, t[1]), PI / 2.0)
		_seat(Vector3(t[0] + 0.85, 0, t[1]), -PI / 2.0)
		if t[2]:
			_seat(Vector3(t[0], 0, t[1] - 0.85), 0.0)


func _cantina() -> void:
	_counter(Vector3(-1.5, 0, -3.55), 4.5, "cantina")
	_shelf_wall(-1.5, 4.0)
	_label("Menu", style.menu, Vector3(2.6, 2.3, -D / 2.0 + 0.08), 40)
	_label("Letreiro", style.name, Vector3(-1.5, 3.0, -D / 2.0 + 0.08), 60, Color(style.band))
	# panos coloridos (padrão de capulana) na parede do fundo
	var panos := ["#ff6f6f", "#ffd166", "#3fa7e0", "#7ed957"]
	for i in 4:
		kit.slab(Kit.at(1.4 + i * 0.75, 0.15, -D / 2.0 + 0.06), 0.6, 0.9, 0.03, Color(panos[i]), 0.05, 0.0)
	for x in [-2.2, 2.2]:
		_table_long(x, 0.0, 3.0)
		for dz in [-0.75, 0.75]:
			_seat(Vector3(x - 0.85, 0, dz), PI / 2.0)
			_seat(Vector3(x + 0.85, 0, dz), -PI / 2.0)


func _loja() -> void:
	_counter(Vector3(3.3, 0, 2.2), 2.4, "loja", -PI / 2.0)
	_label("Letreiro", style.name, Vector3(0, 3.0, -D / 2.0 + 0.08), 60, Color(style.band))
	_label("Menu", style.menu, Vector3(3.2, 2.5, -D / 2.0 + 0.08), 34)
	# gôndolas com produtos coloridos
	var cols := ["#ff6f6f", "#ffd166", "#4fd1c5", "#a77bff", "#7ed957", "#5aaeff", "#ff9f43"]
	for gx in [-3.0, -0.6]:
		kit.slab(Kit.at(gx, 0, -1.2), 1.0, 1.5, 4.2, Color("#fff8ec"), 0.08, 0.02)
		for level in range(3):
			var z := -3.1
			var i := 0
			while z < 0.7:
				for side in [-1.0, 1.0]:
					kit.slab(Kit.at(gx + side * 0.4, 0.25 + level * 0.45, z), 0.22, 0.3, 0.32, Color(cols[(i + level) % cols.size()]), 0.05, 0.015)
				z += 0.42
				i += 1
		_solid(Vector3(1.0, 1.6, 4.2), Vector3(gx, 0.8, -1.2))
	# frigoríficos (vidro luminoso) na parede do fundo
	for fx in [1.8, 3.4]:
		kit.slab(Kit.at(fx, 0, -D / 2.0 + 0.45), 1.4, 2.2, 0.8, Color("#dfe3ee"), 0.08, 0.02)
		kit.slab(Kit.at(fx, 0.25, -D / 2.0 + 0.86), 1.2, 1.7, 0.03, Color("#bfeaff"), 0.04, 0.0)
		_solid(Vector3(1.4, 2.2, 0.8), Vector3(fx, 1.1, -D / 2.0 + 0.45))
	# balcão de janela com bancos altos
	kit.slab(Kit.at(-W / 2.0 + 0.3, 0.95, 2.1), 0.5, 0.06, 2.4, Color("#c9925f"), 0.04, 0.01)
	_solid(Vector3(0.5, 1.0, 2.4), Vector3(-W / 2.0 + 0.3, 0.5, 2.1))
	for z in [1.5, 2.7]:
		_seat(Vector3(-W / 2.0 + 1.0, 0, z), -PI / 2.0, true)
