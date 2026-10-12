extends Node
## Cabinet-owned voices. Samples are cached once, never synthesized per frame.
static var bank: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var motor: AudioStreamPlayer
var cursor := 0
var cabinet := ""

func _ready() -> void:
	if bank.is_empty():
		for spec in [["start",440.0,880.0,.3,0.0],["finish",660.0,1320.0,.6,0.0],
			["launch",180.0,900.0,.3,.1],["bumper",920.0,480.0,.16,.05],
			["flipper",180.0,75.0,.09,.55],["drain",320.0,65.0,.5,.1],
			["hit",110.0,45.0,.18,.65],["swing",380.0,130.0,.13,.7],
			["guard",650.0,220.0,.12,.25],["nitro",180.0,620.0,.4,.3],
			["move",440.0,500.0,.06,0.0],["lock",220.0,110.0,.12,.15],
			["line",660.0,1100.0,.35,0.0],["engine",65.0,65.0,.4,.06]]:
			bank[spec[0]] = _sample(float(spec[1]),float(spec[2]),float(spec[3]),float(spec[4]),spec[0] == "engine")
		for id in ["racer","pinball","fighter","blocks"]:
			bank[id] = _music(id)
	for i in range(6):
		var voice := _player(-13.0)
		voices.append(voice)
	music = _player(-23.0)
	motor = _player(-22.0)
	motor.stream = bank.engine

func _player(gain: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.volume_db = gain
	add_child(player)
	return player

func start(id: String) -> void:
	stop()
	cabinet = id
	music.stream = bank[id]
	music.play()
	if id == "racer": motor.play()
	play("start")

func play(event: String) -> void:
	if not bank.has(event): return
	var voice := voices[cursor]
	cursor = (cursor + 1) % voices.size()
	voice.stream = bank[event]
	voice.play()

func pause_audio(paused: bool) -> void:
	music.stream_paused = paused
	motor.stream_paused = paused
	for voice in voices: voice.stream_paused = paused

func update_engine(speed: float, boost: bool) -> void:
	if cabinet != "racer": return
	motor.pitch_scale = .65 + speed / 135.0
	motor.volume_db = -26.0 + minf(speed / 35.0,7.0) + (2.0 if boost else 0.0)

func stop() -> void:
	cabinet = ""
	for voice in voices:
		voice.stop()
		voice.stream_paused = false
	if music != null:
		music.stop()
		music.stream_paused = false
	if motor != null:
		motor.stop()
		motor.stream_paused = false

static func _wave(data: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	wave.data = data
	if looped:
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_end = int(data.size() * .5)
	return wave

static func _sample(low: float, high: float, duration: float, noise: float, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	var count := int(duration * 22050)
	data.resize(count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 431
	for i in range(count):
		var t := float(i) / count
		phase += TAU * lerpf(low,high,t) / 22050.0
		var envelope := 1.0 if looped else minf(t * 30.0,1.0) * pow(1.0-t,2.0)
		var sample := (sin(phase) * .65 + sin(phase*2.0) * .18) * (1.0-noise) + rng.randf_range(-1.0,1.0) * noise
		data.encode_s16(i*2,int(sample * envelope * 24000.0))
	return _wave(data,looped)

static func _music(id: String) -> AudioStreamWAV:
	var notes: Array = {"racer":[0,7,12,7,3,10,15,10],"pinball":[12,7,16,7,14,9,17,9],
		"fighter":[0,0,3,7,0,10,7,3],"blocks":[12,16,19,16,14,17,21,17]}[id]
	var beat := .22 if id == "racer" else .28 if id == "fighter" else .32
	var count := int(beat * 8.0 * 22050)
	var data := PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var time := float(i)/22050.0
		var index := mini(7,int(time/beat))
		var age := fmod(time,beat)
		var frequency := 220.0 * pow(2.0,float(notes[index])/12.0)
		var melody := (1.0 if sin(TAU*frequency*age) > 0 else -1.0) * exp(-age*11.0) * .2
		var bass := sin(TAU*110.0*age) * exp(-age*8.0) * .3
		var drum := sin(TAU*(70.0*age+3.0*(1.0-exp(-age*25.0)))) * exp(-age*35.0) * .3
		var fade := minf(age*200.0,1.0) * minf((beat-age)*200.0,1.0)
		data.encode_s16(i*2,int((melody+bass+drum)*fade*24000.0))
	return _wave(data,true)
