extends RefCounted
## Luanda City Kit no Godot (jogo Bandula).
## Converte os .glb exportados pelo jogo web (assets/kit/, via tools/kit-export.html)
## em cenas nativas (scenes/kit/*.scn) com o material toon e colisão própria,
## para que qualquer instância movida no editor leve o colisor consigo.

const GLB_DIR := "res://assets/kit/"
const SCN_DIR := "res://scenes/kit/"
const TOON := "res://shaders/toon_stylized.gdshader"

## Colisão por peça: [tipo, raio/tamanho, altura]. "aabb" usa a caixa da malha.
const COLLISION := {
	"palmeira": ["cyl", 0.35, 5.0], "imbondeiro": ["cyl", 1.7, 6.0],
	"quiosque": ["cyl", 2.4, 3.0], "guarda_sol": ["cyl", 0.2, 2.6],
	"torre": ["aabb"], "fortaleza": ["aabb", 0.0, 9.0], "colonial": ["aabb"],
	"casa": ["aabb"], "comercio": ["aabb"],
}


static func toon_material(path: String, settings: Dictionary) -> ShaderMaterial:
	if ResourceLoader.exists(path):
		return load(path)
	var m := ShaderMaterial.new()
	m.shader = load(TOON)
	for k in settings:
		m.set_shader_parameter(k, settings[k])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	return m


## Material das peças do kit: cor por vértice (linear) como albedo.
static func kit_material() -> ShaderMaterial:
	return toon_material("res://materials/kit.tres", {"use_vertex_color": true, "roughness": 0.8})


## Vidro azulado refletivo das torres (brilho toon + rim mais forte).
static func glass_material() -> ShaderMaterial:
	return toon_material("res://materials/vidro.tres", {"use_vertex_color": true, "roughness": 0.08, "metallic": 0.35, "gloss": 0.65, "gloss_size": 0.9, "rim_strength": 0.55})


## Verniz dos carros (clearcoat estilizado).
static func paint_material() -> ShaderMaterial:
	return toon_material("res://materials/verniz.tres", {"use_vertex_color": true, "roughness": 0.3, "gloss": 0.5, "gloss_size": 0.94, "rim_strength": 0.35})


static func prepare_all() -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCN_DIR))
	var done := []
	for f in DirAccess.get_files_at(GLB_DIR):
		if f.get_extension().to_lower() == "glb" and prepare(f.get_basename()) == OK:
			done.append(f.get_basename())
	return done


static func prepare(piece: String) -> Error:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(GLB_DIR + piece + ".glb"), state)
	if err != OK:
		push_error("Kit: não foi possível ler %s.glb (%s)" % [piece, error_string(err)])
		return err
	var src := doc.generate_scene(state)
	var root := Node3D.new()
	root.name = piece
	var opaque := paint_material() if piece.begins_with("carro_") else kit_material()
	var glass := glass_material()
	var aabb := AABB()
	var first := true
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var old := mesh.surface_get_material(s)
			mesh.surface_set_material(s, glass if old != null and "vidro" in old.resource_name.to_lower() else opaque)
		var out := MeshInstance3D.new()
		out.name = mi.name
		out.mesh = mesh
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != src:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		out.transform = t
		root.add_child(out)
		out.owner = root
		var box := t * mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	_add_collision(root, piece, aabb)
	var ps := PackedScene.new()
	ps.pack(root)
	err = ResourceSaver.save(ps, SCN_DIR + piece + ".scn")
	src.free()
	root.free()
	return err


static func _add_collision(root: Node3D, piece: String, aabb: AABB) -> void:
	var spec = null
	for k in COLLISION:
		if piece.begins_with(k):
			spec = COLLISION[k]
	if spec == null:
		return
	var body := StaticBody3D.new()
	body.name = "Colisao"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Forma"
	if spec[0] == "cyl":
		var c := CylinderShape3D.new()
		c.radius = spec[1]
		c.height = spec[2]
		cs.shape = c
		cs.position = Vector3(0, spec[2] / 2.0, 0)
	else:
		var b := BoxShape3D.new()
		var h: float = spec[2] if spec.size() > 2 else aabb.size.y
		b.size = Vector3(aabb.size.x * 0.96, h, aabb.size.z * 0.96)
		cs.shape = b
		cs.position = Vector3(aabb.get_center().x, h / 2.0, aabb.get_center().z)
	body.add_child(cs)
	root.add_child(body)
	body.owner = root
	cs.owner = root


static func scene(piece: String) -> PackedScene:
	return load(SCN_DIR + piece + ".scn")
