extends SceneTree
## Só contratos de enquadramento; a revisão renderizada no Main continua necessária para a oclusão.
const RACE = preload("res://activities/desert_drag/DesertDrag.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	root.size = Vector2i(1280,720)
	var race = RACE.new()
	root.add_child(race)
	race.set_physics_process(false)
	race.set_process(false)
	var camera := Camera3D.new()
	camera.fov = 57
	root.add_child(camera)
	for forward in [Vector3.RIGHT,Vector3.FORWARD,Vector3(1,0,1).normalized()]:
		race.direction = forward
		race.start_point = Vector3(120,6,-40)
		var side: Vector3 = forward.cross(Vector3.UP).normalized()
		var a: Vector3 = race.grid(0).origin
		var b: Vector3 = race.grid(1).origin
		race.phase = "staging"
		race.elapsed = 0.0
		var rear: Dictionary = race.start_camera_frame(a,b)
		race.phase="preparing"
		check(race.start_camera_frame(a,b).position.is_equal_approx(rear.position),"preparation joins countdown at the same rear camera pose")
		race.phase="staging"
		check((rear.position-rear.target).dot(forward)<-14.0 and rear.position.y-rear.target.y>9.0,"countdown starts elevated behind grid for "+str(forward))
		for seconds in [3.0,2.0,1.0,.01]:
			race.countdown = seconds
			check(race.start_camera_frame(a,b).position.is_equal_approx(rear.position),"camera holds rear view until green")
		camera.global_position = rear.position
		camera.look_at(rear.target,Vector3.UP)
		var visible := root.get_visible_rect().grow(-55)
		for point in [a+Vector3.UP*.7,b+Vector3.UP*.7,race.start_point+side*6.2+Vector3.UP*2.65,race.start_point+side*6.2+Vector3.UP*1.73]:
			check(not camera.is_position_behind(point) and visible.has_point(camera.unproject_position(point)),"both cars and full starting tree project inside countdown view")
		race.phase = "racing"
		check(race.start_camera_frame(a,b).position.is_equal_approx(rear.position),"green begins at the same pose without a cut")
		for hz in [30,60,120]:
			var previous: Vector3 = rear.position
			var old_lateral: float = (rear.position-rear.target).dot(side)
			for tick in int(2.1*hz)+1:
				race.elapsed = float(tick)/float(hz)
				var frame: Dictionary = race.start_camera_frame(a,b)
				var lateral: float = (frame.position-frame.target).dot(side)
				check(frame.position.distance_to(previous)<.8,"continuous camera sweep at %d Hz"%hz)
				check(lateral>=old_lateral-.001,"sweep advances toward side without reversal")
				check(Vector2((frame.position-frame.target).x,(frame.position-frame.target).z).length()>16.0,"sweep preserves framing radius")
				camera.global_position = frame.position
				camera.look_at(frame.target,Vector3.UP)
				for point in [a+Vector3.UP*.7,b+Vector3.UP*.7]:
					check(not camera.is_position_behind(point) and visible.has_point(camera.unproject_position(point)),"both racers stay framed during sweep")
				previous = frame.position
				old_lateral = lateral
			var side_frame: Dictionary = race.camera_frame(a,b)
			check(previous.is_equal_approx(side_frame.position),"sweep settles into existing side camera")
		race.phase = "staging"
		race.elapsed = 0.0
		check(race.start_camera_frame(a,b).position.is_equal_approx(rear.position),"rematch restarts at rear view")
	race.free()
	camera.free()
	print("DRAG_START_CAMERA checks=%d failures=%s"%[checks,str(failures)])
	quit(0 if failures.is_empty() else 1)
