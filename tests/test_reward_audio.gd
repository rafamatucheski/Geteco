extends SceneTree

const BANK := preload("res://audio/rewards/RewardAudioBank.gd")
var failures: Array[String] = []

class TestCar extends Node2D:
	var is_driven_by_player := true
	var is_broken := false
	var velocity := Vector2.ZERO

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	for kind in BANK.STREAMS:
		var stream := BANK.sound(kind)
		check(stream.stereo and stream.mix_rate == 48000 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, kind + ": stereo 48 kHz one-shot")
		check(stream == BANK.sound(kind) and stream.get_length() > .2, kind + ": cached and audible duration")
	check(BANK.sound("achievement") != ProceduralAudio.get_mission_passed_stream(), "Achievement and completion have separate cues")
	check(is_equal_approx(ProceduralAudio.get_mission_passed_stream().get_length(), 4.0), "Mission completion lasts exactly four seconds")
	var completion_file := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/rewards/complete.wav"))
	check(completion_file != null and completion_file.data == BANK.sound("complete").data, "Imported completion matches the current edited audio file")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var pickup := Node.new()
	world.add_child(pickup)
	BANK.play(pickup, "pickup")
	var pool := world.get_node("RewardAudioVoices")
	var first := pool.get_child(0) as AudioStreamPlayer
	var original := first.stream
	for i in 20: BANK.play(pickup, "pickup")
	var playing := 0
	for voice in pool.get_children():
		if voice.playing: playing += 1
	check(playing == 1, "A same-frame pile of loot produces one cue")
	pickup.queue_free()
	await process_frame
	check(first.playing and first.bus == &"SFX", "Pickup tail survives consumed item and respects SFX bus")
	# Force elapsed debounce without waiting for wall-clock time in the test.
	pool.set_meta("last_pickup", -1000)
	BANK.play(world, "pickup")
	check(pool.get_child(1).stream != original, "Repeated pickups alternate authored takes")
	for kind in ["cash", "weapon", "collectible", "checkpoint", "complete"]:
		BANK.play(world, kind)
	check(pool.get_child_count() == BANK.VOICES, "Mixed reward bursts use a bounded voice pool")
	var race = load("res://cars/NightRaceController.gd").new()
	race.setup({"checkpoints": [Vector2(200, 0), Vector2(400, 0)]})
	world.add_child(race)
	race.set_process(false)
	var car := TestCar.new()
	world.add_child(car)
	car.position = Vector2(300, 0)
	race._active_car = car
	race._state = race.State.RUNNING
	race._previous_position = Vector2(100, 0)
	pool.set_meta("last_checkpoint", -1000)
	race._process(.016)
	var heard_checkpoint := false
	for voice in pool.get_children():
		if voice.playing and voice.stream == BANK.sound("checkpoint"): heard_checkpoint = true
	check(race._next_checkpoint_index == 1 and heard_checkpoint, "Crossing a real race gate triggers the checkpoint cue")
	var hud = load("res://HUD.tscn").instantiate()
	world.add_child(hud)
	hud.show_achievement("Teste", "Conquista")
	check(hud._achievement_audio.stream == BANK.sound("achievement") and hud._achievement_audio.pitch_scale == 1.0, "HUD plays authored achievement at its original pitch")
	world.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(pool), "Scene teardown releases voices")
	# Let the audio mix thread retire stopped playbacks before process exit.
	await create_timer(0.2).timeout
	print("REWARD_AUDIO failures=", failures)
	quit(0 if failures.is_empty() else 1)
