extends RefCounted
## Constrói a cena do mundo de Luanda para o jogo (scenes/world/luanda.tscn):
##   Terreno (malha + colisão trimesh) · Mar (shader) · Estradas · Cidade (+ colisão)
##   BarreiraCosta · Limites · Marcos (Fortaleza Shopping, Esquadra da Ingombota, torres da Baixa)
##   Coqueiros · Imbondeiros · Quiosques · GuardaSois (peças do kit com colisão)
##   Lotes (Area3D compráveis: Baixa, bairros e Ilha) · Spawns (Marker3D)
## Mesma geografia do jogo web (geo.gd). Se `layout_path` existir (layout.json do
## editor do mapa), usa essas posições para as peças do kit.

const Geo = preload("res://scripts/world/geo.gd")
const Kit = preload("res://scripts/world/kit_library.gd")
const PLOT_SCRIPT := "res://scripts/plot.gd"
const IKit = preload("res://scripts/interiors/interior_kit.gd")

const WORLD_SCENE := "res://scenes/world/luanda.tscn"
const KIOSK_COLORS := ["#ffd166", "#ff8fab", "#4fd1c5", "#ff9f43", "#a77bff", "#7ed957"]
const UMBRELLA_COLORS := ["#ff5a79", "#ffd166", "#4fd1c5", "#ff9f43", "#5aaeff", "#a77bff"]
const LOT_PRICE := {"centro": 1800, "residencial": 1000, "industrial": 1300, "quartel": 900, "ilha": 2200}
const AREA_NAME := {"centro": "Baixa de Luanda", "residencial": "Maianga", "industrial": "Cazenga", "quartel": "Ingombota", "ilha": "Ilha de Luanda"}
const ILHA_PLOTS_Z := [60.0, 8.0, -44.0, -96.0, -148.0, -200.0]

const LAYER_WORLD := 1
const LAYER_INTERACT := 8   # camada 4

var root: Node3D
var rng := RandomNumberGenerator.new()
var _scenes := {}
var _counts := {}


static func build(seed: int = 1234, layout_path := "") -> Node3D:
	var b = new()
	b.rng.seed = seed
	return b._build(layout_path)


static func save(world_root: Node3D, path: String = WORLD_SCENE) -> Error:
	var ps := PackedScene.new()
	var err := ps.pack(world_root)
	return err if err != OK else ResourceSaver.save(ps, path)


func _build(layout_path: String) -> Node3D:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/world"))
	root = Node3D.new()
	root.name = "Luanda"
	var terrain := _terrain_mesh()
	_mesh_node("Terreno", terrain, "res://scenes/world/terreno.res", _toon(0.92))
	_static_shape("ColisaoTerreno", terrain.create_trimesh_shape(), Vector3.ZERO, "res://scenes/world/terreno_colisao.res")
	_mesh_node("Mar", _sea_mesh(), "res://scenes/world/mar.res", null, false)
	_mesh_node("Estradas", _roads_mesh(), "res://scenes/world/estradas.res", _toon(0.88))
	_mesh_node("Cidade", _city_mesh(), "res://scenes/world/cidade.res", _toon(0.8))
	_city_collision()
	_coast_barrier()
	_marcos()
	for g in ["Coqueiros", "Imbondeiros", "Quiosques", "GuardaSois", "Lotes", "Spawns"]:
		_group(g)
	_plots()
	var layout = _read_layout(layout_path)
	if layout != null:
		_apply_layout(layout)
	else:
		_city_palms()
		_marginal()
		_ilha()
		_nature()
	_ilha_restaurants()
	_kiosk_portals()
	_spawns()
	return root


# ------------------------------------------------------------------ utilidades

func _group(name: String) -> Node3D:
	var n := root.get_node_or_null(name) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = name
		root.add_child(n)
		n.owner = root
	return n


func _own(n: Node, parent: Node) -> void:
	parent.add_child(n)
	n.owner = root


func _place(group: String, piece: String, pos: Vector3, rot_y: float = 0.0, s: float = 1.0, meta := {}) -> Node3D:
	if not _scenes.has(piece):
		_scenes[piece] = Kit.scene(piece)
	var inst: Node3D = _scenes[piece].instantiate()
	_counts[group] = _counts.get(group, 0) + 1
	var base: String = {"Coqueiros": "coqueiro", "Imbondeiros": "imbondeiro", "Quiosques": "quiosque", "GuardaSois": "guarda_sol"}.get(group, group.to_lower())
	inst.name = "%s_%03d" % [base, _counts[group]]
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * s
	for k in meta:
		inst.set_meta(k, meta[k])
	_own(inst, _group(group))
	return inst


func _mesh_node(name: String, mesh: ArrayMesh, path: String, mat: Material, shadows := true) -> void:
	if mat != null:
		mesh.surface_set_material(0, mat)
	ResourceSaver.save(mesh, path)
	mesh.take_over_path(path)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(mi, root)


func _static_shape(name: String, shape: Shape3D, pos: Vector3, path := "") -> StaticBody3D:
	if path != "":
		ResourceSaver.save(shape, path)
		shape.take_over_path(path)
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_own(body, root)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	_own(cs, body)
	return body


func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = pos
	_own(cs, parent)


func _toon(roughness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(Kit.TOON)
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("rim_strength", 0.12)
	return m


# ------------------------------------------------------------------ malhas (cores por vértice em espaço linear)

func _terrain_mesh() -> ArrayMesh:
	var half := Geo.MAP_HALF + 60.0
	var step := 4.0
	var n := int(half * 2.0 / step) + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in range(n):
		for i in range(n):
			var x := -half + i * step
			var z := -half + j * step
			var in_city := absf(x) <= Geo.CITY_HALF + 1.0 and absf(z) <= Geo.CITY_HALF + 1.0
			hs[j * n + i] = -0.06 if in_city else Geo.terrain_height(x, z)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in range(n):
		for i in range(n):
			var x := -half + i * step
			var z := -half + j * step
			var h := hs[j * n + i]
			verts.append(Vector3(x, h, z))
			norms.append(Vector3(hs[j * n + maxi(i - 1, 0)] - hs[j * n + mini(i + 1, n - 1)], 2.0 * step, hs[maxi(j - 1, 0) * n + i] - hs[mini(j + 1, n - 1) * n + i]).normalized())
			var in_city := absf(x) <= Geo.CITY_HALF + 1.0 and absf(z) <= Geo.CITY_HALF + 1.0
			cols.append(Geo.terrain_color(x, z, h, in_city).srgb_to_linear())
	for j in range(n - 1):
		for i in range(n - 1):
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sea_mesh() -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2600, 2600)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	var arrays := plane.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for k in range(verts.size()):
		verts[k].y += Geo.WATER_LEVEL
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water_stylized.gdshader")
	mesh.surface_set_material(0, m)
	return mesh


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	if cr.dot(hint) > 0.0:
		var t := b
		b = c
		c = t
		cr = -cr
	st.set_color(col.srgb_to_linear())
	st.set_normal(-cr.normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
	_tri(st, a, b, c, col, hint)
	_tri(st, a, c, d, col, hint)


func _rrect(w: float, d: float, r: float, seg: int = 3) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = clampf(r, 0.0, minf(w, d) / 2.0 - 0.001)
	var hw := w / 2.0 - r
	var hd := d / 2.0 - r
	for corner in [[hw, hd, 0.0], [-hw, hd, PI / 2.0], [-hw, -hd, PI], [hw, -hd, PI * 1.5]]:
		if r <= 0.0:
			pts.append(Vector2(corner[0], corner[1]))
			continue
		for k in range(seg + 1):
			var a: float = corner[2] + (PI / 2.0) * k / seg
			pts.append(Vector2(corner[0] + cos(a) * r, corner[1] + sin(a) * r))
	return pts


## Laje de cantos arredondados com chanfro.
func _slab(st: SurfaceTool, cx: float, y0: float, cz: float, w: float, d: float, h: float, r: float, bev: float, col: Color) -> void:
	bev = minf(bev, h / 3.0)
	var rings := [[bev, y0], [0.0, y0 + bev], [0.0, y0 + h - bev], [bev, y0 + h]]
	var pts := []
	for ring in rings:
		pts.append(_rrect(w - 2.0 * ring[0], d - 2.0 * ring[0], maxf(r - ring[0], 0.0)))
	for k in range(3):
		var lo: PackedVector2Array = pts[k]
		var hi: PackedVector2Array = pts[k + 1]
		var vy := -0.6 if k == 0 else (0.6 if k == 2 else 0.0)
		for i in range(lo.size()):
			var i2 := (i + 1) % lo.size()
			var a := Vector3(cx + lo[i].x, rings[k][1], cz + lo[i].y)
			var b := Vector3(cx + lo[i2].x, rings[k][1], cz + lo[i2].y)
			var e := Vector3(cx + hi[i2].x, rings[k + 1][1], cz + hi[i2].y)
			var f := Vector3(cx + hi[i].x, rings[k + 1][1], cz + hi[i].y)
			var mid := (a + b) / 2.0 - Vector3(cx, 0, cz)
			_quad(st, a, b, e, f, col, Vector3(mid.x, vy * maxf(absf(mid.x), absf(mid.z)), mid.z))
	for cap in [[0, y0, Vector3.DOWN], [3, y0 + h, Vector3.UP]]:
		var ring: PackedVector2Array = pts[cap[0]]
		for i in range(ring.size()):
			var i2 := (i + 1) % ring.size()
			_tri(st, Vector3(cx, cap[1], cz), Vector3(cx + ring[i].x, cap[1], cz + ring[i].y), Vector3(cx + ring[i2].x, cap[1], cz + ring[i2].y), col, cap[2])


func _city_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := Geo.CITY_HALF
	_quad(st, Vector3(-H, 0.004, -H), Vector3(H, 0.004, -H), Vector3(H, 0.004, H), Vector3(-H, 0.004, H), Color("#858cb0"), Vector3.UP)
	var bc := Geo.block_centers()
	# faixas das ruas
	for rc in Geo.road_centers():
		for i in range(Geo.CITY_BLOCKS):
			var from: float = bc[i] - Geo.CITY_BLOCK / 2.0 + 6.0
			while from <= bc[i] + Geo.CITY_BLOCK / 2.0 - 6.0:
				_quad(st, Vector3(from, 0.03, rc - 0.11), Vector3(from + 2.4, 0.03, rc - 0.11), Vector3(from + 2.4, 0.03, rc + 0.11), Vector3(from, 0.03, rc + 0.11), Color("#fff4c2"), Vector3.UP)
				_quad(st, Vector3(rc - 0.11, 0.03, from), Vector3(rc + 0.11, 0.03, from), Vector3(rc + 0.11, 0.03, from + 2.4), Vector3(rc - 0.11, 0.03, from + 2.4), Color("#fff4c2"), Vector3.UP)
				from += 5.0
	for bx in range(Geo.CITY_BLOCKS):
		for bz in range(Geo.CITY_BLOCKS):
			var cx: float = bc[bx]
			var cz: float = bc[bz]
			var district := Geo.block_district(bx, bz)
			var kind := Geo.block_kind(bx, bz)
			_slab(st, cx, -0.18, cz, Geo.CITY_BLOCK, Geo.CITY_BLOCK, 0.36, 0.6, 0.12, Color("#e7defa"))
			var ground: Color = Geo.DISTRICT_GROUND[district]
			if kind == "park":
				ground = Color("#a6e86b")
			elif kind == "plaza" or kind == "towers":
				ground = Color("#ffe0d6")
			var inner := Geo.CITY_BLOCK - Geo.CITY_SIDEWALK * 2.0
			_slab(st, cx, Geo.CITY_CURB, cz, inner, inner, 0.06, 0.5, 0.02, ground)
	return st.commit()


func _roads_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for road in Geo.extra_roads():
		var src: Array = road.pts
		var pts: Array = []
		for i in range(src.size() - 1):
			var a: Vector2 = src[i]
			var b: Vector2 = src[i + 1]
			var nseg := maxi(1, int(ceil(a.distance_to(b) / 3.0)))
			for k in range(nseg):
				pts.append(a.lerp(b, float(k) / nseg))
		pts.append(src[src.size() - 1])
		var hw: float = road.w / 2.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in range(pts.size()):
			var p: Vector2 = pts[i]
			var t: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-t.y, t.x)
			var y := maxf(Geo.terrain_height(p.x, p.y), maxf(Geo.terrain_height(p.x + nrm.x * hw, p.y + nrm.y * hw), Geo.terrain_height(p.x - nrm.x * hw, p.y - nrm.y * hw))) + 0.07
			var l := Vector3(p.x + nrm.x * hw, y, p.y + nrm.y * hw)
			var r := Vector3(p.x - nrm.x * hw, y, p.y - nrm.y * hw)
			if i > 0:
				_quad(st, prev_l, l, r, prev_r, Color("#858cb0"), Vector3.UP)
				if i % 2 == 0:
					var c0 := Vector3(pts[i - 1].x, y + 0.02, pts[i - 1].y)
					var c1 := Vector3(p.x, y + 0.02, p.y)
					var off := Vector3(nrm.x, 0, nrm.y) * 0.11
					_quad(st, c0 + off, c1 + off, c1 - off, c0 - off, Color("#fff4c2"), Vector3.UP)
			prev_l = l
			prev_r = r
	return st.commit()


