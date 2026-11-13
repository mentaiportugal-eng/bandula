extends RefCounted
## Catálogo de mobília do Bandula: cria o nó de cada peça (malha chanfrada/torneada,
## colisão e, quando é o caso, o script interativo). Usado pelo gerador de interiores
## e pelo modo Decoração. Frente das peças = +Z local; base em y = 0.
##
##   seat    → Area3D [interactable_furniture.gd, seat] + SitPoint + Approach
##   counter → Area3D [interactable_furniture.gd, counter] + Atendente
##   outros  → Node3D com malha e StaticBody3D (tapete sem colisão; candeeiro com luz)

const Kit = preload("res://scripts/interiors/interior_kit.gd")
const FURN := "res://scripts/interiors/interactable_furniture.gd"

static var _meshes := {}

## Tamanho ocupado (x, z) de cada peça — usado para colisão e encaixe.
const FOOTPRINT := {
	"cadeira": Vector2(0.5, 0.5), "banco": Vector2(0.45, 0.45), "sofa": Vector2(1.9, 0.85),
	"mesa_redonda": Vector2(1.2, 1.2), "mesa": Vector2(1.8, 1.0), "balcao": Vector2(2.6, 0.8),
	"estante": Vector2(1.6, 0.45), "frigorifico": Vector2(0.9, 0.75), "cama": Vector2(1.6, 2.1),
	"planta": Vector2(0.6, 0.6), "tapete": Vector2(2.4, 1.6), "candeeiro": Vector2(0.4, 0.4),
}


static func footprint(fid: String) -> Vector2:
	return FOOTPRINT.get(fid, Vector2(0.8, 0.8))


