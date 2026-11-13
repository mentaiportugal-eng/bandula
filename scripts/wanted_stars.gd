extends Control
## Cinco estrelas de procurado desenhadas com polígonos (não depende de fontes com ★).
## Piscam quando a Guarda está a ver o jogador.

@export var level := 0
@export var star_radius := 13.0
@export var on_color := Color("#ffd166")
@export var off_color := Color(1, 1, 1, 0.28)


func _ready() -> void:
	custom_minimum_size = Vector2(star_radius * 2.4 * 5, star_radius * 2.2)


func _process(_d: float) -> void:
	if level > 0:
		queue_redraw()


func _draw() -> void:
	var blink := GameManager.police_sees_player and int(Time.get_ticks_msec() / 250) % 2 == 0
	for i in 5:
		var c := Vector2(size.x - star_radius * 1.2 - i * star_radius * 2.4, size.y / 2.0)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			var r := star_radius if k % 2 == 0 else star_radius * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var lit := (4 - i) < level
		var col := on_color if lit else off_color
		if lit and blink:
			col = Color("#ff5a79")
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color("#3b3355", 0.8), 2.0, true)
