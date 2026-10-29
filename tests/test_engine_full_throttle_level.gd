extends SceneTree
## Arrancada real com acelerador cheio até a velocidade máxima: o volume do motor ao chegar no
## teto não pode cair em relação ao meio da arrancada (queixa do playtest 29/10: "o volume na
## aceleração final diminui e o barulho da aceleração é mais alto que ele").
## Mede o nível efetivo (soma de potência das vozes do EngineDesignVoice) e o pitch por segundo.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_engine_full_throttle_level.gd -- --no-save [--table]
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BANKS := preload("res://audio/EngineDesignBanks.gd")
const LEGACY_BANKS := preload("res://audio/EngineBankCache.gd")
const ARCHETYPES := ["sport_coupe", "muscle_classic", "american_dump_truck"]
## Diferença máxima aceita entre o melhor nível da arrancada e o nível sustentado no teto.
const MAX_DROP_DB := 2.5
var checks := 0
var failures: Array[String] = []

class Driving extends Node:
	var occupied := true
	var car: CharacterBody3D

class AudioWorld extends Node3D:
	var driving: Node
	var player: CharacterBody3D
	var session: Node

class WaterFixture extends Node3D:
	func clear_trail() -> void: pass

class Foreground extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		set_process(false)
		radio = AudioStreamPlayer.new()
		add_child(radio)
		for index in 7:
			var voice := AudioStreamPlayer.new()
			add_child(voice)
			layers.append(voice)
		road_audio = AudioStreamPlayer.new()
		shift_audio = AudioStreamPlayer.new()
		air_brake_audio = AudioStreamPlayer.new()
		for voice in [road_audio, shift_audio, air_brake_audio]: add_child(voice)
		water_steps = WaterFixture.new()
		add_child(water_steps)
	func _update_ambience(_delta: float) -> void: pass
	func _update_radio(_delta: float) -> void: pass

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func(): push_error("ENGINE_FULL_THROTTLE timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

## Nível total em dB (soma de potência) e pitch do motor mais alto.
func voice_level(voice: Node3D) -> Dictionary:
	var power := 0.0
	var pitch := 0.0
	var loaded := 0.0
	for i in voice._players.size():
		var p: AudioStreamPlayer3D = voice._players[i]
		if not p.playing: continue
		var linear := db_to_linear(p.volume_db)
		power += linear * linear
		pitch = maxf(pitch, p.pitch_scale)
		if i < 2: loaded += linear * linear
	return {"db": linear_to_db(sqrt(maxf(power, 1e-9))), "pitch": pitch, "loaded_share": loaded / maxf(power, 1e-9)}

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not BANKS.enabled(): quit(2); return
	var table := "--table" in OS.get_cmdline_user_args()
	await LEGACY_BANKS.prewarm(self)
	await BANKS.prewarm(self)
	for archetype in ARCHETYPES:
		var world := AudioWorld.new()
		root.add_child(world)
		var ground := StaticBody3D.new()
		ground.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40, .2, 6000)
		shape.shape = box
		ground.add_child(shape)
		ground.position = Vector3(0, -.1, -2900)
		world.add_child(ground)
		var car := VEHICLE.new()
		car.archetype = archetype
		world.add_child(car)
		car.place(Vector3(0, .04, 0), 0)
		car.set_physics_process(false)
		car.controlled = true
		world.player = CharacterBody3D.new()
		world.add_child(world.player)
		world.driving = Driving.new()
		world.driving.car = car
		world.add_child(world.driving)
		var foreground := Foreground.new()
		foreground.world = world
		world.add_child(foreground)
		Input.action_press("accelerate")
		var delta := 1.0 / 60.0
		var samples: Array[Dictionary] = []
		var reached_cap := -1.0
		var speed_before := 0.0
		for frame in int(90.0 / delta):
			car._physics_process(delta)
			foreground._process(delta)
			var t := frame * delta
			var voice: Node3D = foreground.design_voice if is_instance_valid(foreground.design_voice) else null
			if voice == null: continue
			var level := voice_level(voice)
			var drive: RefCounted = car.get_meta("desert_powertrain") if car.has_meta("desert_powertrain") else null
			level["t"] = t
			level["speed"] = car.speed
			level["cap"] = car.max_forward_speed
			level["gear"] = int(drive.gear) if drive != null else foreground.engine_gear
			level["rpm"] = float(drive.rpm) if drive != null else foreground.engine_rpm
			level["limiter"] = bool(drive.limiter) if drive != null else false
			level["load"] = float(drive.throttle) if drive != null else foreground.engine_load
			samples.append(level)
			# Teto = perto do limite da rua ou velocidade estável (o caminhão V1 estabiliza antes do limite).
			if reached_cap < 0.0 and (car.speed >= car.max_forward_speed * .97 or (t > 4.0 and frame % 60 == 0 and absf(car.speed - speed_before) < .05)): reached_cap = t
			if frame % 60 == 0: speed_before = car.speed
			if reached_cap >= 0.0 and t > reached_cap + 6.0: break
			if t > 70.0: break
		Input.action_release("accelerate")
		check(reached_cap > 0.0, archetype + ": chega à velocidade máxima (cap=" + str(snappedf(car.max_forward_speed, .1)) + ", v=" + str(snappedf(car.speed, .1)) + ")")
		if table:
			for i in range(0, samples.size(), 60):
				var s: Dictionary = samples[i]
				print("ENGINE_FT ", archetype, " t=", snappedf(s.t, .1), " v=", snappedf(s.speed, .1), " gear=", s.gear, " rpm=", int(s.rpm),
					" lim=", s.limiter, " load=", snappedf(s.load, .01), " db=", snappedf(s.db, .1), " pitch=", snappedf(s.pitch, .01), " loaded=", snappedf(s.loaded_share, .01))
		# Referência: melhor nível na aceleração (antes de chegar no teto); sustentado: os 3 últimos segundos.
		var best := -100.0
		var sustained := 0.0
		var count := 0
		for s in samples:
			if reached_cap < 0.0 or s.t < reached_cap: best = maxf(best, s.db)
			elif s.t > reached_cap + 3.0:
				sustained += s.db
				count += 1
		if count > 0:
			sustained /= count
			print("ENGINE_FT_SUMMARY ", archetype, " cap_at=", snappedf(reached_cap, .1), " best_accel_db=", snappedf(best, .1), " sustained_db=", snappedf(sustained, .1), " drop=", snappedf(best - sustained, .1))
			check(best - sustained <= MAX_DROP_DB, archetype + ": nível sustentado no teto fica a até %.1f dB do melhor da arrancada (queda %.1f dB)" % [MAX_DROP_DB, best - sustained])
		world.queue_free()
		await process_frame
	print("ENGINE_FULL_THROTTLE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
