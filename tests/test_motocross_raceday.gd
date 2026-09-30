extends SceneTree
## Race-day venue and mechanics. Support is measured with rays against the real
## collision of the built course (validar-terrenos-pisos: base apoiada, nada
## flutuando, nada invadindo a pista). Does not certify visuals or FPS.
const COURSE := preload("res://activities/motocross/MotocrossCourse.gd")
const BIKE := preload("res://activities/motocross/MotocrossBike.gd")
const PILOT := preload("res://activities/motocross/MotocrossPilot.gd")
const GATE := preload("res://activities/motocross/MotocrossStartGate.gd")
const CONTROLLER := preload("res://activities/motocross/Motocross.gd")
const PROGRESS := preload("res://activities/motocross/MotocrossProgress.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("MOTOCROSS_RACEDAY ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func frames(count: int) -> void:
	for _i in count: await physics_frame

func ground(world: World3D, point: Vector3, exclude: Array[RID] = [], rise := 3.0, depth := 6.0) -> float:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*rise,point-Vector3.UP*depth,1,exclude)
	query.hit_back_faces = false
	var hit := world.direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else NAN

func run() -> void:
	var course := COURSE.new()
	root.add_child(course)
	course.finish_build()
	await frames(5)
	var world := course.get_world_3d()
	var trackside: Node3D = course.trackside
	var solids: StaticBody3D = trackside.get_node("TracksideSolids")
	var stake_body: StaticBody3D = course.get_node("CourseStakes")
	var own: Array[RID] = [solids.get_rid(),stake_body.get_rid()]
	# Stakes: bottom under the real ground at every footprint corner, never deep.
	var worst_float := -INF
	var worst_bury := -INF
	var worst_at := Vector3.ZERO
	var stakes := 0
	for row in course.stake_tops:
		for base in row:
			stakes += 1
			# Stakes are world-aligned 16 cm posts: these are their true corners.
			for corner in [Vector3(.08,0,.08),Vector3(-.08,0,.08),Vector3(.08,0,-.08),Vector3(-.08,0,-.08)]:
				var floor_y := ground(world,base+corner,own)
				var bottom: float = base.y-.05
				worst_float = maxf(worst_float,bottom-floor_y)
				if floor_y-bottom > worst_bury: worst_at = base
				worst_bury = maxf(worst_bury,floor_y-bottom)
	print("MOTOCROSS_RACEDAY_STAKES count=",stakes," worst_float=",worst_float," worst_bury=",worst_bury," deepest_at=",worst_at)
	# The deepest uphill corner is a post driven into the steep outer face of
	# the hairpin berm (~57 deg over its 16 cm footprint); 0.5 m still shows.
	check(stakes > 60 and worst_float <= .005 and worst_bury < .4, "every course stake stands on the shoulder surface, sunk but never floating")
	# The replaced placement: berm-crest height at a fixed 7-point spacing.
	var old_float := 0.0
	var old_floating := 0
	var n: int = course.points.size()-1
	for i in range(0,n,7):
		var p: Vector3 = course.points[i]
		var side: Vector3 = (course.points[i+1]-p).cross(Vector3.UP).normalized()
		for sign_value in [-1.0,1.0]:
			var edge: Vector3 = p+side*(course.HALF_WIDTH+.45)*sign_value
			edge.y += course._bank(i,sign_value)
			var lowest := INF
			for corner in [Vector3(.08,0,.08),Vector3(-.08,0,.08),Vector3(.08,0,-.08),Vector3(-.08,0,-.08)]:
				lowest = minf(lowest,ground(world,edge+corner,own))
			old_float = maxf(old_float,edge.y-lowest)
			if edge.y-lowest > .02: old_floating += 1
	print("MOTOCROSS_RACEDAY_OLD_STAKES floating_over_2cm=",old_floating," worst_float=",old_float)
	# Tape: straight runs between stakes never cross into the riding width.
	var tape_clear := true
	var tape_min := INF
	for row in course.stake_tops:
		for index in row.size():
			var a: Vector3 = row[index]
			var b: Vector3 = row[(index+1)%row.size()]
			for step in 9:
				var lateral := float(course.nearest(a.lerp(b,float(step)/8.0)).lateral)
				tape_min = minf(tape_min,lateral)
				tape_clear = tape_clear and lateral > course.HALF_WIDTH+.15
	print("MOTOCROSS_RACEDAY_TAPE nearest_lateral=",tape_min)
	check(tape_clear, "course tape stays outside the riding width on every corner")
	# Hay bales: all four bottom corners seated on the quarry ground.
	var bale_ok := true
	var bale_clear := true
	var bale_float := -INF
	var bale_bury := -INF
	for where in trackside.bale_transforms:
		for corner in [Vector3(-.5,-.25,-.275),Vector3(.5,-.25,-.275),Vector3(.5,-.25,.275),Vector3(-.5,-.25,.275)]:
			var bottom: Vector3 = where*corner
			var floor_y := ground(world,bottom,own)
			bale_float = maxf(bale_float,bottom.y-floor_y)
			bale_bury = maxf(bale_bury,floor_y-bottom.y)
			bale_ok = bale_ok and is_finite(floor_y) and bottom.y-floor_y <= .02 and floor_y-bottom.y <= .12
		bale_clear = bale_clear and float(course.nearest(where.origin).lateral) > course.HALF_WIDTH+3.2
		for tree in course.get_node("MotocrossScenery").tree_points:
			bale_clear = bale_clear and Vector2(tree.x-where.origin.x,tree.z-where.origin.z).length() > 1.4
	print("MOTOCROSS_RACEDAY_BALES count=",trackside.bale_transforms.size()," apexes=",trackside.apex_count," skipped=",trackside.bale_skips," worst_float=",bale_float," worst_bury=",bale_bury)
	check(trackside.bale_transforms.size() >= 20 and bale_ok, "hay bales sit on the ground at all four corners (<=2 cm gap, <=12 cm seat)")
	check(bale_clear, "hay bales stay on run-off, clear of the course and tree trunks")
	# Bleacher: fans' planted feet on the treads; stand base below the soil.
	var bleacher: Node3D = trackside.bleacher
	var feet_ok := true
	var bodies_clear := true
	for fan in trackside.fans:
		for side in [-1.0,1.0]:
			var foot: Vector3 = fan.model.to_global(Vector3(side*.13,0,.4))
			var floor_y := ground(world,foot,[],.045,.3)
			feet_ok = feet_ok and is_finite(floor_y) and absf(floor_y-foot.y) < .025
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = fan._shape.shape
		query.transform = fan._shape.global_transform
		query.collision_mask = 1
		bodies_clear = bodies_clear and world.direct_space_state.intersect_shape(query,1).is_empty()
	check(trackside.fans.size() == 5 and feet_ok, "five bleacher fans have both planted feet on a real tread")
	check(bodies_clear, "seated fans' bodies do not intersect the stand or terrain")
	for _i in 60: await process_frame
	var fan: Node3D = trackside.fans[0]
	check(not fan.model.is_processing() and not fan.is_processing(), "settled fans stop per-frame pose work")
	fan.notice_threat(fan.global_position+Vector3(4,0,0),30.0)
	check(fan.model.is_processing() and fan.frightened, "a threat wakes the fan's animation for its protective reaction")
	var walkway_ok := true
	for x in [-3.8,-2.0,0.0,2.0,3.8]:
		for z in [-1.55,-1.25]:
			var point: Vector3 = bleacher.transform*Vector3(x,0,z)
			var terrain: float = course.surface_height(Vector2(point.x,point.z))
			walkway_ok = walkway_ok and terrain <= point.y+.001 and point.y-terrain < .5
			var top := ground(world,point,[],.05,.2)
			walkway_ok = walkway_ok and is_finite(top) and absf(top-point.y) < .01
	check(walkway_ok, "bleacher walkway has collision at its visible top and the soil never pokes through it")
	check(float(course.nearest(bleacher.global_position).lateral) > course.HALF_WIDTH+4.0, "bleacher stands back from the final straight")
	# Found in review: a shade trunk stood inside the first bleacher site.
	var stand_clear := true
	var nearest_trunk := INF
	for tree in course.get_node("MotocrossScenery").tree_points:
		var local: Vector3 = bleacher.transform.affine_inverse()*tree
		var outside := Vector2(maxf(0.0,absf(local.x)-4.0),maxf(0.0,absf(local.z+.075)-1.53)).length()
		nearest_trunk = minf(nearest_trunk,outside)
		stand_clear = stand_clear and outside > 3.3
	print("MOTOCROSS_RACEDAY_STAND nearest_trunk_to_footprint=",nearest_trunk)
	check(stand_clear, "no shade tree trunk or low canopy reaches the stand and its board")
	# Found in review: a quarry boulder poked through the stand's east end.
	var volume := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.8,2.2,3.6)
	volume.shape = box
	volume.transform = bleacher.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.45,-.1))
	volume.collision_mask = 1
	volume.exclude = [solids.get_rid()]
	var intruders := world.direct_space_state.intersect_shape(volume,8)
	check(intruders.is_empty(), "no boulder, trunk or stake body intrudes into the stand's volume")
	# Board and banner poles reach below the ground at both feet.
	check(trackside.banner_count >= 2 and is_instance_valid(trackside.board_title), "sponsor banners and the race-control board are built")
	course.set_board("VOLTA 2/3","1º Lobo · 2º Dante")
	check(trackside.board_title.text == "VOLTA 2/3" and trackside.board_detail.text.begins_with("1º"), "race-control board shows controller text")
	# Start gate: lanes, grid spawns and bars that lie on the clay when dropped.
	var gate: Node3D = course.start_gate
	var bars_ok := true
	var bar_error := 0.0
	for index in gate._pivots.size():
		var pivot: Transform3D = gate._pivots[index]
		for corner in [Vector3(-.74,0,0),Vector3(.74,0,0),Vector3(-.74,0,.5),Vector3(.74,0,.5)]:
			# Dropped: the bar's underside spans from the hinge back toward the riders.
			var point: Vector3 = pivot*corner
			var clay := ground(world,point,[],.5,1.0)
			bar_error = maxf(bar_error,absf(point.y-clay))
			bars_ok = bars_ok and is_finite(clay) and absf(point.y-clay) < .045
	print("MOTOCROSS_RACEDAY_GATE lanes=",gate._pivots.size()," worst_bar_gap=",bar_error)
	check(gate._pivots.size() == 6 and bars_ok and not gate.raised, "six dropped gate bars lie on the banked clay within 4.5 cm")
	gate.raise_gate()
	for _i in 60: await process_frame
	var up: Vector3 = gate._bars.multimesh.get_instance_transform(0).basis.y.normalized()
	check(gate.raised and up.y > .95, "raised bars stand upright in front of the grid")
	gate.drop_gate()
	for _i in 30: await process_frame
	check(not gate.is_processing(), "gate animation stops once the bars are down")
	var grid_ok := true
	for index in GATE.LANES.size():
		var pose: Transform3D = gate.grid_pose(index)
		var lane := float(GATE.LANES[index])
		pose.origin.y = course.ribbon_height(GATE.GRID_DISTANCE,lane)+.15
		var clay := ground(world,pose.origin,[],.6,1.0)
		grid_ok = grid_ok and is_finite(clay) and pose.origin.y-clay > .1 and pose.origin.y-clay < .2
		grid_ok = grid_ok and absf(lane)+.45 < course.HALF_WIDTH
	check(grid_ok, "every grid slot spawns 10-20 cm above its own clay height inside the riding width")
	# Mechanic tent legs on the yard floor at the authored 13 cm height.
	var paddock: Node3D = course.get_node("MotocrossPaddock")
	var tent_ok := true
	for x in [-1.45,1.45]:
		for z in [-1.45,1.45]:
			var leg := Vector3(-219.5+x,.13,-30.5+z)+Vector3(.12,0,0)
			var floor_y := ground(world,leg,[],.1,.4)
			tent_ok = tent_ok and is_finite(floor_y) and absf(floor_y-.13) < .02
	check(tent_ok and paddock.get_node_or_null("ToolChest") != null, "mechanic tent stands on the connected yard floor")
	# Gameplay rules independent of the session.
	check(CONTROLLER.launch_quality(.7) == "holeshot" and CONTROLLER.launch_quality(.98) == "wheelie" and CONTROLLER.launch_quality(.1) == "bog" and CONTROLLER.launch_quality(.45) == "good", "gate result follows the rev zone")
	var progress := PROGRESS.new()
	check(not progress.record_lap(10.0) and progress.record_lap(40.0) and not progress.record_lap(45.0) and progress.record_lap(35.0) and is_equal_approx(float(progress.data.best_lap),35.0), "track record accepts only real, faster laps")
	var snapshot := progress.snapshot()
	check(PROGRESS.validate_snapshot(snapshot), "save with a track record validates")
	snapshot.best_lap = 4.0
	check(not PROGRESS.validate_snapshot(snapshot), "impossible lap record is rejected")
	snapshot.erase("best_lap")
	check(PROGRESS.validate_snapshot(snapshot), "older saves without a record stay valid")
	course.free()
	await launch_checks()
	await landing_checks()
	print("MOTOCROSS_RACEDAY_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func launch_checks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var speeds := {}
	var wheelie_pitch := 0.0
	var rear_gap := 0.0
	for quality in ["good","holeshot","bog","wheelie"]:
		var bike := BIKE.new()
		world.add_child(bike)
		bike.reset_to(Transform3D(Basis.IDENTITY,Vector3(0,.05,0)))
		await frames(10)
		bike.launch(quality)
		for i in 60:
			bike.drive(1,0)
			await physics_frame
			if quality == "wheelie" and i == 20:
				wheelie_pitch = bike.visual.rotation.x
				rear_gap = absf(bike.visual.to_global(Vector3(0,0,.83)).y-bike.global_position.y)
		speeds[quality] = bike.speed
		bike.free()
	print("MOTOCROSS_RACEDAY_LAUNCH speeds_after_1s=",speeds," wheelie_pitch=",wheelie_pitch," rear_gap=",rear_gap)
	check(speeds.holeshot > speeds.good+1.0 and speeds.bog < speeds.good-1.0 and speeds.wheelie < speeds.good-1.0, "holeshot surges, a bogged or wheelied start loses real speed")
	check(wheelie_pitch > .25 and rear_gap < .03, "wheelie lifts the front while the rear tire stays on the ground")
	world.free()

func landing_checks() -> void:
	var course := COURSE.new()
	root.add_child(course)
	course.finish_build()
	await frames(4)
	var results := {}
	for policy in ["none","cue"]:
		var bike := BIKE.new()
		bike.is_player = true
		bike.max_speed = 18.0
		root.add_child(bike)
		bike.reset_to(course.pose(2.0))
		var row := {"bike":bike,"lane":0.0}
		var boosted := false
		for i in 60*40:
			PILOT.drive(row,course,[row],16.0,1.0/60.0)
			var lean := 0.0
			if policy == "cue" and absf(bike.air_attitude_error) > .08: lean = -1.0 if bike.air_attitude_error > 0 else 1.0
			bike.air_lean = lean*.8 if not bike.is_on_floor() else 0.0
			await physics_frame
			boosted = boosted or bike.landing_boost > 0.0
		results[policy] = {"perfect":bike.perfect_landings,"rough":bike.rough_landings,"crashes":bike.crash_count,"boost":boosted}
		bike.free()
	print("MOTOCROSS_RACEDAY_LANDINGS ",results)
	check(results.none.rough == 0 and results.none.perfect == 0 and results.none.crashes == 0, "riding without air input lands clean: no bonus, no penalty")
	check(results.cue.perfect >= 3 and results.cue.boost and results.cue.crashes == 0, "following the HUD attitude cue earns perfect landings and their boost")
	course.free()
