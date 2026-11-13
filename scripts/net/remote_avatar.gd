extends Node3D
## Avatar de outro jogador online: interpola a posição recebida, anima (andar, correr,
## sentar), mostra o carro em que vai, o nome por cima da cabeça e balões de conversa.

const KIT := "res://scenes/kit/"
const CAR_SCENES := {"buggy": "carro_buggy", "candongueiro": "carro_candongueiro", "guarda": "carro_guarda"}

var peer_id := 0
var player_name := ""
var room := ""
var _target := Vector3.ZERO
var _yaw := 0.0
var _speed := 0.0
var _state := "walk"
var _vehicle := ""
var _has_state := false
var _bubble_t := 0.0

var voice: AudioStreamPlayer3D
var _voice_pb: AudioStreamGeneratorPlayback
var _talk_t := 0.0

var avatar: Node3D
var name_label: Label3D
var bubble: Label3D
var car: Node3D


func setup(id: int, shown_name: String, look: int) -> void:
	peer_id = id
	player_name = shown_name
	name = "Jogador_%d" % id
	avatar = Node3D.new()
	avatar.name = "AvatarSlot"
	avatar.set_script(load("res://scripts/avatar_slot.gd"))
	avatar.set("avatar_scene", load(Network.LOOKS[clampi(look, 0, Network.LOOKS.size() - 1)]))
	add_child(avatar)
	name_label = _label(shown_name, 2.15, 64, Color("#ffffff"), Color("#3b3355"))
	bubble = _label("", 2.65, 54, Color("#3b3355"), Color("#fff8ec"))
	bubble.visible = false
	visible = false                                   # até chegar o primeiro estado


func _label(text: String, y: float, size: int, col: Color, outline: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = outline
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, y, 0)
	l.pixel_size = 0.004
	l.width = 600.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func apply(s: Dictionary) -> void:
	_target = s.p
	_yaw = s.y
	_speed = s.sp
	_state = s.st
	room = s.r
	if s.v != _vehicle:
		_set_vehicle(s.v)
	if not _has_state:
		_has_state = true
		global_position = _target


func say(text: String) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_t = 6.0


## Voz recebida (mono 16 kHz) → som 3D a sair do avatar.
func push_voice(frames: PackedVector2Array) -> void:
	if voice == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = Voice.RATE
		gen.buffer_length = 0.5
		voice = AudioStreamPlayer3D.new()
		voice.name = "Voz"
		voice.stream = gen
		voice.unit_size = 7.0
		voice.max_distance = Voice.RANGE
		voice.volume_db = 3.0
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		voice.position = Vector3(0, 1.6, 0)
		add_child(voice)
		voice.play()
		_voice_pb = voice.get_stream_playback()
	if _voice_pb and _voice_pb.can_push_buffer(frames.size()):
		_voice_pb.push_buffer(frames)
	_talk_t = 0.3


func is_talking() -> bool:
	return _talk_t > 0.0


func _set_vehicle(kind: String) -> void:
	_vehicle = kind
	if car:
		car.queue_free()
		car = null
	if kind != "" and CAR_SCENES.has(kind):
		car = (load(KIT + CAR_SCENES[kind] + ".scn") as PackedScene).instantiate()
		for body in car.find_children("*", "CollisionObject3D", true, false):
			body.queue_free()
		add_child(car)


func _process(delta: float) -> void:
	if not _has_state:
		return
	if global_position.distance_to(_target) > 12.0:
		global_position = _target                     # teletransporte (entrar/sair de interiores)
	else:
		global_position = global_position.lerp(_target, minf(1.0, delta * 12.0))
	var in_car := _vehicle != ""
	if in_car:
		rotation.y = lerp_angle(rotation.y, _yaw, minf(1.0, delta * 10.0))
		avatar.rotation.y = 0.0
		avatar.position = Vector3(0.4, 0.55, 0.0)
		avatar.scale = Vector3.ONE * 0.85
	else:
		rotation.y = 0.0
		avatar.position = Vector3.ZERO
		avatar.scale = Vector3.ONE
		avatar.rotation.y = lerp_angle(avatar.rotation.y, _yaw, minf(1.0, delta * 12.0))
	avatar.sit(_state == "sit" or in_car)
	if _state == "walk" or _state == "air":
		avatar.set_locomotion(_speed / 4.2 if _speed <= 4.2 else 1.0 + (_speed - 4.2) / 3.3)
	name_label.position.y = 2.6 if in_car else 2.15
	bubble.position.y = name_label.position.y + 0.5
	if _talk_t > 0.0:
		_talk_t -= delta
	name_label.modulate = Color("#7dffb0") if _talk_t > 0.0 else Color.WHITE
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			bubble.visible = false
