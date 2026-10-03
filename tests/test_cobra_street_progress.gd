extends SceneTree
const PROGRESS:=preload("res://systems/campaign/CobraStreetProgress.gd")
const COURSE:=preload("res://gameplay/urban_v1/CobraRaceCourse.gd")
const CAMPAIGN:=preload("res://systems/campaign/CampaignRuntime.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func point(v: Vector3) -> Vector2: return Vector2(v.x,v.z)
func run() -> void:
	var origin:=point(COURSE.grid(3))
	var state:=PROGRESS.start("test",origin)
	check(PROGRESS.validate(state),"Valid street starting grid")
	check(PROGRESS.tick(state,.1,origin+Vector2(5,0),"test",true,0,0).failure=="race_false_start","False start rejected")
	for index in 31: PROGRESS.tick(state,.1,origin,"test",true,0,0)
	check(state.countdown==0 and state.initialized,"Stationary countdown releases race")
	check(PROGRESS.tick(state,.1,origin,"other",true,0,0).failure=="race_vehicle_left","Cannot change racing vehicle")
	check(PROGRESS.tick(state,.1,origin,"test",false,0,0).failure=="race_vehicle_broken","Destroyed vehicle cannot win")
	check(PROGRESS.tick(state,.1,point(COURSE.gate(3)),"test",true,0,0).failure=="race_interrupted","Teleport cannot collect finish")
	var gate:=point(COURSE.gate(0))
	var axis:=point(COURSE.forward(0))
	state.previous=[gate.x+axis.x*2,gate.y+axis.y*2]
	check(PROGRESS.tick(state,.1,gate-axis*2,"test",true,0,0).crossed==-1,"Backward crossing does not count")
	state.previous=[gate.x-axis.x*2,gate.y-axis.y*2]
	check(PROGRESS.tick(state,.1,gate+axis*2,"test",true,0,0).crossed==0,"Swept forward crossing counts at speed")
	check(PROGRESS.tick(state,.1,gate-axis*2,"test",true,0,0).crossed==-1,"Same checkpoint cannot count twice")
	var campaign:=CAMPAIGN.new()
	var snapshot:=campaign.snapshot()
	snapshot.completed=["primeiro_giro","cobra_contact"]
	snapshot.claimed_rewards=snapshot.completed.duplicate()
	snapshot.flags={"harbor_delivery_complete":true,"cobra_contact_complete":true}
	check(campaign.restore_snapshot(snapshot) and campaign.begin("cobra_race"),"Street race respects mission prerequisites")
	check(campaign.apply_event("race_started",{"target_id":"ashbend_start","in_vehicle":true,"elapsed":0,"race_vehicle_id":"test","race_position":origin,"race_course":2}).ok,"Campaign starts six-car race contract")
	for index in 31: campaign.tick_race(.1,origin,"test",true)
	var curve:=COURSE.curve()
	var offset:=curve.get_closest_offset(COURSE.grid(3))
	while offset<curve.get_baked_length():
		offset+=1.0
		var result:=campaign.tick_race(.1,point(curve.sample_baked(offset)),"test",true)
		if result.get("crossed",-1)>=0:
			var at: int=result.crossed
			check(campaign.apply_event("race_checkpoint",{"target_id":"ashbend_gate_%d"%at,"checkpoint":at,"in_vehicle":true,"elapsed":campaign.race_elapsed()}).ok,"Ordered physical street checkpoint %d"%at)
	check(campaign.step==5,"All four street gates required before finish")
	var reload:=CAMPAIGN.new()
	check(reload.restore_snapshot(JSON.parse_string(JSON.stringify(campaign.snapshot()))) and reload.step==0 and reload.race_status().is_empty(),"Reload restarts grid instead of deleting opponents ahead of player")
	campaign.set_street_race_place(2)
	var finish:={"target_id":"ashbend_finish","in_vehicle":true,"elapsed":campaign.race_elapsed()}
	check(campaign.apply_event("race_finished",finish).reason=="race_win_required" and campaign.snapshot().pending_rewards.is_empty(),"Second place receives no victory reward")
	campaign.set_street_race_place(1)
	check(campaign.apply_event("race_finished",finish).ok,"First place completes race")
	check(not campaign.apply_event("race_finished",finish).ok,"Finish cannot pay twice")
	var mortal:=CAMPAIGN.new()
	mortal.restore_snapshot(snapshot)
	mortal.begin("cobra_race")
	var controller:=preload("res://gameplay/urban_v1/CobraStreetRace.gd").new()
	controller.session={"state":{"campaign":mortal},"world":{"driving":null,"gameplay":{"health":0}}}
	controller.running=true
	check(controller.tick(.016).get("failure")=="player_death" and mortal.active_id.is_empty() and mortal.snapshot().pending_rewards.is_empty(),"Player death cancels before any same-frame finish reward")
	controller.running=false
	controller.free()
	print("STREET_PROGRESS failures=",failures)
	quit(0 if failures.is_empty() else 1)
