extends "res://tests/test_vehicle_glass_damage.gd"
## Real audio players and particle pools: no sound/effect stubs can hide a broken event chain.
const AUDIO := preload("res://gameplay/CombatAudio.gd")
class ActualCombat extends "res://gameplay/Gameplay.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		_setup_combat_audio()
		effects = preload("res://gameplay/CombatEffects.gd").new()
		add_child(effects)
	func _damage(_actor: Object, _amount: float, _source: Node, _continuous: bool = false) -> void: pass
func run() -> void:
	var combat := ActualCombat.new()
	root.add_child(combat)
	var actor := CharacterBody3D.new()
	combat.add_child(actor)
	combat.player = actor
	var car := car_at("union_sedan",Vector3.ZERO)
	for tick in 3: await physics_frame
	var ray := ray_for(car,0)
	check(not ray.is_empty(),"production glazing found")
	if ray.is_empty(): car.free(); combat.free(); quit(1); return
	var bus := AudioServer.get_bus_index(AUDIO.WEAPON_BUS_NAME)
	check(bus >= 0 and AudioServer.get_bus_send(bus) == &"Master","Weapons has independent Master route")
	var limiter := AudioServer.get_bus_effect(bus,0) as AudioEffectHardLimiter
	check(limiter != null and limiter.pre_gain_db == 0.0,"firearms never inherit boosted SFX presence")
	var gain := AudioServer.get_bus_volume_db(bus)
	AUDIO.ensure_weapon_bus()
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus),gain) and AudioServer.get_bus_effect_count(bus) == 1,"bus setup never stacks gain or limiters")
	combat._shot_sound("pistol",preload("res://gameplay/WeaponCatalog.gd").get_weapon("pistol"))
	check(combat._weapon_pool.any(func(voice): return voice.playing and voice.bus == AUDIO.WEAPON_BUS_NAME),"real player shot plays on Weapons")
	check(not combat._audio_pool.any(func(voice): return voice.playing),"player gunshot cannot consume a surface-effect voice")
	var filler := AudioStreamWAV.new()
	filler.mix_rate = 22050
	filler.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(44100)
	filler.data = bytes
	for voice in combat._audio_pool + combat._weapon_pool:
		voice.stream = filler
		voice.play()
	check(combat._audio_pool.all(func(voice): return voice.playing) and combat._weapon_pool.all(func(voice): return voice.playing),"both ordinary sound pools are saturated")
	combat._shot_sound("pistol",preload("res://gameplay/WeaponCatalog.gd").get_weapon("pistol"))
	check(combat._weapon_pool.any(func(voice): return voice.playing and voice.stream != filler),"a current gunshot replaces an old tail at the fixed voice ceiling")
	var count := combat.get_child_count()
	var effect_count: int = combat.effects.get_child_count()
	combat._damage_bullet(car,25.0,actor,ray[0],ray[1])
	check(car.snapshot_glass().size() == 1,"real bullet broke one pane")
	check(combat._glass_audio_pool.any(func(voice): return voice.playing and voice.bus == &"SFX" and voice.stream.get_length() >= .8),"glass break plays despite saturated gunfire and effects")
	check(combat.effects._glass_shards.size() == 4,"four reusable glass showers bound simultaneous work")
	check(combat.effects._glass_shards.any(func(emitter): return emitter.emitting),"bullet emits actual glass fragments")
	var burst: CPUParticles3D = combat.effects._glass_shards[0]
	check(burst.amount >= 20 and burst.lifetime >= .8 and burst.gravity.y < -9.0 and not burst.local_coords,"glass fragments tumble and fall in world space")
	check(burst.mesh.size.x >= .04 and burst.mesh.size.z >= .06,"fragments have readable glass size rather than tiny impact chips")
	var serial: int = combat._glass_audio_next
	combat._damage_bullet(car,25.0,actor,Vector3(0,.3,-8),Vector3(0,.3,8))
	check(combat._glass_audio_next == serial,"hood shot does not emit a false glass break")
	var records: Array = car.snapshot_glass()
	car.restore_glass(records)
	check(combat._glass_audio_next == serial,"restoring damage remains silent")
	for i in 12: combat._play_glass_break(Vector3.ZERO)
	check(combat._glass_audio_pool.size() == 4 and combat.get_child_count() == count and combat.effects.get_child_count() == effect_count,"repeated glass events reuse fixed voices and emitters")
	combat.effects.clear()
	check(not combat.effects._glass_shards.any(func(emitter): return emitter.emitting),"effect reset stops every glass shower")
	car.free()
	combat.free()
	print("VEHICLE_GLASS_FEEDBACK checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
