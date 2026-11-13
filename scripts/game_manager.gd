extends Node
## Bandula — GameManager (autoload "GameManager").
## Economia de Luanda (tesouro, imposto, aprovação, população, greves, lotes na
## Baixa / bairros / Ilha de Luanda, construções) e o sistema de procurado de
## 1–5 estrelas (perseguição da Guarda, contagem «ESCAPOU», multa «DETIDO»).

signal treasury_changed(value: float)
signal stats_changed
signal day_passed(day: int, report: Dictionary)
signal plot_changed(plot_id: String)
signal wanted_changed(level: int)
signal escape_progress(seconds_left: float, total: float)
signal escaped
signal busted(fine: int)
signal toast(text: String, kind: String)
signal energy_changed(value: float)
signal purchase_made(shop_type: String, item: Dictionary)
signal furniture_changed(plot_id: String)

# ------------------------------------------------------------------ economia
const DAY_SECONDS := 20.0
## Construções em três tamanhos (exteriores diferentes; interiores com mais divisões).
const BUILD := {
	"casa": {"name": "Residência", "approval": 0.05, "sizes": {
		"p": {"label": "pequena", "cost": 450, "income": 30, "population": 5, "scene": "casa_p"},
		"m": {"label": "média", "cost": 700, "income": 45, "population": 8, "scene": "casa_m"},
		"g": {"label": "grande", "cost": 1200, "income": 80, "population": 14, "scene": "casa_g"}}},
	"comercio": {"name": "Comércio", "approval": 0.15, "sizes": {
		"p": {"label": "pequeno", "cost": 700, "income": 70, "population": 1, "scene": "comercio_p"},
		"m": {"label": "médio", "cost": 1000, "income": 110, "population": 2, "scene": "comercio_m"},
		"g": {"label": "grande", "cost": 1800, "income": 190, "population": 3, "scene": "comercio_g"}}},
}
const SIZES := ["p", "m", "g"]
const BUSINESS_TYPES := {"restaurante": "Restaurante", "cantina": "Cantina", "loja": "Mini-mercado", "boutique": "Boutique", "cafe": "Café"}

## Catálogo de mobília (modo Decoração, tecla M). `kind` define o que a peça faz:
## seat (sentar), counter (balcão de atendimento), table/shelf/bed/decor (conforto e negócio).
const FURNITURE := [
	{"id": "cadeira", "name": "Cadeira", "price": 40, "kind": "seat"},
	{"id": "banco", "name": "Banco alto", "price": 35, "kind": "seat"},
	{"id": "sofa", "name": "Sofá", "price": 220, "kind": "seat"},
	{"id": "mesa_redonda", "name": "Mesa redonda", "price": 90, "kind": "table"},
	{"id": "mesa", "name": "Mesa de jantar", "price": 120, "kind": "table"},
	{"id": "balcao", "name": "Balcão de atendimento", "price": 350, "kind": "counter"},
	{"id": "estante", "name": "Estante com produtos", "price": 180, "kind": "shelf"},
	{"id": "frigorifico", "name": "Frigorífico", "price": 260, "kind": "shelf"},
	{"id": "cama", "name": "Cama", "price": 300, "kind": "bed"},
	{"id": "planta", "name": "Planta", "price": 30, "kind": "decor"},
	{"id": "tapete", "name": "Tapete de capulana", "price": 50, "kind": "decor"},
	{"id": "candeeiro", "name": "Candeeiro", "price": 60, "kind": "decor"},
]
const GUARD_UPKEEP := 40.0

var empire_name := "Império de Bandula"
var treasury := 3000.0
var tax_rate := 0.15
var approval := 62.0
var population := 150
var day := 1
var strike := false
var last_report := {}
var plots := {}          # id → { id, district, area, price, owner ("", "npc", "player"), building, node }
var _day_t := 0.0

