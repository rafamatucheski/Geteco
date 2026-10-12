extends SceneTree
## Off-screen continuation must preserve physical casualties and damage.
const TRANSPORT := preload("res://gameplay/armored/ArmoredTransport.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARMORED_VIRTUAL ", "PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func fixture(phase: String):
	var event = TRANSPORT.new()
	event.data = SCHEDULE.initial({"id":"1:0","origin":"harbor_bank","destination":"desert_bank"},0)
	event.profile = SCHEDULE.security(0)
	event.road = Curve3D.new()
	event.road.add_point(Vector3.ZERO)
	event.road.add_point(Vector3(0,0,-1000))
	event.data.phase = phase
	event.data.elapsed = 80.0
	event.data.guards = [{"health":74.0,"point":[2,0,4],"seat":0,"phase":"car"},{"health":110.0,"point":[3,0,4],"seat":1,"phase":"bank"}]
	for index in 4:
		event.data.vehicles.append({"health":900.0 if index < 2 else 140.0,"point":[0,0,-float(index)*12],"yaw":0.0})
	return event
func _initialize() -> void:
	var event = fixture("boarding")
	event._advance_virtual(.25)
	check(event.data.phase == "driving" and event.data.guards.all(func(record): return record.phase == "board"),"boarding transition marks every seat immediately before readmission")
	event._advance_virtual(5.0)
	check(event.data.vehicles.size() == 4 and event.data.vehicles[0].health == 900.0 and event.data.vehicles[3].health == 140.0,"virtual travel preserves truck and escort damage")
	check(event.data.guards[0].health == 74.0,"virtual travel preserves injured crew")
	check(event.data.vehicles[0].point[2] < -50.0 and event.data.route_offset > 0.0,"saved poses advance with the virtual route instead of restoring old bank positions")
	event.session = {"state":{"world_state":{}}}
	event._persist()
	check(event.data.virtual_poses and event.session.state.world_state[SCHEDULE.KEY].event.virtual_poses,"off-screen persistence retains virtual support marker")
	check(not SCHEDULE.restore(event.data).is_empty(),"advanced damaged service remains valid saved state")
	event.road.clear_points()
	event.road.add_point(Vector3.ZERO)
	event.road.add_point(Vector3(1000,0,0))
	event.data.route_offset = 963.0
	event._advance_virtual(5.0)
	check(event.data.phase == "unloading" and is_equal_approx(float(event.data.vehicles[2].yaw),-PI*.5),"front escort retains road heading at the exact final endpoint")
	event.free()
	for phase in ["loading","boarding","driving","unloading"]:
		event = fixture(phase)
		event.data.vehicles[2].health = 0.0
		event._advance_virtual(5.0)
		check(event.data.phase == "finished" and event.data.vehicles[2].health == 0.0 and event.data.delivered == [false,false],"wreck cannot revive or finish delivery after retirement during "+phase)
		event.free()
	for phase in ["loading","unloading"]:
		event = fixture(phase)
		event.data.guards[0].health = 0.0
		event._advance_virtual(5.0)
		check(event.data.phase == "finished" and event.data.cargo_cycles == [0,0] and event.data.delivered == [false,false],"dead carrier cannot complete off-screen "+phase)
		event.free()
	event = fixture("unloading")
	event.data.route_offset = 964.0
	event._advance_virtual(.25)
	check(event.data.phase == "finished" and event.data.delivered == [true,true],"unharmed off-screen delivery still completes normally")
	event.free()
	event = fixture("driving")
	for offset in [24.0,12.0,36.0,0.0]: event.drivers.append({"offset":offset,"route":null})
	check([event._formation_follower(0),event._formation_follower(1),event._formation_follower(2),event._formation_follower(3)] == [1,3,0,-1],"normal formation follows its nearest rear neighbour")
	for index in 4: event.drivers[index].offset = [20.0,70.0,40.0,100.0][index]
	check([event._formation_follower(0),event._formation_follower(1),event._formation_follower(2),event._formation_follower(3)] == [-1,2,0,1],"escort and truck that bypassed the leader still wait for the actual convoy behind")
	for driver in event.drivers: driver.offset = 20.0
	check([event._formation_follower(0),event._formation_follower(1),event._formation_follower(2),event._formation_follower(3)] == [-1,0,1,2],"parallel bypass positions have deterministic ordering without circular holds")
	for index in 4:
		var connector := Curve3D.new()
		connector.set_meta("formation_origin",[4.0,-8.0,16.0,-20.0][index])
		event.drivers[index].route = connector
	check([event._formation_follower(0),event._formation_follower(1),event._formation_follower(2),event._formation_follower(3)] == [1,3,0,-1],"different bay connector lengths compare progress on the same road")
	event.free()
	print("ARMORED_VIRTUAL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
