extends SceneTree
## Constrói todas as cenas do Bandula (reprodutível, sem erros de edição manual):
##   godot4 --headless --path godot/bandula --script res://tools/build_game.gd
## Gera: scenes/kit/*.scn · scenes/world/luanda.tscn · scenes/camera_rig.tscn
##       scenes/player.tscn · scenes/vehicles/{buggy,candongueiro,guarda}.tscn
##       ui/bandula_theme.tres · scenes/hud.tscn · scenes/main.tscn
## Opções:  -- --sem-mundo   (não regenera o mapa, o passo mais lento)

const Kit = preload("res://scripts/world/kit_library.gd")
const InteriorBuilder = preload("res://scripts/interiors/interior_builder.gd")
const WorldBuilder = preload("res://scripts/world/world_builder.gd")
const SUN_DIR := Vector3(38, 120, 30)

## Dimensões dos veículos (iguais ao jogo web: VEHICLE_TYPES em vehicles.js).
const VEHICLES := {
	"buggy": {"name": "Buggy Urbano", "body": "carro_buggy", "mass": 520.0, "length": 3.4, "width": 1.9, "height": 1.0,
		"wheelbase": 2.2, "track": 1.62, "wheel_r": 0.42, "seat": Vector3(0.38, 0.62, -0.12), "top": 95.0, "police": false},
	"candongueiro": {"name": "Candongueiro", "body": "carro_candongueiro", "mass": 820.0, "length": 4.6, "width": 2.1, "height": 1.7,
		"wheelbase": 3.0, "track": 1.8, "wheel_r": 0.45, "seat": Vector3(0.42, 0.62, 1.15), "top": 78.0, "police": false},
	"guarda": {"name": "Viatura da Guarda", "body": "carro_guarda", "mass": 640.0, "length": 3.9, "width": 2.0, "height": 1.3,
		"wheelbase": 2.5, "track": 1.7, "wheel_r": 0.44, "seat": Vector3(0.4, 0.52, 0.08), "top": 105.0, "police": true},
}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for d in ["res://scenes/vehicles", "res://ui", "res://scenes/world"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	print("Kit: ", Kit.prepare_all().size(), " peças")
	if not args.has("--sem-mundo"):
		var layout := ProjectSettings.globalize_path("res://").path_join("../../assets/luanda/layout.json").simplify_path()
		var w := WorldBuilder.build(1234, layout)
		_check(WorldBuilder.save(w), "mundo")
		print("Mundo: %d coqueiros, %d quiosques, %d lotes (layout: %s)" % [w.get_node("Coqueiros").get_child_count(), w.get_node("Quiosques").get_child_count(), w.get_node("Lotes").get_child_count(), FileAccess.file_exists(layout)])
		w.free()
	for kind in ["restaurante", "cantina", "loja"]:
		_save(InteriorBuilder.build(kind), "res://scenes/interiors/%s.tscn" % kind)
	_save(_camera_rig(), "res://scenes/camera_rig.tscn")
	_save(_player(), "res://scenes/player.tscn")
	for key in VEHICLES:
		_save(_vehicle(VEHICLES[key]), "res://scenes/vehicles/%s.tscn" % key)
	var theme := _theme()
	_check(ResourceSaver.save(theme, "res://ui/bandula_theme.tres"), "tema")
	_save(_hud(load("res://ui/bandula_theme.tres")), "res://scenes/hud.tscn")
	_save(_main(), "res://scenes/main.tscn")
	var server := Node.new()
	server.name = "Servidor"
	server.set_script(load("res://scripts/net/server_main.gd"))
	_save(server, "res://scenes/server.tscn")
	print("Cenas prontas em %d ms" % (Time.get_ticks_msec() - t0))
	quit()


# ------------------------------------------------------------------ utilidades

func _check(err: Error, what: String) -> void:
	if err != OK:
		push_error("Falha ao gravar %s: %s" % [what, error_string(err)])


func _save(root: Node, path: String) -> void:
	var ps := PackedScene.new()
	_check(ps.pack(root), path)
	_check(ResourceSaver.save(ps, path), path)
	root.free()


func _add(parent: Node, child: Node, owner: Node) -> Node:
	parent.add_child(child)
	child.owner = owner
	return child


func _unique(parent: Node, child: Node, owner: Node) -> Node:
	_add(parent, child, owner)
	child.unique_name_in_owner = true
	return child


# ------------------------------------------------------------------ câmara

func _camera_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(load("res://scripts/camera_rig.gd"))
	var yaw := _add(rig, Node3D.new(), rig) as Node3D
	yaw.name = "Yaw"
	var pitch := _add(yaw, Node3D.new(), rig) as Node3D
	pitch.name = "Pitch"
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 4.6
	arm.margin = 0.3
	arm.collision_mask = 1
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	_add(pitch, arm, rig)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 70.0
	cam.far = 900.0
	_add(arm, cam, rig)
	var ray := RayCast3D.new()
	ray.name = "InteractRay"
	ray.target_position = Vector3(0, 0, -30)
	ray.collide_with_areas = true
	ray.collision_mask = 1 | 8
	_add(cam, ray, rig)
	return rig


# ------------------------------------------------------------------ jogador

func _player() -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://scripts/player.gd"))
	p.collision_layer = 2
	p.collision_mask = 1 | 4
	p.floor_snap_length = 0.4
	p.floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	_add(p, cs, p)
	var visual := _add(p, Node3D.new(), p) as Node3D
	visual.name = "Visual"
	var slot := Node3D.new()
	slot.name = "AvatarSlot"
	slot.set_script(load("res://scripts/avatar_slot.gd"))
	_add(visual, slot, p)
	return p


# ------------------------------------------------------------------ veículos

func _vehicle(c: Dictionary) -> VehicleBody3D:
	var v := VehicleBody3D.new()
	v.name = c.name.replace(" ", "")
	v.set_script(load("res://scripts/vehicle.gd"))
	v.mass = c.mass
	v.collision_layer = 4
	v.collision_mask = 1 | 2 | 4
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	v.center_of_mass = Vector3(0, 0.35, 0)
	v.set("display_name", c.name)
	v.set("top_speed_kmh", c.top)
	v.set("max_engine_force", c.mass * 6.5)
	v.set("is_police", c.police)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(c.width * 0.92, c.height * 0.8, c.length * 0.95)
	cs.shape = box
	cs.position = Vector3(0, c.wheel_r + c.height * 0.4, 0)
	_add(v, cs, v)
	var body: Node3D = Kit.scene(c.body).instantiate()
	body.name = "Carrocaria"
	_add(v, body, v)
	var wheel_scene := Kit.scene("roda")
	for w in [["RodaFE", 1, 1], ["RodaFD", -1, 1], ["RodaTE", 1, -1], ["RodaTD", -1, -1]]:
		var wh := VehicleWheel3D.new()
		wh.name = w[0]
		wh.position = Vector3(w[1] * c.track / 2.0, c.wheel_r + 0.25, w[2] * c.wheelbase / 2.0)
		wh.wheel_radius = c.wheel_r
		wh.wheel_rest_length = 0.25
		wh.suspension_travel = 0.25
		wh.suspension_stiffness = 45.0
		wh.suspension_max_force = c.mass * 40.0
		wh.damping_compression = 0.88
		wh.damping_relaxation = 0.98
		wh.wheel_roll_influence = 0.12
		wh.use_as_steering = w[2] > 0
		wh.use_as_traction = w[2] < 0
		_add(v, wh, v)
		var rim: Node3D = wheel_scene.instantiate()
		rim.name = "Malha"
		rim.scale = Vector3.ONE * c.wheel_r
		_add(wh, rim, v)
	for m in [["Seat", c.seat], ["ExitPoint", Vector3(c.width / 2.0 + 1.1, 0.2, c.seat.z)], ["CameraTarget", Vector3(0, 1.0, 0)]]:
		var mk := Marker3D.new()
		mk.name = m[0]
		mk.position = m[1]
		_add(v, mk, v)
	if c.police:
		var siren := Node3D.new()
		siren.name = "Sirene"
		siren.position = Vector3(0, 2.05, -0.25)
		_add(v, siren, v)
		for l in [["Vermelha", Color("#ff3355"), 0.36], ["Azul", Color("#3d7bff"), -0.36]]:
			var light := OmniLight3D.new()
			light.name = l[0]
			light.light_color = l[1]
			light.omni_range = 9.0
			light.light_energy = 3.0
			light.position = Vector3(l[2], 0.1, 0)
			_add(siren, light, v)
			var bulb := MeshInstance3D.new()
			bulb.name = "Lampada"
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.2
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = l[1] * 2.5
			sm.material = mat
			bulb.mesh = sm
			_add(light, bulb, v)
	return v


# ------------------------------------------------------------------ HUD

func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#fff8ec", 0.92)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(12)
	panel.shadow_color = Color("#3b3355", 0.25)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Color("#3b3355"))
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#ffd166")
	btn.set_corner_radius_all(14)
	btn.set_content_margin_all(10)
	var hover := btn.duplicate()
	hover.bg_color = Color("#ffe39a")
	var off := btn.duplicate()
	off.bg_color = Color("#e7defa")
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("disabled", "Button", off)
	t.set_color("font_color", "Button", Color("#3b3355"))
	t.set_color("font_disabled_color", "Button", Color("#9a90b0"))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#e7defa")
	bar_bg.set_corner_radius_all(8)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("#5fcf7a")
	bar_fill.set_corner_radius_all(8)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


