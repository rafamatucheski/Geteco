extends SceneTree
## Embarque na moto do lado esquerdo e do direito, quadro a quadro: o quadril do piloto não pode
## saltar entre o fim da apresentação e a pose montada (relato de 13/10: "teletransportado para o
## outro lado"), e o farol tem de acompanhar a moto quando ela empina.
## Fixture mínima (sem Main, trânsito ou save): mede a cadeia Driving → apresentação → pose montada.
const ACTOR := preload("res://scripts/Actor.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DRIVING := preload("res://scripts/Driving.gd")
class Fixture extends Node3D:
	var player
	var camera := Node3D.new()
	var production = null
	var hud := Control.new()
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("BIKE_BOARDING ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func hips_world(actor) -> Vector3:
	return actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin)

## Maior salto entre quadros visíveis do quadril, das mãos e do rumo do corpo. Compara também
## através do trecho em que a apresentação esconde o corpo: o último quadro visível antes de
## sumir contra o primeiro depois é exatamente onde um "teletransporte" aparece.
## A apresentação anda por tempo real: um quadro lento (máquina ocupada) anda mais. O salto é
## dividido pelo número de quadros de 60 Hz que aquele quadro durou; teletransporte não encolhe.
class Track:
	var hips := 0.0
	var palm := 0.0
	var turn := 0.0
	var at := ""
	var palm_at := ""
	var turn_at := ""
	var _hips := Vector3.INF
	var _facing := Vector3.ZERO
	var _palms := {}
	var _clock := 0
	func sample(actor, label: String) -> void:
		var now := Time.get_ticks_usec()
		var frames := maxf(1.0, float(now - _clock) / 16667.0) if _clock > 0 else 1.0
		_clock = now
		if not actor.is_visible_in_tree(): return
		var point: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin)
		var facing: Vector3 = actor.visual.global_basis.z
		facing.y = 0
		facing = facing.normalized()
		if _hips.is_finite():
			if point.distance_to(_hips) / frames > hips:
				hips = point.distance_to(_hips) / frames
				at = label
			if rad_to_deg(_facing.angle_to(facing)) / frames > turn:
				turn = rad_to_deg(_facing.angle_to(facing)) / frames
				turn_at = label
			for hand in ["Left", "Right"]:
				if actor.combat_palm_position(hand).distance_to(_palms[hand]) / frames > palm:
					palm = actor.combat_palm_position(hand).distance_to(_palms[hand]) / frames
					palm_at = label
		_hips = point
		_facing = facing
		for hand in ["Left", "Right"]: _palms[hand] = actor.combat_palm_position(hand)

func judge(track: Track, label: String) -> void:
	print("BIKE_BOARDING_SAMPLE ", label, " hips=", snappedf(track.hips, .001), " at ", track.at, " palm=", snappedf(track.palm, .001), " at ", track.palm_at, " turn_deg=", snappedf(track.turn, .1), " at ", track.turn_at)
	# Um quadro a 60 Hz anda no máximo uns 8 cm; 20 cm entre quadros é salto, não movimento.
	check(track.hips < .20, "%s hips never jump between frames (%.3f m)" % [label, track.hips])
	check(track.palm < .30, "%s hands never jump between frames (%.3f m)" % [label, track.palm])
	check(track.turn < 25.0, "%s body never flips heading between frames (%.1f deg)" % [label, track.turn])