# ------------------------------------------------------------------ energia e serviços (interiores)
## Catálogo dos estabelecimentos: energia (comida/bebida), aprovação (gestos públicos)
## ou lucro diário (sociedades/investimentos, compra única por estabelecimento).
const SHOP_ITEMS := {
	"restaurante": [
		{"id": "muamba", "name": "Muamba de galinha", "price": 120, "energy": 45.0, "desc": "O prato da casa, com funge."},
		{"id": "calulu", "name": "Calulu de peixe", "price": 150, "energy": 55.0, "desc": "Peixe seco, quiabo e óleo de palma."},
		{"id": "mufete", "name": "Mufete da Ilha", "price": 180, "energy": 60.0, "desc": "Peixe grelhado, feijão de óleo de palma e banana."},
		{"id": "rodada", "name": "Pagar uma rodada à sala", "price": 400, "approval": 4.0, "desc": "Os clientes brindam ao governante."},
		{"id": "socio", "name": "Tornar-se sócio do restaurante", "price": 2500, "income": 120.0, "once": true, "desc": "Lucro diário para o império."},
	],
	"cantina": [
		{"id": "funge", "name": "Funge com feijão", "price": 60, "energy": 30.0, "desc": "Prato do dia da cantina."},
		{"id": "feijao", "name": "Feijão de óleo de palma", "price": 70, "energy": 32.0, "desc": "Com farinha e banana-pão."},
		{"id": "mucua", "name": "Sumo de múcua", "price": 40, "energy": 15.0, "desc": "Fresco, do fruto do imbondeiro."},
		{"id": "gasosa", "name": "Gasosa gelada", "price": 25, "energy": 10.0, "desc": "Para o calor de Luanda."},
		{"id": "patrocinio", "name": "Patrocinar a cantina", "price": 900, "income": 45.0, "once": true, "desc": "Lucro diário para o império."},
	],
	"loja": [
		{"id": "agua", "name": "Água fresca", "price": 20, "energy": 8.0, "desc": "Garrafa de 1,5 L."},
		{"id": "bolinhos", "name": "Bolinhos", "price": 35, "energy": 15.0, "desc": "Docinhos da padaria."},
		{"id": "banana", "name": "Banana-pão assada", "price": 30, "energy": 14.0, "desc": "Com ginguba torrada."},
		{"id": "doacao", "name": "Doação ao bairro", "price": 300, "approval": 3.0, "desc": "Para a escola da zona."},
		{"id": "investir", "name": "Investir no mini-mercado", "price": 1500, "income": 70.0, "once": true, "desc": "Lucro diário para o império."},
	],
	"boutique": [
		{"id": "camisa", "name": "Camisa de capulana", "price": 350, "approval": 2.0, "desc": "Estilo de Luanda — o povo repara."},
		{"id": "fato", "name": "Fato para cerimónias", "price": 1200, "approval": 5.0, "desc": "Para as inaugurações do império."},
		{"id": "socio_moda", "name": "Sociedade na boutique", "price": 2200, "income": 100.0, "once": true, "desc": "Lucro diário para o império."},
	],
	"eletronica": [
		{"id": "radio", "name": "Rádio portátil", "price": 250, "approval": 1.0, "desc": "Para ouvir kizomba na rua."},
		{"id": "telemovel", "name": "Telemóvel novo", "price": 900, "approval": 3.0, "desc": "Sempre contactável pelo povo."},
		{"id": "socio_tech", "name": "Sociedade na loja de eletrónica", "price": 3000, "income": 140.0, "once": true, "desc": "Lucro diário para o império."},
	],
	"escritorio": [
		{"id": "cafe_rececao", "name": "Café da receção", "price": 25, "energy": 10.0, "desc": "Cortesia quase grátis."},
		{"id": "consultoria", "name": "Consultoria de negócios", "price": 1500, "income": 60.0, "once": true, "desc": "Os analistas da torre otimizam o império."},
		{"id": "publicidade", "name": "Publicidade na Baixa", "price": 800, "approval": 3.0, "desc": "Cartazes do governante pela cidade."},
	],
	"esquadra": [
		{"id": "entregar", "name": "Entregar-se à Guarda", "price": 0, "surrender": true, "desc": "Multa pela metade e estrelas limpas."},
		{"id": "doacao_guarda", "name": "Doação à Guarda de Bandula", "price": 500, "approval": 2.0, "desc": "Novas viaturas para o bairro."},
	],
	"cafe": [
		{"id": "cafe", "name": "Café de Angola", "price": 30, "energy": 12.0, "desc": "Café do Amboim, bem forte."},
		{"id": "pastel", "name": "Pastel de nata", "price": 40, "energy": 14.0, "desc": "Acabado de sair do forno."},
		{"id": "ginguba", "name": "Ginguba torrada", "price": 20, "energy": 8.0, "desc": "O petisco de Luanda."},
	],
}
var energy := 80.0
var investments := 0.0            # lucro diário dos estabelecimentos onde o jogador investiu
var _bought_once := {}            # "estabelecimento:item" já comprados (sociedades)

