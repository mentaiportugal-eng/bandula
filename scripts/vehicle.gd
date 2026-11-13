extends VehicleBody3D
## Veículo arcade do Bandula (buggy, candongueiro, viatura da Guarda).
## Suspensão afinada, direção sensível à velocidade, travão de mão com drift
## (Espaço), auto-desvirar, condutor jogador/NPC, IA de trânsito na grelha de ruas
## (mão direita) e perseguição da Guarda com sirene.

const Geo = preload("res://scripts/world/geo.gd")

@export var display_name := "Buggy"
@export var max_engine_force := 2600.0
@export var max_brake := 45.0
@export var top_speed_kmh := 95.0
@export var max_steer := 0.55
@export var steer_rate := 2.8
@export var grip := 10.5
@export var drift_grip := 1.4
@export var is_police := false
@export_enum("parked", "cruise", "chase") var ai_mode := "parked"
@export var cruise_kmh := 38.0
## Sentido da força do motor no VehicleBody3D (+1: engine_force > 0 empurra para +Z local).
@export var forward_sign := 1.0

@onready var seat: Marker3D = $Seat
@onready var exit_point: Marker3D = $ExitPoint
@onready var camera_target: Marker3D = $CameraTarget
@onready var siren: Node3D = get_node_or_null("Sirene")

var driver = null                     # null · "npc" · nó do jogador
var _steer := 0.0
var _flip_t := 0.0
var _hit_cd := 0.0
var _safe := Transform3D()
var _safe_t := 0.0
var _siren_t := 0.0
var _ai_node := Vector2i(-1, -1)
var _ai_prev := Vector2i(-1, -1)
var _ai_target := Vector3.ZERO
var _rear: Array[VehicleWheel3D] = []
var _front: Array[VehicleWheel3D] = []


func _ready() -> void:
	add_to_group("vehicles")
	if is_police:
		add_to_group("police")
	for w in find_children("*", "VehicleWheel3D", false, false):
		(_front if w.use_as_steering else _rear).append(w)
		w.wheel_friction_slip = grip
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_safe = global_transform
	if ai_mode != "parked" and driver == null:
		driver = "npc"
	set_siren(false)


func speed() -> float:
	return linear_velocity.dot(global_basis.z)          # frente do modelo = +Z


func speed_kmh() -> float:
	return absf(speed()) * 3.6


func set_driver(d) -> void:
	driver = d
	if d is Node:
		ai_mode = "parked"


func eject_driver() -> void:
	driver = null
	ai_mode = "parked"
	set_siren(false)


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver is Node and GameManager.input_locked:
		pass                                            # a escrever no chat: o carro segue sem comandos
	elif driver is Node:
		throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("handbrake")
	elif driver == "npc" and ai_mode != "parked":
		var ai := _ai_controls()
		throttle = ai.x
		steer_in = ai.y
	_drive(throttle, steer_in, handbrake, delta)
	_recover(delta)
	if siren and siren.visible:
		_siren_t += delta
		var phase := int(_siren_t * 6.0) % 2
		($Sirene/Vermelha as OmniLight3D).light_energy = 3.0 if phase == 0 else 0.2
		($Sirene/Azul as OmniLight3D).light_energy = 0.2 if phase == 0 else 3.0
	_hit_cd = maxf(0.0, _hit_cd - delta)


func _drive(throttle: float, steer_in: float, handbrake: bool, delta: float) -> void:
	var v := speed()
	var top := top_speed_kmh / 3.6
	# direção mais curta em alta velocidade
	var limit := lerpf(max_steer, max_steer * 0.35, clampf(absf(v) / top, 0.0, 1.0))
	_steer = move_toward(_steer, steer_in * limit, steer_rate * delta)
	steering = _steer
	var force := 0.0
	var brk := 0.0
	if throttle > 0.05:
		if v < -1.0:
			brk = max_brake
		elif v < top:
			force = max_engine_force * throttle * (1.0 - maxf(v, 0.0) / (top * 1.1))
	elif throttle < -0.05:
		if v > 1.0:
			brk = max_brake
		elif -v < top * 0.35:
			force = max_engine_force * 0.6 * throttle
	else:
		brk = 1.5                                            # rolamento
	engine_force = force * forward_sign
	brake = brk
	for w in _rear:
		w.wheel_friction_slip = lerpf(w.wheel_friction_slip, drift_grip if handbrake else grip, minf(1.0, delta * 8.0))
		w.brake = max_brake * 0.6 if handbrake else brk
	# força para baixo: estabilidade a alta velocidade
	apply_central_force(Vector3.DOWN * mass * minf(absf(v), 30.0) * 0.12)