func run() -> void:
	# --unbatched compara com a hierarquia original das motos (peças soltas), sem trocar arquivos.
	if "--unbatched" in OS.get_cmdline_user_args(): preload("res://runtime/RedesignedFleet.gd").enabled = false
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.add_child(fixture.camera)
	var help := Label.new()
	help.name = "Help"
	fixture.hud.add_child(help)
	fixture.add_child(fixture.hud)
	for id in ["bike_urban", "bike_sport", "bike_cruiser"]:
		for side in [-1, 1]:
			var player = ACTOR.new()
			player.is_player = true
			fixture.player = player
			fixture.add_child(player)
			player.set_physics_process(false)
			var bike = VEHICLE.new()
			bike.archetype = id
			fixture.add_child(bike)
			bike.set_physics_process(false)
			bike.rotation.y = .71
			var driving = DRIVING.new()
			driving.world = fixture
			fixture.add_child(driving)
			driving.set_physics_process(false)
			player.teleport(bike.driver_door_anchor(side))
			await process_frame
			driving.car = bike
			driving.occupied = true
			driving._start_boarding(side)
			var entry := Track.new()
			var frame := 0
			var mounted_frames := 0
			for i in 400:
				await process_frame
				frame += 1
				# Depois da entrada o Driving segue a moto no physics_process; aqui um passo manual por quadro.
				if driving.transition == null and bike.controlled:
					driving._update_mounted_player()
					mounted_frames += 1
				# O Actor da fixture nasce na pose de repouso, sem andar; no jogo ele chega caminhando.
				# Os dois primeiros quadros só trocam essa pose pelo ciclo de caminhada.
				if frame > 2: entry.sample(player, "frame %d %s" % [frame, driving.transition.phase if driving.transition != null else "mounted"])
				if mounted_frames > 4: break
			check(mounted_frames > 0, "%s side %d boarding completes" % [id, side])
			var label := "%s side %d entry" % [id, side]
			judge(entry, label)
			var seated: Vector3 = bike.to_local(hips_world(player))
			check(absf(seated.x) < .12, "%s mounted hips centred on the saddle (x=%.3f)" % [label, seated.x])
			var holds: Dictionary = bike.motorcycle_handholds()
			check(holds.has("Left") and holds.has("Right"), "%s mounted pose has both grips" % label)
			# Saída parada pelo mesmo lado, como Driving.leave (sem raycasts de exit_position).
			bike.controlled = false
			bike.input_locked = true
			player.visual.rotation = Vector3(0, bike.global_rotation.y, 0)
			var exit_track := Track.new()
			exit_track.sample(player, "mounted")
			var transition = preload("res://gameplay/VehicleBoardingPresentation.gd").new()
			driving.add_child(transition)
			var landing: Vector3 = bike.to_global(Vector3(side * (bike.half_width + .61), 0, bike._cab_z()))
			transition.begin_exit(fixture, bike, player, landing, side)
			var exited := false
			for i in 400:
				exit_track.sample(player, "exit frame %d %s" % [i, transition.phase if is_instance_valid(transition) else "done"])
				if not is_instance_valid(transition):
					exited = true
					break
				await process_frame
			check(exited, "%s side %d dismount completes" % [id, side])
			judge(exit_track, "%s side %d exit" % [id, side])
			driving.queue_free()
			bike.queue_free()
			player.queue_free()
			await process_frame
	# O projetor do farol pertence à moto apresentada: empinar ou tombar a carroceria leva o feixe junto.
	for id in ["bike_urban", "bike_sport", "bike_cruiser"]:
		var bike = VEHICLE.new()
		bike.archetype = id
		fixture.add_child(bike)
		bike.set_physics_process(false)
		var equipment = bike.ensure_equipment(fixture)
		await process_frame
		var lamp: Node3D = equipment.lamps[0].lamp
		var lens_local: Vector3 = bike.visual.to_local(lamp.global_position)
		bike.visual.transform = Transform3D(Basis(Vector3.RIGHT, .45), Vector3(0, .3, 0)) * bike.visual.transform
		var drift: float = lamp.global_position.distance_to(bike.visual.to_global(lens_local))
		check(drift < .01, "%s headlight follows the pitched bike (%.3f m)" % [id, drift])
		bike.reset_motorcycle_wheelie()
		bike.queue_free()
		await process_frame
	fixture.queue_free()
	await process_frame
	print("BIKE_BOARDING_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