static func mesh(fid: String, accent := Color("#e2725b")) -> ArrayMesh:
	var key := "%s|%s" % [fid, accent.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var k = Kit.new()
	var wood := Color("#c9925f")
	var dark := Color("#8a5a3c")
	match fid:
		"cadeira", "banco":
			var leg_h := 0.44 if fid == "cadeira" else 0.7
			for p in [[-0.19, -0.19], [0.19, -0.19], [-0.19, 0.19], [0.19, 0.19]]:
				k.lathe(Kit.at(p[0], 0, p[1]), [Vector2(0, 0), Vector2(0.03, 0), Vector2(0.025, leg_h), Vector2(0, leg_h)], wood, 8)
			k.slab(Kit.at(0, leg_h - 0.02, 0), 0.48, 0.07, 0.48, accent, 0.08, 0.02)
			if fid == "cadeira":
				k.slab(Kit.at(0, 0.48, -0.21), 0.46, 0.5, 0.06, wood, 0.03, 0.015)
				k.slab(Kit.at(0, 0.88, -0.21), 0.5, 0.08, 0.08, accent, 0.03, 0.015)
		"sofa":
			k.slab(Kit.at(0, 0, 0), 1.9, 0.42, 0.85, accent, 0.18, 0.06)
			k.slab(Kit.at(0, 0.42, -0.32), 1.9, 0.5, 0.22, accent.darkened(0.12), 0.12, 0.05)
			for sx in [-1.0, 1.0]:
				k.slab(Kit.at(sx * 0.86, 0.42, 0), 0.2, 0.28, 0.85, accent.darkened(0.12), 0.08, 0.04)
			for sx in [-0.45, 0.45]:
				k.slab(Kit.at(sx, 0.42, 0.06), 0.82, 0.1, 0.62, Color("#fff1d6"), 0.12, 0.04)
		"mesa_redonda":
			k.lathe(Kit.at(0, 0, 0), [Vector2(0, 0), Vector2(0.32, 0), Vector2(0.3, 0.05), Vector2(0.07, 0.1), Vector2(0.06, 0.7), Vector2(0, 0.7)], dark)
			k.lathe(Kit.at(0, 0.7, 0), [Vector2(0, 0), Vector2(0.58, 0), Vector2(0.6, 0.03), Vector2(0.58, 0.06), Vector2(0, 0.06)], Color("#f6e7c9"), 24)
		"mesa":
			k.slab(Kit.at(0, 0.7, 0), 1.8, 0.07, 1.0, Color("#f6e7c9"), 0.12, 0.02)
			for p in [[-0.8, -0.4], [0.8, -0.4], [-0.8, 0.4], [0.8, 0.4]]:
				k.lathe(Kit.at(p[0], 0, p[1]), [Vector2(0, 0), Vector2(0.045, 0), Vector2(0.04, 0.7), Vector2(0, 0.7)], wood, 8)
		"balcao":
			k.slab(Kit.at(0, 0, 0), 2.6, 1.0, 0.75, wood, 0.08, 0.03)
			k.slab(Kit.at(0, 1.0, 0), 2.75, 0.08, 0.9, Color("#fff8ec"), 0.06, 0.02)
			k.slab(Kit.at(0, 0.25, 0.39), 2.4, 0.5, 0.04, accent, 0.04, 0.01)
			k.slab(Kit.at(0.7, 1.08, 0), 0.4, 0.3, 0.3, Color("#3b3355"), 0.04, 0.01)     # caixa registadora
		"estante":
			k.slab(Kit.at(0, 0, 0), 1.6, 1.9, 0.45, Color("#fff8ec"), 0.05, 0.02)
			var cols := ["#ff6f6f", "#ffd166", "#4fd1c5", "#a77bff", "#7ed957", "#5aaeff"]
			for lvl in 4:
				var y := 0.2 + lvl * 0.45
				for i in 5:
					k.slab(Kit.at(-0.6 + i * 0.3, y, 0.08), 0.22, 0.3, 0.26, Color(cols[(i + lvl) % cols.size()]), 0.05, 0.015)
		"frigorifico":
			k.slab(Kit.at(0, 0, 0), 0.9, 2.0, 0.75, Color("#dfe3ee"), 0.08, 0.02)
			k.slab(Kit.at(0, 0.25, 0.38), 0.75, 1.55, 0.03, Color("#bfeaff"), 0.04, 0.0)
		"cama":
			k.slab(Kit.at(0, 0, 0), 1.6, 0.42, 2.1, wood, 0.08, 0.03)
			k.slab(Kit.at(0, 0.42, 0.05), 1.5, 0.18, 1.95, Color("#fff8ec"), 0.12, 0.05)
			k.slab(Kit.at(0, 0.6, 0.35), 1.5, 0.06, 1.3, accent, 0.1, 0.02)              # lençol de capulana
			k.slab(Kit.at(0, 0, -1.0), 1.6, 1.0, 0.12, dark, 0.05, 0.02)                  # cabeceira
			for sx in [-0.38, 0.38]:
				k.slab(Kit.at(sx, 0.6, -0.72), 0.6, 0.14, 0.36, Color("#ffffff"), 0.1, 0.05)
		"planta":
			k.lathe(Kit.at(0, 0, 0), [Vector2(0, 0), Vector2(0.2, 0), Vector2(0.27, 0.45), Vector2(0.24, 0.5), Vector2(0, 0.5)], Color("#e2725b"))
			k.lathe(Kit.at(0, 0.45, 0), [Vector2(0, 0), Vector2(0.32, 0.12), Vector2(0.4, 0.5), Vector2(0.28, 0.85), Vector2(0, 0.95)], Color("#5fcf7a"))
		"tapete":
			var stripes := ["#e2725b", "#ffd166", "#2fbfb0", "#3b3355"]
			for i in 4:
				k.slab(Kit.at(0, 0.0, -0.6 + i * 0.4), 2.4, 0.015, 0.4, Color(stripes[i]), 0.02, 0.0)
		"candeeiro":
			k.lathe(Kit.at(0, 0, 0), [Vector2(0, 0), Vector2(0.18, 0), Vector2(0.16, 0.04), Vector2(0.03, 0.08), Vector2(0.025, 1.5), Vector2(0, 1.5)], Color("#3b3355"), 10)
			k.lathe(Kit.at(0, 1.4, 0), [Vector2(0.22, 0), Vector2(0.12, 0.35), Vector2(0, 0.37)], Color("#ffd166"), 14)
	var m: ArrayMesh = k.commit()
	_meshes[key] = m
	return m


## Nó pronto a colocar. `shop_type` só conta para balcões.
static func create(fid: String, shop_type := "loja", accent := Color("#e2725b")) -> Node3D:
	var fp := footprint(fid)
	var kind: String = GameManager.furniture_def(fid).get("kind", "decor")
	var root: Node3D
	if kind == "seat" or kind == "counter":
		var a := Area3D.new()
		a.set_script(load(FURN))
		a.set("kind", "seat" if kind == "seat" else "counter")
		a.set("shop_type", shop_type)
		a.set("label", GameManager.furniture_def(fid).get("name", fid))
		root = a
		var zone := CollisionShape3D.new()
		if kind == "seat":
			var sp := SphereShape3D.new()
			sp.radius = 1.25
			zone.shape = sp
			zone.position = Vector3(0, 0.8, 0)
		else:
			var bx := BoxShape3D.new()
			bx.size = Vector3(fp.x, 2.0, 1.6)
			zone.shape = bx
			zone.position = Vector3(0, 1.0, 1.2)
		root.add_child(zone)
		if kind == "seat":
			var seat_y := 0.05 if fid != "banco" else 0.3
			for m in [["SitPoint", Vector3(0, seat_y, 0.22 if fid != "sofa" else 0.3)], ["Approach", Vector3(0, 0.05, 0.9 if fid == "sofa" else -0.85)]]:
				var mk := Marker3D.new()
				mk.name = m[0]
				mk.position = m[1]
				root.add_child(mk)
		else:
			var clerk := Marker3D.new()
			clerk.name = "Atendente"
			clerk.position = Vector3(0, 0, -0.85)
			root.add_child(clerk)
	else:
		root = Node3D.new()
	root.name = fid.capitalize().replace(" ", "")
	root.set_meta("furniture_id", fid)
	var mi := MeshInstance3D.new()
	mi.name = "Malha"
	mi.mesh = mesh(fid, accent)
	root.add_child(mi)
	if fid != "tapete":
		var body := StaticBody3D.new()
		body.name = "Colisao"
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var h: float = {"cadeira": 0.5, "banco": 0.75, "sofa": 0.5, "mesa_redonda": 0.8, "mesa": 0.8, "balcao": 1.1, "estante": 1.9, "frigorifico": 2.0, "cama": 0.6, "planta": 1.3, "candeeiro": 1.5}.get(fid, 1.0)
		box.size = Vector3(fp.x, h, fp.y)
		cs.shape = box
		cs.position = Vector3(0, h / 2.0, 0)
		body.add_child(cs)
		root.add_child(body)
	if fid == "candeeiro":
		var l := OmniLight3D.new()
		l.light_color = Color("#ffd9a3")
		l.light_energy = 1.1
		l.omni_range = 4.5
		l.position = Vector3(0, 1.55, 0)
		root.add_child(l)
	return root
