extends SceneTree
const COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
const STATE := preload("res://activities/desert_wash/DesertWashState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var failures: Array[String]=[]
var checks:=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	print("WASH ","PASS " if ok else "FAIL ",label)

func run() -> void:
	var world: Dictionary={}
	var wallet=ECONOMY.new()
	check(STATE.validate_world(world,wallet.snapshot()),"old save without wash state is accepted")
	check(not STATE.record(world,NAN) and not STATE.record(world,INF) and not STATE.record(world,0),"invalid times cannot earn progress")
	check(STATE.record(world,50.0) and not STATE.claim(world,wallet),"slow finish records time without prize")
	check(STATE.record(world,42.0) and STATE.claim(world,wallet),"legitimate target time earns first prize")
	var balance: int=wallet.balance
	check(STATE.record(world,40.0) and not STATE.claim(world,wallet) and wallet.balance==balance,"repeats improve best without duplicating prize")
	check(STATE.data(world).best==40 and STATE.data(world).finishes==3,"best and completed attempts retained")
	check(STATE.validate_world(JSON.parse_string(JSON.stringify(world)),wallet.snapshot()),"JSON save roundtrip preserves progress and receipt")
	var corrupt:=world.duplicate(true)
	corrupt.desert_wash.won=false
	check(not STATE.validate_world(corrupt,wallet.snapshot()),"receipt cannot survive tampered win")
	check(not STATE.validate_world({},wallet.snapshot()),"orphaned reward rejected")
	for i in range(1,COURSE.GATES):
		var p:=COURSE.gate(i)
		var forward:=COURSE.direction(i)
		var side:=forward.cross(Vector3.UP)
		check(COURSE.LANDFORMS.WASH_BOUNDS.has_point(Vector2(p.x,p.z)),"gate %d belongs to existing wash"%i)
		check(is_equal_approx(COURSE.crossing(p-forward,p+forward,i),.5),"gate %d forward crossing timed"%i)
		check(COURSE.crossing(p+forward,p-forward,i)<0,"gate %d backwards crossing refused"%i)
		check(COURSE.crossing(p-forward+side*5,p+forward+side*5,i)<0,"gate %d outside cones refused"%i)
		check(COURSE.crossing(p-forward+Vector3.UP*5,p+forward+Vector3.UP*5,i)<0,"gate %d airborne shortcut refused"%i)
	check(COURSE.distance_to_course(COURSE.gate(6))<.01,"centreline belongs to route")
	check(COURSE.distance_to_course(COURSE.gate(6)+Vector3.RIGHT*100)>16,"off-course escape detectable")
	print("WASH_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
