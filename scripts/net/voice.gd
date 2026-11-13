extends Node
## Bandula — Voice (autoload "Voice"). Conversa por microfone entre jogadores online.
##
##   microfone → bus «Microfone» (mudo) + AudioEffectCapture → mono 16 kHz → μ-law 8 bits
##   → pacotes de 60 ms (960 B) pelo canal 1 → servidor → só para quem está perto (≤ RANGE)
##   e no mesmo sítio (rua ou o mesmo interior) → AudioStreamPlayer3D no avatar de quem fala.
##
## Modos: «ptt» (premir V para falar, por omissão), «open» (microfone aberto com limiar)
## e «off». No browser o microfone só funciona em https:// ou em localhost.

signal transmitting_changed(on: bool)
signal voice_received(id: int, frames: PackedVector2Array)
signal mic_status(text: String)

const RATE := 16000
const PACKET := 960                 # amostras (60 ms)
const RANGE := 45.0                 # m
const GATE := 0.025                 # limiar RMS do microfone aberto
const HANGOVER := 0.5               # s a continuar a transmitir depois de calar
const MAX_PACKET_BYTES := 2048
const MAX_PACKETS_PER_SEC := 30
const MODES := ["ptt", "open", "off"]
const MODE_NAMES := ["Voz: premir V para falar", "Voz: microfone aberto", "Voz: desligada"]

var mode := "ptt"
var transmitting := false
var mic_gain := 1.0
var sent_packets := 0
var received := {}                  # id → pacotes recebidos (estatística/testes)

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _pending := PackedFloat32Array()
var _acc := 0.0
var _acc_n := 0
var _phase := 0.0
var _hang := 0.0
var _no_frames_t := 0.0
var _decode := PackedFloat32Array()
var _budget := {}                   # (servidor) id → [início da janela ms, pacotes]


func _ready() -> void:
	_decode.resize(256)
	for u in 256:
		_decode[u] = _mulaw_decode(u)
	Network.connection_changed.connect(func(online: bool, _s: String):
		if online:
			start_mic()
		else:
			stop_mic())
	Network.peer_left.connect(func(id: int, _n: String): received.erase(id))


func set_mode(m: String) -> void:
	mode = m if m in MODES else "ptt"
	if mode == "off":
		stop_mic()
	elif Network.is_online():
		start_mic()


# ------------------------------------------------------------------ microfone

func start_mic() -> void:
	if mode == "off" or _mic_player != null or DisplayServer.get_name() == "headless":
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		mic_status.emit("Microfone desativado no projeto")
		return
	var bus := AudioServer.get_bus_index("Microfone")
	if bus < 0:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "Microfone")
		AudioServer.set_bus_mute(bus, true)          # não se ouvir a si próprio
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(bus, _capture)
	else:
		_capture = AudioServer.get_bus_effect(bus, 0)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "Microfone"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Microfone"
	_mic_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_mic_player)
	_mic_player.play()
	_no_frames_t = 0.0
	mic_status.emit("ready")


func stop_mic() -> void:
	if _mic_player:
		_mic_player.queue_free()
		_mic_player = null
	_pending.clear()
	_set_tx(false)


func _process(delta: float) -> void:
	if _mic_player == null or _capture == null or not Network.is_online():
		return
	var n := _capture.get_frames_available()
	if n == 0:
		_no_frames_t += delta
		if _no_frames_t > 4.0 and _no_frames_t - delta <= 4.0:
			mic_status.emit("Sem som do microfone — permita o acesso no browser")
		return
	_no_frames_t = 0.0
	var buf := _capture.get_buffer(n)
	var want := false
	if mode == "ptt":
		want = Input.is_action_pressed("voice") and not GameManager.input_locked
	elif mode == "open":
		var e := 0.0
		for f in buf:
			e += f.x * f.x + f.y * f.y
		if sqrt(e / (2.0 * buf.size())) * mic_gain > GATE:
			_hang = HANGOVER
		else:
			_hang -= delta
		want = _hang > 0.0
	_set_tx(want)
	if not want:
		_pending.clear()
		return
	_downsample(buf, AudioServer.get_mix_rate())
	while _pending.size() >= PACKET:
		_send(_pending.slice(0, PACKET))
		_pending = _pending.slice(PACKET)


func _set_tx(on: bool) -> void:
	if on != transmitting:
		transmitting = on
		transmitting_changed.emit(on)


## Estéreo à taxa do mixer → mono 16 kHz (média por janela — filtro simples anti-aliasing).
func _downsample(buf: PackedVector2Array, mix_rate: float) -> void:
	var step := mix_rate / RATE
	for f in buf:
		_acc += (f.x + f.y) * 0.5
		_acc_n += 1
		_phase += 1.0
		if _phase >= step:
			_pending.append(clampf(_acc / _acc_n * mic_gain, -1.0, 1.0))
			_acc = 0.0
			_acc_n = 0
			_phase -= step


## Envia amostras mono a 16 kHz (também usado nos testes, sem microfone).
func send_pcm(samples: PackedFloat32Array) -> void:
	var i := 0
	while i < samples.size():
		_send(samples.slice(i, i + PACKET))
		i += PACKET


func _send(samples: PackedFloat32Array) -> void:
	if not Network.is_online():
		return
	var bytes := PackedByteArray()
	bytes.resize(samples.size())
	for i in samples.size():
		bytes[i] = _mulaw_encode(samples[i])
	sent_packets += 1
	_voice_up.rpc_id(1, bytes)


# ------------------------------------------------------------------ rede

@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _voice_up(data: PackedByteArray) -> void:
	if not Network.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not Network.peers.has(id) or data.is_empty() or data.size() > MAX_PACKET_BYTES:
		return
	var now := Time.get_ticks_msec()
	var b: Array = _budget.get(id, [now, 0])
	if now - int(b[0]) > 1000:
		b = [now, 0]
	b[1] = int(b[1]) + 1
	_budget[id] = b
	if int(b[1]) > MAX_PACKETS_PER_SEC:             # anti-abuso
		return
	var me: Dictionary = Network.last_state.get(id, {})
	if me.is_empty():
		return
	for pid in Network.peers:
		if pid == id:
			continue
		var o: Dictionary = Network.last_state.get(pid, {})
		if not o.is_empty() and o.r == me.r and (o.p as Vector3).distance_to(me.p) <= RANGE:
			_voice.rpc_id(pid, id, data)


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _voice(id: int, data: PackedByteArray) -> void:
	received[id] = int(received.get(id, 0)) + 1
	var frames := PackedVector2Array()
	frames.resize(data.size())
	for i in data.size():
		var s := _decode[data[i]]
		frames[i] = Vector2(s, s)
	voice_received.emit(id, frames)


# ------------------------------------------------------------------ μ-law (G.711)

static func _mulaw_encode(x: float) -> int:
	var s := int(clampf(x, -1.0, 1.0) * 32635.0)
	var sign := 0
	if s < 0:
		s = -s
		sign = 0x80
	s += 0x84
	var e := 7
	var mask := 0x4000
	while e > 0 and (s & mask) == 0:
		e -= 1
		mask >>= 1
	var mant := (s >> (e + 3)) & 0x0F
	return ~(sign | (e << 4) | mant) & 0xFF


static func _mulaw_decode(u: int) -> float:
	u = ~u & 0xFF
	var e := (u >> 4) & 0x07
	var s := (((u & 0x0F) << 3) + 0x84) << e
	s -= 0x84
	return (-s if (u & 0x80) != 0 else s) / 32768.0
