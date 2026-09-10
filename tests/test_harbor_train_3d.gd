extends SceneTree
## Contratos de apresentação, oclusão, portais e fontes espaciais do trem.
var failures := 0

class DrivenCar extends Node2D:
	var is_driven_by_player := true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := Node2D.new()
	player.add_to_group("player")
	world.add_child(player)
	var rail = load("res://world/harbor/HarborRailLine.gd").new()
	world.add_child(rail)
	var train = rail.get_node("AmbientTrain")
	train.set_process(false)
	rail.set_process(false)
	await process_frame
	check(train.locomotive.model.get_child_count() > 30, "A locomotiva deve ter geometria 3D")
	check(train._freight_visuals.size() == 6, "Seis vagões articulados")
	check(train._rail_sounds.size() == 7, "Som de trilho acompanha cada peça")
	var route: Curve2D = rail.get_route_curve()
	for point in [Vector2(1300, 892), Vector2(3020, 1000), Vector2(3114, 1750)]:
		train._progress = route.get_closest_offset(point)
		train._update_pose()
		check(absf(angle_difference(train.locomotive.model.rotation.y, -train.global_rotation)) < 0.007, "Locomotiva gira a geometria 3D na direção do trilho")
		var previous: Vector2 = train.global_position
		for i in train._freight_visuals.size():
			var wagon = train._freight_visuals[i]
			check(wagon.global_position.distance_to(rail.to_global(route.sample_baked(train._wagon_offset(i), true))) < 0.01, "Vagão segue seu próprio ponto da curva")
			check(absf(wagon.global_rotation) < 0.001, "A imagem 3D não gira como uma placa")
			var offset: float = train._wagon_offset(i)
			var tangent := route.sample_baked(offset, true).direction_to(route.sample_baked(fposmod(offset + 6.0, rail.get_route_length()), true))
			check(absf(angle_difference(wagon.model.rotation.y, -tangent.angle())) < 0.007, "Cada modelo 3D acompanha a tangente do seu vagão")
			check(previous.distance_to(wagon.global_position) < 73.0, "Engates permanecem próximos nas curvas")
			check(train._rail_sounds[i + 1].global_position.distance_to(wagon.global_position) < 0.01, "Som acompanha o vagão")
			previous = wagon.global_position
	player.position = Vector2(1300, 892)
	rail._process(0.1)
	check(rail._reveal_amount > 0.0 and rail._reveal_amount < 1.0, "Transparência aparece gradualmente")
	rail._process(0.3)
	check(is_equal_approx(rail._reveal_amount, 1.0), "Pedestre sob o viaduto fica visível")
	player.position.y += 180.0
	rail._process(0.3)
	check(is_zero_approx(rail._reveal_amount), "Viaduto volta ao normal após a saída")
	var car := DrivenCar.new()
	car.add_to_group("vehicle")
	car.position = Vector2(1700, 892)
	world.add_child(car)
	rail._process(0.3)
	check(rail._reveal_position == car.position and rail._reveal_radius >= 96.0 and rail._reveal_amount == 1.0, "Carro dirigido recebe abertura maior")
	player.set_meta("harbor_interior", true)
	rail._process(0.3)
	check(rail._reveal_amount == 0.0, "Interiores não abrem transparência na ferrovia")
	player.remove_meta("harbor_interior")
	car.is_driven_by_player = false
	player.position = Vector2(3114, 3300)
	rail._process(0.3)
	check(rail._reveal_amount == 0.0, "Trecho no chão não se torna atravessável visualmente")
	train._progress = rail._visible_end + 25.0
	train._update_pose()
	check(train.locomotive.modulate.a == 0.0, "Locomotiva desaparece dentro do túnel")
	check(train._freight_visuals[0].modulate.a > 0.9, "Vagão fora do túnel permanece visível")
	train._update_train_audio(1.0)
	check(train._rail_sounds[0].volume_db < -60.0 and train._rail_sounds[1].volume_db > -30.0, "Só a peça enterrada perde o som de trilho externo")
	train._progress = rail._visible_start + 25.0
	train._update_pose()
	train._update_train_audio(0.1)
	check(train._horn.playing, "Buzina anuncia a saída do túnel")
	train._update_train_audio(0.1)
	check(train._horn_cooldown > 17.0, "Buzina tem intervalo contra repetição")
	train.speed = 0.0
	train._update_train_audio(1.0)
	check(train._rail_sounds[0].volume_db < -60.0, "Rodas paradas não fazem som de movimento")
	var bank = train._audio_bank
	for kind in ["diesel", "rail", "bridge", "curve", "horn"]:
		var sound: AudioStreamWAV = bank.sound(kind)
		check(sound.data.size() == 88200, "Áudio PCM completo: " + kind)
		check(sound == bank.sound(kind), "Áudio reutiliza o mesmo recurso: " + kind)
		var peak := 0
		for index in range(0, sound.data.size(), 2):
			peak = maxi(peak, absi(sound.data.decode_s16(index)))
		check(peak > 1000 and peak < 32767, "Som audível sem saturação PCM: " + kind)
	world.queue_free()
	await process_frame
	print("HARBOR_TRAIN_3D failures=%d" % failures)
	quit(1 if failures else 0)
