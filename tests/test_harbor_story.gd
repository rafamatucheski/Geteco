extends SceneTree
const STORY := preload("res://systems/campaign/HarborStory.gd")
var checks := 0
func _initialize() -> void:
	var world := {}
	_check(STORY.PRISON_YEARS == 8,"Eight years is current canon")
	_check(STORY.validate_snapshot(STORY.data(world)),"Old saves default to valid new story")
	_check(not STORY.record_brother_route(world,true),"Route needs Maciota meeting")
	_check(STORY.mark_opening(world),"Opening records once")
	_check(not STORY.mark_opening(world),"Skip/replay cannot duplicate opening")
	_check(STORY.mark_maciota(world),"Maciota meeting")
	_check(not STORY.record_brother_route(world,false),"No route before physical mission completion")
	_check(STORY.record_brother_route(world,true),"Final list opens next act")
	_check(not STORY.record_brother_route(world,true),"Final reward cannot repeat")
	_check(STORY.validate_snapshot(STORY.data(world)),"Completed snapshot valid")
	var invalid := STORY.data(world)
	invalid.act_two_available = false
	_check(not STORY.validate_snapshot(invalid),"Contradictory unlock rejected")
	invalid = STORY.data(world)
	invalid.maciota_met = false
	_check(not STORY.validate_snapshot(invalid),"Route without source rejected")
	print("HARBOR_STORY PASS ",checks)
	quit()
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