# ------------------------------------------------------------------ colisões

func _city_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "ColisaoCidade"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_own(body, root)
	var H := Geo.CITY_HALF
	_box(body, Vector3(H * 2.0 + 4.0, 1.0, H * 2.0 + 4.0), Vector3(0, -0.5, 0))          # asfalto (topo em y = 0)
	for cx in Geo.block_centers():
		for cz in Geo.block_centers():
			_box(body, Vector3(Geo.CITY_BLOCK, 0.36, Geo.CITY_BLOCK), Vector3(cx, 0.0, cz))  # quadras com meio-fio


## Paredes invisíveis ao longo de toda a beira-mar (ninguém entra no mar) + limites do mapa.
func _coast_barrier() -> void:
	var body := StaticBody3D.new()
	body.name = "BarreiraCosta"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_own(body, root)
	var st := 4.0
	var L := Geo.MAP_HALF
	var x := -L
	while x <= L:
		var z := -L
		while z <= L:
			if Geo.is_water(x, z) and not (Geo.is_water(x + st, z) and Geo.is_water(x - st, z) and Geo.is_water(x, z + st) and Geo.is_water(x, z - st)):
				_box(body, Vector3(st * 1.1, 6.0, st * 1.1), Vector3(x, Geo.WATER_LEVEL + 1.2, z))
			z += st
		x += st
	var lim := Geo.MAP_HALF - 5.0
	for b in [[Vector3(lim + 1.0, 10, 0), Vector3(2, 40, lim * 2.0 + 4.0)], [Vector3(-lim - 1.0, 10, 0), Vector3(2, 40, lim * 2.0 + 4.0)], [Vector3(0, 10, lim + 1.0), Vector3(lim * 2.0 + 4.0, 40, 2)], [Vector3(0, 10, -lim - 1.0), Vector3(lim * 2.0 + 4.0, 40, 2)]]:
		_box(body, b[1], b[0])