# ------------------------------------------------------------------ procurado
const HEAT_LEVELS := [15.0, 40.0, 70.0, 105.0, 145.0]
const OFFENSES := {
	"carjack": {"heat": 14.0, "label": "Roubo de veículo"},
	"police_carjack": {"heat": 32.0, "label": "Roubo de viatura da Guarda"},
	"police_crash": {"heat": 20.0, "label": "Batida numa viatura da Guarda"},
	"crash": {"heat": 6.0, "label": "Condução perigosa"},
	"property": {"heat": 10.0, "label": "Dano a propriedade"},
}
const BUST_RANGE := 7.0
const BUST_TIME := 2.2

var heat := 0.0
var wanted_level := 0
var escape_left := 0.0
var police_sees_player := false
var _bust_t := 0.0

var player: Node3D = null            # registado pelo player.gd
## true enquanto se escreve no chat ou no ecrã inicial (o avatar não se mexe).
var input_locked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_input_map()


## Teclas por defeito (só cria as que não existirem em Projeto → Mapa de entrada).
func _ensure_input_map() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "handbrake": [KEY_SPACE],
		"interact": [KEY_E], "vehicle": [KEY_F], "menu": [KEY_B], "horn": [KEY_H],
		"decorate": [KEY_M], "rotate_item": [KEY_R], "remove_item": [KEY_X], "next_item": [KEY_TAB],
		"chat": [KEY_T], "voice": [KEY_V],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _process(delta: float) -> void:
	drain_energy(delta * 0.05)                      # ~1 ponto a cada 20 s
	_day_t += delta
	if _day_t >= DAY_SECONDS:
		_day_t -= DAY_SECONDS
		_new_day()
	_update_wanted(delta)


# ------------------------------------------------------------------ lotes

func register_plot(node: Node) -> void:
	var id: String = node.plot_id
	var h := absi(hash(id))
	var size: String = "" if node.initial_building == "" else SIZES[h % 3]
	plots[id] = {"id": id, "district": node.district, "area": node.area_name, "price": node.price,
		"owner": node.initial_owner, "building": node.initial_building, "size": size,
		"business": "", "furniture": [], "node": node}


## Dados do prédio de um lote (tipo + tamanho) — {} se vazio.
func building_info(p: Dictionary) -> Dictionary:
	if p.get("building", "") == "":
		return {}
	var b: Dictionary = BUILD[p.building]
	var key: String = p.get("size", "")
	var s: Dictionary = b.sizes[key if key != "" else "m"]
	return s.merged({"name": b.name, "approval": b.approval, "kind": p.building})


func building_name(p: Dictionary) -> String:
	var i := building_info(p)
	if i.is_empty():
		return "terreno vazio"
	var n: String = BUSINESS_TYPES.get(p.get("business", ""), i.name) if p.building == "comercio" else i.name
	return "%s %s" % [n, i.label]


