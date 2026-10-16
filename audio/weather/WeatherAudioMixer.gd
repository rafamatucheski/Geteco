extends Node
## Three constant voices, authored offline. No PCM generation or transient Tweens.
## A private bus filters only this weather instance, then sends to the user's Ambient.
const FIREFLY := preload("res://audio/FireflyBank.gd")
## Sons gerados no ElevenLabs (2026-10-16) em audio/ambience_el: chuva fraca e forte, tempestade
## (vento + chuva) e trovões (estalo próximo + ribombo). Os arquivos de chuva já são loops
## sem emenda; os trovões são pontuais.
const LOOPS := [["rain_light_0.wav"], ["rain_light_1.wav"], ["rain_heavy_0.wav"], ["storm_0.wav"]]
const THUNDER_KEYS := ["thunder_crack", "thunder_roll"]
# Rain is a background bed, including storms: retain space for voices/engines/shots.
const RAIN_TRIM_DB := -16.0
var layers: Array[AudioStreamPlayer] = []
var thunder: AudioStreamPlayer
var target_intensity := 0.0
var intensity := 0.0
var sheltered := false
var interior_silence := false
var shelter_mix := 0.0
var dialogue_focused := false
var focus_gain := 1.0
var low_pass: AudioEffectLowPassFilter
var bus_name: StringName
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	bus_name = StringName("Weather_%d" % get_instance_id())
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master")
	low_pass = AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = 18000.0
	AudioServer.add_bus_effect(index, low_pass)
	for i in LOOPS.size():
		var player := AudioStreamPlayer.new()
		player.name = ["RainBed", "SurfaceDrops", "HeavySheets", "StormBed"][i]
		player.stream = FIREFLY.loop("ambience_el", LOOPS[i][0])
		player.bus = bus_name
		player.volume_db = -80.0
		add_child(player)
		layers.append(player)
	thunder = AudioStreamPlayer.new()
	thunder.name = "Thunder"
	thunder.bus = bus_name
	thunder.volume_db = -16.0
	add_child(thunder)

func set_conditions(amount: float, inside: bool) -> void:
	target_intensity = clampf(amount, 0.0, 1.0)
	sheltered = inside

func set_interior_silence(active: bool) -> void:
	interior_silence = active
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus_name), active)
	if active:
		thunder.stop()

func set_dialogue_focus(active: bool) -> void:
	dialogue_focused = active

func _process(delta: float) -> void:
	focus_gain = move_toward(focus_gain, 0.5 if dialogue_focused else 1.0, delta / (0.2 if dialogue_focused else 0.8))
	# One moving target: a rapid enter/leave or clear/rain cannot leave a stale stop.
	intensity = move_toward(intensity, target_intensity, delta / 3.0)
	shelter_mix = move_toward(shelter_mix, 1.0 if sheltered else 0.0, delta / 0.8)
	low_pass.cutoff_hz = exp(lerpf(log(18000.0), log(850.0), shelter_mix))
	var outside_gain := lerpf(1.0, 0.24, shelter_mix)
	var gains := [sqrt(intensity) * 0.72, intensity * lerpf(0.64, 0.08, shelter_mix), smoothstep(0.38, 1.0, intensity) * 0.78, smoothstep(0.7, 1.0, intensity) * 0.5]
	for i in layers.size():
		var player := layers[i]
		if player.stream == null: continue
		var gain: float = gains[i] * outside_gain * focus_gain
		player.volume_db = linear_to_db(maxf(gain, 0.0001)) + RAIN_TRIM_DB
		if gain > 0.001 and not player.playing:
			player.play(_rng.randf_range(0.0, player.stream.get_length()))
		elif gain <= 0.001 and player.playing:
			player.stop()
	thunder.volume_db = lerpf(-16.0, -28.0, shelter_mix) + linear_to_db(focus_gain)

func play_thunder() -> void:
	if interior_silence:
		return
	var pool: Array[AudioStream] = []
	for key in THUNDER_KEYS: pool.append_array(FIREFLY.all("ambience_el", key))
	if pool.is_empty(): return
	thunder.stream = pool[_rng.randi_range(0, pool.size() - 1)]
	thunder.pitch_scale = _rng.randf_range(0.94, 1.04)
	thunder.play()

func _exit_tree() -> void:
	for player in layers:
		player.stop()
	if is_instance_valid(thunder):
		thunder.stop()
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.remove_bus(index)
