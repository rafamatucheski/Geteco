extends SceneTree
const RACE := preload("res://activities/desert_drag/DesertDrag.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const MODELS := {"digo":"desert_faisca","livia":"desert_faisca_rally","raul":"desert_coyote_drag","jessica":"desert_siroco","nadir":"desert_mirage_gt","rauhz":"rauhz_focus_mk1"}
var failures: Array[String]=[]

class ProfileVehicle extends Node:
	var archetype := ""

func _initialize() -> void:
	for identity in ["porto_rosso","monaliza","desert_mirage_gt"]:
		var car := ProfileVehicle.new()
		car.archetype=identity
		var profile := RACE.powertrain_profile_for_vehicle(car)
		var expected := TUNING.base_spec(identity)
		var actual := DRIVE.new()
		actual.configure(profile)
		check(profile==identity,"drag preserves the authored car profile: "+identity)
		check(actual.spec.torque_nm==expected.torque_nm and actual.spec.gears==expected.gears and actual.spec.final_drive==expected.final_drive,"drag keeps actual torque and gearbox from free driving: "+identity)
		car.free()
	var previous := INF
	for identity in RACE.RIVALS:
		var parts: Dictionary=RACE.rival_parts(identity)
		check(TUNING.clean_parts(parts)==parts,"rival uses legal tuning slots: "+identity)
		var reaction: float=RACE.RIVALS[identity].reaction
		var stock := run_car(MODELS[identity],{},reaction)
		var prepared := run_car(MODELS[identity],parts,reaction)
		print("DRAG_BALANCE ",identity," stock=",stock," prepared=",prepared)
		check(prepared<stock-.5,"rival preparation materially improves real drivetrain: "+identity)
		check(prepared<previous,"ladder grows faster with each rival: "+identity)
		check(prepared>=15.0 and prepared<24.0,"800m build stays inside authored playable range: "+identity)
		previous=prepared
	var stock_player := run_car("desert_mirage",{},0.0)
	var digo := run_car(MODELS.digo,RACE.rival_parts("digo"),RACE.RIVALS.digo.reaction)
	print("DRAG_BALANCE stock_mirage=",stock_player," digo=",digo)
	check(digo-stock_player<2.0,"first rival cannot be left several seconds behind by stock coupe")
	check(stock_player<digo,"clean stock coupe driving can still beat the first rival")
	var poor_player := run_car("desert_mirage",{},0.0,.70,.85)
	check(poor_player>digo,"wheelspin and early shifts cost the stock coupe its first-rival victory")
	print("DRAG_BALANCE poor_stock_mirage=",poor_player)
	print("DESERT_DRAG_BALANCE failures=",failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool,label: String) -> void:
	print("DRAG_BALANCE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run_car(model: String,parts: Dictionary,reaction: float,shift_ratio: float=.91,launch_pedal: float=.52) -> float:
	var drive := DRIVE.new()
	drive.configure(model,parts)
	drive.stage(1.0,launch_pedal)
	drive.launch()
	var time := 0.0
	var wait := -1.0
	const STEP := 1.0/60.0
	while time<65 and drive.distance_m<800:
		if drive.rpm>=drive.redline*shift_ratio:
			if wait<0: wait=.04
			wait-=STEP
			if wait<=0:
				drive.shift_up()
				wait=-1
		drive.step(STEP,1.0 if time>=reaction else 0.0,drive.gear>=3 and time>6.0)
		time+=STEP
	return time
