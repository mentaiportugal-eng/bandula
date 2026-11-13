extends Node3D
## Trânsito de Luanda e perseguição da Guarda.
## Mantém carros civis a circular na grelha, envia viaturas da Guarda conforme as
## estrelas (1 por estrela, até 4), informa o GameManager de quem vê o jogador e
## da distância da viatura mais próxima (para o «DETIDO»).

const Geo = preload("res://scripts/world/geo.gd")

@export var civilian_scenes: Array[PackedScene] = []
@export var police_scene: PackedScene
@export var civilian_count := 8
@export var max_police := 4
@export var sight_range := 45.0

var _police: Array = []
var _spawn_t := 0.0


func _ready() -> void:
	randomize()
	call_deferred("_spawn_civilians")


func _spawn_civilians() -> void:
	for i in civilian_count:
		if civilian_scenes.is_empty():
			return
		var scene: PackedScene = civilian_scenes[i % civilian_scenes.size()]
		_spawn(scene, _random_road_node(40.0), "cruise")


func _random_road_node(min_dist: float, max_dist := INF) -> Vector2i:
	var n := Geo.road_centers().size()
	var p := GameManager.player.global_position if GameManager.player else Vector3.ZERO
	for attempt in 40:
		var c := Vector2i(randi() % n, randi() % n)
		var d := preload("res://scripts/vehicle.gd").node_pos(c).distance_to(p)
		if d >= min_dist and d <= max_dist:
			return c
	return Vector2i(randi() % n, randi() % n)


func _spawn(scene: PackedScene, node: Vector2i, mode: String) -> VehicleBody3D:
	var v: VehicleBody3D = scene.instantiate()
	add_child(v)
	var pos: Vector3 = v.node_pos(node) + Vector3(2.4, 0.8, 0)
	v.global_position = pos
	v.start_ai(mode)
	return v


func _physics_process(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return
	var level: int = GameManager.wanted_level
	var want := mini(level, max_police)
	_police = _police.filter(func(v): return is_instance_valid(v))
	var chasing := _police.filter(func(v): return v.ai_mode == "chase")
	_spawn_t -= delta
	if chasing.size() < want and _spawn_t <= 0.0 and police_scene:
		_spawn_t = 2.5
		_police.append(_spawn(police_scene, _random_road_node(70.0, 160.0), "chase"))
	if level == 0:
		for v in _police:                                  # perseguição terminou: voltam à patrulha
			if v.ai_mode == "chase":
				v.start_ai("cruise")
			if v.global_position.distance_to(player.global_position) > 160.0:
				v.queue_free()
	# quem vê o jogador e quão perto está a viatura mais próxima
	var nearest := INF
	var sees := false
	for v in _police:
		if not is_instance_valid(v) or v.driver is Node:
			continue
		var d: float = v.global_position.distance_to(player.global_position)
		nearest = minf(nearest, d)
		if d < sight_range:
			sees = true
	GameManager.police_sees_player = sees
	GameManager.police_check(nearest, player.current_speed(), delta)
