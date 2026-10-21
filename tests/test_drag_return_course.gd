extends SceneTree
const COURSE=preload("res://activities/desert_drag/DragReturnCourse.gd")
const DRIVE=preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
var failures: Array[String]=[]

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for direction in [Vector3.RIGHT,Vector3.FORWARD]:
		var course=COURSE.new()
		root.add_child(course)
		course.configure(Vector3(50,0,10),direction)
		for lane in 2:
			for hz in [30,60,120]:
				var car=Node3D.new()
				root.add_child(car)
				var drive=DRIVE.new()
				drive.configure("desert_mirage")
				drive.race_mode=true
				drive.stage(2,.54)
				drive.launch()
				var entry={"car":car,"drive":drive}
				course.prepare(entry,lane)
				car.global_position=course.point_at(0,entry.return_lane)
				var elapsed=0.0
				while entry.return_progress<COURSE.LENGTH and elapsed<110:
					var brake: float=course.brake(entry)
					if drive.rpm>=drive.ideal_shift_rpm: drive.shift_up()
					if drive.rpm<drive.redline*.4: drive.shift_down()
					drive.step(1.0/hz,0.0 if brake>0 else 1.0,false,brake)
					var heading: Vector3=course.heading(entry,1.0/hz)
					car.global_position+=heading*drive.speed_mps/hz
					course.observe(entry)
					elapsed+=1.0/hz
				check(entry.return_progress>=COURSE.LENGTH and entry.return_gate==2,"two straights and barrel completed at %s Hz lane %s"%[hz,lane])
				check((car.global_position-course.start).dot(direction)<.1,"finish is back at the starting line")
				print("RETURN_ROUTE hz=",hz," lane=",lane," seconds=",elapsed," progress=",entry.return_progress," gate=",entry.return_gate)
				car.free()
		# A shortcut from the launch to the return line must not count as a lap.
		var fake_car=Node3D.new()
		root.add_child(fake_car)
		var shortcut={"car":fake_car,"drive":DRIVE.new()}
		course.prepare(shortcut,0)
		fake_car.global_position=course.start-direction*2
		check(course.observe(shortcut)<COURSE.LENGTH and shortcut.return_gate==0,"finish requires ordered barrel gates")
		fake_car.free()
		course.free()
	var world={"desert_drag":{"wins":["digo"],"finishes":1}}
	var ladder: Dictionary=world.desert_drag.duplicate(true)
	var result: Dictionary=COURSE.record_finish(world,"digo",45.0,46.0)
	check(result.return_mode and result.won and world.desert_drag==ladder,"return result never advances the ladder")
	COURSE.record_finish(world,"digo",47.0,46.0)
	var restored: Dictionary=JSON.parse_string(JSON.stringify(world))
	check(restored.desert_drag_return.finishes==2 and restored.desert_drag_return.best.digo==45.0,"own best time survives serialization and slower rematch")
	check(COURSE.record_finish(world,"digo",INF,46.0).is_empty(),"unfinished run grants no result")
	var fixture=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
	var checkpoint: Dictionary=fixture.full_snapshot(Vector3(-915,0,-1304),true)
	checkpoint.world.desert_drag_return=world.desert_drag_return.duplicate(true)
	var folder: String=fixture.output_dir("drag-return-save")
	var path: String=fixture.write_fixture(folder,"checkpoint.json",checkpoint)
	var saved: Dictionary=preload("res://runtime/SaveStore.gd").read_valid(path)
	var state=preload("res://runtime/GameState.gd").new()
	check(not path.is_empty() and not saved.is_empty() and state.restore_snapshot(saved),"return ledger survives real SaveStore and GameState round trip in isolated file")
	var ledger: Dictionary=state.world_state.get("desert_drag_return",{})
	check(ledger.get("finishes",-1)==2 and ledger.get("best",{}).get("digo",-1)==45.0,"saved best and finishes are retained")
	checkpoint.world.desert_drag_return.best.digo=-1.0
	check(not state.restore_snapshot(checkpoint),"corrupt return time is rejected before touching live state")
	print("DRAG_RETURN ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
