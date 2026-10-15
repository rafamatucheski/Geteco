extends SceneTree

## Sons gerados no Firefly (2026-10-15): existem, estão importados, o sorteio de tiros os
## inclui, os loops repetem e a camada posicional toca. Não mede a qualidade do som (isso é
## de ouvido); mede que o jogo os encontra e usa.
const FIREFLY := preload("res://audio/FireflyBank.gd")
const COMBAT := preload("res://gameplay/CombatAudio.gd")
const EQUIPMENT_AUDIO := preload("res://gameplay/VehicleEquipmentAudio.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	# (pasta, nome, mínimo de tomadas). Tomadas fracas foram descartadas no tratamento, então
	# o mínimo é o que sobrou de bom, não 4.
	var banks := [
		["weapons_fire", "pistol", 3], ["weapons_fire", "shotgun", 3], ["weapons_fire", "rifle_shot", 3],
		["weapons_fire", "distant_shot", 1], ["weapons_fire", "dry_fire", 3], ["weapons_fire", "gun_draw", 3],
		["weapons_fire", "gun_holster", 3], ["weapons_fire", "grenade_pin", 3], ["weapons_fire", "explosion_tail", 3],
		["weapons_fire", "ricochet", 3], ["weapons_fire", "bullet_whiz", 3], ["katana", "draw", 3], ["katana", "sheath", 3],
		["vehicle_fx", "ignition", 2], ["vehicle_fx", "engine_off", 1], ["vehicle_fx", "door_open", 3],
		["vehicle_fx", "door_close", 3], ["vehicle_fx", "handbrake", 3], ["vehicle_fx", "backfire", 2],
		["vehicle_fx", "car_horn", 3], ["vehicle_fx", "wastegate", 3], ["vehicle_fx", "turbo_flutter", 3],
		["vehicle_fx", "turbo_spool", 3], ["vehicle_fx", "turbo_spooldown", 3], ["vehicle_fx", "diesel_turbo", 3],
		["service_vehicles", "horn", 3], ["wildlife", "coyote", 3], ["wildlife", "crickets", 1],
		["mining", "drip", 3], ["mining", "machinery", 3], ["desert_ambience", "wind", 3],
		["forklift", "mast", 3], ["forklift", "pallet_drop", 3], ["helicopter", "rotor_loop", 3], ["helicopter", "flyover", 2],
	]
	for bank in banks:
		var count: int = FIREFLY.count(bank[0], bank[1])
		check(count >= int(bank[2]), "%s/%s tem %d tomadas importadas (mínimo %d)" % [bank[0], bank[1], count, bank[2]])
		for index in count:
			var stream: AudioStream = FIREFLY.stream(bank[0], bank[1], index)
			check(stream != null and stream.get_length() > 0.05, "%s/%s_%d carrega" % [bank[0], bank[1], index])
			check(stream == null or stream.get_length() < 16.0, "%s/%s_%d não passa de 16 s" % [bank[0], bank[1], index])
	for entry in [["service_vehicles", "siren_loop.wav", 3.0], ["service_vehicles", "reverse_beep_loop.wav", 1.5], ["vehicle_fx", "supercharger_loop.wav", 1.0], ["weapons_fire", "rocket_flight_loop.wav", 1.5]]:
		var looped: AudioStreamWAV = FIREFLY.loop(entry[0], entry[1])
		check(looped != null and looped.loop_mode == AudioStreamWAV.LOOP_FORWARD and looped.get_length() >= float(entry[2]) and looped.loop_end > 0, "%s/%s repete sem parar" % [entry[0], entry[1]])
	# Armas com tiro gravado sorteiam só os novos (sem repetir o anterior); a camada sintética de corpo sai.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for family in ["pistol", "shotgun", "ak47", "m4a1"]:
		var recorded := 0
		var classic := 0
		var previous: AudioStream
		for i in 400:
			var take: AudioStream = COMBAT.gunfire_take(family, rng)
			check(take != null, "%s sempre devolve um take" % family)
			check(take != previous, "%s não repete o take anterior" % family)
			previous = take
			if take != null and take.resource_path.begins_with("res://audio/weapons_fire/"): recorded += 1
			elif take != null: classic += 1
		check(COMBAT.gun_body(family) == null, "%s não soma o corpo sintético antigo" % family)
		check(recorded == 400 and classic == 0, "%s usa só os takes novos (%d novos, %d do V1)" % [family, recorded, classic])
	for family in ["suppressed_pistol", "magnum", "hunting_rifle"]:
		for i in 60:
			var take: AudioStream = COMBAT.gunfire_take(family, rng)
			check(take == null or not take.resource_path.begins_with("res://audio/weapons_fire/"), "%s continua só com os takes do V1" % family)
	# Buzina de carro e de ar são as gravadas; sirene é a gravada e repete.
	check(EQUIPMENT_AUDIO.horn_stream("street").resource_path.is_empty() or EQUIPMENT_AUDIO.horn_stream("street").get_length() > 0.3, "buzina de carro tem duração de buzina")
	check(EQUIPMENT_AUDIO.siren_stream().get_length() > 3.0, "sirene gravada")
	# A camada posicional toca e se limpa sozinha.
	var holder := Node3D.new()
	root.add_child(holder)
	var voice: AudioStreamPlayer3D = FIREFLY.play_at(holder, FIREFLY.take("vehicle_fx", "door_close"), Vector3(1, 0, 2), -8.0)
	check(voice != null and voice.playing and voice.bus != &"", "play_at toca um som posicional")
	check(FIREFLY.play_at(holder, null, Vector3.ZERO, 0.0) == null, "play_at sem som não faz nada")
	holder.free()
	await process_frame
	print("FIREFLY_SOUNDS failures=", failures)
	quit(0 if failures.is_empty() else 1)
