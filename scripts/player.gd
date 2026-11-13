extends CharacterBody3D
## Jogador em terceira pessoa (estilo GTA): movimento relativo à câmara, sprint,
## salto, squash-and-stretch ao aterrar, interação (E: ver/comprar lotes de Luanda),
## veículos (F: entrar/sair; o avatar senta-se no banco do condutor, à esquerda) e
## edifícios: portas, cadeiras e balcões (grupo "interactable": can_interact /
## interaction_text / interact). Sentado, W ou Espaço levanta. Correr gasta energia.

signal interaction_changed(text: String)

@export var walk_speed := 4.2
@export var run_speed := 7.5
@export var jump_velocity := 7.2
@export var gravity := 22.0
@export var acceleration := 12.0
@export var turn_speed := 10.0
@export var vehicle_reach := 3.6

@onready var visual: Node3D = $Visual
@onready var avatar: Node3D = $Visual/AvatarSlot

var camera_rig: Node3D                 # ligado pelo main.gd
var vehicle: VehicleBody3D = null      # veículo atual (null = a pé)
var _sq := 0.0                         # mola do squash-and-stretch
var _sq_v := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _prompt := ""
var _plot_target: Node = null
var _vehicle_target: VehicleBody3D = null
var interior: Node3D = null            # interior atual (null = na rua)
var seat: Node = null                  # mobiliário onde está sentado
var _interact_target: Node = null
var _tired_warned := false


func _ready() -> void:
	add_to_group("player")
	GameManager.player = self


func _physics_process(delta: float) -> void:
	if seat != null:                                   # sentado: W ou Espaço levanta
		velocity = Vector3.ZERO
		if not GameManager.input_locked and (Input.is_action_just_pressed("move_forward") or Input.is_action_just_pressed("jump")):
			stand_up()
		_update_prompt()
		return
	if vehicle != null:
		global_position = vehicle.seat.global_position
		velocity = Vector3.ZERO
		_update_prompt()
		return
	var input := Vector2.ZERO if GameManager.input_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if camera_rig:
		dir = camera_rig.flat_basis() * Vector3(input.x, 0, input.y)
	var sprinting := Input.is_action_pressed("sprint") and input.length() > 0.1
	if sprinting and GameManager.energy < 8.0:          # sem energia não se corre
		sprinting = false
		if not _tired_warned:
			_tired_warned = true
			GameManager.toast.emit("Sem energia para correr — coma qualquer coisa num restaurante.", "warn")
	elif GameManager.energy > 15.0:
		_tired_warned = false
	if sprinting:
		GameManager.drain_energy(delta * 0.35)
	var speed := run_speed if sprinting else walk_speed
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, acceleration * delta))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, acceleration * delta))
	if not is_on_floor():
		velocity.y -= gravity * delta
		_fall_speed = velocity.y
	elif Input.is_action_just_pressed("jump") and not GameManager.input_locked:
		velocity.y = jump_velocity
		_sq_v += 2.4                                   # estica ao saltar
		avatar.jump()
	move_and_slide()
	if is_on_floor() and not _was_on_floor:            # aterrou: achata e volta com mola
		_sq_v -= 3.2 + absf(_fall_speed) * 0.35
		avatar.land()
	_was_on_floor = is_on_floor()
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(velocity.x, velocity.z), minf(1.0, turn_speed * delta))
	avatar.set_locomotion(flat.length() / walk_speed if flat.length() <= walk_speed else 1.0 + (flat.length() - walk_speed) / (run_speed - walk_speed))
	_update_prompt()


