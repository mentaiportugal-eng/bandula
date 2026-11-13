extends Area3D
## Mobiliário interativo dos interiores.
##   kind "seat"    → cadeira/banco: E senta (posição exata do SitPoint, animação Sit
##                    do esqueleto, câmara acolhedora); W ou Espaço levanta. Jogador e
##                    NPCs reservam o lugar — ninguém se senta em cima de ninguém.
##   kind "counter" → balcão de serviço: E abre a loja do estabelecimento (HUD).

@export_enum("seat", "counter") var kind := "seat"
@export var shop_type := "restaurante"
@export var label := "Cadeira"
## (balcões) nome da loja quando há várias no mesmo interior (ex.: Fortaleza Shopping).
@export var place_name := ""

var occupant: Node = null
var player_near := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("seats" if kind == "seat" else "counters")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(func(b): if b.is_in_group("player"): player_near = true)
	body_exited.connect(func(b): if b.is_in_group("player"): player_near = false)


func interior() -> Node:
	var p := get_parent()
	while p != null and not p.has_method("activate"):
		p = p.get_parent()
	return p


# ------------------------------------------------------------------ lugares

func is_free() -> bool:
	return occupant == null or not is_instance_valid(occupant)


func reserve(who: Node) -> bool:
	if not is_free() and occupant != who:
		return false
	occupant = who
	return true


func release(who: Node) -> void:
	if occupant == who:
		occupant = null


## Transformação onde o avatar fica sentado (origem nos pés, virado para +Z da cadeira).
func sit_transform() -> Transform3D:
	return ($SitPoint as Marker3D).global_transform


## Ponto onde se fica de pé antes de sentar / depois de levantar.
func approach_position() -> Vector3:
	return ($Approach as Marker3D).global_position


# ------------------------------------------------------------------ API de interação

func can_interact(player: Node) -> bool:
	if not player_near or player.seat != null:
		return false
	return kind == "counter" or is_free()


func interaction_text(_player: Node) -> String:
	if kind == "counter":
		var i := interior()
		if i and i.owner_plot_id != "":
			return "E — Ver as contas do seu negócio"
		return "E — Pedir ao balcão (%s)" % (place_name if place_name != "" else (i.display_name if i else label))
	return "E — Sentar (%s)" % label.to_lower()


func interact(player: Node) -> void:
	if kind == "counter":
		var i := interior()
		if i and i.owner_plot_id != "":
			get_tree().call_group("hud", "open_business", i.owner_plot_id)
			return
		var shown: String = place_name if place_name != "" else (i.display_name if i else label)
		var pid: String = (i.place_id if i else "") + (":" + place_name if place_name != "" else "")
		get_tree().call_group("hud", "open_shop", shop_type, pid, shown)
	else:
		player.sit_on(self)
