extends Node3D
## Raiz de um interior (restaurante, cantina, loja). Ativado pelo InteriorManager:
## põe o nome do estabelecimento no letreiro, coloca o atendente, senta alguns
## clientes logo à entrada do jogador e vai trazendo outros pela porta.

const Patron = preload("res://scripts/interiors/patron_npc.gd")
const NPC_AVATARS := [
	"res://scenes/characters/kianda.scn", "res://scenes/characters/zeca.scn",
	"res://scenes/characters/nzinga.scn", "res://scenes/characters/mateus.scn",
	"res://scenes/characters/rosa.scn", "res://scenes/characters/sr_antonio.scn",
	"res://scenes/characters/luena.scn",
]

@export var interior_type := "restaurante"
@export var display_name := "Restaurante"
@export var max_patrons := 4
@export var spawn_interval := Vector2(6.0, 14.0)
## Lote do jogador a que este interior pertence ("" = estabelecimento de terceiros).
@export var owner_plot_id := ""
## Moradores já sentados ao entrar (casas dos NPCs).
@export var residents := 0

var place_id := ""
var active := false
var _spawn_t := 0.0


func entrance() -> Marker3D:
	return $Entrada


func seats() -> Array:
	return _mine("seats")


func counters() -> Array:
	return _mine("counters")


func _mine(group: String) -> Array:
	return get_tree().get_nodes_in_group(group).filter(func(n): return is_ancestor_of(n))


func free_seats() -> Array:
	return seats().filter(func(s): return s.is_free())


func patrons() -> Array:
	return $Clientes.get_children().filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())


func activate(id: String, shown_name: String) -> void:
	place_id = id
	display_name = shown_name
	var sign := get_node_or_null("Letreiro") as Label3D
	if sign:
		sign.text = shown_name
	active = true
	for counter in counters():                       # um atendente por balcão
		var clerk := _spawn_npc()
		clerk.stand_behind_counter(counter.get_node("Atendente"))
	if residents > 0:                                # moradores em casa (sofá, mesa…)
		var spots := free_seats()
		spots.shuffle()
		for i in mini(residents, spots.size()):
			var npc := _spawn_npc()
			if spots[i].reserve(npc):
				npc.sit_now(spots[i], 1.0e9)
	if max_patrons <= 0 or counters().is_empty():      # negócio sem balcão = fechado
		return
	# alguns clientes já sentados
	var free := free_seats()
	free.shuffle()
	for i in mini(randi_range(1, max_patrons - 1), free.size()):
		var npc := _spawn_npc()
		if free[i].reserve(npc):
			npc.sit_now(free[i])
	_spawn_t = randf_range(2.0, 5.0)


func deactivate() -> void:
	active = false
	for n in $Clientes.get_children():
		n.queue_free()
	for s in seats():
		s.occupant = null


func _spawn_npc() -> AnimatableBody3D:
	var npc: AnimatableBody3D = Patron.create(load(NPC_AVATARS[randi() % NPC_AVATARS.size()]))
	npc.interior = self
	$Clientes.add_child(npc)
	return npc


func _process(delta: float) -> void:
	if not active:
		return
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t = randf_range(spawn_interval.x, spawn_interval.y)
	var guests := patrons().filter(func(n): return n.mode == "patron").size()
	var free := free_seats()
	if guests >= max_patrons or free.is_empty() or counters().is_empty():
		return
	var npc := _spawn_npc()
	var s = free[randi() % free.size()]
	s.reserve(npc)
	npc.walk_to_seat(s, entrance().global_position)