# ------------------------------------------------------------------ marcos

func _marcos() -> void:
	var marcos := _group("Marcos")
	_fortaleza_shopping(marcos)
	_esquadra(marcos)
	var bc := Geo.block_centers()
	for t in [["torre_a", -7.5, -7.0], ["torre_b", 9.0, -6.5], ["torre_c", -3.0, 9.5]]:
		var tower := Kit.scene(t[0]).instantiate() as Node3D
		tower.name = "TorreBaixa_" + t[0].substr(6)
		tower.position = Vector3(bc[2] + t[1], Geo.CITY_CURB, bc[2] + t[2])
		_own(tower, marcos)
		var front: float = _front_of(tower)
		_portal(tower, Vector3(0, 0, front + 0.7), {"kind": "comercio", "size": "g", "business": "escritorio", "furnish": "auto"},
			{"torre_a": "Torre Kianda Business", "torre_b": "Torre Ngola", "torre_c": "Edifício Marginal"}[t[0]], "torre-" + t[0].substr(6), "escritorio")


## Fortaleza Shopping: centro comercial moderno no morro (interior gerado, 6 lojas).
func _fortaleza_shopping(parent: Node3D) -> void:
	var fy := Geo.terrain_height(Geo.FORT.x, Geo.FORT.z)
	var mall := Node3D.new()
	mall.name = "FortalezaShopping"
	mall.position = Vector3(Geo.FORT.x, fy, Geo.FORT.z)
	mall.rotation.y = PI / 2.0                                    # entrada virada para a estrada de subida
	_own(mall, parent)
	var k = IKit.new()
	k.slab(IKit.at(0, -0.3, 0), 40.0, 0.6, 30.0, Color("#efe4d2"), 0.6, 0.1)
	k.slab(IKit.at(0, 0, 0), 36.0, 11.0, 26.0, Color("#fff1d6"), 1.2, 0.2)
	k.slab(IKit.at(0, 1.0, 13.02), 30.0, 8.0, 0.14, Color("#a6e3ff"), 0.2, 0.03)          # fachada de vidro
	for i in range(11):
		k.slab(IKit.at(-15.0 + i * 3.0, 1.0, 13.12), 0.22, 8.0, 0.12, Color("#ffffff"), 0.05, 0.02)
	for x in [-17.6, 17.6]:
		k.slab(IKit.at(x, 0, 13.0), 0.8, 11.0, 1.0, Color("#e2725b"), 0.2, 0.05)
	k.slab(IKit.at(0, 11.0, 0), 36.6, 0.6, 26.6, Color("#e2725b"), 0.4, 0.08)            # platibanda
	k.slab(IKit.at(0, 4.3, 15.5), 13.0, 0.45, 5.0, Color("#e2725b"), 0.4, 0.1)            # marquise
	for x in [-5.5, 5.5]:
		k.lathe(IKit.at(x, 0, 17.4), [Vector2(0, 0), Vector2(0.3, 0), Vector2(0.24, 0.2), Vector2(0.2, 4.3), Vector2(0, 4.3)], Color("#fff8ec"), 14)
	k.slab(IKit.at(0, 0, 13.05), 6.0, 3.8, 0.16, Color("#7fc4ea"), 0.1, 0.02)              # portas de vidro
	k.slab(IKit.at(0, 11.6, 11.6), 20.0, 2.6, 0.8, Color("#3b3355"), 0.3, 0.06)            # caixa do letreiro
	var mi := MeshInstance3D.new()
	mi.name = "Edificio"
	mi.mesh = k.commit()
	_own(mi, mall)
	var sign := Label3D.new()
	sign.name = "Letreiro"
	sign.text = "FORTALEZA SHOPPING"
	sign.font_size = 220
	sign.outline_size = 24
	sign.modulate = Color("#ffd166")
	sign.outline_modulate = Color("#3b3355")
	sign.position = Vector3(0, 12.9, 12.05)
	_own(sign, mall)
	var body := StaticBody3D.new()
	body.name = "Colisao"
	_own(body, mall)
	_box(body, Vector3(36.0, 11.0, 26.0), Vector3(0, 5.5, 0))
	var portal := Area3D.new()
	portal.name = "Porta"
	portal.set_script(load("res://scripts/interiors/building_portal.gd"))
	portal.set("mode", "fade")
	portal.set("generated", true)
	portal.set("interior_type", "shopping")
	portal.set("spec", {"kind": "shopping"})
	portal.set("display_name", "Fortaleza Shopping")
	portal.set("portal_id", "fortaleza-shopping")
	portal.position = Vector3(0, 0, 13.9)
	_own(portal, mall)