## Auto-desvirar: capotado ~1,5 s (ou caiu do mapa) → volta de pé no último sítio seguro.
func _recover(delta: float) -> void:
	var up := global_basis.y
	if up.y > 0.9 and absf(speed()) < 30.0:
		_safe_t += delta
		if _safe_t > 1.0:
			_safe_t = 0.0
			_safe = global_transform
	if up.y < 0.35:
		_flip_t += delta
	else:
		_flip_t = 0.0
	if _flip_t > 1.5 or global_position.y < -8.0:
		_flip_t = 0.0
		var yaw := atan2(global_basis.z.x, global_basis.z.z)
		var pos := global_position + Vector3(0, 1.2, 0) if global_position.y > -8.0 else _safe.origin + Vector3(0, 1.0, 0)
		global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func _on_body_entered(body: Node) -> void:
	if not (driver is Node) or _hit_cd > 0.0:
		return
	var rel := linear_velocity.length()
	if body is RigidBody3D:
		rel = (linear_velocity - (body as RigidBody3D).linear_velocity).length()
	if body.is_in_group("police") and rel > 4.0:
		GameManager.report_offense("police_crash")
		_hit_cd = 1.5
	elif body.is_in_group("vehicles") and rel > 9.0:
		GameManager.report_offense("crash")
		_hit_cd = 1.5


func set_siren(on: bool) -> void:
	if siren:
		siren.visible = on


# ------------------------------------------------------------------ IA (grelha de ruas, mão direita)

static func node_pos(n: Vector2i) -> Vector3:
	var rc := Geo.road_centers()
	return Vector3(rc[n.x], 0.0, rc[n.y])


static func nearest_node(p: Vector3) -> Vector2i:
	var rc := Geo.road_centers()
	var idx := func(v: float) -> int: return clampi(int(round((v - rc[0]) / Geo.CITY_PITCH)), 0, rc.size() - 1)
	return Vector2i(idx.call(p.x), idx.call(p.z))


func start_ai(mode: String) -> void:
	ai_mode = mode
	driver = "npc"
	set_siren(mode == "chase" and is_police)
	_ai_prev = Vector2i(-1, -1)
	_ai_node = nearest_node(global_position)
	_ai_pick_next()


func _ai_pick_next() -> void:
	var n := Geo.road_centers().size()
	var options: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = _ai_node + d
		if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and c != _ai_prev:
			options.append(c)
	if options.is_empty():
		options.append(_ai_prev)
	var next: Vector2i = options[randi() % options.size()]
	var a := node_pos(_ai_node)
	var b := node_pos(next)
	var dir := (b - a).normalized()
	var right := Vector3(-dir.z, 0, dir.x)                  # mão direita (Angola)
	_ai_target = b + right * 2.4
	_ai_prev = _ai_node
	_ai_node = next


## Devolve (acelerador, volante) para o modo de IA atual.
func _ai_controls() -> Vector2:
	var target := _ai_target
	var want := cruise_kmh / 3.6
	if ai_mode == "chase" and GameManager.player:
		target = GameManager.player.global_position
		want = top_speed_kmh / 3.6 * 0.9
		if target.distance_to(global_position) < 6.0:
			want = 0.0
	elif Vector2(target.x - global_position.x, target.z - global_position.z).length() < 7.0:
		_ai_pick_next()
		target = _ai_target
	var local := global_transform.affine_inverse() * target
	var ang := atan2(local.x, local.z)                   # >0 = alvo à esquerda
	if absf(ang) > 0.6:
		want = minf(want, 6.0)                                # abranda nas curvas
	for v in get_tree().get_nodes_in_group("vehicles"):    # trava se houver carro à frente
		if v == self:
			continue
		var rel: Vector3 = global_transform.affine_inverse() * v.global_position
		if rel.z > 0.0 and rel.z < 9.0 and absf(rel.x) < 2.2:
			want = minf(want, 0.0 if ai_mode != "chase" else want)
	var thr := clampf((want - speed()) * 0.5, -1.0, 1.0)
	return Vector2(thr, clampf(ang * 1.6, -1.0, 1.0))