func plot_label(id: String) -> String:
	var p: Dictionary = plots.get(id, {})
	if p.is_empty():
		return ""
	if p.owner == "player":
		return "Gerir propriedade em %s" % p.area
	if p.owner == "npc":
		return "%s particular · %s" % [building_name(p), p.area]
	return "Comprar lote em %s (Kz %s)" % [p.area, fmt(p.price)]


func buy_plot(id: String) -> Dictionary:
	var p: Dictionary = plots.get(id, {})
	if p.is_empty():
		return {"ok": false, "reason": "Lote desconhecido."}
	if p.owner != "":
		return {"ok": false, "reason": "Este lote não está à venda."}
	if treasury < p.price:
		return {"ok": false, "reason": "Tesouro insuficiente (faltam Kz %s)." % fmt(p.price - treasury)}
	_spend(p.price)
	p.owner = "player"
	plot_changed.emit(id)
	toast.emit("Lote comprado em %s!" % p.area, "success")
	return {"ok": true}


func build_on_plot(id: String, kind: String, size := "m", business := "loja") -> Dictionary:
	var p: Dictionary = plots.get(id, {})
	if p.is_empty() or p.owner != "player":
		return {"ok": false, "reason": "Só pode construir nos seus lotes."}
	if not BUILD.has(kind) or not BUILD[kind].sizes.has(size):
		return {"ok": false, "reason": "Tipo de construção inválido."}
	if p.building != "":
		return {"ok": false, "reason": "Já existe um prédio neste lote."}
	var cost: int = BUILD[kind].sizes[size].cost
	if treasury < cost:
		return {"ok": false, "reason": "Tesouro insuficiente (Kz %s)." % fmt(cost)}
	_spend(cost)
	p.building = kind
	p.size = size
	p.business = business if kind == "comercio" else ""
	p.furniture = []
	population += BUILD[kind].sizes[size].population
	plot_changed.emit(id)
	stats_changed.emit()
	toast.emit("%s construído em %s — entre e mobile-o (M)." % [building_name(p).capitalize(), p.area], "success")
	return {"ok": true}


# ------------------------------------------------------------------ mobília (modo Decoração)

func furniture_def(fid: String) -> Dictionary:
	for f in FURNITURE:
		if f.id == fid:
			return f
	return {}


## Coloca uma peça num interior do jogador (posição local ao interior). Paga do tesouro.
func place_furniture(plot_id: String, fid: String, pos: Vector3, yaw: float) -> Dictionary:
	var p: Dictionary = plots.get(plot_id, {})
	var f := furniture_def(fid)
	if p.is_empty() or p.owner != "player" or f.is_empty():
		return {"ok": false, "reason": "Só pode mobilar os seus prédios."}
	if treasury < f.price:
		return {"ok": false, "reason": "Tesouro insuficiente (Kz %s)." % fmt(f.price)}
	_spend(f.price)
	var entry := {"id": fid, "x": snappedf(pos.x, 0.01), "z": snappedf(pos.z, 0.01), "yaw": snappedf(yaw, 0.01)}
	p.furniture.append(entry)
	furniture_changed.emit(plot_id)
	return {"ok": true, "entry": entry}


## Retira uma peça (devolve metade do preço).
func remove_furniture(plot_id: String, entry: Dictionary) -> void:
	var p: Dictionary = plots.get(plot_id, {})
	if p.is_empty():
		return
	var i: int = p.furniture.find(entry)
	if i < 0:
		return
	p.furniture.remove_at(i)
	var f := furniture_def(entry.id)
	treasury += f.get("price", 0) * 0.5
	treasury_changed.emit(treasury)
	furniture_changed.emit(plot_id)