## Esquadra da Ingombota (Guarda de Bandula): destino de quem é detido.
func _esquadra(parent: Node3D) -> void:
	var bc := Geo.block_centers()
	var st := Node3D.new()
	st.name = "EsquadraIngombota"
	st.position = Vector3(bc[0], Geo.CITY_CURB, bc[5])
	st.rotation.y = PI                                            # fachada para a rua a norte
	_own(st, parent)
	var k = IKit.new()
	var blue := Color("#2f3b8f")
	k.slab(IKit.at(0, 0, 0), 28.0, 0.3, 16.0, Color("#e7defa"), 0.5, 0.08)
	k.slab(IKit.at(0, 0.3, 0), 24.0, 7.4, 12.0, Color("#f4f6ff"), 0.5, 0.12)
	k.slab(IKit.at(0, 5.5, 0), 24.3, 0.9, 12.3, blue, 0.4, 0.08)
	k.slab(IKit.at(0, 7.7, 0), 24.8, 0.4, 12.8, Color("#e7defa"), 0.4, 0.08)
	for x in [-9.0, -6.0, -3.0, 3.0, 6.0, 9.0]:
		for y in [1.6, 3.9]:
			k.slab(IKit.at(x, y, 6.02), 1.5, 1.3, 0.08, Color("#a9dcff"), 0.08, 0.02)
			k.slab(IKit.at(x, y - 0.12, 6.08), 1.8, 0.12, 0.2, Color("#ffffff"), 0.04, 0.01)
	k.slab(IKit.at(0, 0.3, 6.04), 2.6, 2.7, 0.12, Color("#3b3355"), 0.1, 0.02)              # porta
	k.slab(IKit.at(0, 3.5, 7.4), 7.0, 0.35, 3.0, blue, 0.3, 0.06)                          # pórtico
	for x in [-3.0, 3.0]:
		k.lathe(IKit.at(x, 0.3, 8.6), [Vector2(0, 0), Vector2(0.24, 0), Vector2(0.2, 0.15), Vector2(0.17, 3.2), Vector2(0, 3.2)], Color("#ffffff"), 14)
	k.lathe(IKit.at(10.5, 0.3, 9.0), [Vector2(0, 0), Vector2(0.14, 0), Vector2(0.06, 0.2), Vector2(0.05, 9.0), Vector2(0, 9.0)], Color("#ffffff"), 10)
	k.slab(IKit.at(11.3, 7.9, 9.0), 1.6, 1.0, 0.05, blue, 0.05, 0.0)                       # bandeira da Guarda
	var mi := MeshInstance3D.new()
	mi.name = "Edificio"
	mi.mesh = k.commit()
	_own(mi, st)
	for t in [["Letreiro", "ESQUADRA DA INGOMBOTA", 6.55, 120, Color("#ffffff")], ["Subtitulo", "Guarda de Bandula", 4.7, 80, blue]]:
		var l := Label3D.new()
		l.name = t[0]
		l.text = t[1]
		l.font_size = t[3]
		l.outline_size = 16
		l.modulate = t[4]
		l.outline_modulate = Color("#3b3355") if t[0] == "Letreiro" else Color("#ffffff")
		l.position = Vector3(0, t[2], 6.3 if t[0] == "Letreiro" else 9.0)
		_own(l, st)
	var body := StaticBody3D.new()
	body.name = "Colisao"
	_own(body, st)
	_box(body, Vector3(24.0, 7.6, 12.0), Vector3(0, 4.1, 0))
	_portal(st, Vector3(0, 0, 9.4), {"kind": "esquadra", "furnish": "auto"}, "Esquadra da Ingombota", "esquadra-ingombota", "esquadra")
	for x in [-8.0, -4.5]:                                        # viaturas estacionadas
		var car: Node3D = load("res://scenes/vehicles/guarda.tscn").instantiate()
		car.position = Vector3(x, 0.6, 11.0)
		_own(car, st)


