extends SceneTree
## Bandula — gera as personagens a partir do pack «Universal Base Characters» (Quaternius, CC0).
##   python3 -I tools/import_ubc.py "<zip>"          (1.º: copia os glTF para assets/characters/ubc)
##   godot4 --headless --path godot/bandula --script res://tools/build_characters.gd
##
## 1. Retarget: as animações do avatar antigo (Idle, Walk, Run, Jump, Sitting, …) são
##    convertidas para o esqueleto novo (estilo UE: pelvis, spine_01, thigh_l…). A conversão é
##    feita em espaço do modelo, osso a osso: a rotação global de cada osso em relação à pose de
##    repouso passa para o osso equivalente, corrigindo a diferença pose-A → pose-T pela direção
##    dos ossos. Funciona apesar de o rig antigo ter os pés pendurados na raiz (IK).
## 2. Roupa: cada vértice do corpo recebe máscaras (tronco, braço, antebraço, anca, canela, pé)
##    a partir dos pesos dos ossos → o shader toon_character pinta camisa, calças e sapatos.
## 3. Uma cena por personagem (corpo + cabelo no osso da cabeça + AnimationPlayer + materiais)
##    em res://scenes/characters/<id>.scn.

const SRC := "res://assets/characters/ubc/"
const OUT := "res://assets/characters/"
const SCENES := "res://scenes/characters/"
const OLD_AVATAR := "res://assets/avatar/avatar_bandula.glb"
const FPS := 30.0

const BODIES := {
	"f": {"gltf": "Superhero_Female_FullBody", "mesh": "Superhero_Female", "height": 1.70},
	"m": {"gltf": "Superhero_Male_FullBody", "mesh": "SuperHero_Male", "height": 1.80},
}

## osso antigo → osso novo
const BONE_MAP := {
	"Hips": "pelvis", "Abdomen": "spine_01", "Torso": "spine_03", "Neck": "neck_01", "Head": "Head",
	"ShoulderL": "clavicle_l", "UpperArmL": "upperarm_l", "LowerArmL": "lowerarm_l", "PalmL": "hand_l",
	"ShoulderR": "clavicle_r", "UpperArmR": "upperarm_r", "LowerArmR": "lowerarm_r", "PalmR": "hand_r",
	"UpperLegL": "thigh_l", "LowerLegL": "calf_l", "FootL": "foot_l",
	"UpperLegR": "thigh_r", "LowerLegR": "calf_r", "FootR": "foot_r",
}
## direção de cada osso para alinhar as poses de repouso: [filho antigo, filho novo]
## ("@tail" = ponta do osso antigo, do nó <osso>_end importado do glb)
const DIR_CHILD := {
	"Hips": ["Abdomen", "spine_01"], "Abdomen": ["Torso", "spine_03"], "Torso": ["Neck", "neck_01"],
	"Neck": ["Head", "Head"],
	"ShoulderL": ["UpperArmL", "upperarm_l"], "UpperArmL": ["LowerArmL", "lowerarm_l"],
	"LowerArmL": ["PalmL", "hand_l"], "PalmL": ["MiddleHandL", "middle_01_l"],
	"ShoulderR": ["UpperArmR", "upperarm_r"], "UpperArmR": ["LowerArmR", "lowerarm_r"],
	"LowerArmR": ["PalmR", "hand_r"], "PalmR": ["MiddleHandR", "middle_01_r"],
	"UpperLegL": ["LowerLegL", "calf_l"], "LowerLegL": ["FootL", "foot_l"], "FootL": ["@tail", "ball_l"],
	"UpperLegR": ["LowerLegR", "calf_r"], "LowerLegR": ["FootR", "foot_r"], "FootR": ["@tail", "ball_r"],
}
## máscara de roupa por osso: 0 tronco · 1 braço · 2 antebraço · 3 anca+coxa · 4 canela · 5 pé · -1 pele
const REGION := {
	"spine_01": 0, "spine_02": 0, "spine_03": 0, "clavicle_l": 0, "clavicle_r": 0,
	"upperarm_l": 1, "upperarm_r": 1, "lowerarm_l": 2, "lowerarm_r": 2,
	"pelvis": 3, "thigh_l": 3, "thigh_r": 3, "calf_l": 4, "calf_r": 4,
	"foot_l": 5, "foot_r": 5, "ball_l": 5, "ball_r": 5, "ball_leaf_l": 5, "ball_leaf_r": 5,
}
const HAIR_TEX := {"Hair_Buns": 2, "Hair_Long": 2}

## Personagens. pele: multiplicador da textura · cabelo: cor · roupa: camisa/calças/sapatos,
## mangas (0/1/2), pernas compridas, faixa de destaque.
const LOOKS := [
	{"id": "governante", "name": "Governante", "body": "m", "skin": "#7a5a4c", "hair": ["Hair_SimpleParted"], "hair_color": "#1d1714",
		"shirt": "#d8d0bf", "pants": "#2c3550", "shoes": "#3a2a22", "sleeves": 2, "long": true, "accent": "#c8342c", "accent_amount": 1.0},
	{"id": "kianda", "name": "Kianda", "body": "f", "skin": "#6c4c40", "hair": ["Hair_Buns"], "hair_color": "#17110f",
		"shirt": "#ffb43a", "pants": "#d8402e", "shoes": "#d8ccb8", "sleeves": 1, "long": false, "accent": "#2a6fdb", "accent_amount": 1.0},
	{"id": "zeca", "name": "Zeca", "body": "m", "skin": "#5e4238", "hair": ["Hair_Buzzed"], "hair_color": "#120e0c",
		"shirt": "#2fae8e", "pants": "#3b3f46", "shoes": "#d8d8d8", "sleeves": 1, "long": false},
	{"id": "nzinga", "name": "Nzinga", "body": "f", "skin": "#4f3830", "hair": ["Hair_Long"], "hair_color": "#140f0d",
		"shirt": "#8e3fbf", "pants": "#8e3fbf", "shoes": "#d9a441", "sleeves": 0, "long": true, "accent": "#ffcf3a", "accent_amount": 1.0},
	{"id": "mateus", "name": "Mateus", "body": "m", "skin": "#a07a64", "hair": ["Hair_SimpleParted", "Hair_Beard"], "hair_color": "#4a3122",
		"shirt": "#3d7bd9", "pants": "#c9b48a", "shoes": "#5a3b2a", "sleeves": 1, "long": true},
	{"id": "rosa", "name": "Rosa", "body": "f", "skin": "#8a6452", "hair": ["Hair_BuzzedFemale"], "hair_color": "#2a1a14",
		"shirt": "#ff7a9c", "pants": "#d6cbb8", "shoes": "#c8342c", "sleeves": 1, "long": true},
	{"id": "sr_antonio", "name": "Sr. António", "body": "m", "skin": "#6a4a3e", "hair": ["Hair_Buzzed", "Hair_Beard"], "hair_color": "#b9b2a8",
		"shirt": "#d6c08a", "pants": "#5b4a3a", "shoes": "#2a211c", "sleeves": 2, "long": true, "accent": "#7a5a2a", "accent_amount": 1.0},
	{"id": "luena", "name": "Luena", "body": "f", "skin": "#5a4036", "hair": ["Hair_Long"], "hair_color": "#3a2016",
		"shirt": "#2fbf71", "pants": "#1f3a5f", "shoes": "#d8d8d8", "sleeves": 1, "long": false},
]

