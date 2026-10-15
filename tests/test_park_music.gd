extends SceneTree

## A música do parque existe, repete e toca presa ao parque. Não mede a qualidade do som.
const PARK := preload("res://world/places/amusement_park/ParkLume.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	var stream := load("res://audio/amusement_park/park_music.ogg") as AudioStreamOggVorbis
	check(stream != null and stream.get_length() > 60.0, "música do parque carrega e dura mais de 1 min")
	var park := PARK.new()
	root.add_child(park)
	await process_frame
	var voice := park.get_node_or_null("ParkMusic") as AudioStreamPlayer3D
	check(voice != null and voice.playing, "parque toca a música")
	check(voice != null and voice.stream is AudioStreamOggVorbis and (voice.stream as AudioStreamOggVorbis).loop, "a música repete")
	park.free()
	await process_frame
	print("PARK_MUSIC failures=", failures)
	quit(0 if failures.is_empty() else 1)
