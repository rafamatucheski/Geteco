extends SceneTree
const OFFICER := preload("res://gameplay/dispatch/DispatchOfficer.gd")
const UNIT := preload("res://gameplay/dispatch/DispatchUnit.gd")
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
var failures: Array[String]=[]
var checks:=0
var bundle: Dictionary
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func spawn(tier: int,motorcycle:=false):
	var officer:=OFFICER.new()
	officer.tier=tier
	officer.motorcycle_officer=motorcycle
	officer.controller=bundle.gameplay
	bundle.scene.add_child(officer)
	officer.set_physics_process(false)
	return officer
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	bundle=KIT.build(self,KIT.grid_roads(),Vector3(30,0,10))
	var swat=spawn(2)
	check(swat.health==95.0 and swat.armor==80.0,"SWAT spawns with separate 95 health and 80 armor")
	var events: Array=[]
	swat.durability_changed.connect(func(h,mh,a,ma): events.append([h,mh,a,ma]))
	swat.receive_damage(20.0)
	check(swat.armor==60.0 and swat.health==95.0,"Armor absorbs a hit without reducing health")
	swat.receive_damage(60.0)
	check(swat.armor==0.0 and swat.health==95.0 and not swat.dead,"Exact armor depletion does not kill or injure the officer")
	swat.receive_damage(15.0)
	check(swat.health==80.0 and swat.armor==0.0,"Unarmored officer takes full health damage")
	check(events.size()==3 and events[-1]==[80.0,95.0,0.0,80.0],"One final durability notification is emitted per valid hit")
	var snapshot: Dictionary=swat.get_durability_state()
	var last_damage: float=swat.last_damage_time
	for invalid in [0.0,-10.0,NAN,INF,-INF]: swat.receive_damage(invalid)
	check(swat.get_durability_state()==snapshot and swat.last_damage_time==last_damage,"Invalid damage cannot heal or mutate either reserve")
	var overflow=spawn(2)
	overflow.receive_damage(85.0)
	check(overflow.armor==0.0 and overflow.health==90.0,"Damage overflow crosses the broken shield exactly once")
	var army=spawn(4)
	check(army.health==130.0 and army.armor==110.0,"Army spawns with separate 130 health and 110 armor")
	for tier in [0,1,3]:
		var ordinary=spawn(tier)
		var initial: float=ordinary.health
		ordinary.receive_damage(10.0)
		check(ordinary.max_armor==0.0 and ordinary.health==initial-10.0,"Ordinary/FBI tier%d preserves direct health damage"%tier)
	var motorcycle=spawn(4,true)
	check(motorcycle.armor==0.0 and motorcycle.max_armor==0.0,"Motorcycle officers do not gain invisible heavy armor")
	var combat=spawn(2)
	bundle.gameplay._damage_bullet(combat,18.0,bundle.player)
	check(combat.armor==62.0 and combat.health==95.0,"The real bullet damage pipeline consumes police armor first")
	check(bundle.gameplay.stars>=2,"A hit absorbed by armor still counts as assault on police")
	bundle.gameplay._damage(combat,70.0,bundle.player,true)
	check(combat.armor==0.0 and combat.health==87.0,"Continuous combat damage crosses the shield through the same pipeline")
	var unit:=UNIT.new()
	unit.controller=bundle.controller
	unit.crew_remaining=0
	unit.officers.append(swat)
	unit.on_officer_boarded(swat)
	unit.on_officer_boarded(swat)
	check(unit.crew_remaining==1 and unit._seated_durability.size()==1,"A returning officer is counted and retained only once")
	var returned=spawn(2)
	unit._restore_seated_durability(returned)
	check(returned.health==80.0 and returned.armor==0.0,"Boarding and redeploying cannot restore spent armor or wounds")
	check(unit._seated_durability.is_empty(),"A crew snapshot is consumed once rather than cloning durability")
	returned.receive_damage(80.0)
	check(returned.dead and returned.health==0.0,"Officer dies only when the health reserve reaches zero")
	var dead_state: Dictionary=returned.get_durability_state()
	returned.receive_damage(500.0)
	check(returned.get_durability_state()==dead_state,"A dead officer ignores additional hits")
	var fatal=spawn(2)
	fatal.receive_damage(175.0,bundle.player)
	check(fatal.dead and fatal.armor==0.0 and fatal.health==0.0,"A fatal hit can exhaust both reserves without leaving negative values")
	unit.officers.append(fatal)
	unit.on_officer_boarded(fatal)
	check(unit.crew_remaining==1 and unit._seated_durability.is_empty(),"Dead crew cannot reboard or regain a reserve")
	print("POLICE_ARMOR checks=",checks," failures=",failures)
	KIT.teardown(bundle)
	quit(0 if failures.is_empty() else 1)
