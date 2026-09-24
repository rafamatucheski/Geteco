extends SceneTree

class RadioCar extends Node2D:
	var is_driven_by_player := true
	var radio_tracks: Array = []
	var radio_index := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var car := RadioCar.new()
	car.radio_tracks = preload("res://audio/living_city/LivingCityAudio.gd").stations()
	root.add_child(car)
	var audio := AudioStreamPlayer2D.new()
	car.add_child(audio)
	preload("res://audio/living_city/VehicleRadioReceiver.gd").attach(audio)
	audio.stream = car.radio_tracks[0]
	audio.play()
	await process_frame
	await process_frame
	var receiver = audio.get_node("RadioReceiver")
	var failures := 0
	if car.radio_tracks.size() != 12: failures += 1
	for stream in car.radio_tracks.slice(0, -1):
		if stream.get_length() < 120: failures += 1
	if is_instance_valid(receiver._notice): failures += 1
	# Wheel advances once per press, reverses, and wraps through radio off.
	for entry in [[MOUSE_BUTTON_WHEEL_UP, 1], [MOUSE_BUTTON_WHEEL_DOWN, 0], [MOUSE_BUTTON_WHEEL_DOWN, 11], [MOUSE_BUTTON_WHEEL_UP, 0]]:
		for down in [true, false]:
			var wheel := InputEventMouseButton.new()
			wheel.position = Vector2(700, 400)
			wheel.button_index = entry[0]
			wheel.pressed = down
			root.push_input(wheel)
			await process_frame
		if car.radio_index != entry[1]: failures += 1
		if audio.stream != car.radio_tracks[entry[1]]: failures += 1
		if not receiver._notice.visible: failures += 1
	# O mesmo receptor atende carros e motos: L1 volta, R1 avança.
	for entry in [[JOY_BUTTON_RIGHT_SHOULDER, 1], [JOY_BUTTON_LEFT_SHOULDER, 0]]:
		for down in [true, false]:
			var shoulder := InputEventJoypadButton.new()
			shoulder.button_index = entry[0]
			shoulder.pressed = down
			root.push_input(shoulder)
			await process_frame
		if car.radio_index != entry[1]: failures += 1
		if audio.stream != car.radio_tracks[entry[1]]: failures += 1
	await create_timer(2.0).timeout
	if not receiver._notice.visible: failures += 1
	await create_timer(1.2).timeout
	if receiver._notice.visible: failures += 1
	# Pausing and leaving a vehicle must release the wheel to other controls.
	paused = true
	var blocked_wheel := InputEventMouseButton.new()
	blocked_wheel.position = Vector2(700, 400)
	blocked_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	blocked_wheel.pressed = true
	root.push_input(blocked_wheel)
	if car.radio_index != 0: failures += 1
	paused = false
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/radio-controls.png")
	car.is_driven_by_player = false
	root.push_input(blocked_wheel)
	if car.radio_index != 0: failures += 1
	await process_frame
	await process_frame
	if receiver._notice.visible: failures += 1
	car.is_driven_by_player = true
	await process_frame
	await process_frame
	if receiver._notice.visible: failures += 1
	print("RADIO_CONTROLS: %d failures" % failures)
	car.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
