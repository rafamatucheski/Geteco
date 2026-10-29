extends SceneTree
## Playtest 29/10 (2): "o som do pneu derrapando em curva quase não existe" e "é igual em todos os
## carros". Dirige um Vehicle real em curva forte e exige que a voz de deriva toque e seja audível
## (pico >= -18 dB, ~6 dB abaixo do motor); depois compara dois arquétipos com a mesma entrada:
## o leve tem de guinchar mais agudo que o pesado, e o freio de mão tem de ficar abaixo do drift.
const STREET = preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	stage.add_child(ground)
	await _drift(stage, "police_cruiser")
	var voices := {}
	for id in ["sport_coupe", "american_dump_truck"]:
		voices[id] = await _voice(stage, id)
	var light: Dictionary = voices["sport_coupe"]
	var heavy: Dictionary = voices["american_dump_truck"]
	var ok: bool = light.pitch > heavy.pitch * 1.15 and light.stream != heavy.stream and light.hb < light.drift - 6.0
	print(("CASE PASS " if ok else "CASE FAIL ") + "variação leve=%s heavy=%s" % [light, heavy])
	if not ok: failures += 1
	print("SKID_DRIFT_BALANCE failures=%d" % failures)
	quit(1 if failures else 0)

func _spawn(stage: Node3D, id: String) -> CharacterBody3D:
	var car: CharacterBody3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.position = Vector3(0, 0.05, 0)
	stage.add_child(car)
	if STREET.has(id): preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car)
	car.controlled = true
	for i in 10: await physics_frame
	return car

func _drift(stage: Node3D, id: String) -> void:
	var input = root.get_node("/root/GameInput")
	var car := await _spawn(stage, id)
	input.touch_move = Vector2(0, -1)
	for i in 60 * 14:
		await physics_frame
		if Vector2(car.velocity.x, car.velocity.z).length() >= 22.0: break
	input.touch_move = Vector2(1, -1)
	var tires = car.effects.tire_effects
	var played := 0
	var peak := -99.0
	for i in 75:
		await physics_frame
		var audio = tires.skid_audio
		if is_instance_valid(audio) and audio.playing:
			played += 1
			peak = maxf(peak, audio.volume_db)
	input.touch_move = Vector2.ZERO
	var ok := played >= 30 and peak >= -18.0
	print(("CASE PASS " if ok else "CASE FAIL ") + "drift %s quadros_com_chiado=%d/75 pico=%.1f dB" % [id, played, peak])
	if not ok: failures += 1
	car.queue_free()
	await physics_frame

## Mesma entrada (16 m/s, deriva forte e depois freio de mão) aplicada direto na voz do carro real.
func _voice(stage: Node3D, id: String) -> Dictionary:
	var car := await _spawn(stage, id)
	var tires = car.effects.tire_effects
	tires._update_skid_audio(true, 16.25, 6.0, 0)
	var result := {"pitch": snappedf(tires.skid_audio.pitch_scale, .01), "drift": snappedf(tires.skid_audio.volume_db, .1),
		"stream": tires.skid_audio.stream.get_instance_id()}
	tires._update_skid_audio(true, 16.25, 0.0, 2)
	result["hb"] = snappedf(tires.skid_audio.volume_db, .1)
	car.queue_free()
	await physics_frame
	return result
