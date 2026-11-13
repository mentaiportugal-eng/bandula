extends Node
## Bandula — InteriorManager (autoload "Interiors").
## Transições entre a rua e os interiores dos estabelecimentos:
##   fade     → ecrã preto (ColorRect) 0,3 s, interior instanciado numa zona reservada
##              sob o mapa, jogador e câmara colocados à entrada, fade de volta
##   seamless → o interior surge no lugar do edifício (casco escondido e sem colisão)
##              e a câmara desliza para dentro sem cortes

signal entered(interior: Node3D, portal: Node)
signal exited

const FADE_ORIGIN := Vector3(0, -400, 0)
const FADE_TIME := 0.3

var current: Node3D = null
var portal: Node = null
var busy := false
var _fade: ColorRect
var _shell_layers := {}


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func is_inside() -> bool:
	return current != null


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tw.finished


func enter(p: Node, player: Node) -> void:
	if busy or current != null:
		return
	busy = true
	var seamless: bool = p.mode == "seamless" and p.shell() != null
	if not seamless:
		await _fade_to(1.0)
	var interior: Node3D = p.make_interior()
	player.get_parent().add_child(interior)          # mesma cena do jogador (main)
	if seamless:
		var shell: Node3D = p.shell()
		interior.global_transform = shell.global_transform
		_set_shell(shell, false)
	else:
		interior.global_position = FADE_ORIGIN
	interior.activate(p.portal_id, p.display_name)
	current = interior
	portal = p
	player.enter_interior(interior, not seamless)
	if not seamless:
		await _fade_to(0.0)
	busy = false
	entered.emit(interior, p)


func exit(player: Node, instant := false) -> void:
	if busy or current == null:
		return
	busy = true
	var seamless: bool = portal.mode == "seamless" and portal.shell() != null
	if not seamless and not instant:
		await _fade_to(1.0)
	if player.seat != null:
		player.stand_up()
	player.leave_interior(portal.outside_transform(), not seamless)
	if seamless:
		_set_shell(portal.shell(), true)
	current.deactivate()
	current.queue_free()
	current = null
	portal = null
	if not seamless and not instant:
		await _fade_to(0.0)
	busy = false
	exited.emit()


## Esconde/mostra o casco do edifício (malhas e colisão) no modo seamless.
func _set_shell(shell: Node3D, on: bool) -> void:
	for n in shell.find_children("*", "", true, false):
		if n is MeshInstance3D:
			n.visible = on
		elif n is CollisionObject3D and not n is Area3D:
			if not on:
				_shell_layers[n] = n.collision_layer
				n.collision_layer = 0
			elif _shell_layers.has(n):
				n.collision_layer = _shell_layers[n]
	if on:
		_shell_layers.clear()
