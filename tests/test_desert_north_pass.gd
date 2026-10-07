extends SceneTree
const L:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const ART:=preload("res://world/desert/north_pass/DesertNorthPassScenery.gd")
const STORY:=preload("res://runtime/desert/DesertStoryState.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func blocked(a: Vector3,b: Vector3) -> bool:
	return not root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1)).is_empty()
func run() -> void:
	check(not L.completed({}),"Old save keeps roadworks closed")
	var story:=STORY.defaults()
	story.delivered=true
	check(not L.completed({"desert_story":story}),"Forged final flag cannot release passage")
	for flag in STORY.FLAGS: story[flag]=true
	check(L.completed({"desert_story":story}),"Valid act-two completion releases passage")
	check(L.restore_point(Vector3(342.5,0,-1900),{})==Vector3(348,0,-1778),"Old north-corridor save restores south of unfinished works")
	check(L.restore_point(Vector3(318,0,-1810),{})==Vector3(348,0,-1778),"Old save inside new cliff restores safely")
	check(L.restore_point(Vector3(342.5,0,-1900),{"desert_story":story})==Vector3(342.5,0,-1900),"Completed campaign preserves northern saved position")
	check(L.restore_point(Vector3(280,0,-1900),{})==Vector3(280,0,-1900),"Unrelated northern terrain save remains unchanged")
	var road: Dictionary=L.roads()[0]
	check(road.points[0].is_equal_approx(L.JUNCTION),"Exact authored junction")
	var found:=false
	for existing in preload("res://world/desert/DesertLayout.gd").roads():
		if existing.id!="desert_route_66": continue
		for point in existing.points:
			if point.is_equal_approx(L.JUNCTION): found=true
	check(found,"New route meets real rounded old highway vertex")
	check(not road.traffic,"Ambient cars cannot enter worksite")
	check(road.points[-1]==L.END,"Continuation ends within current map")
	check(not L.reservation_clear(Vector2(L.X,-1810),30),"Road and rock-cut reserved from decorations")
	var poles: Dictionary={}
	var utilities:=preload("res://world/desert/DesertUtilityLines.gd").records()
	var pole_clear:=true
	for record in utilities:
		if record.kind!="utility_pole": continue
		poles[record.position]=true
		if record.position.z<=-1500 and record.position.z>=-1950 and absf(record.position.x-L.X)<65:
			pole_clear=pole_clear and absf(record.position.x-L.X)>=7.5
	check(pole_clear,"Utility poles leave both new lanes and shoulders clear")
	var continuous:=true
	for record in utilities:
		if record.kind=="utility_span": continuous=continuous and poles.has(record.a) and poles.has(record.b)
	check(continuous,"Rerouted overhead spans still connect existing poles")
	for worker in L.workers(): check(absf(worker.position.x-L.X)>7.0 and worker.position.z>-1796,"Workers behind barrier and outside both traffic lanes")
	var stage:=Node3D.new()
	root.add_child(stage)
	# Independent 96m chunks exercise joints at -1824/-1920; no coarse substitute.
	for z in [-2016,-1920,-1824]: ART.build_chunk(stage,Rect2(288,z,96,96))
	await physics_frame
	await physics_frame
	var gates:=get_nodes_in_group(L.GROUP)
	check(gates.size()==1,"One worksite across chunk grid")
	for x in [330.5,333.0,337.5,342.5,347.5,352.0,354.5]:
		check(blocked(Vector3(x,1,-1790),Vector3(x,1,-1840)),"Closed worksite blocks lanes and shoulders x="+str(x))
	for z in [-1835,-1910,-1935]:
		check(blocked(Vector3(300,1,z),Vector3(342.5,1,z)),"West cliff prevents bypass "+str(z))
		check(blocked(Vector3(385,1,z),Vector3(342.5,1,z)),"East cliff prevents bypass "+str(z))
		check(blocked(Vector3(342.5,1,z),Vector3(300,1,z)),"West cliff contains road corridor "+str(z))
		check(blocked(Vector3(342.5,1,z),Vector3(385,1,z)),"East cliff contains road corridor "+str(z))
	if not gates.is_empty(): ART.set_completed(gates[0],true)
	await physics_frame
	for x in [338.5,342.5,346.5]: check(not blocked(Vector3(x,1,-1790),Vector3(x,1,-1938)),"Both directions physically open after completion x="+str(x))
	check(blocked(Vector3(342.5,.73,-1935),Vector3(342.5,.73,-1949)),"End guardrail prevents driving into missing future map")
	if not gates.is_empty(): ART.set_completed(gates[0],false)
	await physics_frame
	check(blocked(Vector3(342.5,1,-1790),Vector3(342.5,1,-1840)),"Restoring old progress restores physical gate")
	stage.free()
	await physics_frame
	var restored:=Node3D.new()
	root.add_child(restored)
	ART.build_chunk(restored,Rect2(288,-1824,96,96),true)
	await physics_frame
	check(not blocked(Vector3(342.5,1,-1790),Vector3(342.5,1,-1840)),"Completed checkpoint constructs open gate before player admission")
	print("DESERT_NORTH_PASS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
