extends RefCounted
## Geografia de Luanda para o Bandula — porta fiel das funções de world.js
## (terrainHeight, landField, coastX, ilhaX, southShore, estradas fora da grade,
## distritos e a grade 6×6 da cidade). 1 unidade = 1 m; Y para cima; norte = −Z.

const CITY_BLOCKS := 6
const CITY_BLOCK := 40.0
const CITY_ROAD := 10.0
const CITY_PITCH := 50.0
const CITY_SIDEWALK := 3.0
const CITY_HALF := 155.0
const CITY_CURB := 0.18
const CITY_LOT := 16.0
const MAP_HALF := 300.0
const WATER_LEVEL := -0.35
const CITY_EDGE := CITY_HALF + 2.0
const ILHA_HALF := 16.0
const FORT := {"x": -150.0, "z": -232.0, "plateau": 25.0, "base": 95.0, "h": 12.0}

const DISTRICT_GROUND := {
	"centro": Color("#ffe9d6"), "residencial": Color("#c9ef8a"),
	"industrial": Color("#efdcd0"), "quartel": Color("#e4ecff"),
}

static var _roads: Array = []


static func road_centers() -> Array:
	var out := []
	for k in range(CITY_BLOCKS + 1):
		out.append(-CITY_HALF + CITY_ROAD / 2.0 + k * CITY_PITCH)
	return out


static func block_centers() -> Array:
	var out := []
	for i in range(CITY_BLOCKS):
		out.append(-CITY_HALF + CITY_ROAD + CITY_BLOCK / 2.0 + i * CITY_PITCH)
	return out


static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------------ ruído (idêntico ao JS)

static func _u32(v: int) -> int:
	return v & 0xFFFFFFFF


