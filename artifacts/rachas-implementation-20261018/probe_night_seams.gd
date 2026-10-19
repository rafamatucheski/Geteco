extends "res://tests/test_drag_night_session.gd"
## Read-only instrumentation of the real Main + ranked 800 m session.
## Run the inherited test with --no-save --drive; no physics/gameplay overrides
## are introduced beyond those already owned by the parent fixture.
var _seam_previous: Dictionary = {}
var _seam_last_physics_frame := -1
var _seam_drop_count := 0

func _process(_delta: float) -> bool:
	if not is_instance_valid(world) or world.session == null:
		return false
	if world.session.desert == null:
		return false
	var race = world.session.desert.drag
	if not is_instance_valid(race) or not race.active or race.phase != "racing":
		_seam_previous.clear()
		return false
	var physics_frame := Engine.get_physics_frames()
	if physics_frame == _seam_last_physics_frame:
		return false
	_seam_last_physics_frame = physics_frame
	for index in race.racers.size():
		var entry: Dictionary = race.racers[index]
		var car = entry.car
		if not is_instance_valid(car):
			continue
		var drive = entry.drive
		var key: int = car.get_instance_id()
		var sample := {
			"racer_index": index,
			"car": str(car.get_path()),
			"physics_frame": physics_frame,
			"race_elapsed": float(race.elapsed),
			"position": _seam_vector(car.global_position),
			"speed_mps": float(drive.speed_mps),
			"rpm": float(drive.rpm),
			"gear": int(drive.gear),
			"shift_remaining": float(drive.shift_remaining),
			"torque_factor": float(drive.shift_torque_factor),
			"throttle": float(drive.throttle),
			"nitro_active": bool(drive.nitro_active),
			"velocity": _seam_vector(car.velocity),
			"real_velocity": _seam_vector(car.get_real_velocity()),
			"on_floor": bool(car.is_on_floor()),
			"half_length": float(car.half_length),
			"safe_margin": float(car.safe_margin),
			"slide_count": int(car.get_slide_collision_count()),
		}
		if _seam_previous.has(key):
			var previous: Dictionary = _seam_previous[key]
			var drop: float = float(previous.speed_mps) - float(sample.speed_mps)
			if float(sample.race_elapsed) > float(previous.race_elapsed) and drop > 5.0:
				_seam_drop_count += 1
				var contacts: Array[Dictionary] = []
				for slide_index in car.get_slide_collision_count():
					var contact: KinematicCollision3D = car.get_slide_collision(slide_index)
					for collision_index in contact.get_collision_count():
						var collider: Object = contact.get_collider(collision_index)
						var collider_path := "<freed>"
						if is_instance_valid(collider):
							collider_path = str(collider.get_path()) if collider is Node else str(collider)
						contacts.append({
							"slide": slide_index,
							"contact": collision_index,
							"collider": collider_path,
							"collider_id": contact.get_collider_id(collision_index),
							"collider_shape_index": contact.get_collider_shape_index(collision_index),
							"normal": _seam_vector(contact.get_normal(collision_index)),
							"point": _seam_vector(contact.get_position(collision_index)),
							"travel": _seam_vector(contact.get_travel()),
							"remainder": _seam_vector(contact.get_remainder()),
						})
				print("SEAM_PROBE ", JSON.stringify({
					"drop_number": _seam_drop_count,
					"drop_mps": drop,
					"sampled_physics_frames": int(sample.physics_frame) - int(previous.physics_frame),
					"before": previous,
					"after": sample,
					"slide_collisions": contacts,
				}))
		_seam_previous[key] = sample
	return false

func _seam_vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func finish() -> void:
	check(_seam_drop_count == 0, "no abrupt physical deceleration during the four real passes")
	super.finish()

