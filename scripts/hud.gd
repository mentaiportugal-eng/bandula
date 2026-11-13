extends CanvasLayer
## HUD estilo GTA do Bandula: tesouro, dia e aprovação, estrelas de procurado com
## contagem «ESCAPANDO», minimapa ao vivo (SubViewport com câmara ortográfica),
## velocímetro, prompts de interação, avisos, faixa «DETIDO/ESCAPOU» e o
## Menu do Império (B): propriedades, leis (imposto) e relatório. Dentro dos
## estabelecimentos: nome do local, energia e o painel da loja (balcão).

@onready var treasury_label: Label = %Treasury
@onready var day_label: Label = %Day
@onready var empire_label: Label = %Empire
@onready var approval_bar: ProgressBar = %Approval
@onready var stars: Control = %Stars
@onready var wanted_info: Label = %WantedInfo
@onready var speedo: Control = %Speedo
@onready var speed_value: Label = %SpeedValue
@onready var vehicle_name: Label = %VehicleName
@onready var prompt: Label = %Prompt
@onready var toasts: VBoxContainer = %Toasts
@onready var banner: Label = %Banner
@onready var minimap_viewport: SubViewport = %MinimapViewport
@onready var minimap_cam: Camera3D = %MinimapCam
@onready var minimap_overlay: Control = %MinimapOverlay
@onready var menu: Control = %Menu
@onready var tabs: TabContainer = %Tabs
@onready var plot_list: ItemList = %PlotList
@onready var plot_info: Label = %PlotInfo
@onready var build_casa: Button = %BuildCasa
@onready var build_comercio: Button = %BuildComercio
@onready var tax_slider: HSlider = %TaxSlider
@onready var tax_label: Label = %TaxLabel
@onready var report_label: Label = %Report
@onready var energy_bar: ProgressBar = %Energy
@onready var location_label: Label = %Location
@onready var shop: Control = %Shop
@onready var shop_title: Label = %ShopTitle
@onready var shop_items: VBoxContainer = %ShopItems
@onready var shop_footer: Label = %ShopFooter
@onready var shop_close: Button = %ShopClose
@onready var minimap_frame: Control = $Root/MinimapFrame
@onready var build_size: OptionButton = %BuildSize
@onready var build_business: OptionButton = %BuildBusiness
@onready var decor_panel: Control = %Decor
@onready var decor_list: Label = %DecorList
@onready var decor_help: Label = %DecorHelp
@onready var crosshair: Label = %Crosshair
@onready var chat_log: VBoxContainer = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var online_label: Label = %Online
@onready var net_menu: Control = %NetMenu
@onready var net_name: LineEdit = %NetName
@onready var net_look: OptionButton = %NetLook
@onready var net_url: LineEdit = %NetUrl
@onready var net_solo: Button = %NetSolo
@onready var net_join: Button = %NetJoin
@onready var net_status: Label = %NetStatus
@onready var net_voice: OptionButton = %NetVoice
@onready var voice_label: Label = %VoiceStatus

var _shop := {"type": "", "place": "", "name": ""}

var player: Node3D
var _plot_ids: Array = []
var _mm_t := 0.0


