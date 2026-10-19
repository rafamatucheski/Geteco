extends SceneTree
## Focused regression: real collision at the paddock seam, reversible physical
## obstruction, and queue ownership while the driver explores on foot.
const MEET := preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const OPEN := preload("res://activities/desert_drag/DragOpenMeet.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
var failures: Array[String] = []

class Hull extends CharacterBody3D:
	var speed := 0.0
	var health := 100.0
	var engine_disabled := false
	func _ready() -> void:
		collision_layer=4
		collision_mask=1
		floor_snap_length=.3
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size=Vector3(3.8,1.3,1.8)
		collider.shape=box
		collider.position.y=.65
		add_child(collider)

class Session extends Node:
	var ready_for_play := false
	var world: Dictionary = {"driving":{"occupied":false,"car":null}}
	var messages: Array[String] = []
	func show_message(message: String) -> void: messages.append(message)

class Race extends Node3D:
	var session
	var active := false
	var direction := Vector3.RIGHT
	var starts := 0
	var cancelled := 0
	func start_block_reason() -> String: return ""
	func start_rival(_identity: String) -> bool:
		starts+=1
		return true
	func cancel_waiting_context(_reason: String) -> void: cancelled+=1

func _initialize() -> void:
	create_timer(25).timeout.connect(func(): push_error("MEET_REDESIGN timeout"); quit(3))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("MEET_REDESIGN ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var mat := StandardMaterial3D.new()
	G.quad(scene,"RoadDatum",PackedVector3Array([Vector3(-1060,0,-1290),Vector3(-1020,0,-1290),Vector3(-1020,0,-1270),Vector3(-1060,0,-1270)]),mat,true)
	MEET.build_ground(scene,Rect2(-1050,-1285,30,10))
	var hull := Hull.new()
	hull.position=Vector3(-1046,.08,-1280)
	scene.add_child(hull)
	for frame in 20: await physics_frame
	for sign_x in [1.0,-1.0]:
		for frame in 180:
			await physics_frame
			hull.velocity=Vector3(sign_x*4.0,0.0 if hull.is_on_floor() else hull.velocity.y-18.0/60.0,0)
			hull.move_and_slide()
		check(hull.position.x>-1036 if sign_x>0 else hull.position.x<-1044,"car-sized hull crosses actual paddock boundary %s without snap"%str(sign_x))
		check(absf(hull.position.y)<.02,"continuous physical floor support at road datum")
	var session := Session.new()
	root.add_child(session)
	var race := Race.new()
	race.session=session
	scene.add_child(race)
	var queue := OPEN.new()
	queue.configure(race)
	race.add_child(queue)
	session.world.driving.car=hull
	queue.registered_car=hull
	queue.pending="livia"
	queue._dispatch(30.0)
	check(queue.pending=="livia" and race.starts==0 and queue.ready_clock==0.0,"waiting on foot preserves ticket and does not consume admission timeout")
	check(queue.ticket().on_foot and not str(queue.ticket().reason).is_empty(),"queue exposes an actionable reboarding reason")
	session.world.driving.occupied=true
	queue._dispatch(.1)
	check(queue.pending.is_empty() and race.starts==1 and race.cancelled==0,"reboarding dispatches and consumes ticket without cancelling its context")
	queue.clear_visit()
	check(race.cancelled==0,"releasing ambient visit after ticket consumption preserves the race context")
	queue.registered_car=hull
	queue.pending="livia"
	queue.cancel_ticket(false,"fixture cancellation")
	check(race.cancelled==1 and queue.pending.is_empty(),"explicit cancellation disarms pending context")
	var drive := DRIVE.new()
	drive.configure("desert_faisca")
	queue.pending="livia"
	queue.heat=[{"car":hull,"drive":drive,"finish":INF}]
	queue.phase="blocked"
	queue.blocked_phase="racing"
	var obstacle := G.box(scene,"TemporaryObstruction",hull.position+Vector3(2.3,.7,0),Vector3(.5,1.4,2.0),Color.GRAY,true)
	await physics_frame
	await physics_frame
	queue._try_resume_blocked(.6)
	check(queue.phase=="blocked" and queue.pending=="livia","actual obstruction keeps heat stopped and preserves the ticket")
	obstacle.queue_free()
	await physics_frame
	await physics_frame
	queue._try_resume_blocked(.6)
	check(queue.phase=="racing" and queue.pending=="livia" and drive.gear==1,"removing obstruction resumes heat from rest without a fake finish")
	queue.heat.clear()
	var visitor := preload("res://runtime/desert/drag_meet/DragMeetGuest.gd").new()
	visitor.identity=9808
	visitor.position=Vector3(-1030,.03,-1280)
	visitor.specification={"coat":Color("754534"),"walk_end":visitor.position,"focus":visitor.position+Vector3.RIGHT,"team":"test","roamer":false}
	scene.add_child(visitor)
	await physics_frame
	check(visitor.visual.get_child_count()==1,"authored guest creates exactly one visible body")
	if preload("res://assets/civilians/CivilianBodyCatalog.gd").enabled:
		check(not visitor.person.body_source.is_empty(),"authored guest uses an available current body")
		var appearance := preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd")
		var rig_class := preload("res://assets/civilians/MeshyBodyRig.gd")
		var was_counting: bool = rig_class.count_sync_calls
		rig_class.count_sync_calls=true
		appearance.set_animation_active(visitor.person,false)
		var before_sync: int = rig_class.sync_calls
		var before_clock: float = visitor.person.clock
		for frame in 4: await process_frame
		check(visitor.person.visible and not visitor.person.is_processing() and not visitor.person._meshy.driver.is_processing() and rig_class.sync_calls==before_sync and visitor.person.clock==before_clock,"freezing a visible imported guest stops both procedural pose and child rig sync")
		appearance.set_animation_active(visitor.person,true)
		for frame in 4: await process_frame
		check(visitor.person.is_processing() and visitor.person._meshy.driver.is_processing() and rig_class.sync_calls>before_sync,"reactivating guest restores real rig synchronization")
		appearance.set_animation_active(visitor.person,false)
		visitor.alert(visitor.global_position+Vector3.RIGHT)
		check(visitor.person.is_processing() and visitor.person._meshy.driver.is_processing(),"threat wakes a previously frozen imported guest")
		appearance.set_animation_active(visitor.person,false)
		rig_class.count_sync_calls=was_counting
	visitor.receive_damage(5.0)
	check(visitor.health==95.0 and visitor._panic>0.0,"current body preserves civilian damage and retreat")
	if visitor.person._meshy != null:
		check(visitor.person._meshy.driver.is_processing(),"damage restores imported rig synchronization")
		visitor.receive_damage(1000.0)
		preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(visitor.person,false)
		check(visitor.dead and visitor.person._meshy.driver.is_processing(),"distance suppression cannot stop the dead guest's fall pose driver")
	var ids: Array[String] = []
	for entry in preload("res://activities/desert_drag/DragOpenRoster.gd").CARS.values():
		if str(entry.car) not in ids: ids.append(str(entry.car))
	check(ids.size()==6,"six open visitors have six actual vehicle archetypes")
	print("MEET_REDESIGN failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
