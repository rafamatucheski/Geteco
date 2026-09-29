extends RefCounted
## Exact V1 ProceduralAudio fallback oscillators; the source has no horn/siren asset.
static var horn: AudioStreamWAV
static var siren: AudioStreamWAV
static var alarm: AudioStreamWAV

## Buzina por família de motor (`VehicleEngineProfile.family`): tons, duração, ataque,
## harmônicos e saturação. "street" é o oscilador original da V1; caminhão, ônibus e
## bombeiro usam buzina de ar (acorde grave, longa, saturada); moto é um bipe agudo curto.
const HORN_PROFILES := {
	"street": {"tones": [435.0, 545.0], "length": .40, "attack": .03, "release": .05, "harmonics": 0.0, "drive": 0.0},
	"electric": {"tones": [600.0, 760.0], "length": .30, "attack": .02, "release": .05, "harmonics": 0.0, "drive": 0.0},
	"suv": {"tones": [370.0, 466.0], "length": .45, "attack": .03, "release": .06, "harmonics": .20, "drive": 1.1},
	"muscle": {"tones": [392.0, 494.0], "length": .45, "attack": .03, "release": .06, "harmonics": .28, "drive": 1.3},
	"diesel": {"tones": [330.0, 415.0], "length": .50, "attack": .04, "release": .07, "harmonics": .32, "drive": 1.4},
	"sport": {"tones": [510.0, 640.0], "length": .32, "attack": .02, "release": .05, "harmonics": .18, "drive": 1.1},
	"vq35": {"tones": [520.0, 655.0], "length": .32, "attack": .02, "release": .05, "harmonics": .18, "drive": 1.1},
	"m8_v8": {"tones": [500.0, 630.0], "length": .34, "attack": .02, "release": .05, "harmonics": .22, "drive": 1.2},
	"rosso_v12": {"tones": [560.0, 700.0], "length": .30, "attack": .02, "release": .05, "harmonics": .15, "drive": 1.0},
	"police": {"tones": [500.0, 630.0], "length": .30, "attack": .02, "release": .05, "harmonics": .20, "drive": 1.2},
	"ambulance": {"tones": [420.0, 530.0], "length": .50, "attack": .03, "release": .06, "harmonics": .22, "drive": 1.2},
	"truck": {"tones": [165.0, 208.0, 247.0], "length": .95, "attack": .06, "release": .14, "harmonics": .55, "drive": 1.9},
	"bus": {"tones": [155.0, 196.0, 233.0], "length": .90, "attack": .06, "release": .14, "harmonics": .50, "drive": 1.8},
	"fire_diesel": {"tones": [150.0, 190.0, 225.0, 300.0], "length": 1.10, "attack": .07, "release": .16, "harmonics": .55, "drive": 2.0},
	"tank": {"tones": [196.0, 207.0], "length": .80, "attack": .04, "release": .10, "harmonics": .70, "drive": 2.6},
	"bike_urban": {"tones": [740.0, 930.0], "length": .22, "attack": .015, "release": .04, "harmonics": .10, "drive": 0.0},
	"bike_sport": {"tones": [820.0, 1030.0], "length": .20, "attack": .015, "release": .04, "harmonics": .10, "drive": 0.0},
	"bike_cruiser": {"tones": [560.0, 700.0], "length": .30, "attack": .02, "release": .05, "harmonics": .15, "drive": 0.0},
}
## Famílias de buzina de ar: mais alta e com alcance maior que a de carro.
const HEAVY_HORNS := ["truck", "bus", "fire_diesel", "tank"]
static var horns: Dictionary = {}

static func is_heavy_horn(family: String) -> bool:
	return family in HEAVY_HORNS

## `archetype` desafina de -4 % a +4 % de forma estável: dois modelos da mesma família
## não soam idênticos. Sem arquétipo (chamada antiga) sai o oscilador original.
static func horn_stream(family: String = "street", archetype: String = "") -> AudioStreamWAV:
	if not HORN_PROFILES.has(family): family = "street"
	var key := family + "|" + archetype
	if horns.has(key): return horns[key]
	var profile: Dictionary = HORN_PROFILES[family]
	var detune := 1.0 if archetype.is_empty() else 1.0 + float(archetype.hash() % 9 - 4) * .01
	var tones: Array = profile.tones
	var length: float = profile.length
	var samples := int(length * 22050.0)
	var attack: float = profile.attack
	var release: float = profile.release
	var harmonics: float = profile.harmonics
	var drive: float = profile.drive
	var level := .5 if family in HEAVY_HORNS else .4
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / 22050.0
		var env := 1.0
		if t < attack: env = t / attack
		elif t > length - release: env = maxf(0.0, (length - t) / release)
		var mix := 0.0
		for tone in tones:
			var phase := TAU * float(tone) * detune * t
			mix += sin(phase) + harmonics * sin(phase * 2.0) + harmonics * .5 * sin(phase * 3.0)
		mix /= float(tones.size())
		var sample := (tanh(mix * drive) if drive > 0.0 else mix) * env * level
		data.encode_s16(i * 2, clampi(int(sample * 32767), -32768, 32767))
	var stream := _stream(data)
	horns[key] = stream
	if family == "street" and archetype.is_empty(): horn = stream
	return stream

static func siren_stream() -> AudioStreamWAV:
	if siren: return siren
	var data := PackedByteArray()
	data.resize(66150 * 2)
	var phase := 0.0
	for i in 66150:
		var t := float(i) / 22050.0
		var frequency := 650 + 500 * (.5 - .5 * cos(TAU * t / 3.0))
		var tone := sin(phase) + sin(phase * 2) * .10 + sin(phase * 3) * .04
		phase += TAU * frequency / 22050.0
		data.encode_s16(i * 2, clampi(int(tanh(tone * .75) * .55 * 32767), -32768, 32767))
	siren = _stream(data)
	siren.loop_mode = AudioStreamWAV.LOOP_FORWARD
	siren.loop_end = 66150
	return siren

## V1 `ProceduralAudio._generate_police_alarm_stream`: 880/1320 Hz alternando a
## cada 0,4 s. Os 0,8 s fecham ciclos inteiros das duas portadoras e o crossfade
## é um tanh de seno, então o laço não estala na emenda.
static func alarm_stream() -> AudioStreamWAV:
	if alarm: return alarm
	var samples := 17640
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in samples:
		var t := float(i) / 22050.0
		var tone_a := sin(phase_a) + sin(phase_a * 2) * .08
		var tone_b := sin(phase_b) + sin(phase_b * 2) * .08
		phase_a += TAU * 880 / 22050.0
		phase_b += TAU * 1320 / 22050.0
		var blend := .5 + .5 * tanh(12 * sin(TAU * t / .4))
		data.encode_s16(i * 2, clampi(int((tone_a * blend + tone_b * (1 - blend)) * .38 * 32767), -32768, 32767))
	alarm = _stream(data)
	alarm.loop_mode = AudioStreamWAV.LOOP_FORWARD
	alarm.loop_end = samples
	return alarm

static func _stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream
