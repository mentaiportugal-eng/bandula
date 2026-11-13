extends AnimatableBody3D
## Cliente NPC dos interiores: entra pela porta, procura um lugar livre (reserva-o),
## anda até lá, senta-se (animação Sit), fica um bocado e vai-se embora.
## No modo "clerk" fica de pé atrás do balcão a atender.

const SPEED := 1.35

var interior: Node3D
var seat: Node = null
var mode := "patron"              # "patron" | "clerk"
var state := "idle"               # walk_in · seated · walk_out · idle
var path: Array[Vector3] = []
var timer := 0.0
var avatar: Node3D


## Cria o NPC com um avatar .glb (AvatarSlot) e a colisão em cápsula.
static func create(avatar_scene: PackedScene) -> AnimatableBody3D:
	var npc: AnimatableBody3D = new()
	npc.name = "Cliente"
	npc.collision_layer = 1
	npc.collision_mask = 0
	npc.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	npc.add_child(cs)
	var slot: Node3D = Node3D.new()
	slot.name = "AvatarSlot"
	slot.set_script(load("res://scripts/avatar_slot.gd"))
	slot.set("avatar_scene", avatar_scene)
	slot.set("target_height", 1.72)
	npc.add_child(slot)
	npc.avatar = slot
	return npc


## Entra pela porta e vai até ao lugar `s` (já reservado).
func walk_to_seat(s: Node, entrance: Vector3) -> void:
	seat = s
	global_position = entrance
	var approach: Vector3 = s.approach_position()
	path = [Vector3(approach.x, entrance.y, entrance.z - 0.4), approach]
	state = "walk_in"


## Já sentado quando o jogador entra (sala com vida desde o primeiro segundo).
func sit_now(s: Node, duration := -1.0) -> void:
	seat = s
	_sit()
	timer = duration if duration > 0.0 else randf_range(8.0, 40.0)


func stand_behind_counter(marker: Marker3D) -> void:
	mode = "clerk"
	global_transform = marker.global_transform
	state = "idle"


func _sit() -> void:
	var t: Transform3D = seat.sit_transform()
	global_position = t.origin
	avatar.rotation.y = t.basis.get_euler().y
	collision_layer = 0                                  # sentado não empurra ninguém
	avatar.sit(true)
	state = "seated"
	timer = randf_range(15.0, 45.0)


func _physics_process(delta: float) -> void:
	match state:
		"walk_in", "walk_out":
			if path.is_empty():
				if state == "walk_in":
					_sit()
				else:
					queue_free()
				return
			var target: Vector3 = path[0]
			var to := target - global_position
			to.y = 0.0
			if to.length() < 0.08:
				path.pop_front()
				return
			var stepv := to.normalized() * minf(SPEED * delta, to.length())
			global_position += stepv
			avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 10.0))
			avatar.set_locomotion(1.0)
		"seated":
			timer -= delta
			if timer <= 0.0:
				_leave()
		_:
			avatar.set_locomotion(0.0)


func _leave() -> void:
	avatar.sit(false)
	collision_layer = 1
	var approach: Vector3 = seat.approach_position()
	seat.release(self)
	global_position = approach
	var entrance: Vector3 = interior.entrance().global_position
	path = [Vector3(approach.x, entrance.y, entrance.z - 0.4), entrance]
	state = "walk_out"
