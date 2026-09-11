extends Node
## Três stems offline compartilham o mesmo relógio e respeitam pausa/seek/pulo.
const BASE := "res://cutscenes/opening/v3/audio/"
var players: Array[AudioStreamPlayer] = []
var language := "pt"
var active := false
var gain := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for entry in [["RainLoop","foley","SFX"],["ProvisionalUnderscore","music","Music"],["Dialogue","voice_pt","SFX"]]:
		var p:=AudioStreamPlayer.new(); p.name=entry[0]
		p.stream=load(BASE+entry[1]+".ogg")
		p.bus=entry[2] if AudioServer.get_bus_index(entry[2])>=0 else "Master"
		add_child(p); players.append(p)

func configure(locale: String, speed: float) -> void:
	language="en" if locale.begins_with("en") else "pt"
	players[2].stream=load(BASE+"voice_"+language+".ogg")
	for p in players: p.pitch_scale=speed

func play_from(time: float) -> void:
	active=true
	for p in players:
		p.volume_db=0; p.stream_paused=false; p.play(time)

func set_paused(value: bool) -> void:
	for p in players: p.stream_paused=value

func set_gain(value: float) -> void:
	gain=value
	for p in players: p.volume_db=value

func stop_all() -> void:
	active=false
	for p in players: p.stop(); p.stream_paused=false

func reset() -> void: stop_all()

func _exit_tree() -> void:
	stop_all()
	for p in players:
		p.stream=null
	players.clear()

func play_cue(_id: StringName, _payload: Dictionary={}) -> void:
	# Eventos semânticos ficam disponíveis para observadores; o som está nos stems.
	pass