var _old_root: Node3D
var _old_skel: Skeleton3D
var _old_player: AnimationPlayer


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES))
	_old_root = load(OLD_AVATAR).instantiate()
	_old_skel = _old_root.find_children("*", "Skeleton3D", true, false)[0]
	_old_player = _old_root.find_children("*", "AnimationPlayer", true, false)[0]
	var libs := {}
	var meshes := {}
	for key in BODIES:
		var body: Node3D = load(SRC + BODIES[key].gltf + ".gltf").instantiate()
		var skel: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
		var lib := _bake_library(body, skel)
		_save(lib, OUT + "anims_%s.res" % key)
		libs[key] = load(OUT + "anims_%s.res" % key)
		var mi: MeshInstance3D = skel.get_node(BODIES[key].mesh)
		_save(_masked_mesh(mi), OUT + "body_%s.res" % key)
		meshes[key] = load(OUT + "body_%s.res" % key)
		body.free()
	for look in LOOKS:
		_build_look(look, libs[look.body], meshes[look.body])
	_old_root.free()
	print("Personagens prontas em %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("não gravou %s (%s)" % [path, error_string(err)])


# ------------------------------------------------------------------ transformações

## Transformação de um nó relativa a `root` (sem precisar de estar na árvore).
func _xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p := n
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Pose global de todos os ossos em espaço do modelo, a partir das poses locais atuais.
func _globals(skel: Skeleton3D, M: Transform3D, local: Array) -> Array:
	var g := []
	g.resize(skel.get_bone_count())
	for i in _order(skel):
		var p := skel.get_bone_parent(i)
		g[i] = (M if p < 0 else g[p]) * local[i]
	return g


## Ossos por ordem pai → filhos.
func _order(skel: Skeleton3D) -> Array:
	var out := []
	var stack := Array(skel.get_parentless_bones())
	stack.reverse()
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(b)
		var ch := Array(skel.get_bone_children(b))
		ch.reverse()
		stack.append_array(ch)
	return out


func _rest_locals(skel: Skeleton3D) -> Array:
	var out := []
	for i in skel.get_bone_count():
		out.append(skel.get_bone_rest(i))
	return out


# ------------------------------------------------------------------ retarget

func _bake_library(body: Node3D, skel: Skeleton3D) -> AnimationLibrary:
	var Mo := _xf(_old_skel, _old_root)
	var Mn := _xf(skel, body)
	var old_rest := _globals(_old_skel, Mo, _rest_locals(_old_skel))
	var new_rest_local := _rest_locals(skel)
	var new_rest := _globals(skel, Mn, new_rest_local)
	var oi := {}
	var ni := {}
	for ob in BONE_MAP:
		oi[ob] = _old_skel.find_bone(ob)
		ni[ob] = skel.find_bone(BONE_MAP[ob])
		assert(oi[ob] >= 0 and ni[ob] >= 0, "osso em falta: %s → %s" % [ob, BONE_MAP[ob]])
	# correção de repouso (pose A → pose T): rotação mínima que leva a direção nova à antiga
	var align := {}
	for ob in BONE_MAP:
		var d: Array = DIR_CHILD.get(ob, [])
		var q := Quaternion.IDENTITY
		if d.size() == 2:
			var o_from: Vector3 = old_rest[oi[ob]].origin
			var o_to: Vector3 = _old_tail(ob, Mo) if d[0] == "@tail" else old_rest[_old_skel.find_bone(d[0])].origin
			var n_from: Vector3 = new_rest[ni[ob]].origin
			var n_to: Vector3 = new_rest[skel.find_bone(d[1])].origin
			var dold := (o_to - o_from).normalized()
			var dnew := (n_to - n_from).normalized()
			if dold.length() > 0.5 and dnew.length() > 0.5 and dold.dot(dnew) < 0.99999:
				q = Quaternion(dnew, dold)
		align[ob] = q
	var hips_o: int = oi["Hips"]
	var hips_n: int = ni["Hips"]
	var k: float = (new_rest[hips_n].origin.y - Mn.origin.y) / maxf(0.01, old_rest[hips_o].origin.y - Mo.origin.y)
	var order := _order(skel)
	var new_by_bone := {}
	for ob in BONE_MAP:
		new_by_bone[ni[ob]] = ob

	var lib := AnimationLibrary.new()
	var skel_path := "Body/" + str(body.get_path_to(skel))
	for anim_name in _old_player.get_animation_list():
		if anim_name == "RESET":
			continue
		var src: Animation = _old_player.get_animation(anim_name)
		var dst := Animation.new()
		dst.length = src.length
		dst.loop_mode = src.loop_mode
		var tracks := {}
		for b in new_by_bone:
			var t := dst.add_track(Animation.TYPE_ROTATION_3D)
			dst.track_set_path(t, skel_path + ":" + skel.get_bone_name(b))
			tracks[b] = t
		var hip_track := dst.add_track(Animation.TYPE_POSITION_3D)
		dst.track_set_path(hip_track, skel_path + ":" + skel.get_bone_name(hips_n))
		var frames := maxi(1, int(ceil(src.length * FPS)))
		for f in frames + 1:
			var time := minf(src.length, f / FPS)
			var old_pose := _old_globals_at(src, time, Mo)
			var targets := {}
			for ob in BONE_MAP:
				var o: int = oi[ob]
				var delta: Quaternion = old_pose[o].basis.get_rotation_quaternion() * old_rest[o].basis.get_rotation_quaternion().inverse()
				targets[ni[ob]] = delta * align[ob] * new_rest[ni[ob]].basis.get_rotation_quaternion()
			var grot := {}
			for b in order:
				var p := skel.get_bone_parent(b)
				var prot: Quaternion = Mn.basis.get_rotation_quaternion() if p < 0 else grot[p]
				if targets.has(b):
					grot[b] = targets[b]
					dst.rotation_track_insert_key(tracks[b], time, (prot.inverse() * targets[b]).normalized())
				else:
					grot[b] = prot * new_rest_local[b].basis.get_rotation_quaternion()
			# anca: deslocamento do repouso, escalado pela altura da anca
			var off: Vector3 = (old_pose[hips_o].origin - old_rest[hips_o].origin) * k
			var hp := skel.get_bone_parent(hips_n)
			var parent_xf: Transform3D = Mn if hp < 0 else new_rest[hp]
			dst.position_track_insert_key(hip_track, time, parent_xf.affine_inverse() * (new_rest[hips_n].origin + off))
		lib.add_animation(anim_name, dst)
	print("  retarget %s: %d animações (k anca %.2f)" % [body.name, lib.get_animation_list().size(), k])
	return lib


## Ponta de um osso antigo (nó «<osso>_end» que o importador cria dentro do BoneAttachment).
func _old_tail(bone: String, Mo: Transform3D) -> Vector3:
	var att := _old_skel.get_node_or_null(bone)
	var i := _old_skel.find_bone(bone)
	var g := Mo * _old_skel.get_bone_global_rest(i)
	if att and att.get_child_count() > 0:
		return g * (att.get_child(0) as Node3D).position
	return g * Vector3(0, 0.1, 0)


## Pose do esqueleto antigo num instante da animação (amostragem direta das pistas).
func _old_globals_at(anim: Animation, time: float, Mo: Transform3D) -> Array:
	var local := _rest_locals(_old_skel)
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var bone_name := path.get_concatenated_subnames()
		if bone_name == "":
			continue
		var b := _old_skel.find_bone(bone_name)
		if b < 0:
			continue
		var xf: Transform3D = local[b]
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				xf.origin = anim.position_track_interpolate(t, time)
			Animation.TYPE_ROTATION_3D:
				xf.basis = Basis(anim.rotation_track_interpolate(t, time)).scaled(xf.basis.get_scale())
			Animation.TYPE_SCALE_3D:
				xf.basis = Basis(xf.basis.get_rotation_quaternion()).scaled(anim.scale_track_interpolate(t, time))
		local[b] = xf
	return _globals(_old_skel, Mo, local)


# ------------------------------------------------------------------ máscaras de roupa

func _masked_mesh(mi: MeshInstance3D) -> ArrayMesh:
	var src: ArrayMesh = mi.mesh
	var skin: Skin = mi.skin
	var skel: Skeleton3D = mi.get_node(mi.skeleton)
	var bind_region := []
	for i in skin.get_bind_count():
		var bn := skin.get_bind_name(i)
		if bn == "":
			bn = skel.get_bone_name(skin.get_bind_bone(i))
		bind_region.append(REGION.get(bn, -1))
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / n
		var colors := PackedColorArray()
		var uv2 := PackedVector2Array()
		colors.resize(n)
		uv2.resize(n)
		for v in n:
			var m := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for j in per:
				var r: int = bind_region[bones[v * per + j]]
				if r >= 0:
					m[r] += weights[v * per + j]
			colors[v] = Color(m[0], m[1], m[2], m[3])
			uv2[v] = Vector2(m[4], m[5])
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[c] = null                                # canais extra do exportador (não usados)
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	out.resource_name = mi.name + "_roupa"
	return out


# ------------------------------------------------------------------ materiais

func _tex_mat(tex: Texture2D, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon_stylized.gdshader")
	m.set_shader_parameter("use_vertex_color", false)
	m.set_shader_parameter("use_texture", true)
	m.set_shader_parameter("albedo_texture", tex)
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("roughness", 0.75)
	m.set_shader_parameter("rim_strength", 0.25)
	return m


func _hair_mat(look: Dictionary, which: int) -> ShaderMaterial:
	var c := Color(look.hair_color)
	# a textura do cabelo é cinzenta clara: multiplicar diretamente dá a cor pedida
	return _tex_mat(load(SRC + "T_Hair_%d_BaseColor.png" % which), Color(c.r * 1.35, c.g * 1.35, c.b * 1.35))


func _body_mat(look: Dictionary, body_key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon_character.gdshader")
	var tex := "T_Superhero_Female_Dark_BaseColor.png" if body_key == "f" else "T_Superhero_Male_Dark.png"
	m.set_shader_parameter("albedo_texture", load(SRC + tex))
	# tom de pele: a textura é bronzeada clara (~#c88a68) → multiplicador relativo
	var s := Color(look.skin)
	var base := Color("#c88a68")
	m.set_shader_parameter("skin_tint", Color(minf(1.6, s.r / base.r), minf(1.6, s.g / base.g), minf(1.6, s.b / base.b)))
	m.set_shader_parameter("shirt_color", Color(look.shirt))
	m.set_shader_parameter("pants_color", Color(look.pants))
	m.set_shader_parameter("shoe_color", Color(look.shoes))
	m.set_shader_parameter("sleeves", int(look.sleeves))
	m.set_shader_parameter("long_legs", bool(look.long))
	m.set_shader_parameter("accent_color", Color(look.get("accent", "#000000")))
	m.set_shader_parameter("accent_amount", float(look.get("accent_amount", 0.0)))
	return m


# ------------------------------------------------------------------ cenas

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _build_look(look: Dictionary, lib: AnimationLibrary, mesh: ArrayMesh) -> void:
	var key: String = look.body
	var root := Node3D.new()
	root.name = "Personagem"
	root.set_meta("toon_ready", true)
	root.set_meta("height", BODIES[key].height)
	root.set_meta("look_id", look.id)
	var body: Node3D = load(SRC + BODIES[key].gltf + ".gltf").instantiate()
	body.name = "Body"
	body.scene_file_path = ""
	root.add_child(body)
	var skel: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = skel.get_node(BODIES[key].mesh)
	mi.mesh = mesh
	mi.material_override = _body_mat(look, key)
	var eyes: MeshInstance3D = skel.get_node("Eyes")
	var eye_mat: StandardMaterial3D = eyes.mesh.surface_get_material(0)
	eyes.material_override = _tex_mat(eye_mat.albedo_texture if eye_mat else null, Color.WHITE)
	var brows: MeshInstance3D = skel.get_node("Eyebrows")
	brows.material_override = _hair_mat(look, 2 if key == "f" else 1)
	for mesh_inst in [mi, eyes, brows]:
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# cabelo: glTF «origin at 0» (no espaço do corpo) preso ao osso da cabeça
	var head := skel.find_bone("Head")
	var att := BoneAttachment3D.new()
	att.name = "Cabeca"
	att.bone_name = "Head"
	skel.add_child(att)
	var offset := Node3D.new()
	offset.name = "Penteado"
	# 3 % maior à volta do centro da cabeça: o couro cabeludo não fura o cabelo rapado
	var head_rest := skel.get_bone_global_rest(head)
	var c := head_rest.affine_inverse() * (head_rest.origin + Vector3(0, 0.1, 0.02))
	var grow := Transform3D(Basis.from_scale(Vector3.ONE * 1.03), Vector3.ZERO)
	offset.transform = Transform3D(Basis(), c) * grow * Transform3D(Basis(), -c) * head_rest.affine_inverse()
	att.add_child(offset)
	for h in look.hair:
		var hair: Node3D = load(SRC + h + ".gltf").instantiate()
		hair.name = h
		hair.scene_file_path = ""
		offset.add_child(hair)
		var mat := _hair_mat(look, HAIR_TEX.get(h, 1))
		for hm in ([hair] if hair is MeshInstance3D else []) + hair.find_children("*", "MeshInstance3D", true, false):
			(hm as MeshInstance3D).material_override = mat
			(hm as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", lib)
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack %s: %s" % [look.id, error_string(err)])
	_save(ps, SCENES + look.id + ".scn")
	print("  personagem %s (%s)" % [look.id, look.name])
	root.free()
