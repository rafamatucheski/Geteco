extends RefCounted
## Reversible station choreography using Dante's real skeleton, in the main world.
const SECONDS := 3.4

static func present(park, seconds: float, exiting: bool, _delta: float) -> void:
	var actor = park.world.player
	var dock: Transform3D = park.site.sample_coaster(0)
	var t := clampf(seconds,0,SECONDS)
	var open := smoothstep(0,.30,t)*(1.0-smoothstep(2.5,2.85,t))
	park.site.set_boarding_open(open)
	actor.global_basis = Basis.IDENTITY
	actor.visual.position = Vector3.ZERO
	actor.visual.rotation = Vector3.ZERO
	var start: Vector3 = park._saved.point
	var stand := Vector3(dock.origin.x+1.8,start.y,dock.origin.z+.35)
	var walk := smoothstep(.30,1.6,t)
	var step := smoothstep(1.6,2.5,t)
	actor.global_position = start.lerp(stand,walk)
	var direction := stand-start
	if exiting: direction = -direction
	var heading := atan2(-direction.x,-direction.z)
	actor.visual.rotation.y = lerp_angle(float(park._saved.heading) if not exiting else heading,heading,walk)
	if is_instance_valid(actor.animation):
		actor._pose_cycle("Walking",(SECONDS-t if exiting else t)*1.8,actor.WALK_START)
		var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
		hip.x = actor.hip_rest.x
		hip.z = actor.hip_rest.z
		actor.skeleton.set_bone_pose_position(actor.hips,hip)
	if t >= 1.6:
		actor.global_position = stand.lerp(dock.origin+Vector3(0,.36,.35),step)
		actor.global_position.y = lerpf(stand.y,dock.origin.y+.36,smoothstep(0,.3,step))+sin(step*PI)*.12
		actor.visual.rotation.y = lerp_angle(-PI*.5 if exiting else PI*.5,0,step)
		var walking: Array = actor._capture_pose()
		var sit := smoothstep(.35,1.0,step)
		var pelvis: Vector3 = actor.pose_seated_base(.08)
		var offset: Vector3 = dock.origin+Vector3(0,.58,.35)-actor.global_position-pelvis
		actor.visual.position = offset
		actor.pose_seated_limbs({"Left":actor.to_local(dock*Vector3(-.22,.35,-.40)),"Right":actor.to_local(dock*Vector3(.22,.35,-.40))}, {})
		actor._apply_blend(walking,actor._capture_pose(),sit)
		actor.visual.position = offset*sit
	var station := Transform3D(Basis.IDENTITY,dock.origin+Vector3(4.0,2.1,2.6))
	station = station.looking_at(dock.origin+Vector3(1.6,1.0,.25),Vector3.UP)
	var eye := dock.translated_local(Vector3(0,1.15,-.35))
	if exiting: eye = park._saved.get("ride_eye",eye)
	var blend := smoothstep(2.85,SECONDS,t)
	park.view.global_transform = station.interpolate_with(eye,blend)
	# Keep Dante visible while stepping/sitting; the final head camera owns the ride.
	actor.visual.visible = bool(park._saved.visible) and blend < .65
	actor.reset_physics_interpolation()
