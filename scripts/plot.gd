extends Area3D
## Lote comprável de Luanda (Baixa, bairros ou Ilha). Regista-se no GameManager,
## mostra a borda/placa «À VENDA» e ergue o prédio do kit quando construído.

const Kit = preload("res://scripts/world/kit_library.gd")
const Geo = preload("res://scripts/world/geo.gd")
const Portal = preload("res://scripts/interiors/building_portal.gd")
## Estabelecimentos dos comércios dos NPCs (cada um com interior visitável).
const SHOPS := {
	"restaurante": ["Restaurante Kitanda", "Restaurante Muxima", "Tasca do Mussulo"],
	"cantina": ["Cantina da Mamã Rosa", "Cantina Kizomba", "Cantina do Bairro"],
	"loja": ["Mini-Mercado Kianda", "Loja Ngola", "Mercearia Sambizanga"],
}

@export var plot_id := ""
@export var district := "centro"
@export var area_name := "Baixa de Luanda"
@export var price := 1800
@export var size := 16.0
@export var initial_owner := ""          # "", "npc" ou "player"
@export var initial_building := ""       # "", "casa" ou "comercio"

var _border: MeshInstance3D
var _sign: Label3D
var _building: Node3D


func _ready() -> void:
	add_to_group("plots")
	GameManager.register_plot(self)
	GameManager.plot_changed.connect(func(id): if id == plot_id: refresh())
	_border = MeshInstance3D.new()
	_border.mesh = _frame_mesh(size)
	_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_border)
	_sign = Label3D.new()
	_sign.text = "À VENDA\nKz %s" % GameManager.fmt(price)
	_sign.font_size = 72
	_sign.outline_size = 18
	_sign.modulate = Color("#7ed957")
	_sign.outline_modulate = Color.WHITE
	_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sign.position = Vector3(size / 2.0 - 1.6, 2.4, size / 2.0 - 1.6)
	add_child(_sign)
	refresh()


func info() -> Dictionary:
	return GameManager.plots.get(plot_id, {})


func refresh() -> void:
	var p := info()
	var owner: String = p.get("owner", "")
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ffd166") if owner == "player" else Color("#ffffff")
	_border.material_override = mat
	_border.visible = owner != "npc" and p.get("building", "") == ""
	_sign.visible = owner == ""
	var b: String = p.get("building", "")
	if b != "" and _building == null:
		_building = Kit.scene(GameManager.building_info(p).scene).instantiate()
		_building.rotation.y = _street_yaw()
		add_child(_building)
		if owner == "npc" and b == "comercio" and district != "ilha":
			_add_portal()
		elif owner == "npc":
			_add_house_portal(p)
		elif owner == "player":
			_add_player_portal(p)


## Distância do centro do prédio à fachada (a partir da colisão do kit).
func _front_z() -> float:
	var cs := _building.get_node_or_null("Colisao/Forma") as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		return cs.position.z + (cs.shape as BoxShape3D).size.z / 2.0
	return 5.4


## Casas dos NPCs: interior gerado, mobilado e com moradores.
const FAMILIES := ["Neto", "dos Santos", "Kiala", "Mbala", "Fernandes", "Cassoma", "Lukeny", "Domingos", "Sebastião", "Mateus"]

func _add_house_portal(p: Dictionary) -> void:
	var portal: Area3D = Portal.new()
	portal.name = "Porta"
	portal.mode = "fade"
	portal.generated = true
	portal.interior_type = "casa"
	portal.portal_id = plot_id
	portal.spec = {"kind": "casa", "size": p.size, "furnish": "auto", "residents": 1 + absi(hash(plot_id)) % 3}
	portal.display_name = "Casa da família %s" % FAMILIES[absi(hash(plot_id)) % FAMILIES.size()]
	portal.position = Vector3(0, 0, _front_z() + 0.7)
	_building.add_child(portal)


## Porta dos prédios do jogador: interior gerado (tamanho, divisões, mobília guardada).
func _add_player_portal(p: Dictionary) -> void:
	var portal: Area3D = Portal.new()
	portal.name = "Porta"
	portal.mode = "fade"
	portal.generated = true
	portal.interior_type = p.business if p.building == "comercio" else "casa"
	portal.portal_id = plot_id
	portal.spec = {"kind": p.building, "size": p.size, "business": p.business, "plot_id": plot_id}
	var kind_name: String = GameManager.BUSINESS_TYPES.get(p.business, "Comércio") if p.building == "comercio" else "Casa"
	portal.display_name = "%s · %s" % [kind_name, GameManager.empire_name]
	portal.position = Vector3(0, 0, _front_z() + 0.7)
	_building.add_child(portal)
	if p.building == "comercio":
		var sign := Label3D.new()
		sign.text = portal.display_name
		sign.font_size = 56
		sign.outline_size = 14
		sign.modulate = Color("#e2725b")
		sign.outline_modulate = Color("#fff8ec")
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.position = Vector3(0, 4.6, _front_z())
		_building.add_child(sign)


## Fachada virada para a rua mais próxima (os lotes ficam nos cantos das quadras).
func _street_yaw() -> float:
	var bx := _nearest(Geo.block_centers(), global_position.x)
	var bz := _nearest(Geo.block_centers(), global_position.z)
	var dx := signf(global_position.x - bx)
	var dz := signf(global_position.z - bz)
	return atan2(dx, 0.0) if hash(plot_id) % 2 == 0 else atan2(0.0, dz)


static func _nearest(values: Array, v: float) -> float:
	var best: float = values[0]
	for c in values:
		if absf(c - v) < absf(best - v):
			best = c
	return best


## Porta do estabelecimento (restaurante / cantina / loja), à frente do pórtico.
func _add_portal() -> void:
	var types := SHOPS.keys()
	var h := absi(hash(plot_id))
	var kind: String = types[h % types.size()]
	var p: Area3D = Portal.new()
	p.name = "Porta"
	p.mode = "fade"
	p.interior_type = kind
	p.display_name = SHOPS[kind][(h / 3) % SHOPS[kind].size()]
	p.portal_id = plot_id
	p.position = Vector3(0, 0, _front_z() + 0.7)
	_building.add_child(p)
	var sign := Label3D.new()
	sign.text = p.display_name
	sign.font_size = 56
	sign.outline_size = 14
	sign.modulate = Color("#3b3355")
	sign.outline_modulate = Color("#fff8ec")
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(0, 4.6, _front_z())
	_building.add_child(sign)


## Moldura fina do lote (4 faixas planas).
static func _frame_mesh(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := s / 2.0 - 0.3
	var w := 0.35
	for seg in [[-h, -h, h, -h + w], [-h, h - w, h, h], [-h, -h, -h + w, h], [h - w, -h, h, h]]:
		var a := Vector3(seg[0], 0.1, seg[1])
		var b := Vector3(seg[2], 0.1, seg[1])
		var c := Vector3(seg[2], 0.1, seg[3])
		var d := Vector3(seg[0], 0.1, seg[3])
		for v in [a, c, b, a, d, c]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