func _ready() -> void:
	add_to_group("hud")
	GameManager.treasury_changed.connect(func(_v): _refresh_stats())
	GameManager.stats_changed.connect(_refresh_stats)
	GameManager.day_passed.connect(func(_d, _r): _refresh_stats(); _refresh_menu())
	GameManager.plot_changed.connect(func(_id): _refresh_menu())
	GameManager.wanted_changed.connect(_on_wanted)
	GameManager.escape_progress.connect(func(left, _total): wanted_info.text = "ESCAPANDO… %ds" % ceili(left))
	GameManager.escaped.connect(func(): show_banner("ESCAPOU", Color("#5dff9e")))
	GameManager.busted.connect(func(fine): show_banner("DETIDO", Color("#ff5a79"), "Multa: Kz %s" % GameManager.fmt(fine)))
	GameManager.toast.connect(show_toast)
	for sz in GameManager.SIZES:
		build_size.add_item(GameManager.BUILD.casa.sizes[sz].label.capitalize())
	build_size.select(1)
	for b in GameManager.BUSINESS_TYPES:
		build_business.add_item(GameManager.BUSINESS_TYPES[b])
	build_size.item_selected.connect(func(_i): _refresh_plot_info())
	build_business.item_selected.connect(func(_i): _refresh_plot_info())
	var deco = get_tree().current_scene.get_node_or_null("Decorator") if get_tree().current_scene else null
	if deco == null:
		deco = get_parent().get_node_or_null("Decorator")
	if deco:
		deco.decor_changed.connect(update_decor)
	decor_panel.visible = false
	crosshair.visible = false
	_setup_net()
	build_casa.pressed.connect(func(): _build("casa"))
	build_comercio.pressed.connect(func(): _build("comercio"))
	plot_list.item_selected.connect(func(_i): _refresh_plot_info())
	tax_slider.value_changed.connect(func(v): GameManager.set_tax(v / 100.0))
	tax_slider.value = GameManager.tax_rate * 100.0
	GameManager.energy_changed.connect(func(v): energy_bar.value = v)
	GameManager.purchase_made.connect(func(_t, _i): _refresh_shop())
	Interiors.entered.connect(func(interior, _p):
		location_label.text = interior.display_name
		location_label.visible = true
		minimap_frame.visible = false)
	Interiors.exited.connect(func():
		location_label.visible = false
		minimap_frame.visible = true
		close_shop())
	shop_close.pressed.connect(close_shop)
	energy_bar.value = GameManager.energy
	location_label.visible = false
	shop.visible = false
	menu.visible = false
	banner.visible = false
	speedo.visible = false
	minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_refresh_stats()
	_on_wanted(0)


func bind(p: Node3D) -> void:
	player = p
	player.interaction_changed.connect(func(text): prompt.text = text; prompt.visible = text != "")
	minimap_overlay.player = p


func _unhandled_input(event: InputEvent) -> void:
	if shop.visible and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		close_shop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not net_menu.visible and not chat_input.visible:
		open_chat()
		get_viewport().set_input_as_handled()
		return
	if net_menu.visible:
		return
	if event.is_action_pressed("menu"):
		if menu.visible:
			close_menu()
		else:
			open_menu("properties")


func _process(delta: float) -> void:
	if player == null:
		return
	# minimapa: câmara ortográfica sobre o jogador (redesenha 10×/s para poupar a GPU na web)
	minimap_cam.global_position = player.global_position + Vector3(0, 220, 0)
	_mm_t += delta
	if _mm_t > 0.1:
		_mm_t = 0.0
		minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	minimap_overlay.queue_redraw()
	# velocímetro
	var v = player.vehicle
	speedo.visible = v != null
	if v != null:
		speed_value.text = "%d" % roundi(v.speed_kmh())
		vehicle_name.text = "km/h · " + v.display_name
	if decor_panel.visible:
		decor_help.text = decor_help.text.split("\n")[0] + "\nTab/1–9 escolher · R rodar · X retirar · M sair · Kz %s" % GameManager.fmt(GameManager.treasury)
	if GameManager.wanted_level > 0 and GameManager.police_sees_player:
		var bp := GameManager.bust_progress()
		wanted_info.text = "A GUARDA ESTÁ A VER-TE" + (" · RENDE-TE %d%%" % roundi(bp * 100.0) if bp > 0.0 else "")


# ------------------------------------------------------------------ estado

func _refresh_stats() -> void:
	treasury_label.text = "Kz %s" % GameManager.fmt(GameManager.treasury)
	treasury_label.modulate = Color("#ff5a79") if GameManager.treasury < 0 else Color.WHITE
	empire_label.text = GameManager.empire_name
	day_label.text = "Dia %d · Pop. %d%s" % [GameManager.day, GameManager.population, " · GREVE" if GameManager.strike else ""]
	approval_bar.value = GameManager.approval
	tax_label.text = "Imposto: %d%%" % roundi(GameManager.tax_rate * 100.0)


func _on_wanted(level: int) -> void:
	stars.set("level", level)
	stars.queue_redraw()
	wanted_info.text = "" if level == 0 else "PROCURADO"


func show_toast(text: String, kind: String = "info") -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", {"error": Color("#ffd0da"), "success": Color("#c9ffe0"), "warn": Color("#fff1b8")}.get(kind, Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color("#3b3355"))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toasts.add_child(l)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func show_banner(title: String, color: Color, sub := "") -> void:
	banner.text = title + ("\n" + sub if sub != "" else "")
	banner.add_theme_color_override("font_color", color)
	banner.visible = true
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.3, 1.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_interval(2.2)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(func(): banner.visible = false)


# ------------------------------------------------------------------ loja / balcão de serviço

func open_shop(shop_type: String, place_id: String, place_name: String) -> void:
	_shop = {"type": shop_type, "place": place_id, "name": place_name}
	shop.visible = true
	menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_shop()


func close_shop() -> void:
	if not shop.visible:
		return
	shop.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_shop() -> void:
	if not shop.visible:
		return
	shop_title.text = _shop.name
	for c in shop_items.get_children():
		c.queue_free()
	for item in GameManager.SHOP_ITEMS.get(_shop.type, []):
		var b := Button.new()
		var effect := ""
		if item.has("energy"):
			effect = "+%d energia" % int(item.energy)
		elif item.has("approval"):
			effect = "+%d aprovação" % int(item.approval)
		elif item.has("income"):
			effect = "+Kz %s / dia" % GameManager.fmt(item.income)
		b.text = "%s — Kz %s   (%s)" % [item.name, GameManager.fmt(item.price), effect]
		b.tooltip_text = item.desc
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var owned: bool = item.get("once", false) and GameManager.is_bought(_shop.place, item.id)
		b.disabled = owned or GameManager.treasury < item.price
		if owned:
			b.text = "%s — já é sócio" % item.name
		var id: String = item.id
		b.pressed.connect(func():
			var r := GameManager.purchase(_shop.type, _shop.place, id)
			if not r.ok:
				show_toast(r.reason, "warn"))
		shop_items.add_child(b)
	shop_footer.text = "Tesouro: Kz %s · Energia: %d%% · Lucro dos investimentos: Kz %s/dia" % [
		GameManager.fmt(GameManager.treasury), roundi(GameManager.energy), GameManager.fmt(GameManager.investments)]


## Contas de um negócio do jogador (balcão do próprio comércio).
func open_business(plot_id: String) -> void:
	var p: Dictionary = GameManager.plots.get(plot_id, {})
	if p.is_empty():
		return
	_shop = {"type": "", "place": plot_id, "name": GameManager.building_name(p).capitalize()}
	shop.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shop_title.text = "O seu negócio: " + _shop.name
	for c in shop_items.get_children():
		c.queue_free()
	var inc: Dictionary = GameManager.plot_income(p)
	var counts := {}
	for e in p.furniture:
		counts[e.id] = counts.get(e.id, 0) + 1
	var lines := PackedStringArray()
	for id in counts:
		lines.append("%d × %s" % [counts[id], GameManager.furniture_def(id).name])
	var l := Label.new()
	l.text = "Rende Kz %s por dia (%s).\nMobília: %s\n\nMais cadeiras, mesas, prateleiras e decoração trazem mais clientes. Use M para mobilar." % [
		GameManager.fmt(inc.income), inc.note, ", ".join(lines) if lines.size() > 0 else "nenhuma"]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_items.add_child(l)
	shop_footer.text = "Tesouro: Kz %s" % GameManager.fmt(GameManager.treasury)


## Barra do modo Decoração (catálogo, peça escolhida, se cabe ou não).
func update_decor(active: bool, index: int, valid: bool) -> void:
	decor_panel.visible = active
	crosshair.visible = active
	if not active:
		return
	var rows := PackedStringArray()
	for i in GameManager.FURNITURE.size():
		var f: Dictionary = GameManager.FURNITURE[i]
		rows.append("%s %d. %s · Kz %s" % [">" if i == index else "  ", i + 1, f.name, GameManager.fmt(f.price)])
	decor_list.text = "\n".join(rows)
	decor_help.text = ("Cabe aqui — E ou clique para colocar" if valid else "Não cabe aqui") + "\nTab/1–9 escolher · R rodar · X retirar · M sair"
	crosshair.modulate = Color("#5dff9e") if valid else Color("#ff5a79")


# ------------------------------------------------------------------ Menu do Império (B)

