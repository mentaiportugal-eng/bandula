extends Node3D
## Câmara orbital estilo GTA: Yaw → Pitch → SpringArm3D → Camera3D (+ InteractRay).
## Segue o jogador a pé ou o carro (perfil próprio, FOV pela velocidade e
## realinhamento automático atrás do veículo). O SpringArm evita atravessar paredes.

@export var target: Node3D
@export var mouse_sensitivity := 0.0028
@export var min_pitch := -1.2
@export var max_pitch := 0.35

const PROFILES := {
	"foot": {"length": 4.6, "height": 1.55, "fov": 70.0, "follow": 14.0},
	"vehicle": {"length": 8.5, "height": 2.2, "fov": 74.0, "follow": 9.0},
	"indoor": {"length": 3.0, "height": 1.45, "fov": 64.0, "follow": 12.0},
	"seated": {"length": 2.3, "height": 1.1, "fov": 56.0, "follow": 6.0},
}

@onready var yaw: Node3D = $Yaw
@onready var pitch: Node3D = $Yaw/Pitch
@onready var arm: SpringArm3D = $Yaw/Pitch/SpringArm3D
@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D
@onready var interact_ray: RayCast3D = $Yaw/Pitch/SpringArm3D/Camera3D/InteractRay

var profile := "foot"
var vehicle: Node3D = null            # VehicleBody3D a seguir (null = a pé)
var _since_mouse := 10.0
var _length := 4.6
var _height := 1.55
var _yaw_goal = null                   # alinhamento suave pedido (null = livre)
var _pitch_goal := -0.25


func _ready() -> void:
	top_level = true
	pitch.rotation.x = -0.25
	arm.collision_mask = 1          # só o mundo (jogador e carros não empurram a câmara)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED        # na web só é possível após um clique
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw.rotation.y -= event.relative.x * mouse_sensitivity
		pitch.rotation.x = clampf(pitch.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		_since_mouse = 0.0


## Coloca a câmara atrás de quem olha para `facing_yaw` (suave, ou imediato com snap).
func look_from_behind(facing_yaw: float, pitch_rad := -0.25, snap := false) -> void:
	_yaw_goal = facing_yaw + PI
	_pitch_goal = pitch_rad
	if snap:
		yaw.rotation.y = _yaw_goal
		pitch.rotation.x = pitch_rad
		_yaw_goal = null
		if target:
			var p: Dictionary = PROFILES[profile]
			_length = p.length
			_height = p.height
			global_position = target.global_position + Vector3(0, _height, 0)


## Muda o alvo/perfil (transição suave do comprimento do braço, altura e FOV).
func follow(node: Node3D, new_profile: String, as_vehicle: Node3D = null) -> void:
	target = node
	profile = new_profile
	vehicle = as_vehicle


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var p: Dictionary = PROFILES[profile]
	_since_mouse += delta
	_length = lerpf(_length, p.length, minf(1.0, delta * 3.0))
	_height = lerpf(_height, p.height, minf(1.0, delta * 3.0))
	arm.spring_length = _length
	var goal := target.global_position + Vector3(0, _height, 0)
	global_position = global_position.lerp(goal, minf(1.0, delta * p.follow))
	var fov: float = p.fov
	if vehicle != null and vehicle is RigidBody3D:
		var v: Vector3 = vehicle.linear_velocity
		var speed := v.length()
		fov += clampf(speed * 0.35, 0.0, 14.0)                       # sensação de velocidade
		if _since_mouse > 1.2 and speed > 4.0:                         # volta para trás do carro
			var fwd := vehicle.global_transform.basis.z
			var behind := atan2(-fwd.x, -fwd.z)
			yaw.rotation.y = lerp_angle(yaw.rotation.y, behind, minf(1.0, delta * 2.2))
			pitch.rotation.x = lerpf(pitch.rotation.x, -0.22, minf(1.0, delta * 1.5))
	if _yaw_goal != null:
		if _since_mouse < 0.3:
			_yaw_goal = null                                          # o jogador assumiu a câmara
		else:
			yaw.rotation.y = lerp_angle(yaw.rotation.y, _yaw_goal, minf(1.0, delta * 3.0))
			pitch.rotation.x = lerpf(pitch.rotation.x, _pitch_goal, minf(1.0, delta * 3.0))
			if absf(angle_difference(yaw.rotation.y, _yaw_goal)) < 0.01:
				_yaw_goal = null
	camera.fov = lerpf(camera.fov, fov, minf(1.0, delta * 4.0))


## Direção horizontal "para a frente" da câmara (para mover o jogador relativo à câmara).
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw.global_rotation.y)
