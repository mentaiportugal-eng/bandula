extends Node3D
## Os outros jogadores online no mundo local: cria/remove os avatares, aplica os
## estados recebidos, mostra só quem está no mesmo sítio (rua ou o mesmo interior)
## e põe os balões de conversa (também sobre o próprio jogador).

const RemoteAvatar = preload("res://scripts/net/remote_avatar.gd")

var avatars := {}                 # id → RemoteAvatar
var _own_bubble: Label3D
var _own_t := 0.0


func _ready() -> void:
	Network.peer_joined.connect(_on_joined)
	Network.peer_left.connect(_on_left)
	Network.state_received.connect(func(id, s): if avatars.has(id): avatars[id].apply(s))
	Network.chat_received.connect(_on_chat)
	Voice.voice_received.connect(func(id, frames): if avatars.has(id): avatars[id].push_voice(frames))


func _on_joined(id: int, shown_name: String, look: int) -> void:
	if avatars.has(id):
		return
	var a: Node3D = RemoteAvatar.new()
	add_child(a)
	a.setup(id, shown_name, look)
	avatars[id] = a


func _on_left(id: int, _n: String) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)


func _on_chat(id: int, _name: String, text: String) -> void:
	if id == 0:
		return
	if avatars.has(id):
		avatars[id].say(text)
	elif id == multiplayer.get_unique_id():
		_say_own(text)


## Balão sobre o próprio avatar quando é o jogador local a falar.
func _say_own(text: String) -> void:
	var p = GameManager.player
	if p == null:
		return
	if _own_bubble == null or not is_instance_valid(_own_bubble):
		_own_bubble = Label3D.new()
		_own_bubble.font_size = 54
		_own_bubble.outline_size = 14
		_own_bubble.modulate = Color("#3b3355")
		_own_bubble.outline_modulate = Color("#fff8ec")
		_own_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_own_bubble.no_depth_test = true
		_own_bubble.pixel_size = 0.004
		_own_bubble.width = 600.0
		_own_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_own_bubble.position = Vector3(0, 2.6, 0)
		p.add_child(_own_bubble)
	_own_bubble.text = text
	_own_bubble.visible = true
	_own_t = 6.0


func local_room() -> String:
	return str(Interiors.portal.portal_id) if Interiors.is_inside() and Interiors.portal != null else ""


func _process(delta: float) -> void:
	var here := local_room()
	for id in avatars:
		var a = avatars[id]
		a.visible = a._has_state and a.room == here
	if _own_t > 0.0:
		_own_t -= delta
		if _own_t <= 0.0 and is_instance_valid(_own_bubble):
			_own_bubble.visible = false
