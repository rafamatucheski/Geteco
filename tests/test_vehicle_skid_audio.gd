extends SceneTree

const PROCEDURAL_AUDIO := preload("res://ProceduralAudio.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _init() -> void:
	var monaliza := PROCEDURAL_AUDIO.get_skid_stream("monaliza") as AudioStreamWAV
	var coupe := PROCEDURAL_AUDIO.get_skid_stream("sport_coupe") as AudioStreamWAV
	var sedan := PROCEDURAL_AUDIO.get_skid_stream("sedan_classic") as AudioStreamWAV
	var truck := PROCEDURAL_AUDIO.get_skid_stream("american_dump_truck") as AudioStreamWAV

	check(monaliza != null, "Monaliza receives its own skid audio")
	check(coupe != null and sedan != null and truck != null, "regular vehicles receive skid audio")
	if monaliza != null and coupe != null and sedan != null and truck != null:
		check(coupe.loop_mode == AudioStreamWAV.LOOP_FORWARD, "skid audio loops for the full slide")
		check(monaliza.data != coupe.data, "Monaliza and sport coupe have distinct skid timbres")
		check(coupe.data != sedan.data, "sport coupe and sedan have distinct skid timbres")
		check(sedan.data != truck.data, "sedan and heavy truck have distinct skid timbres")
		check(PROCEDURAL_AUDIO.get_skid_stream("sport_coupe") == coupe, "generated skid audio is cached per vehicle")

	if failures.is_empty():
		print("VEHICLE_SKID_AUDIO: PASS")
		quit(0)
	else:
		print("VEHICLE_SKID_AUDIO: FAIL (%d)" % failures.size())
		quit(1)