## Rendimento diário de um prédio do jogador, conforme o tamanho e o recheio.
## Comércios: sem balcão não abrem; cadeiras, prateleiras e decoração atraem clientes.
## Casas: o conforto (cama, sofá, decoração) sobe um pouco a aprovação.
func plot_income(p: Dictionary) -> Dictionary:
	var info := building_info(p)
	if info.is_empty():
		return {"income": 0.0, "note": ""}
	var counts := {"seat": 0, "counter": 0, "shelf": 0, "table": 0, "bed": 0, "decor": 0}
	for e in p.get("furniture", []):
		var k: String = furniture_def(e.id).get("kind", "decor")
		counts[k] = counts.get(k, 0) + 1
	if p.building == "comercio":
		if counts.counter == 0:
			return {"income": 0.0, "note": "fechado: falta um balcão"}
		var bonus: float = minf(counts.seat, 12) * 6.0 + minf(counts.shelf, 6) * 10.0 + minf(counts.table, 6) * 4.0 + minf(counts.decor, 8) * 2.0
		return {"income": float(info.income) + bonus, "note": "+Kz %s pelo recheio" % fmt(bonus)}
	var comfort: float = minf(counts.bed, 3) * 1.0 + minf(counts.seat, 4) * 0.3 + minf(counts.decor, 6) * 0.2
	return {"income": float(info.income), "note": "conforto %.1f" % comfort, "comfort": comfort}



func player_plots() -> Array:
	return plots.values().filter(func(p): return p.owner == "player")


func set_tax(rate: float) -> void:
	tax_rate = clampf(rate, 0.0, 0.4)
	stats_changed.emit()


func _spend(amount: float) -> void:
	treasury -= amount
	treasury_changed.emit(treasury)


func _new_day() -> void:
	day += 1
	var buildings_income := 0.0
	for p in player_plots():
		if p.building != "":
			buildings_income += plot_income(p).income
	if strike:
		buildings_income *= 0.0
	var tax_income := population * tax_rate * 4.0
	var upkeep := GUARD_UPKEEP
	buildings_income += investments
	var net := buildings_income + tax_income - upkeep
	treasury += net
	# aprovação tende a um alvo que cai com impostos altos e sobe com prédios
	var bonus := 0.0
	for p in player_plots():
		if p.building != "":
			bonus += BUILD[p.building].approval + plot_income(p).get("comfort", 0.0) * 0.05
	var target := clampf(82.0 - tax_rate * 150.0 + bonus * 10.0 - wanted_level * 3.0, 5.0, 100.0)
	approval = lerpf(approval, target, 0.25)
	if not strike and approval < 25.0:
		strike = true
		toast.emit("Greve geral! Os comércios fecharam — baixe os impostos.", "error")
	elif strike and approval > 40.0:
		strike = false
		toast.emit("A greve acabou.", "success")
	population += int(maxf(0.0, (approval - 50.0) * 0.08))
	last_report = {"day": day, "buildings": buildings_income, "taxes": tax_income, "upkeep": upkeep, "net": net}
	treasury_changed.emit(treasury)
	stats_changed.emit()
	day_passed.emit(day, last_report)


# ------------------------------------------------------------------ energia e compras

func drain_energy(amount: float) -> void:
	var before := energy
	energy = clampf(energy - amount, 0.0, 100.0)
	if int(before) != int(energy):
		energy_changed.emit(energy)


func is_bought(place_id: String, item_id: String) -> bool:
	return _bought_once.has(place_id + ":" + item_id)