func _process(delta: float) -> void:
	# squash-and-stretch com mola amortecida (volume ~constante)
	_sq_v += (-140.0 * _sq - 11.0 * _sq_v) * minf(delta, 1.0 / 30.0)
	_sq = clampf(_sq + _sq_v * minf(delta, 1.0 / 30.0), -0.32, 0.3)
	if vehicle == null and seat == null:
		visual.scale = Vector3(1.0 - _sq * 0.5, 1.0 + _sq, 1.0 - _sq * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("vehicle"):
		if vehicle != null:
			exit_vehicle()
		elif _vehicle_target != null:
			enter_vehicle(_vehicle_target)
	elif event.is_action_pressed("interact") and vehicle == null and seat == null and _interact_target != null:
		_interact_target.interact(self)
	elif event.is_action_pressed("interact") and vehicle == null and _plot_target != null:
		var p: Dictionary = _plot_target.info()
		if p.get("owner", "") == "":
			var r := GameManager.buy_plot(_plot_target.plot_id)
			if not r.ok:
				GameManager.toast.emit(r.reason, "warn")
		elif p.get("owner", "") == "player":
			get_tree().call_group("hud", "open_menu", "properties", _plot_target.plot_id)


# ------------------------------------------------------------------ interação

func _update_prompt() -> void:
	var text := ""
	_vehicle_target = null
	_plot_target = null
	_interact_target = null
	if seat != null:
		text = "W / Espaço — Levantar"
	elif vehicle != null:
		text = "F — Sair do %s" % vehicle.display_name
	else:
		# portas, cadeiras e balcões por perto (o mais próximo ganha)
		var best_d := INF
		for n in get_tree().get_nodes_in_group("interactable"):
			if n.can_interact(self):
				var d: float = n.global_position.distance_to(global_position)
				if d < best_d:
					best_d = d
					_interact_target = n
		if _interact_target:
			text = _interact_target.interaction_text(self)
	if seat == null and vehicle == null and interior == null:
		var best := vehicle_reach
		for v in get_tree().get_nodes_in_group("vehicles"):
			var d: float = v.global_position.distance_to(global_position)
			if d < best:
				best = d
				_vehicle_target = v
		if _vehicle_target:
			var vline := "F — %s %s" % ["Roubar" if _vehicle_target.driver != null else "Conduzir", _vehicle_target.display_name]
			text = vline if text == "" else text + "\n" + vline
		var plot := _plot_under_aim() if _interact_target == null else null
		if plot:
			_plot_target = plot
			var line := "E — " + GameManager.plot_label(plot.plot_id)
			text = line if text == "" else text + "\n" + line
	if text != _prompt:
		_prompt = text
		interaction_changed.emit(text)


## Lote apontado pela câmara (raio do centro do ecrã) ou, em alternativa, o lote sob o jogador.
func _plot_under_aim() -> Node:
	if camera_rig and camera_rig.interact_ray.is_colliding():
		var c = camera_rig.interact_ray.get_collider()
		if c and c.is_in_group("plots") and c.global_position.distance_to(global_position) < 18.0:
			return c
	var q := PhysicsPointQueryParameters3D.new()
	q.position = global_position + Vector3(0, 0.5, 0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 8
	for hit in get_world_3d().direct_space_state.intersect_point(q, 4):
		if hit.collider.is_in_group("plots"):
			return hit.collider
	return null


# ------------------------------------------------------------------ veículos

func enter_vehicle(v: VehicleBody3D) -> void:
	if v.driver != null and v.driver != self:
		GameManager.report_offense("police_carjack" if v.is_police else "carjack")
		v.eject_driver()
	vehicle = v
	v.set_driver(self)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	visual.reparent(v.seat, false)                       # avatar no banco do condutor (esquerda)
	visual.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * 0.85)
	avatar.sit(true)
	if camera_rig:
		camera_rig.follow(v.camera_target, "vehicle", v)


func exit_vehicle() -> void:
	var v := vehicle
	if v == null:
		return
	var out: Vector3 = v.exit_point.global_position
	v.set_driver(null)
	vehicle = null
	visual.reparent(self, false)
	visual.transform = Transform3D.IDENTITY
	avatar.sit(false)
	global_position = out + Vector3(0, 0.3, 0)
	collision_layer = 2
	collision_mask = 1 | 4
	if camera_rig:
		camera_rig.follow(self, "foot")


# ------------------------------------------------------------------ edifícios e mobiliário

## Senta o avatar na cadeira (posição exata do SitPoint, animação Sit, câmara acolhedora).
func sit_on(furniture: Node) -> void:
	if not furniture.reserve(self):
		GameManager.toast.emit("Esse lugar está ocupado.", "warn")
		return
	seat = furniture
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	var t: Transform3D = furniture.sit_transform()
	global_position = t.origin
	var yaw := t.basis.get_euler().y
	visual.rotation.y = yaw
	visual.scale = Vector3.ONE
	avatar.sit(true)
	if camera_rig:
		camera_rig.follow(self, "seated")
		camera_rig.look_from_behind(yaw, -0.32)          # por cima do ombro, a olhar para a mesa


func stand_up() -> void:
	if seat == null:
		return
	var f := seat
	seat = null
	f.release(self)
	global_position = f.approach_position()
	collision_layer = 2
	collision_mask = 1 | 4
	avatar.sit(false)
	if camera_rig:
		camera_rig.follow(self, "indoor" if interior != null else "foot")


## Chamado pelo InteriorManager: coloca o jogador à entrada do interior.
func enter_interior(new_interior: Node3D, snap_camera: bool) -> void:
	interior = new_interior
	var e: Marker3D = new_interior.entrance()
	global_position = e.global_position
	velocity = Vector3.ZERO
	visual.rotation.y = e.global_rotation.y
	if camera_rig:
		camera_rig.follow(self, "indoor")
		camera_rig.look_from_behind(e.global_rotation.y, -0.2, snap_camera)


func leave_interior(outside: Transform3D, snap_camera: bool) -> void:
	interior = null
	global_position = outside.origin
	velocity = Vector3.ZERO
	var yaw := outside.basis.get_euler().y
	visual.rotation.y = yaw
	if camera_rig:
		camera_rig.follow(self, "foot")
		camera_rig.look_from_behind(yaw, -0.25, snap_camera)


func current_speed() -> float:
	return vehicle.linear_velocity.length() if vehicle != null else Vector2(velocity.x, velocity.z).length()