## Porta com interior gerado para um edifício do mapa.
func _portal(building: Node3D, pos: Vector3, spec: Dictionary, shown: String, id: String, kind: String) -> void:
	var portal := Area3D.new()
	portal.name = "Porta"
	portal.set_script(load("res://scripts/interiors/building_portal.gd"))
	portal.set("mode", "fade")
	portal.set("generated", true)
	portal.set("interior_type", kind)
	portal.set("spec", spec)
	portal.set("display_name", shown)
	portal.set("portal_id", id)
	portal.position = pos
	_own(portal, building)


## Distância do centro de uma peça do kit à fachada (+Z), pela sua colisão.
func _front_of(piece: Node3D) -> float:
	var cs := piece.get_node_or_null("Colisao/Forma") as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		return cs.position.z + (cs.shape as BoxShape3D).size.z / 2.0
	return 5.0


## Cada quiosque da Ilha tem um pequeno café lá dentro.
func _kiosk_portals() -> void:
	var names := ["Quiosque Ginga", "Quiosque do Mar", "Quiosque Muxima", "Quiosque Sol da Ilha", "Quiosque Kianda", "Quiosque Palmeira", "Quiosque Mussulo"]
	var i := 0
	for k in _group("Quiosques").get_children():
		_portal(k, Vector3(0, 0, 3.3), {"kind": "comercio", "size": "p", "business": "cafe", "furnish": "auto"},
			names[i % names.size()], "quiosque-%d" % i, "cafe")
		i += 1


# ------------------------------------------------------------------ lotes compráveis

func _plot(id: String, district: String, center: Vector3, size: float, owner: String, building: String) -> void:
	var a := Area3D.new()
	a.name = id
	a.set_script(load(PLOT_SCRIPT))
	a.position = center
	a.collision_layer = LAYER_INTERACT
	a.collision_mask = 0
	a.monitoring = false
	a.set("plot_id", id)
	a.set("district", district)
	a.set("area_name", AREA_NAME[district])
	a.set("price", LOT_PRICE[district])
	a.set("size", size)
	a.set("initial_owner", owner)
	a.set("initial_building", building)
	_own(a, _group("Lotes"))
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 3.0, size)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.5, 0)
	_own(cs, a)


func _plots() -> void:
	var bc := Geo.block_centers()
	for bx in range(Geo.CITY_BLOCKS):
		for bz in range(Geo.CITY_BLOCKS):
			if Geo.block_kind(bx, bz) != "lots":
				continue
			var district := Geo.block_district(bx, bz)
			for ix in [0, 1]:
				for iz in [0, 1]:
					var center := Vector3(bc[bx] + (9.0 if ix else -9.0), Geo.CITY_CURB, bc[bz] + (9.0 if iz else -9.0))
					var roll := rng.randf()
					var npc := (district == "centro" and roll < 0.7) or (district == "residencial" and roll < 0.66) or (district in ["industrial", "quartel"] and roll < 0.5)
					var building := ""
					if npc:
						building = "comercio" if district in ["centro", "industrial"] else "casa"
					_plot("L%d-%d-%d%d" % [bx, bz, ix, iz], district, center, Geo.CITY_LOT, "npc" if npc else "", building)
	var k := 0
	for z in ILHA_PLOTS_Z:
		var x := Geo.ilha_x(z) - 9.5
		_plot("ILHA-%d" % k, "ilha", Vector3(x, Geo.terrain_height(x, z), z), 11.0, "", "")
		k += 1