func open_menu(tab: String = "properties", plot_id: String = "") -> void:
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tabs.current_tab = {"properties": 0, "laws": 1, "report": 2}.get(tab, 0)
	_refresh_menu()
	if plot_id != "":
		var i := _plot_ids.find(plot_id)
		if i >= 0:
			plot_list.select(i)
			_refresh_plot_info()


func close_menu() -> void:
	menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_menu() -> void:
	plot_list.clear()
	_plot_ids.clear()
	for p in GameManager.player_plots():
		var b: String = p.building
		plot_list.add_item("%s · %s" % [p.area, GameManager.building_name(p)])
		_plot_ids.append(p.id)
	_refresh_plot_info()
	var r: Dictionary = GameManager.last_report
	report_label.text = "Ainda sem relatório — espere o fim do dia." if r.is_empty() else \
		"Dia %d\nPrédios: Kz %s\nImpostos: Kz %s\nGuarda: −Kz %s\nSaldo: Kz %s\n\nAprovação: %d%%%s" % [
			r.day, GameManager.fmt(r.buildings), GameManager.fmt(r.taxes), GameManager.fmt(r.upkeep), GameManager.fmt(r.net),
			roundi(GameManager.approval), "\nGREVE GERAL em curso!" if GameManager.strike else ""]


func _selected_plot() -> String:
	var sel := plot_list.get_selected_items()
	return _plot_ids[sel[0]] if sel.size() > 0 and sel[0] < _plot_ids.size() else ""


func _refresh_plot_info() -> void:
	var id := _selected_plot()
	var p: Dictionary = GameManager.plots.get(id, {})
	var empty: bool = not p.is_empty() and p.building == ""
	build_casa.disabled = not empty
	build_comercio.disabled = not empty
	var sz: String = GameManager.SIZES[maxi(build_size.selected, 0)]
	build_casa.text = "Residência (Kz %s)" % GameManager.fmt(GameManager.BUILD.casa.sizes[sz].cost)
	build_comercio.text = "%s (Kz %s)" % [build_business.get_item_text(maxi(build_business.selected, 0)), GameManager.fmt(GameManager.BUILD.comercio.sizes[sz].cost)]
	if p.is_empty():
		plot_info.text = "Compre lotes na Baixa, nos bairros ou na Ilha de Luanda (E sobre um lote à venda)." if _plot_ids.is_empty() else "Escolha uma propriedade."
	else:
		var inc: Dictionary = GameManager.plot_income(p)
		plot_info.text = "%s — %s%s" % [p.area, GameManager.building_name(p) if p.building != "" else "terreno pronto para construir (escolha o tamanho)",
			"\nRende Kz %s/dia · %s · entre e mobile com M" % [GameManager.fmt(inc.income), inc.note] if p.building != "" else ""]


func _build(kind: String) -> void:
	var sz: String = GameManager.SIZES[maxi(build_size.selected, 0)]
	var business: String = GameManager.BUSINESS_TYPES.keys()[maxi(build_business.selected, 0)]
	var r := GameManager.build_on_plot(_selected_plot(), kind, sz, business)
	if not r.ok:
		show_toast(r.reason, "warn")
	_refresh_menu()


# ------------------------------------------------------------------ multijogador: ecrã inicial e chat

var _auto_join_left := 0


