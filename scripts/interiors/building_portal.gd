extends Area3D
## Porta de um estabelecimento de Luanda (restaurante, cantina, loja).
## Fica à entrada do edifício; com o jogador por perto, E entra.
##   mode "fade"     → ecrã preto rápido e o interior aparece numa zona reservada do mapa
##   mode "seamless" → o interior aparece no lugar do próprio edifício (o casco é
##                     escondido) e a câmara desliza lá para dentro, sem cortes
## A porta interior de cada sala usa este mesmo script com `is_exit = true`.

@export_enum("fade", "seamless") var mode := "fade"
@export var interior_type := "restaurante"
@export var display_name := "Restaurante Kitanda"
## Identificador único do estabelecimento (sociedades/investimentos ficam ligados a ele).
@export var portal_id := ""
@export var is_exit := false
## (seamless) edifício a esconder enquanto se está lá dentro.
@export var shell_path: NodePath
## Interior gerado (tamanhos e divisões) em vez de uma cena fixa: ver interior_generator.gd.
@export var generated := false
@export var spec := {}

var player_near := false


func _ready() -> void:
	add_to_group("interactable")
	if not is_exit:
		add_to_group("portals")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2                               # jogador
	body_entered.connect(func(b): if b.is_in_group("player"): player_near = true)
	body_exited.connect(func(b): if b.is_in_group("player"): player_near = false)
	if get_child_count() == 0:                        # portas criadas em código: zona de 3 × 2.5 × 3.6 m
		var shape := BoxShape3D.new()                    # (cobre a soleira e o passeio onde fica «Fora»)
		shape.size = Vector3(3.2, 2.5, 3.6)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, 1.25, 0.8)
		add_child(cs)
	if not is_exit and get_node_or_null("Fora") == null:
		var out := Marker3D.new()
		out.name = "Fora"
		out.position = Vector3(0, 0.1, 1.8)
		add_child(out)


func interior_scene() -> PackedScene:
	return load("res://scenes/interiors/%s.tscn" % interior_type)


## Cria o interior: gerado (casas/comércios do jogador, shopping) ou a cena do tipo.
func make_interior() -> Node3D:
	if generated:
		var s := spec.duplicate()
		s["name"] = display_name
		return load("res://scripts/interiors/interior_generator.gd").generate(s)
	return interior_scene().instantiate()


## Onde o jogador reaparece ao sair (à porta, virado para a rua).
func outside_transform() -> Transform3D:
	return ($Fora as Marker3D).global_transform


func shell() -> Node3D:
	return get_node_or_null(shell_path) as Node3D if shell_path != NodePath("") else null


# ------------------------------------------------------------------ API de interação

func can_interact(player: Node) -> bool:
	return player_near and player.vehicle == null and player.seat == null and not Interiors.busy


func interaction_text(_player: Node) -> String:
	return "E — Sair para a rua" if is_exit else "E — Entrar: %s" % display_name


func interact(player: Node) -> void:
	if is_exit:
		Interiors.exit(player)
	else:
		Interiors.enter(self, player)
