extends Node3D
## Cena principal do Bandula: liga jogador, câmara, HUD, trânsito e mundo de Luanda,
## estaciona os primeiros carros e trata da detenção (leva o jogador à Fortaleza).

@export var parked: Dictionary = {
	"CarroBuggy": preload("res://scenes/vehicles/buggy.tscn"),
	"CarroCandongueiro": preload("res://scenes/vehicles/candongueiro.tscn"),
}

@onready var world: Node3D = $Luanda
@onready var player: CharacterBody3D = $Player
@onready var rig: Node3D = $CameraRig
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	var spawns := world.get_node("Spawns")
	player.global_position = spawns.get_node("Jogador").global_position
	player.camera_rig = rig
	rig.follow(player, "foot")
	rig.global_position = player.global_position + Vector3(0, 1.5, 0)
	hud.bind(player)
	for marker_name in parked:
		var mk: Node3D = spawns.get_node_or_null(marker_name)
		if mk == null:
			continue
		var v: VehicleBody3D = parked[marker_name].instantiate()
		$Traffic.add_child(v)
		v.global_transform = mk.global_transform
	GameManager.busted.connect(_on_busted)
	_debug_auto_enter()


func _on_busted(_fine: int) -> void:
	if Interiors.is_inside():
		Interiors.exit(player, true)
	if player.seat:
		player.stand_up()
	if player.vehicle:
		player.exit_vehicle()
	var door: Node3D = world.get_node("Spawns/PortaEsquadra")    # detido → Esquadra da Ingombota
	player.global_position = door.global_position
	player.velocity = Vector3.ZERO


## Atalho de demonstração na web: ...index.html?interior=restaurante|cantina|loja|ilha
## entra logo no primeiro estabelecimento desse tipo (útil para testar e mostrar).
func _debug_auto_enter() -> void:
	if not OS.has_feature("web"):
		return
	var q := str(JavaScriptBridge.eval("location.search", true))
	var m := RegEx.create_from_string("interior=([a-z]+)").search(q)
	if m == null:
		return
	await get_tree().create_timer(1.5).timeout
	for p in get_tree().get_nodes_in_group("portals"):
		var want := m.get_string(1)
		if (want == "ilha" and p.mode == "seamless") or (want != "ilha" and p.mode == "fade" and p.interior_type == want):
			Interiors.enter(p, player)
			return