func _setup_net() -> void:
	for n in Network.LOOK_NAMES:
		net_look.add_item(n)
	net_url.text = Network.default_url()
	net_name.text = "Governante %d" % randi_range(10, 99)
	net_solo.pressed.connect(func():
		_apply_look()
		_hide_net_menu())
	for n in Voice.MODE_NAMES:
		net_voice.add_item(n)
	net_join.pressed.connect(func():
		Voice.set_mode(Voice.MODES[net_voice.selected])
		Network.join(net_url.text.strip_edges(), net_name.text, net_look.selected))
	Voice.transmitting_changed.connect(func(_on): _refresh_voice())
	Voice.mic_status.connect(func(t: String):
		if t != "ready":
			show_toast(t, "error")
		_refresh_voice())
	Network.connection_changed.connect(_on_connection)
	Network.chat_received.connect(_add_chat)
	Network.peer_joined.connect(func(_i, _n, _l): _refresh_online())
	Network.peer_left.connect(func(_i, _n): _refresh_online())
	chat_input.visible = false
	chat_input.text_submitted.connect(_send_chat)
	chat_input.gui_input.connect(func(e): if e.is_action_pressed("ui_cancel"): _close_chat())
	_refresh_online()
	# ecrã inicial: não aparece em testes (headless) nem com parâmetros de demonstração na web
	var q := ""
	if OS.has_feature("web"):
		q = str(JavaScriptBridge.eval("location.search", true))
	if DisplayServer.get_name() == "headless" or "interior=" in q or "solo" in q:
		net_menu.visible = false
	else:
		net_menu.visible = true
		GameManager.input_locked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "online=1" in q:                                 # ...index.html?online=1&nome=Ana&aparencia=2
		var nm := RegEx.create_from_string("nome=([^&]+)").search(q)
		var lk := RegEx.create_from_string("aparencia=(\\d)").search(q)
		if nm:
			net_name.text = nm.get_string(1).uri_decode()
		if lk:
			net_look.select(int(lk.get_string(1)))
		var vz := RegEx.create_from_string("voz=(\\w+)").search(q)        # voz=aberto | ptt | off
		if vz:
			net_voice.select({"aberto": 1, "open": 1, "off": 2, "desligada": 2}.get(vz.get_string(1), 0))
		Voice.set_mode(Voice.MODES[net_voice.selected])
		_auto_join_left = 3
		_auto_join.call_deferred()


## Ligação automática (?online=1): espera que os primeiros fotogramas (os mais pesados —
## compilação de shaders) passem, senão o aperto de mão WebSocket expira em máquinas lentas.
func _auto_join() -> void:
	for i in 5:
		await get_tree().process_frame
	_auto_join_left -= 1
	Network.join(net_url.text, net_name.text, net_look.selected)


func _apply_look() -> void:
	Network.look = net_look.selected
	var p = GameManager.player
	if p and net_look.selected != 0:
		p.avatar.set_avatar(load(Network.LOOKS[net_look.selected]))


func _hide_net_menu() -> void:
	net_menu.visible = false
	GameManager.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_connection(online: bool, status: String) -> void:
	net_status.text = status
	if online:
		_auto_join_left = 0
	elif _auto_join_left > 0 and net_menu.visible and status == "Não foi possível ligar ao servidor.":
		net_status.text = status + " A tentar de novo…"
		_auto_join()
		return
	if online:
		_apply_look()
		_hide_net_menu()
		show_toast("Ligado! T escreve no chat · V fala ao microfone (quem está perto ouve).", "success")
	elif not net_menu.visible and status != "Offline":
		show_toast(status, "error")
	_refresh_online()


func _refresh_online() -> void:
	online_label.visible = Network.is_online()
	online_label.text = "Online · %d em Luanda" % (Network.peers.size() + 1)
	_refresh_voice()


func _refresh_voice() -> void:
	voice_label.visible = Network.is_online() and Voice.mode != "off"
	if Voice.transmitting:
		voice_label.text = "● A falar…"
		voice_label.modulate = Color("#ff8f8f")
	else:
		voice_label.text = "V para falar" if Voice.mode == "ptt" else "Microfone aberto"
		voice_label.modulate = Color.WHITE


func open_chat() -> void:
	chat_input.visible = true
	chat_input.grab_focus()
	GameManager.input_locked = true


func _close_chat() -> void:
	chat_input.text = ""
	chat_input.visible = false
	chat_input.release_focus()
	GameManager.input_locked = false


func _send_chat(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		if Network.is_online():
			Network.say(t)
		else:
			_add_chat(-1, "", "Está offline — escolha «Jogar online» para conversar.")
	_close_chat()


func _add_chat(id: int, who: String, text: String) -> void:
	var l := Label.new()
	l.text = text if id <= 0 else "%s: %s" % [who, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color("#c9ffe0") if id <= 0 else (Color("#ffd166") if id == multiplayer.get_unique_id() else Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color("#3b3355"))
	l.add_theme_constant_override("outline_size", 6)
	chat_log.add_child(l)
	while chat_log.get_child_count() > 8:
		var old := chat_log.get_child(0)
		chat_log.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_interval(25.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
