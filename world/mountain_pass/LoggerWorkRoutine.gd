extends RefCounted
const POSE = preload("res://world/mountain_pass/LoggerChopPose.gd")
var resident: CharacterBody2D
var working := false
var time := 0.0
var side := -1.0
var impact_cycle := -1
var shared := false

func configure(actor: CharacterBody2D) -> void:
	resident = actor

func choose_position() -> Vector2:
	side = -side
	return resident.work_station.global_position + Vector2(side*13.0,0)

func stop() -> void:
	working = false
	time = 0.0
	impact_cycle = -1
	if not is_instance_valid(resident.model): return
	resident.model.work_pose_active = false
	if is_instance_valid(resident.model.chop_pose):
		resident.model.chop_pose.hide()
		for index in [1,3]: resident.model.limbs[index].show()
	if not shared: return
	shared = false
	var station: Node2D = resident.work_station
	if not is_instance_valid(station) or not is_instance_valid(station.model): return
	station.model.reparent(station.viewport_3d,false)
	station.model.transform = Transform3D.IDENTITY
	station.sprite_3d.show()
	station.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func update(delta: float) -> void:
	var station: Node2D = resident.work_station
	if not is_instance_valid(station) or not is_instance_valid(station.model):
		stop()
		return
	# A push, interruption or blocked approach must never turn into an off-target chop.
	if resident.global_position.distance_to(resident.destination) > .5:
		stop()
		resident.activity = "walk"
		resident._return_to_work = true
		resident.travel_time = 0.0
		return
	var yaw := PI*.5 if resident.global_position.x < station.global_position.x else -PI*.5
	resident.model.rotation.y = rotate_toward(resident.model.rotation.y,yaw,delta*3.0)
	if absf(angle_difference(resident.model.rotation.y,yaw)) > .015:
		resident.model.work_pose_active = false
		return
	resident.model.rotation.y = yaw
	if not shared:
		# The axe and wood share depth testing during work. Separate sprites cannot
		# represent a hand passing behind the log and a blade in front of it.
		station.model.reparent(resident.viewport,false)
		station.sprite_3d.hide()
		shared = true
		var pixel: Vector2 = resident.presentation_sprite.to_local(station.global_position)+Vector2(resident.viewport.size)*.5
		var camera: Camera3D = resident.presentation_camera
		var ray := camera.project_ray_normal(pixel)
		var origin := camera.project_ray_origin(pixel)
		station.model.position = origin-ray*(origin.y/ray.y)
		resident.model.work_target = resident.model.to_local(station.model.position+Vector3(0,.695,0))
	resident.model.work_pose_active = true
	if not working:
		working = true
		time = 0.0
		impact_cycle = -1
	time += delta
	resident.model.work_time = time
	var cycle := int(floor((time-POSE.CONTACT_TIME)/POSE.DURATION))
	if cycle >= 0 and cycle > impact_cycle:
		impact_cycle = cycle
		station.model.chop()
		preload("res://audio/combat/CombatImpactAudio.gd").play_hit(resident,station.global_position,&"wood",18)