# ------------------------------------------------------------------ peças do kit

func _read_layout(path: String):
	if path == "" or not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and data.get("version", 0) == 1 else null


func _apply_layout(L: Dictionary) -> void:
	for p in L.get("palmeira", []):
		_place("Coqueiros", "palmeira", Vector3(p[0], Geo.height_at(p[0], p[1]), p[1]), p[2], p[3])
	for p in L.get("imbondeiro", []):
		_place("Imbondeiros", "imbondeiro", Vector3(p[0], Geo.terrain_height(p[0], p[1]) - 0.1, p[1]), p[2], p[3])
	for p in L.get("quiosque", []):
		var ci := maxi(0, KIOSK_COLORS.find(str(p[3])))
		_place("Quiosques", "quiosque_%d" % ci, Vector3(p[0], Geo.terrain_height(p[0], p[1]), p[1]), p[2], 1.0, {"cor": KIOSK_COLORS[ci]})
	for p in L.get("guarda_sol", []):
		if _near_ilha_plot(p[0], p[1]):
			continue
		var ui := maxi(0, UMBRELLA_COLORS.find(str(p[3])))
		_place("GuardaSois", "guarda_sol_%d" % ui, Vector3(p[0], Geo.terrain_height(p[0], p[1]), p[1]), p[2], 1.0, {"cor": UMBRELLA_COLORS[ui]})


func _near_ilha_plot(x: float, z: float) -> bool:
	for pz in ILHA_PLOTS_Z:
		if absf(z - pz) < 8.0 and absf(x - (Geo.ilha_x(pz) - 9.5)) < 8.0:
			return true
	return false


func _palm(x: float, z: float, s: float, y = null) -> void:
	_place("Coqueiros", "palmeira", Vector3(x, Geo.height_at(x, z) if y == null else y, z), rng.randf() * TAU, s)


func _umbrella(x: float, z: float) -> void:
	var y := Geo.terrain_height(x, z)
	if y < 0.05 or _near_ilha_plot(x, z):
		return
	var ci := rng.randi_range(0, UMBRELLA_COLORS.size() - 1)
	_place("GuardaSois", "guarda_sol_%d" % ci, Vector3(x, y, z), rng.randf() * TAU, 1.0, {"cor": UMBRELLA_COLORS[ci]})


func _city_palms() -> void:
	var bc := Geo.block_centers()
	for bx in range(Geo.CITY_BLOCKS):
		for bz in range(Geo.CITY_BLOCKS):
			var district := Geo.block_district(bx, bz)
			var chance := 0.8 if district == "centro" else (0.25 if district == "industrial" else 0.65)
			for side in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
				if rng.randf() >= chance:
					continue
				var tx: float = bc[bx] + side[0] * 18.6 + ((rng.randf() - 0.5) * 16.0 if side[1] != 0 else 0.0)
				var tz: float = bc[bz] + side[1] * 18.6 + ((rng.randf() - 0.5) * 16.0 if side[0] != 0 else 0.0)
				if district == "centro" or rng.randf() < 0.55:
					_palm(tx, tz, 0.8 + rng.randf() * 0.25, Geo.CITY_CURB)
	for off in [[-14, 3], [14, 4], [8, 14], [14, -15], [-14, -15], [-14, 14]]:
		_palm(bc[2] + off[0], bc[2] + off[1], 0.9, Geo.CITY_CURB)
	for dz in [-9.0, 9.0]:
		_palm(Geo.FORT.x + 29.0, Geo.FORT.z + dz, 1.0)


func _marginal() -> void:
	var z := -150.0
	while z <= 92.0:
		var x := Geo.coast_x(z) + 17.0
		var zi := int(round(z))
		if zi % 12 == 0:
			_palm(x - 4.6, z + (rng.randf() - 0.5) * 2.0, 0.95 + rng.randf() * 0.3)
		if zi % 18 == 0 and z < 85.0:
			_umbrella(Geo.coast_x(z) + 5.0 + rng.randf() * 3.0, z + (rng.randf() - 0.5) * 6.0)
		z += 3.0