static func _s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## Math.imul do JavaScript (multiplicação inteira de 32 bits).
static func _imul(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFFFFFF
	var lo := (a & 0xFFFF) * b
	var hi := ((((a >> 16) & 0xFFFF) * b) & 0xFFFF) << 16
	return _s32(lo + hi)


static func hash2(x: int, y: int, s: int) -> float:
	var h := _s32(_imul(x, 374761393) + _imul(y, 668265263) + _imul(s, 982451653))
	h = _imul(h ^ (_u32(h) >> 13), 1274126177)
	h = h ^ (_u32(h) >> 16)
	return float(_u32(h)) / 4294967296.0


static func vnoise(x: float, y: float, s: int) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := hash2(xi, yi, s)
	var b := hash2(xi + 1, yi, s)
	var c := hash2(xi, yi + 1, s)
	var d := hash2(xi + 1, yi + 1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


static func fbm(x: float, y: float, s: int, oct: int = 4) -> float:
	var sum := 0.0
	var amp := 1.0
	var norm := 0.0
	var f := 1.0
	for i in range(oct):
		sum += amp * vnoise(x * f, y * f, s + i * 1013)
		norm += amp
		amp *= 0.5
		f *= 2.0
	return sum / norm


# ------------------------------------------------------------------ costa, Ilha, Fortaleza

static func coast_x(z: float) -> float:
	return -186.0 + sin(z * 0.035) * 5.0 + sin(z * 0.011 + 1.0) * 4.0


static func ilha_x(z: float) -> float:
	return -252.0 + sin((z + 40.0) * 0.013) * 8.0


static func south_shore(x: float) -> float:
	return 96.0 + sin(x * 0.04) * 3.0


## Estradas fora da grade: aterro + estrada da Ilha, e a subida da Fortaleza.
static func extra_roads() -> Array:
	if _roads.is_empty():
		var ilha: Array = [Vector2(-155, 100), Vector2(-200, 100), Vector2(-232, 99)]
		var z := 92.0
		while z >= -292.0:
			ilha.append(Vector2(ilha_x(z), z))
			z -= 8.0
		var forte: Array = [Vector2(-100, -155), Vector2(-100, -196), Vector2(-104, -214), Vector2(-116, -227), Vector2(-124, -232)]
		for r in [{"id": "ilha", "w": 9.0, "pts": ilha}, {"id": "fortaleza", "w": 8.0, "pts": forte}]:
			var x0 := INF; var x1 := -INF; var z0 := INF; var z1 := -INF
			for p in r.pts:
				x0 = minf(x0, p.x); x1 = maxf(x1, p.x); z0 = minf(z0, p.y); z1 = maxf(z1, p.y)
			r["box"] = [x0, x1, z0, z1]
			_roads.append(r)
	return _roads


static func poly_dist(pts: Array, x: float, z: float) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		var t := clampf(((x - a.x) * d.x + (z - a.y) * d.y) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, Vector2(x, z).distance_to(a + d * t))
	return best


static func extra_road_dist(x: float, z: float) -> float:
	var best := INF
	for r in extra_roads():
		var bx: Array = r.box
		var m := 12.0
		if x < bx[0] - m or x > bx[1] + m or z < bx[2] - m or z > bx[3] + m:
			best = minf(best, m)
			continue
		best = minf(best, poly_dist(r.pts, x, z) - r.w / 2.0)
	return best


## > 0 em terra (≈ metros até a água), < 0 no mar.
static func land_field(x: float, z: float) -> float:
	var main := maxf(x - coast_x(z), z - south_shore(x))
	var ilha := ILHA_HALF - absf(x - ilha_x(z)) if z < 104.0 else -99.0
	return maxf(main, ilha)


## Altura do terreno natural (fora da cidade) — idêntica a terrainHeight do world.js.
static func terrain_height(x: float, z: float) -> float:
	var ax := absf(x)
	var az := absf(z)
	var d_out := Vector2(maxf(0.0, ax - CITY_EDGE), maxf(0.0, az - CITY_EDGE)).length()
	var s := land_field(x, z)
	var h: float
	if s < 0.0:
		h = -0.6 - smooth(0.0, 22.0, -s) * 3.2
	else:
		h = smooth(0.0, 9.0, s) * 0.55
		var main := maxf(x - coast_x(z), z - south_shore(x))
		if main > 30.0 and d_out > 0.0:
			h += smooth(30.0, 70.0, main) * smooth(0.0, 45.0, d_out) * maxf(0.0, (fbm(x * 0.012 + 40.0, z * 0.012 + 40.0, 7) - 0.42) * 11.0)
		var edge := minf(45.0, maxf(x, absf(z)) - (MAP_HALF - 12.0))
		if edge > 0.0 and x > -170.0:
			h += edge * edge * 0.014 * (0.55 + fbm(x * 0.02, z * 0.02, 19, 3) * 0.9)
	var fd := Vector2(x - FORT.x, z - FORT.z).length()
	if fd < FORT.base:
		var hill: float = FORT.h * smooth(FORT.base, FORT.plateau, fd) * smooth(0.0, 24.0, d_out)
		var rough := 0.0
		if fd > FORT.plateau + 4.0:
			rough = (fbm(x * 0.08, z * 0.08, 41, 2) - 0.5) * 1.6 * smooth(FORT.plateau + 4.0, FORT.plateau + 16.0, fd)
		h = maxf(h, hill + rough * (hill / FORT.h))
	var rd := extra_road_dist(x, z)
	if rd < 3.0 and s > 0.0:
		h = maxf(h, 0.45)
	return h


static func inside_city(x: float, z: float) -> bool:
	return absf(x) <= CITY_HALF and absf(z) <= CITY_HALF


static func block_index(v: float) -> int:
	var u := v + CITY_HALF - CITY_ROAD
	var i := int(floor(u / CITY_PITCH))
	var w := u - i * CITY_PITCH
	return i if i >= 0 and i < CITY_BLOCKS and w >= 0.0 and w <= CITY_BLOCK else -1


## Altura do chão como o jogo a calcula (meio-fio nas quadras, 0 nas ruas, relevo fora).
static func height_at(x: float, z: float) -> float:
	if inside_city(x, z):
		return CITY_CURB if block_index(x) >= 0 and block_index(z) >= 0 else 0.0
	return maxf(terrain_height(x, z), WATER_LEVEL - 0.05)


static func is_water(x: float, z: float) -> bool:
	return not inside_city(x, z) and terrain_height(x, z) < WATER_LEVEL - 0.05


static func block_district(bx: int, bz: int) -> String:
	if bx >= 2 and bx <= 3 and bz >= 1 and bz <= 4:
		return "centro"
	if bz <= 2:
		return "residencial"
	if bx >= 4:
		return "industrial"
	return "quartel"


static func block_kind(bx: int, bz: int) -> String:
	if bx == 2 and bz == 2:
		return "towers"
	if bx == 3 and bz == 2:
		return "plaza"
	if (bx == 5 and bz == 0) or (bx == 0 and bz == 3):
		return "park"
	if bx == 0 and bz == 5:
		return "esquadra"          # Esquadra da Ingombota (Guarda de Bandula)
	return "lots"


## Áreas decoradas à mão (sem vegetação aleatória) — igual ao world.js.
static func reserved(x: float, z: float) -> bool:
	return (absf(x) < CITY_HALF + 8.0 and absf(z) < CITY_HALF + 8.0) \
		or extra_road_dist(x, z) < 4.0 \
		or Vector2(x - FORT.x, z - FORT.z).length() < FORT.plateau + 8.0 \
		or (z < 104.0 and absf(x - ilha_x(z)) < ILHA_HALF + 3.0) \
		or (x < -150.0 and x > coast_x(z) - 2.0 and z > -160.0 and z < 100.0)


## Cor do terreno (praia, laterita, encostas, mar) — igual ao _buildTerrain do world.js.
static func terrain_color(x: float, z: float, h: float, in_city: bool) -> Color:
	var s_f := land_field(x, z)
	if h < WATER_LEVEL:
		return Color("#63e6d6").lerp(Color("#2a9fc6"), smooth(-0.8, -3.6, h))
	if not in_city and h < 1.2 and (s_f < 9.0 or (z < 104.0 and absf(x - ilha_x(z)) < ILHA_HALF + 1.0)):
		return Color("#f0c58a").lerp(Color("#ffe1a1"), smooth(0.5, 3.0, s_f))
	var n := fbm(x * 0.05, z * 0.05, 3, 3)
	var c := Color("#9fdc4f").lerp(Color("#c6ea6c") if n > 0.5 else Color("#7fcf44"), absf(n - 0.5) * 1.6)
	var lat := fbm(x * 0.018 + 9.0, z * 0.018 + 3.0, 23, 3)
	if lat > 0.56:
		c = c.lerp(Color("#e0905e"), smooth(0.56, 0.7, lat) * 0.8)
	var fd := Vector2(x - FORT.x, z - FORT.z).length()
	if fd < FORT.base:
		c = c.lerp(Color("#dd9c6a"), smooth(FORT.plateau + 2.0, FORT.plateau + 9.0, fd) * smooth(FORT.base * 0.8, FORT.plateau + 16.0, fd) * 0.75)
	var edge := maxf(x, absf(z)) - (MAP_HALF - 12.0)
	if edge > 0.0 and x > -170.0:
		c = c.lerp(Color("#9bd85c"), smooth(0.0, 30.0, edge))
	return c
