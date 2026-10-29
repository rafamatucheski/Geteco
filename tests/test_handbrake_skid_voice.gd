extends SceneTree
## Playtest 29/10: "os carros não fazem barulho de pneu no freio de mão". Dirige o Vehicle
## de verdade numa pista plana a ~15 m/s, puxa o freio de mão (ação "handbrake", como o
## Espaço) e exige que a voz de derrapagem toque, uma só, e que parado não toque.
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
	var street: Array = STREET.ids()
	for id in ["sport_coupe", "police_cruiser", str(street[0])]:
		await _case(stage, id)
	print("HANDBRAKE_SKID_VOICE failures=%d" % failures)
	quit(1 if failures else 0)

func _voices(car: Node) -> int:
	var n := 0
	for child in car.get_children():
		if child.name.begins_with("VehicleSkid"): n += 1
	return n

func _case(stage: Node3D, id: String) -> void:
	var input = root.get_node("/root/GameInput")
	var car: CharacterBody3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.position = Vector3(0, 0.05, 0)
	stage.add_child(car)
	if STREET.has(id): preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car)
	car.controlled = true
	for i in 10: await physics_frame
	input.touch_move = Vector2(0, -1)
	for i in 60 * 14:
		await physics_frame
		if Vector2(car.velocity.x, car.velocity.z).length() >= 15.0: break
	input.touch_move = Vector2.ZERO
	var tires = car.effects.tire_effects
	var speed_at_pull := Vector2(car.velocity.x, car.velocity.z).length()
	Input.action_press("handbrake")
	var played := 0
	var max_voices := 0
	var peak_db := -99.0
	for i in 60:
		await physics_frame
		var audio = tires.skid_audio
		if is_instance_valid(audio) and audio.playing:
			played += 1
			peak_db = maxf(peak_db, audio.volume_db)
		max_voices = maxi(max_voices, _voices(car))
	Input.action_release("handbrake")
	# Parado, com o freio puxado, não pode chiar.
	for i in 60 * 6: await physics_frame
	Input.action_press("handbrake")
	for i in 30: await physics_frame
	var idle_audio = tires.skid_audio
	var idle_playing: bool = is_instance_valid(idle_audio) and idle_audio.playing
	Input.action_release("handbrake")
	# Playtest 29/10 (2): o freio de mão ficava em -10 dB, no nível do motor. Agora fica audível
	# (>= -22) mas bem abaixo do motor em cruzeiro (<= -15, ~3 dB ou mais abaixo dele).
	var audible_cap: bool = peak_db >= -22.0 and peak_db <= -15.0
	var ok := played >= 12 and max_voices <= 1 and not idle_playing and audible_cap
	print(("CASE PASS " if ok else "CASE FAIL ") + "%s v=%.1f m/s quadros_com_chiado=%d/60 vozes=%d parado_chia=%s pico=%.1f dB faixa_ok=%s" % [id, speed_at_pull, played, max_voices, idle_playing, peak_db, audible_cap])
	if not ok: failures += 1
	car.queue_free()
	await physics_frame
