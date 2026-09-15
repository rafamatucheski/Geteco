extends "res://tests/measure_city_scenarios.gd"
## Fixed production checkpoint, ten real flame/grenade/RPG impacts in 30 seconds.
var next_hit := 0
var hits := 0

func _report_render() -> void:
	super._report_render()
	if not _tracking or Time.get_ticks_msec() < next_hit: return
	next_hit = Time.get_ticks_msec() + 3000
	var person = load("res://characters/AnimatedPedestrian3D.gd").new()
	person.position = _subject.global_position + Vector2(90, 35)
	current_scene.add_child(person)
	person.ensure_presentation()
	person.set_physics_process(false)
	if hits % 3 == 0:
		var flame = load("res://guns/FlameJet.tscn").instantiate()
		flame.position = person.position - Vector2(55, 0)
		current_scene.add_child(flame)
		flame.setup(flame.position, Vector2.RIGHT, _subject)
	elif hits % 3 == 1:
		var grenade = load("res://guns/GrenadeProjectile.tscn").instantiate()
		grenade.position = person.position + Vector2(8, 0)
		current_scene.add_child(grenade)
		grenade.setup(grenade.position, Vector2.ZERO, 0, _subject)
		grenade.current_fuse = 0.1
	else:
		var rocket = load("res://guns/Bullet.tscn").instantiate()
		rocket.position = person.position - Vector2(45, 0)
		rocket.is_explosive = true
		rocket.damage = 200
		rocket.owner_body = _subject
		rocket.direction = Vector2.RIGHT
		current_scene.add_child(rocket)
	hits += 1
