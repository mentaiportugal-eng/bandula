extends Node3D
## Modo Decoração (M) — mobilar as casas e os comércios do jogador.
## Uma peça-fantasma segue a mira (centro do ecrã) sobre o chão, encaixa numa grelha
## de 25 cm e fica verde se couber (sem tocar paredes nem outros móveis) ou vermelha.
##   Tab / 1–9 escolher peça · R rodar 90° · E ou clique colocar (paga do tesouro)
##   X retirar a peça apontada (devolve metade) · M sair
## A mobília fica guardada no lote (GameManager.plots[id].furniture).

signal decor_changed(active: bool, index: int, valid: bool)

const Catalog = preload("res://scripts/interiors/furniture_catalog.gd")
const Generator = preload("res://scripts/interiors/interior_generator.gd")
const GRID := 0.25

@export var player_path: NodePath = ^"../Player"

var player: CharacterBody3D
var active := false
var index := 0
var yaw := 0.0
var valid := false
var ghost: Node3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D


func _ready() -> void:
	player = get_node(player_path)
	_ok_mat = _ghost_mat(Color(0.36, 1.0, 0.62, 0.45))
	_bad_mat = _ghost_mat(Color(1.0, 0.35, 0.47, 0.45))
	Interiors.exited.connect(stop)


static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func current_id() -> String:
	return GameManager.FURNITURE[index].id


func can_decorate() -> bool:
	var i: Node = Interiors.current
	return i != null and i.owner_plot_id != "" and player.seat == null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("decorate"):
		if active:
			stop()
		elif can_decorate():
			start()
		elif Interiors.is_inside():
			GameManager.toast.emit("Só pode mobilar os seus próprios prédios.", "warn")
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var handled := true
	if event.is_action_pressed("next_item"):
		select((index + 1) % GameManager.FURNITURE.size())
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		select(mini(event.keycode - KEY_1, GameManager.FURNITURE.size() - 1))
	elif event.is_action_pressed("rotate_item"):
		yaw = wrapf(yaw + PI / 2.0, -PI, PI)
	elif event.is_action_pressed("interact") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		place()
	elif event.is_action_pressed("remove_item"):
		remove_aimed()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func start() -> void:
	active = true
	select(index)


func stop() -> void:
	if not active:
		return
	active = false
	if ghost:
		ghost.queue_free()
		ghost = null
	decor_changed.emit(false, index, false)


func select(i: int) -> void:
	index = i
	if ghost:
		ghost.queue_free()
	ghost = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Catalog.mesh(current_id())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(mi)
	add_child(ghost)
	decor_changed.emit(true, index, valid)


func _process(_delta: float) -> void:
	if not active:
		return
	if not can_decorate():
		stop()
		return
	var interior: Node3D = Interiors.current
	var cam: Camera3D = player.camera_rig.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var floor_y := interior.global_position.y
	var pos: Vector3 = player.global_position + player.visual.global_basis.z * 1.6     # alternativa: à frente do avatar
	if dir.y < -0.05:
		var t := (floor_y - from.y) / dir.y
		if t > 0.0 and t < 14.0:
			pos = from + dir * t
	pos.x = snappedf(pos.x, GRID)
	pos.z = snappedf(pos.z, GRID)
	pos.y = floor_y
	ghost.global_position = pos
	ghost.global_rotation = Vector3(0, yaw, 0)
	var was := valid
	valid = _fits(interior, pos)
	(ghost.get_child(0) as MeshInstance3D).material_override = _ok_mat if valid else _bad_mat
	if was != valid:
		decor_changed.emit(true, index, valid)


## Cabe? Dentro da sala, longe da porta e sem tocar paredes, móveis ou pessoas.
func _fits(interior: Node3D, pos: Vector3) -> bool:
	var local := interior.to_local(pos)
	var b: Vector2 = interior.get_meta("bounds", Vector2(10, 9))
	var fp := Catalog.footprint(current_id())
	var half := Vector2(fp.x, fp.y).rotated(yaw).abs() / 2.0
	if absf(local.x) + half.x > b.x / 2.0 - 0.15 or absf(local.z) + half.y > b.y / 2.0 - 0.15:
		return false
	if local.z > b.y / 2.0 - 1.8 and absf(local.x) < 1.6:              # deixar a porta livre
		return false
	if current_id() == "tapete":
		return true
	var shape := BoxShape3D.new()
	shape.size = Vector3(fp.x * 0.95, 0.9, fp.y * 0.95)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.6, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func place() -> void:
	var interior: Node3D = Interiors.current
	if not valid:
		GameManager.toast.emit("Não cabe aqui — tente outro sítio ou rode (R).", "warn")
		return
	var local := interior.to_local(ghost.global_position)
	var r := GameManager.place_furniture(interior.owner_plot_id, current_id(), local, wrapf(yaw - interior.global_rotation.y, -PI, PI))
	if not r.ok:
		GameManager.toast.emit(r.reason, "warn")
		return
	var business: String = interior.interior_type
	Generator.add_furniture(interior, r.entry, business)
	var f: Dictionary = GameManager.furniture_def(current_id())
	GameManager.toast.emit("%s colocado(a) — Kz %s" % [f.name, GameManager.fmt(f.price)], "success")


func remove_aimed() -> void:
	var cam: Camera3D = player.camera_rig.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 12.0, 1)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var n: Node = hit.get("collider")
	while n != null and not n.has_meta("furniture_entry"):
		n = n.get_parent()
	if n == null:
		GameManager.toast.emit("Aponte para uma peça sua para a retirar.", "info")
		return
	var entry: Dictionary = n.get_meta("furniture_entry")
	GameManager.remove_furniture(Interiors.current.owner_plot_id, entry)
	n.queue_free()
	GameManager.toast.emit("%s retirado(a) (metade do valor devolvida)." % GameManager.furniture_def(entry.id).get("name", "Peça"), "info")
