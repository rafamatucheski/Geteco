extends SceneTree
const POLICY:=preload("res://runtime/desert/DesertPopulation.gd")
const SOCIAL:=preload("res://runtime/desert/DesertSocialActor.gd")
const DIRECTOR:=preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")
var failures:=0
class CrowdWorld extends Node3D:
	var people: Array=[]
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	print("DESERT_SOCIAL ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func run() -> void:
	seed(6102026)
	var near_end:=0
	var on_segment:=true
	for i in 500:
		var t:=POLICY.nearby_parameter(Vector3.ZERO,Vector3(1000,0,0),Vector3(25,0,0),95)
		on_segment=on_segment and t>=0 and t<=1
		if absf(t*1000-25)<95: near_end+=1
	check(near_end>450,"long-road endpoints can actually receive traffic")
	check(on_segment,"traffic samples stay on segment")
	var areas:={"santa_lua":Rect2(-565,-865,75,87),"truckstop":Rect2(235,-795,90,70),"town":Rect2(-275,-875,125,20)}
	var counts:={}
	for slot in POLICY.slots():
		counts[slot.place]=int(counts.get(slot.place,0))+1
		for point in slot.route:
			check(areas[slot.place].has_point(Vector2(point.x,point.z)),"routine remains within inhabited destination")
	check(counts.santa_lua<=8 and counts.truckstop<=6 and counts.town<=6,"small settlements have bounded occupancy")
	var stage:=CrowdWorld.new()
	root.add_child(stage)
	var floor_body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(160,1,160)
	collider.shape=box; collider.position.y=-.5
	floor_body.add_child(collider); stage.add_child(floor_body)
	var resident=SOCIAL.new()
	resident.identity=6100
	resident.position=Vector3(0,.08,0)
	resident.route=PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
	stage.add_child(resident); stage.people.append(resident)
	var director=DIRECTOR.new()
	stage.add_child(director); director.configure(stage,null)
	for i in 90: await physics_frame
	check(resident.is_on_floor() and resident.global_position.length()<.2,"conversation stands on physical ground")
	check(resident.person.activity=="talk","conversation uses the animated civilian gesture")
	director.report_explosion(Vector3(4,0,0),20)
	for i in 90: await physics_frame
	check(resident.controlled_automatically and resident.global_position.length()>1,"real reaction director can move the resident away from danger")
	check(resident.person.activity=="","panic interrupts conversation")
	for i in 1800: await physics_frame
	check(not resident.controlled_automatically,"real reaction timer releases control")
	print("DESERT_SOCIAL recovery position=",resident.position," speed=",resident.speed," activity=",resident.person.activity)
	check(Vector2(resident.position.x,resident.position.z).length()<.8 and resident.person.activity=="talk","resident returns home and resumes conversation")
	stage.people.clear(); resident.queue_free()
	for i in 3: await physics_frame
	check(director.reactors.is_empty(),"retirement leaves no reaction owner")
	stage.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