## Compra num estabelecimento: desconta do tesouro e aplica o efeito do item.
func purchase(shop_type: String, place_id: String, item_id: String) -> Dictionary:
	var item := {}
	for it in SHOP_ITEMS.get(shop_type, []):
		if it.id == item_id:
			item = it
	if item.is_empty():
		return {"ok": false, "reason": "Produto indisponível."}
	if item.get("surrender", false):
		if wanted_level == 0:
			return {"ok": false, "reason": "Não está a ser procurado pela Guarda."}
		var fine := int((150.0 * wanted_level + treasury * 0.06 * wanted_level) * 0.5)
		treasury -= fine
		heat = 0.0
		wanted_level = 0
		_bust_t = 0.0
		treasury_changed.emit(treasury)
		wanted_changed.emit(0)
		toast.emit("Entregou-se à Guarda — multa de Kz %s (metade)." % fmt(fine), "info")
		purchase_made.emit(shop_type, item)
		return {"ok": true, "item": item, "fine": fine}
	if item.get("once", false) and is_bought(place_id, item_id):
		return {"ok": false, "reason": "Já é sócio deste estabelecimento."}
	if item.has("energy") and energy >= 99.0:
		return {"ok": false, "reason": "Está de barriga cheia."}
	if treasury < item.price:
		return {"ok": false, "reason": "Tesouro insuficiente (faltam Kz %s)." % fmt(item.price - treasury)}
	_spend(item.price)
	if item.has("energy"):
		energy = minf(100.0, energy + item.energy)
		energy_changed.emit(energy)
	if item.has("approval"):
		approval = minf(100.0, approval + item.approval)
		stats_changed.emit()
	if item.has("income"):
		investments += item.income
		_bought_once[place_id + ":" + item_id] = true
		stats_changed.emit()
	purchase_made.emit(shop_type, item)
	toast.emit("%s — Kz %s" % [item.name, fmt(item.price)], "success")
	return {"ok": true, "item": item}


# ------------------------------------------------------------------ procurado

func report_offense(kind: String) -> void:
	if not OFFENSES.has(kind):
		return
	heat = minf(heat + OFFENSES[kind].heat, HEAT_LEVELS[-1] + 30.0)
	escape_left = escape_time()
	toast.emit("%s! A Guarda de Bandula está de olho." % OFFENSES[kind].label, "error")
	_recompute_level()


func escape_time(level: int = wanted_level) -> float:
	return 6.0 + 4.0 * maxi(level, 1)


func _recompute_level() -> void:
	var lvl := 0
	for i in HEAT_LEVELS.size():
		if heat >= HEAT_LEVELS[i]:
			lvl = i + 1
	if lvl != wanted_level:
		wanted_level = lvl
		escape_left = escape_time()
		wanted_changed.emit(lvl)


func _update_wanted(delta: float) -> void:
	if wanted_level == 0:
		heat = maxf(0.0, heat - delta * 2.0)
		return
	if police_sees_player:
		escape_left = escape_time()
	else:
		escape_left -= delta
		escape_progress.emit(maxf(escape_left, 0.0), escape_time())
		if escape_left <= 0.0:
			heat = 0.0
			wanted_level = 0
			_bust_t = 0.0
			wanted_changed.emit(0)
			escaped.emit()
			toast.emit("Escapou da Guarda!", "success")


## Chamado pelo TrafficManager a cada frame de física com a viatura mais próxima.
func police_check(nearest_police_dist: float, player_speed: float, delta: float) -> void:
	if wanted_level == 0:
		_bust_t = 0.0
		return
	if nearest_police_dist < BUST_RANGE and player_speed < 3.0:
		_bust_t += delta
		if _bust_t >= BUST_TIME:
			bust()
	else:
		_bust_t = maxf(0.0, _bust_t - delta)


func bust_progress() -> float:
	return clampf(_bust_t / BUST_TIME, 0.0, 1.0)


func bust() -> void:
	var fine := int(150.0 * wanted_level + treasury * 0.06 * wanted_level)
	treasury -= fine
	heat = 0.0
	wanted_level = 0
	_bust_t = 0.0
	escape_left = 0.0
	treasury_changed.emit(treasury)
	wanted_changed.emit(0)
	busted.emit(fine)


static func fmt(n: float) -> String:
	var s := str(int(round(absf(n))))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
