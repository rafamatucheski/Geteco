extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var controller := preload("res://runtime/ProductionWorld.gd").new()
	controller.state.region_id = "harbor"
	controller.state.world_state = {}
	check(not controller._startup_focus_hint().is_finite(),"new game retains default spawn")
	controller.state.world_state.pedestrian = {"region":"harbor","position":[20,1,40]}
	check(controller._startup_focus_hint() == Vector3(20,1,40),"saved pedestrian selected before mount")
	controller.state.world_state.vehicles = [{"region":"harbor","was_driven":true,"position":[60,2,80]}]
	check(controller._startup_focus_hint() == Vector3(60,2,80),"occupied saved vehicle has priority")
	controller.state.world_state.vehicles[0].was_driven = false
	check(controller._startup_focus_hint() == Vector3(20,1,40),"parked vehicle does not move spawn")
	controller.state.place_id = "garage"
	check(not controller._startup_focus_hint().is_finite(),"interior restore ignores stale exterior coordinates")
	controller.play_at_request = {"point":Vector3(-400,0,-900)}
	check(controller._startup_focus_hint() == Vector3(-400,0,-900),"explicit play-at owns initial cell")
	controller.play_at_request = {}
	controller.state.place_id = ""
	controller.state.region_id = "mountain"
	check(not controller._startup_focus_hint().is_finite(),"coordinates from another region rejected")
	controller.free()
	print("STARTUP_FOCUS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