func _label(text: String, size: int, color := Color("#3b3355"), outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color("#3b3355"))
		l.add_theme_constant_override("outline_size", outline)
	return l


func _hud(theme: Theme) -> CanvasLayer:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	hud.set_script(load("res://scripts/hud.gd"))
	var root := Control.new()
	root.name = "Root"
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(hud, root, hud)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# --- canto superior esquerdo: império, dia, aprovação
	var tl := PanelContainer.new()
	tl.name = "TopLeft"
	_add(root, tl, hud)
	tl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(16, 16)
	var tlv := _add(tl, VBoxContainer.new(), hud)
	var emp := _unique(tlv, _label("Império", 20, Color("#ff6f6f")), hud)
	emp.name = "Empire"
	var day := _unique(tlv, _label("Dia 1", 16), hud)
	day.name = "Day"
	var ah := _add(tlv, HBoxContainer.new(), hud)
	_add(ah, _label("Aprovação", 14), hud)
	var bar := ProgressBar.new()
	bar.name = "Approval"
	bar.custom_minimum_size = Vector2(140, 14)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_unique(ah, bar, hud)
	var eh := _add(tlv, HBoxContainer.new(), hud)
	_add(eh, _label("Energia   ", 14), hud)
	var ebar := ProgressBar.new()
	ebar.name = "Energy"
	ebar.custom_minimum_size = Vector2(140, 14)
	ebar.show_percentage = false
	ebar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var efill := StyleBoxFlat.new()
	efill.bg_color = Color("#ff9f43")
	efill.set_corner_radius_all(8)
	ebar.add_theme_stylebox_override("fill", efill)
	_unique(eh, ebar, hud)
	var loc := _unique(tlv, _label("", 16, Color("#2fbfb0")), hud) as Label
	loc.name = "Location"

	# --- canto superior direito: tesouro e estrelas
	var tr := VBoxContainer.new()
	tr.name = "TopRight"
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	_add(root, tr, hud)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -330
	tr.offset_top = 16
	tr.offset_right = -16
	var money := _unique(tr, _label("Kz 3.000", 38, Color.WHITE, 10), hud) as Label
	money.name = "Treasury"
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var stars := Control.new()
	stars.name = "Stars"
	stars.set_script(load("res://scripts/wanted_stars.gd"))
	stars.custom_minimum_size = Vector2(160, 30)
	_unique(tr, stars, hud)
	var wi := _unique(tr, _label("", 16, Color("#ffd0da"), 6), hud) as Label
	wi.name = "WantedInfo"
	wi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var onl := _unique(tr, _label("Online", 16, Color("#c9ffe0"), 6), hud) as Label
	onl.name = "Online"
	onl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vs := _unique(tr, _label("", 15, Color("#fff3c4"), 6), hud) as Label
	vs.name = "VoiceStatus"
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# --- minimapa ao vivo (canto inferior esquerdo)
	var mm := PanelContainer.new()
	mm.name = "MinimapFrame"
	_add(root, mm, hud)
	mm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	mm.offset_left = 16
	mm.offset_top = -256
	mm.offset_right = 256
	mm.offset_bottom = -16
	var stack := _add(mm, Control.new(), hud) as Control
	stack.name = "Stack"
	stack.custom_minimum_size = Vector2(216, 216)
	stack.clip_contents = true
	var svc := SubViewportContainer.new()
	svc.name = "MinimapContainer"
	svc.stretch = true
	_add(stack, svc, hud)
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sv := SubViewport.new()
	sv.name = "MinimapViewport"
	sv.size = Vector2i(216, 216)
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.positional_shadow_atlas_size = 0
	_unique(svc, sv, hud)
	var mcam := Camera3D.new()
	mcam.name = "MinimapCam"
	mcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	mcam.size = 320.0
	mcam.far = 600.0
	mcam.rotation = Vector3(-PI / 2.0, 0, 0)
	mcam.position = Vector3(0, 220, 0)
	_unique(sv, mcam, hud)
	var overlay := Control.new()
	overlay.name = "MinimapOverlay"
	overlay.set_script(load("res://scripts/minimap_overlay.gd"))
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unique(stack, overlay, hud)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var north := _label("N", 14, Color.WHITE, 5)
	_add(stack, north, hud)
	north.position = Vector2(100, 2)

	# --- velocímetro (canto inferior direito)
	var sp := PanelContainer.new()
	sp.name = "Speedo"
	_unique(root, sp, hud)
	sp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	sp.offset_left = -236
	sp.offset_top = -116
	sp.offset_right = -16
	sp.offset_bottom = -16
	var spv := _add(sp, VBoxContainer.new(), hud)
	var sval := _unique(spv, _label("0", 46, Color("#3b3355")), hud) as Label
	sval.name = "SpeedValue"
	sval.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vname := _unique(spv, _label("km/h", 15), hud) as Label
	vname.name = "VehicleName"
	vname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# --- prompt de interação, avisos e faixa central
	var prompt := _unique(root, _label("", 20, Color.WHITE, 8), hud) as Label
	prompt.name = "Prompt"
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -420
	prompt.offset_right = 420
	prompt.offset_top = -150
	prompt.offset_bottom = -70
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var toasts := VBoxContainer.new()
	toasts.name = "Toasts"
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unique(root, toasts, hud)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_left = -360
	toasts.offset_right = 360
	toasts.offset_top = 18
	toasts.offset_bottom = 200
	var banner := _unique(root, _label("DETIDO", 84, Color("#ff5a79"), 18), hud) as Label
	banner.name = "Banner"
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -500
	banner.offset_right = 500
	banner.offset_top = -120
	banner.offset_bottom = 120
	banner.pivot_offset = Vector2(500, 120)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# --- loja / balcão de serviço
	var shop := PanelContainer.new()
	shop.name = "Shop"
	_unique(root, shop, hud)
	shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	shop.offset_left = -320
	shop.offset_right = 320
	shop.offset_top = -230
	shop.offset_bottom = 230
	var sv2 := _add(shop, VBoxContainer.new(), hud) as VBoxContainer
	sv2.add_theme_constant_override("separation", 10)
	var st_title := _unique(sv2, _label("Restaurante", 26, Color("#e2725b")), hud) as Label
	st_title.name = "ShopTitle"
	_add(sv2, _label("O que vai ser hoje? (pago do tesouro do império)", 15), hud)
	var items := VBoxContainer.new()
	items.name = "ShopItems"
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unique(sv2, items, hud)
	var foot := _unique(sv2, _label("", 14), hud) as Label
	foot.name = "ShopFooter"
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := Button.new()
	close.name = "ShopClose"
	close.text = "Fechar (E)"
	_unique(sv2, close, hud)

	# --- chat (T): histórico e caixa de texto (lado esquerdo)
	var cb := VBoxContainer.new()
	cb.name = "ChatBox"
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(root, cb, hud)
	cb.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)   # entre o painel do império e o minimapa
	cb.offset_left = 16
	cb.offset_right = 420
	cb.offset_top = 160
	cb.offset_bottom = -268
	cb.clip_contents = true
	cb.alignment = BoxContainer.ALIGNMENT_END
	var log := VBoxContainer.new()
	log.name = "ChatLog"
	log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log.alignment = BoxContainer.ALIGNMENT_END
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unique(cb, log, hud)
	var ci := LineEdit.new()
	ci.name = "ChatInput"
	ci.placeholder_text = "Escreva e Enter para enviar · Esc cancela"
	ci.max_length = 160
	_unique(cb, ci, hud)

	# --- modo Decoração (M): mira + catálogo
	var cross := _unique(root, _label("+", 44, Color.WHITE, 8), hud) as Label
	cross.name = "Crosshair"
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -20
	cross.offset_right = 20
	cross.offset_top = -30
	cross.offset_bottom = 30
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var deco := PanelContainer.new()
	deco.name = "Decor"
	_unique(root, deco, hud)
	deco.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	deco.offset_left = -330
	deco.offset_right = -16
	deco.offset_top = -230
	deco.offset_bottom = 230
	var dv := _add(deco, VBoxContainer.new(), hud)
	_add(dv, _label("Modo Decoração", 22, Color("#2fbfb0")), hud)
	var dl := _unique(dv, _label("", 15), hud) as Label
	dl.name = "DecorList"
	var dh := _unique(dv, _label("", 14, Color("#e2725b")), hud) as Label
	dh.name = "DecorHelp"
	dh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# --- ecrã inicial: jogar sozinho ou online
	var nm := PanelContainer.new()
	nm.name = "NetMenu"
	_unique(root, nm, hud)
	nm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nm.offset_left = -260
	nm.offset_right = 260
	nm.offset_top = -285
	nm.offset_bottom = 285
	var nv := _add(nm, VBoxContainer.new(), hud) as VBoxContainer
	nv.add_theme_constant_override("separation", 8)
	_add(nv, _label("Bandula", 40, Color("#ff6f6f")), hud)
	_add(nv, _label("Luanda espera por si. Jogue sozinho ou encontre outros jogadores online e converse com eles.", 15), hud).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(nv, _label("Nome", 15), hud)
	var nn := LineEdit.new()
	nn.name = "NetName"
	nn.max_length = 20
	_unique(nv, nn, hud)
	_add(nv, _label("Aparência", 15), hud)
	var nlook := OptionButton.new()
	nlook.name = "NetLook"
	_unique(nv, nlook, hud)
	_add(nv, _label("Microfone", 15), hud)
	var nvoice := OptionButton.new()
	nvoice.name = "NetVoice"
	_unique(nv, nvoice, hud)
	_add(nv, _label("Servidor", 15), hud)
	var nu := LineEdit.new()
	nu.name = "NetUrl"
	_unique(nv, nu, hud)
	var nb := _add(nv, HBoxContainer.new(), hud)
	for b in [["NetSolo", "Jogar sozinho"], ["NetJoin", "Jogar online"]]:
		var btn := Button.new()
		btn.name = b[0]
		btn.text = b[1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_unique(nb, btn, hud)
	var ns := _unique(nv, _label("", 14, Color("#2fbfb0")), hud) as Label
	ns.name = "NetStatus"
	ns.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# --- Menu do Império (B)
	var menu := PanelContainer.new()
	menu.name = "Menu"
	_unique(root, menu, hud)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -330
	menu.offset_right = 330
	menu.offset_top = -230
	menu.offset_bottom = 230
	var mv := _add(menu, VBoxContainer.new(), hud)
	_add(mv, _label("Menu do Império · Bandula (B fecha)", 22, Color("#ff6f6f")), hud)
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unique(mv, tabs, hud)
	var props := VBoxContainer.new()
	props.name = "Propriedades"
	_add(tabs, props, hud)
	var list := ItemList.new()
	list.name = "PlotList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 160)
	_unique(props, list, hud)
	var pinfo := _unique(props, _label("", 16), hud) as Label
	pinfo.name = "PlotInfo"
	pinfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var opts := _add(props, HBoxContainer.new(), hud)
	_add(opts, _label("Tamanho", 15), hud)
	var osz := OptionButton.new()
	osz.name = "BuildSize"
	_unique(opts, osz, hud)
	_add(opts, _label("  Negócio", 15), hud)
	var obz := OptionButton.new()
	obz.name = "BuildBusiness"
	_unique(opts, obz, hud)
	var bh := _add(props, HBoxContainer.new(), hud)
	for b in [["BuildCasa", "Construir Residência"], ["BuildComercio", "Construir Comércio"]]:
		var btn := Button.new()
		btn.name = b[0]
		btn.text = b[1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_unique(bh, btn, hud)
	var laws := VBoxContainer.new()
	laws.name = "Leis"
	_add(tabs, laws, hud)
	var tl2 := _unique(laws, _label("Imposto: 15%", 20), hud) as Label
	tl2.name = "TaxLabel"
	var slider := HSlider.new()
	slider.name = "TaxSlider"
	slider.min_value = 0
	slider.max_value = 40
	slider.step = 1
	slider.value = 15
	_unique(laws, slider, hud)
	var law_info := _label("Impostos altos enchem o tesouro mas baixam a aprovação. Abaixo de 25% de aprovação começa uma greve geral.", 15)
	law_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(laws, law_info, hud)
	var rep := VBoxContainer.new()
	rep.name = "Relatório"
	_add(tabs, rep, hud)
	var rl := _unique(rep, _label("", 17), hud) as Label
	rl.name = "Report"
	return hud


# ------------------------------------------------------------------ cena principal

func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#1f9cff")
	sky_mat.sky_horizon_color = Color("#ffe6cc")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color("#c9ab84")
	sky_mat.ground_horizon_color = Color("#ffe6cc")
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	# luz ambiente: céu + lilás (sombras nunca pretas)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("#b3a6ff")
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.75
	# tonemapping cinematográfico
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# bloom subtil (só o que brilha de verdade: sirenes, sol, brilhos)
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# névoa morna de distância
	env.fog_enabled = true
	env.set("fog_mode", 1)                       # FOG_MODE_DEPTH (Godot 4.3+)
	env.set("fog_depth_begin", 160.0)
	env.set("fog_depth_end", 560.0)
	env.fog_light_color = Color("#ffe7d4")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.25
	# saturação/contraste pastel
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	return env


func _main() -> Node3D:
	var main := Node3D.new()
	main.name = "Main"
	main.set_script(load("res://scripts/main.gd"))
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _environment()
	_add(main, we, main)
	var sun := DirectionalLight3D.new()
	sun.name = "SolEquatorial"
	sun.light_color = Color("#ffd9a3")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.transform = Transform3D(Basis.looking_at(-SUN_DIR.normalized(), Vector3.UP), Vector3.ZERO)
	_add(main, sun, main)
	_add(main, load("res://scenes/world/luanda.tscn").instantiate(), main)
	_add(main, load("res://scenes/player.tscn").instantiate(), main)
	_add(main, load("res://scenes/camera_rig.tscn").instantiate(), main)
	var traffic := Node3D.new()
	traffic.name = "Traffic"
	traffic.set_script(load("res://scripts/traffic_manager.gd"))
	var civ: Array[PackedScene] = [load("res://scenes/vehicles/buggy.tscn"), load("res://scenes/vehicles/candongueiro.tscn")]
	traffic.set("civilian_scenes", civ)
	traffic.set("police_scene", load("res://scenes/vehicles/guarda.tscn"))
	_add(main, traffic, main)
	_add(main, load("res://scenes/hud.tscn").instantiate(), main)
	var remote := Node3D.new()
	remote.name = "RemotePlayers"
	remote.set_script(load("res://scripts/net/remote_players.gd"))
	_add(main, remote, main)
	var deco := Node3D.new()
	deco.name = "Decorator"
	deco.set_script(load("res://scripts/interiors/decorator.gd"))
	_add(main, deco, main)
	return main
