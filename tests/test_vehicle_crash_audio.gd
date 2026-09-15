extends SceneTree

const Bank = preload("res://audio/VehicleCrashAudio.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	assert(Bank.family(65.0, &"metal") == "bumper")
	assert(Bank.family(200.0, &"metal") == "metal")
	assert(Bank.family(200.0, &"concrete") == "solid")
	assert(Bank.family(420.0, &"concrete") == "heavy")
	for speed in [65.0, 200.0, 420.0]:
		assert(Bank.family(speed, &"metal", true) == "motorcycle")
		assert(Bank.family(speed, &"concrete", true) == "motorcycle")
	var digests: Array[int] = []
	for kind in ["bumper", "metal", "solid", "heavy", "motorcycle"]:
		var previous := PackedByteArray()
		for take in 4:
			var stream := Bank.sound(kind, take)
			assert(stream.format == AudioStreamWAV.FORMAT_16_BITS)
			assert(stream.mix_rate == Bank.RATE)
			assert(not stream.stereo)
			assert(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)
			assert(hash(stream.data) not in digests, "Duplicate recording edit")
			digests.append(hash(stream.data))
			assert(stream.data != previous, "Repeated take")
			previous = stream.data
			assert(abs(stream.data.decode_s16(0)) < 10)
			assert(abs(stream.data.decode_s16(stream.data.size() - 2)) < 10)
			var peak := 0
			for i in stream.data.size() / 2:
				var sample := stream.data.decode_s16(i * 2)
				peak = maxi(peak, abs(sample))
			assert(peak > 3000 and peak < 31000, "Invalid headroom")
	assert(Bank.sound("heavy").get_length() > Bank.sound("bumper").get_length() * 2.0)
	var owner := Node2D.new()
	var target := Node2D.new()
	root.add_child(owner)
	root.add_child(target)
	Bank.play(owner, target, Vector2(100, 200), 200.0)
	var player := root.get_child(root.get_child_count() - 1) as AudioStreamPlayer2D
	assert(player != null and player.global_position == Vector2(100, 200))
	var children := root.get_child_count()
	Bank.play(owner, target, Vector2.ZERO, 200.0)
	Bank.play(target, owner, Vector2.ZERO, 200.0)
	assert(root.get_child_count() == children, "Duplicate contact audio")
	# Audio is attached to the world, so destroying the car cannot cut off debris.
	owner.queue_free()
	await process_frame
	assert(is_instance_valid(player))
	player.queue_free()
	target.queue_free()
	await process_frame
	for bike_is_owner in [true, false]:
		var bike := Node2D.new()
		var car := Node2D.new()
		root.add_child(bike)
		root.add_child(car)
		bike.add_to_group("motorcycle")
		Bank.play(bike if bike_is_owner else car, car if bike_is_owner else bike, Vector2.ZERO, 420.0)
		var impact := root.get_child(root.get_child_count() - 1) as AudioStreamPlayer2D
		assert(impact != null and impact.stream in Bank.SAMPLES.motorcycle, "Either collision reporter selects glass-free motorcycle Foley")
		impact.queue_free()
		bike.queue_free()
		car.queue_free()
		await process_frame
	print("PASS: 20 recorded crash edits, PCM/headroom, boundaries, motorcycle contact in both directions, deduplication and world-space playback")
	quit()
