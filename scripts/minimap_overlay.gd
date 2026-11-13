extends Control
## Camada por cima do minimapa: seta do jogador, viaturas da Guarda (vermelho/azul),
## carros civis e as suas propriedades (dourado). Norte para cima.

@export var world_span := 320.0          # metros visíveis (= size da câmara ortográfica)

var player: Node3D


func _w2m(p: Vector3) -> Vector2:
	var rel := Vector2(p.x - player.global_position.x, p.z - player.global_position.z)
	return size / 2.0 + rel * (size.x / world_span)


func _draw() -> void:
	if player == null:
		return
	var half := size / 2.0
	for p in GameManager.player_plots():
		var n: Node3D = p.node
		var m := _w2m(n.global_position)
		if Rect2(Vector2.ZERO, size).has_point(m):
			draw_rect(Rect2(m - Vector2(5, 5), Vector2(10, 10)), Color("#ffd166"))
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == player.vehicle:
			continue
		var m := _w2m(v.global_position)
		if not Rect2(Vector2.ZERO, size).has_point(m):
			continue
		if v.is_police:
			var flash := int(Time.get_ticks_msec() / 200) % 2 == 0
			draw_circle(m, 5.0, Color("#ff3355") if flash else Color("#3d7bff"))
		else:
			draw_circle(m, 3.0, Color("#5aaeff"))
	# seta do jogador (direção do avatar ou do carro)
	var heading := 0.0
	if player.vehicle:
		var f: Vector3 = player.vehicle.global_basis.z
		heading = atan2(f.x, f.z)
	else:
		heading = player.visual.global_rotation.y
	var fwd := Vector2(sin(heading), cos(heading))
	var side := Vector2(fwd.y, -fwd.x)
	var tip := half + fwd * 9.0
	draw_colored_polygon(PackedVector2Array([tip, half - fwd * 6.0 + side * 6.0, half - fwd * 2.0, half - fwd * 6.0 - side * 6.0]), Color("#ff6f6f"))
	draw_arc(half, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
