extends SceneTree
## Bounded real collision validation, including protection and pool cleanup.
const AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
var checks := 0
var failures := 0
class StreetFixture extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		instance = self
		preload("res://scripts/Vehicle.gd").STREET.instance = self
		set_physics_process(false)
class Person extends CharacterBody3D:
	var dead := false
	var health := 100.0
	var visual: Node3D
	func _ready() -> void:
		collision_layer = 2
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3; capsule.height = 1.7
		shape.shape = capsule; shape.position.y = .86
		add_child(shape)
		visual = Node3D.new(); add_child(visual)
	func receive_damage(amount: float, _source = null) -> void: health -= amount
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at
	return body
func frames(count: int) -> void:
	for tick in count: await physics_frame
func pair_key(first: Node, second: Node) -> String:
	return "%d|%d" % [mini(first.get_instance_id(),second.get_instance_id()),maxi(first.get_instance_id(),second.get_instance_id())]
func recorded(pool, key: String) -> bool:
	return float(pool.contacts.get(key,{}).get("played",-1000.0)) >= 0.0
func run() -> void:
	var capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-capture="): capture_path = argument.trim_prefix("--audio-capture=")
	if not capture_path.is_empty() and DisplayServer.get_name() == "headless": quit(2); return
	var recording: AudioEffectRecord
	var capture_started_ms := 0
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,25.3,25.3)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	box(world, Vector3(0,-.1,0), Vector3(60,.2,60))
	var wall := box(world, Vector3(0,1,-5), Vector3(12,2,.4))
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	world.add_child(car)
	car.place(Vector3(0,.04,0),0)
	car.handling.reset()
	car.set_physics_process(false)
	check(not AUDIO.play_contact(car,wall,Vector3.ZERO,.2), "light contact suppressed")
	check(AUDIO.play_contact(car,wall,Vector3.ZERO,3), "parking collision has audio")
	var pool = AUDIO.pool(car)
	var light_volume: float = pool.voices[0].volume_db
	check(AUDIO.pool(car) == pool, "one pool per world")
	check(pool.voices.size() == AUDIO.MAX_VOICES, "voice pool bounded")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(pool.voices[0].bus)) == &"SFX" and pool.voices[0].unit_size == 32, "SFX bus and isometric attenuation")
	check(not AUDIO.play_contact(car,wall,Vector3.ZERO,3), "same contact does not repeat")
	await frames(8)
	check(not AUDIO.play_contact(car,wall,Vector3.ZERO,12), "pair cooldown survives short separation")
	await frames(30)
	check(AUDIO.play_contact(car,wall,Vector3.ZERO,18), "separated pair can hit again")
	check(pool.voices.any(func(voice): return voice.playing and voice.volume_db > light_volume), "strong impact is louder")
	for tick in 40:
		await physics_frame
		AUDIO.play_contact(car,wall,Vector3.ZERO,18)
	check(pool.played_count == 2, "sustained contact remains silent beyond cooldown")
	for voice in pool.voices: voice.stop()
	pool.contacts.clear(); pool.sources.clear()
	for material in ["metal", "wood", "glass", "flesh"]:
		wall.set_meta("impact_material", material)
		check(AUDIO.contact_kind(wall,200,false) == material, "authored material " + material)
		check(AUDIO.play_contact(car,wall,Vector3.ZERO,12,material,material), "stream for " + material)
		await frames(8)
	check(not AUDIO.play_contact(car,wall,Vector3(500,0,0),12), "distant contact culled before emission")
	for voice in pool.voices: voice.stop()
	pool.contacts.clear(); pool.sources.clear()
	for index in 30: pool.emit_contact(1000 + index, "stress%d" % index, Vector3.ZERO,12,"metal")
	check(pool.get_child_count() == AUDIO.MAX_VOICES and pool.dropped_count > 0, "stress cannot grow or saturate the pool")
	for index in 400: pool.emit_contact(1000, "crowd%d" % index, Vector3.ZERO,12,"metal")
	check(pool.contacts.size() <= AUDIO.MAX_CONTACTS, "rejected contacts cannot grow the cooldown table")
	for voice in pool.voices: voice.stop()
	pool.contacts.clear(); pool.sources.clear()
	var before: int = pool.played_count
	wall.set_meta("impact_material","concrete")
	if not capture_path.is_empty():
		recording = AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(pool.bus_name),recording)
		recording.set_recording_active(true)
		capture_started_ms = Time.get_ticks_msec()
	car.set_external_driver(true)
	car.speed = 12
	car.horizontal_velocity = Vector3(0,0,-12)
	car.set_physics_process(true)
	await frames(40)
	car.set_physics_process(false)
	check(pool.played_count > before and recorded(pool,pair_key(car,wall)), "real move_and_slide wall collision reaches audio")
	print("CONTACT_PHYSICAL wall emissions=",pool.played_count-before," capture_ms=",Time.get_ticks_msec()-capture_started_ms)
	# Car-to-car uses the established crash fixture in test_vehicle_contact_collision.
	var street := StreetFixture.new()
	world.add_child(street)
	wall.position.x = 30
	pool.contacts.clear(); pool.sources.clear()
	await frames(8)
	var fragile := preload("res://gameplay/street_physics/FragileProps3D.gd")
	var post := Node3D.new()
	world.add_child(post)
	post.position = Vector3(0,0,-3)
	fragile.register_node("lamp",post,world)
	var items: Array = fragile.query(post.position,1)
	car.place(Vector3(0,.04,0),0)
	car.speed = 8
	car.horizontal_velocity = Vector3(0,0,-8)
	before = pool.played_count
	car.set_physics_process(true)
	for tick in 20:
		await physics_frame
		if not items.is_empty() and items[0].state == "down": break
	car.set_physics_process(false)
	check(not items.is_empty() and items[0].state == "down" and pool.played_count > before and recorded(pool,"prop|" + str(Vector3i((post.position * 2.0).round()))), "vehicle pre-move topples registered post and emits audio")
	print("CONTACT_PHYSICAL post emissions=",pool.played_count-before," capture_ms=",Time.get_ticks_msec()-capture_started_ms)
	fragile.cells.clear()
	pool.contacts.clear(); pool.sources.clear()
	await frames(8)
	var person := Person.new()
	world.add_child(person)
	person.position = Vector3(0,.04,-2.7)
	car.place(Vector3(0,.04,0),0)
	street._people_cache = [person]
	car.velocity = Vector3(0,0,-12)
	car.speed = 12
	car.horizontal_velocity = Vector3(0,0,-12)
	before = pool.played_count
	car.set_physics_process(true)
	for tick in 20:
		await physics_frame
		if person.has_node("BodyFlight3D"): break
	car.set_physics_process(false)
	check(person.has_node("BodyFlight3D") and pool.played_count > before and recorded(pool,pair_key(car,person)), "vehicle pre-move atropelamento reaches flesh audio")
	print("CONTACT_PHYSICAL person emissions=",pool.played_count-before," capture_ms=",Time.get_ticks_msec()-capture_started_ms)
	if person.has_node("BodyFlight3D"): person.get_node("BodyFlight3D").free()
	person.collision_layer = 2; person.collision_mask = 7
	person.remove_meta("street_down")
	person.remove_meta("street_flying")
	person.position = Vector3(0,.04,-2.7)
	person.set_meta("invulnerable",true)
	car.remove_collision_exception_with(person)
	car.place(Vector3(0,.04,0),0)
	car.speed = 12
	car.horizontal_velocity = Vector3(0,0,-12)
	car.set_physics_process(true)
	await frames(20)
	car.set_physics_process(false)
	check(not person.has_node("BodyFlight3D") and person.health == 100, "protected person remains untouched by audio hooks")
	if recording != null:
		await create_timer(2.0).timeout
		recording.set_recording_active(false)
		recording.get_recording().save_to_wav(capture_path)
		print("CONTACT_AUDIO_CAPTURE ",capture_path," physical wall, post and person; excludes direct emitter stress")
	pool.contacts.clear(); pool.sources.clear()
	before = pool.played_count
	street.play_prop_hit(Vector3.ZERO,"metal",8)
	street.play_prop_hit(Vector3.ZERO,"metal",8)
	check(pool.played_count == before + 1, "prop contacts share suppression")
	var pool_bus: String = pool.bus_name
	var old_pool: WeakRef = weakref(pool)
	world.queue_free()
	await process_frame
	check(old_pool.get_ref() == null and AudioServer.get_bus_index(pool_bus) == -1, "world unload releases every voice and pair")
	print("CONTACT_AUDIO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
