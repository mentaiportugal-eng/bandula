extends RefCounted
## Geometria dos interiores do Bandula (Luanda City Kit no Godot): lajes de cantos
## arredondados com chanfro e peças torneadas (lathe), com cor por vértice (linear)
## no material toon. Sem caixas primitivas.

var st := SurfaceTool.new()


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Triângulo com a frente virada para `hint` (Godot: frente = sentido horário).
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
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


func rrect(w: float, d: float, r: float, seg: int = 3) -> PackedVector2Array:
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


## Laje w × h × d com a base em y = 0 do referencial `xf` (cantos r, chanfro bev).
func slab(xf: Transform3D, w: float, h: float, d: float, col: Color, r := 0.06, bev := 0.025) -> void:
	bev = minf(bev, minf(h, minf(w, d)) / 3.0)
	r = minf(r, minf(w, d) / 2.0 - 0.002)
	var seg := 2 if r > 0.05 else 1
	var rings := [[bev, 0.0], [0.0, bev], [0.0, h - bev], [bev, h]]
	var pts := []
	for ring in rings:
		pts.append(rrect(w - 2.0 * ring[0], d - 2.0 * ring[0], maxf(r - ring[0], 0.0), seg))
	for k in range(3):
		var lo: PackedVector2Array = pts[k]
		var hi: PackedVector2Array = pts[k + 1]
		var vy := -0.6 if k == 0 else (0.6 if k == 2 else 0.0)
		for i in range(lo.size()):
			var i2 := (i + 1) % lo.size()
			var a := Vector3(lo[i].x, rings[k][1], lo[i].y)
			var b := Vector3(lo[i2].x, rings[k][1], lo[i2].y)
			var e := Vector3(hi[i2].x, rings[k + 1][1], hi[i2].y)
			var f := Vector3(hi[i].x, rings[k + 1][1], hi[i].y)
			var mid := (a + b) / 2.0
			var hint := Vector3(mid.x, vy * maxf(absf(mid.x), absf(mid.z)), mid.z)
			_quad_x(xf, a, b, e, f, col, hint)
	for cap in [[0, 0.0, Vector3.DOWN], [3, h, Vector3.UP]]:
		var ring: PackedVector2Array = pts[cap[0]]
		for i in range(ring.size()):
			var i2 := (i + 1) % ring.size()
			tri(xf * Vector3(0, cap[1], 0), xf * Vector3(ring[i].x, cap[1], ring[i].y), xf * Vector3(ring[i2].x, cap[1], ring[i2].y), col, xf.basis * cap[2])


func _quad_x(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
	var h := xf.basis * hint
	tri(xf * a, xf * b, xf * c, col, h)
	tri(xf * a, xf * c, xf * d, col, h)


## Peça torneada: perfil [(raio, y), …] de baixo para cima, girado em `seg` passos.
func lathe(xf: Transform3D, profile: Array, col: Color, seg := 16) -> void:
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x))
		for k in range(seg):
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var c0 := Vector3(cos(a0), 0, sin(a0))
			var c1 := Vector3(cos(a1), 0, sin(a1))
			var v00 := c0 * p0.x + Vector3(0, p0.y, 0)
			var v01 := c1 * p0.x + Vector3(0, p0.y, 0)
			var v10 := c0 * p1.x + Vector3(0, p1.y, 0)
			var v11 := c1 * p1.x + Vector3(0, p1.y, 0)
			var mid := (c0 + c1).normalized()
			var hint := xf.basis * (mid * n2.x + Vector3(0, n2.y, 0))
			if p0.x > 0.0005 or p1.x > 0.0005:
				tri(xf * v00, xf * v01, xf * v11, col, hint)
				tri(xf * v00, xf * v11, xf * v10, col, hint)


static func at(x: float, y: float, z: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


func commit() -> ArrayMesh:
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, load("res://materials/kit.tres"))
	return mesh
