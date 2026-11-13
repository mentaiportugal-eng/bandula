extends Node3D
## Slot modular do avatar (.glb). Instancia o modelo, normaliza a altura, aplica o
## material toon (cores por vértice) e monta um AnimationTree:
##   StateMachine ─ Locomotion (BlendSpace1D: Idle 0 · Walk 1 · Run 2)
##                ├ Jump  (uma vez)
##                └ Sit   (ao volante)
## Personagens: res://scenes/characters/*.scn (tools/build_characters.gd, pack Universal Base
## Characters) — já trazem materiais toon e altura real (metas «toon_ready» e «height»).
## Também aceita qualquer .glb com esqueleto e clipes (ajuste `anim_names` se preciso).

@export var avatar_scene: PackedScene = preload("res://scenes/characters/governante.scn")
@export var target_height := 1.78
@export var apply_toon_material := true
@export var anim_names := {"idle": "Idle", "walk": "Walk", "run": "Run", "jump": "Jump", "sit": "Sitting"}

var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback


func _ready() -> void:
	set_avatar(avatar_scene)


func set_avatar(scene: PackedScene) -> void:
	if model:
		model.queue_free()
	if anim_tree:
		anim_tree.queue_free()
	anim_tree = null
	if scene == null:
		return
	model = scene.instantiate()
	add_child(model)
	var ready_made := model.has_meta("toon_ready")
	if not model.has_meta("height"):           # as personagens novas já estão em metros
		_normalize()
	if apply_toon_material and not ready_made:
		var mat: Material = load("res://materials/kit.tres")
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var players := model.find_children("*", "AnimationPlayer", true, false)
	anim_player = players[0] if players.size() > 0 else null
	if anim_player:
		_build_tree()


func _normalize() -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != self:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		b = t * b
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y <= 0.001:
		return
	var k := target_height / box.size.y
	model.scale *= k
	model.position.y -= box.position.y * k


func _clip(key: String) -> String:
	var n: String = anim_names.get(key, "")
	return n if anim_player and anim_player.has_animation(n) else ""


func _build_tree() -> void:
	for key in ["idle", "walk", "run", "sit"]:
		var n := _clip(key)
		if n != "":
			anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 2.0
	var pos := 0.0
	for key in ["idle", "walk", "run"]:
		var n := _clip(key)
		if n != "":
			var a := AnimationNodeAnimation.new()
			a.animation = n
			loco.add_blend_point(a, pos, -1, StringName(key))
		pos += 1.0
	sm.add_node("Locomotion", loco, Vector2(0, 0))
	for st in [["Jump", "jump"], ["Sit", "sit"]]:
		var n := _clip(st[1])
		if n == "":
			continue
		var a := AnimationNodeAnimation.new()
		a.animation = n
		sm.add_node(st[0], a, Vector2(200, 0 if st[0] == "Jump" else 120))
		var go := AnimationNodeStateMachineTransition.new()
		go.xfade_time = 0.12
		var back := AnimationNodeStateMachineTransition.new()
		back.xfade_time = 0.22
		sm.add_transition("Locomotion", st[0], go)
		sm.add_transition(st[0], "Locomotion", back)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO   # sem isto fica na pose T até ao 1.º travel()
	sm.add_transition("Start", "Locomotion", start)
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	add_child(anim_tree)
	anim_tree.tree_root = sm
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	_playback = anim_tree.get("parameters/playback")


## 0 = parado · 1 = andar · 2 = correr (valores intermédios misturam).
func set_locomotion(blend: float) -> void:
	if anim_tree:
		anim_tree.set("parameters/Locomotion/blend_position", clampf(blend, 0.0, 2.0))


func jump() -> void:
	_travel("Jump")


func land() -> void:
	_travel("Locomotion")


func sit(on: bool) -> void:
	_travel("Sit" if on else "Locomotion")


func _travel(state: String) -> void:
	if _playback and anim_tree.tree_root.has_node(state):
		_playback.travel(state)