func _ilha() -> void:
	var k := 0
	var z := 80.0
	while z >= -280.0:
		var kx := Geo.ilha_x(z) + 9.6
		_place("Quiosques", "quiosque_%d" % (k % 6), Vector3(kx, Geo.terrain_height(kx, z), z), -PI / 2.0, 1.0, {"cor": KIOSK_COLORS[k % 6]})
		k += 1
		z -= 26.0
	z = 90.0
	while z >= -285.0:
		var ax := Geo.ilha_x(z)
		if rng.randf() < 0.75:
			_palm(ax - 6.2, z + (rng.randf() - 0.5) * 4.0, 0.85 + rng.randf() * 0.35)
		if rng.randf() < 0.8:
			_umbrella(ax - 10.5 - rng.randf() * 3.0, z + (rng.randf() - 0.5) * 5.0)
		z -= 12.0


func _nature() -> void:
	var lim := Geo.MAP_HALF - 8.0
	var gx := -lim
	while gx <= lim:
		var gz := -lim
		while gz <= lim:
			var x := gx + (rng.randf() - 0.5) * 6.0
			var z := gz + (rng.randf() - 0.5) * 6.0
			gz += 8.5
			if Geo.reserved(x, z) or Geo.terrain_height(x, z) < 0.15:
				continue
			var roll := rng.randf()
			if Geo.land_field(x, z) < 12.0:
				if roll < 0.35:
					_palm(x, z, 0.85 + rng.randf() * 0.4)
			elif roll < 0.035:
				_place("Imbondeiros", "imbondeiro", Vector3(x, Geo.terrain_height(x, z) - 0.1, z), rng.randf() * TAU, 0.8 + rng.randf() * 0.45)
			elif roll < 0.2 and Geo.fbm(x * 0.02, z * 0.02, 11, 3) > 0.45:
				_palm(x, z, 0.85 + rng.randf() * 0.4)
		gx += 8.5


# ------------------------------------------------------------------ restaurantes da Ilha (interior seamless)

func _ilha_restaurants() -> void:
	var group := _group("Estabelecimentos")
	for r in [[15.0, "Restaurante Kitanda da Ilha", "ilha-kitanda"], [-115.0, "Esplanada Mar Azul", "ilha-mar-azul"]]:
		var z: float = r[0]
		var x := Geo.ilha_x(z) + 10.8
		var pos := Vector3(x, Geo.terrain_height(x, z), z)
		for g in ["Coqueiros", "GuardaSois", "Quiosques"]:            # abre espaço no areal
			for c in _group(g).get_children():
				if (c as Node3D).position.distance_to(pos) < 8.5:
					c.free()
		var shell: Node3D = Kit.scene("colonial_a").instantiate()
		shell.name = str(r[2]).replace("-", "_")
		shell.position = pos
		shell.rotation.y = -PI / 2.0                                  # fachada para a estrada da Ilha
		_own(shell, group)
		var portal := Area3D.new()
		portal.name = "Porta"
		portal.set_script(load("res://scripts/interiors/building_portal.gd"))
		portal.set("mode", "seamless")
		portal.set("interior_type", "restaurante")
		portal.set("display_name", r[1])
		portal.set("portal_id", r[2])
		portal.set("shell_path", NodePath(".."))
		portal.position = Vector3(0, 0, 6.6)
		_own(portal, shell)
		var sign := Label3D.new()
		sign.name = "Letreiro"
		sign.text = r[1]
		sign.font_size = 64
		sign.outline_size = 16
		sign.modulate = Color("#e2725b")
		sign.outline_modulate = Color("#fff8ec")
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.position = Vector3(0, 5.2, 6.4)
		_own(sign, shell)


# ------------------------------------------------------------------ spawns

func _spawns() -> void:
	var sp := _group("Spawns")
	var bc := Geo.block_centers()
	for m in [
		["Jogador", Vector3(11, 0.4, -19), 0.0],
		["CarroBuggy", Vector3(3.9, 0.7, -30), PI],
		["CarroCandongueiro", Vector3(-3.9, 0.7, -42), 0.0],
		["GuardaBase", Vector3(bc[0], 0.7, 100.0), PI / 2.0],
		["PortaEsquadra", Vector3(bc[0], Geo.CITY_CURB + 0.3, bc[5] - 10.5), PI],
	]:
		var mk := Marker3D.new()
		mk.name = m[0]
		mk.position = m[1]
		mk.rotation.y = m[2]
		_own(mk, sp)
