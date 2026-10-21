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
	var north_point:=Vector3(L.X,0,L.END.z+10)
	var safe_point:=Vector3(348,0,L.GATE.z+32)
	check(L.restore_point(north_point,{})==safe_point,"North-corridor save restores south of unfinished works")
	check(L.restore_point(Vector3(318,0,L.GATE.z),{})==safe_point,"Save inside new cliff restores safely")
	check(L.restore_point(north_point,{"desert_story":story})==north_point,"Completed campaign preserves northern saved position")
	check(L.restore_point(Vector3(280,0,north_point.z),{})==Vector3(280,0,north_point.z),"Unrelated northern terrain save remains unchanged")
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
	check(not L.reservation_clear(Vector2(L.X,L.GATE.z),30),"Road and rock-cut reserved from decorations")
	var poles: Dictionary={}
	var utilities:=preload("res://world/desert/DesertUtilityLines.gd").records()
	var pole_clear:=true
	for record in utilities:
		if record.kind!="utility_pole": continue
		poles[record.position]=true
		if record.position.z<=L.JUNCTION.z and record.position.z>=L.END.z-5 and absf(record.position.x-L.X)<65:
			pole_clear=pole_clear and absf(record.position.x-L.X)>=7.5
	check(pole_clear,"Utility poles leave both new lanes and shoulders clear")
	var continuous:=true
	for record in utilities:
		if record.kind=="utility_span": continuous=continuous and poles.has(record.a) and poles.has(record.b)
	check(continuous,"Rerouted overhead spans still connect existing poles")
	for worker in L.workers(): check(absf(worker.position.x-L.X)>7.0 and worker.position.z>L.GATE.z+14,"Workers behind barrier and outside both traffic lanes")
	var stage:=Node3D.new()
	root.add_child(stage)
	# Independent real-grid chunks cover the relocated gate and the entire end.
	for cell_z in range(floori((L.END.z-16)/96),floori((L.GATE.z+32)/96)+1): ART.build_chunk(stage,Rect2(288,cell_z*96,96,96))
	await physics_frame
	await physics_frame
	var gates:=get_nodes_in_group(L.GROUP)
	check(gates.size()==1,"One worksite across chunk grid")
	for x in [330.5,333.0,337.5,342.5,347.5,352.0,354.5]:
		check(blocked(Vector3(x,1,L.GATE.z+20),Vector3(x,1,L.GATE.z-30)),"Closed worksite blocks lanes and shoulders x="+str(x))
	for z in [L.GATE.z-25,lerpf(L.GATE.z,L.END.z,.7),L.END.z+10]:
		check(blocked(Vector3(300,1,z),Vector3(342.5,1,z)),"West cliff prevents bypass "+str(z))
		check(blocked(Vector3(385,1,z),Vector3(342.5,1,z)),"East cliff prevents bypass "+str(z))
		check(blocked(Vector3(342.5,1,z),Vector3(300,1,z)),"West cliff contains road corridor "+str(z))
		check(blocked(Vector3(342.5,1,z),Vector3(385,1,z)),"East cliff contains road corridor "+str(z))
	if not gates.is_empty(): ART.set_completed(gates[0],true)
	await physics_frame
	for x in [338.5,342.5,346.5]: check(not blocked(Vector3(x,1,L.GATE.z+20),Vector3(x,1,L.END.z+7)),"Both directions physically open after completion x="+str(x))
	check(blocked(Vector3(342.5,.73,L.END.z+10),Vector3(342.5,.73,L.END.z-4)),"End guardrail prevents driving into missing future map")
	if not gates.is_empty(): ART.set_completed(gates[0],false)
	await physics_frame
	check(blocked(Vector3(342.5,1,L.GATE.z+20),Vector3(342.5,1,L.GATE.z-30)),"Restoring old progress restores physical gate")
	stage.free()
	await physics_frame
	var restored:=Node3D.new()
	root.add_child(restored)
	ART.build_chunk(restored,Rect2(288,floori(L.GATE.z/96)*96,96,96),true)
	await physics_frame
	check(not blocked(Vector3(342.5,1,L.GATE.z+20),Vector3(342.5,1,L.GATE.z-30)),"Completed checkpoint constructs open gate before player admission")
	print("DESERT_NORTH_PASS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
