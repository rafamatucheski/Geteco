extends SceneTree
const DETAIL := preload("res://gameplay/urban_v1/VerticeSiteDressing.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	var detail:=DETAIL.new()
	stage.add_child(detail)
	for frame in 3: await physics_frame
	var stations:=0
	for placement in detail.placements:
		if String(placement.id).begins_with("Packing"):
			stations+=1
			check(placement.center.z-placement.size.z*.5>=6.8 and placement.center.z+placement.size.z*.5<=9.2,"Packing furniture stays inside allocated depth")
	check(stations==6,"Both stations have bench, roller bed and parcel trolley colliders")
	for player in [true,false]:
		var actor:=ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		actor.position=Vector3(100,.04,100)
		stage.add_child(actor)
		actor.set_physics_process(false)
		var who:="Player" if player else "NPC"
		for frame in 2: await physics_frame
		for x in [-19.0,19.0]:
			for hit in [
				[Vector3(x-.55,.04,5),Vector3(0,0,4),"bench"],
				[Vector3(x-.55,.04,11),Vector3(0,0,-4),"roller bed"],
				[Vector3(x+1.35,.04,11),Vector3(0,0,-4),"parcel trolley"]]:
				actor.position=hit[0]
				check(actor.move_and_collide(hit[1])!=null,who+" actual motion stops at "+hit[2]+str(x))
				check(is_equal_approx(actor.position.y,.04),who+" remains on ground at "+hit[2])
		actor.position=Vector3(100,.04,100)
		for x in [-24.0,-12.0,0.0,12.0,24.0]:
			check(not actor.test_move(Transform3D(Basis.IDENTITY,Vector3(x,.04,3)),Vector3(0,0,12)),who+" longitudinal aisle remains clear x"+str(x))
		check(not actor.test_move(Transform3D(Basis.IDENTITY,Vector3(-25,.04,12)),Vector3(50,0,0)),who+" full transverse aisle remains clear z12")
		for x in [-18.0,0.0,18.0]:
			check(not actor.test_move(Transform3D(Basis.IDENTITY,Vector3(x,.04,17)),Vector3(0,0,-5)),who+" dock vestibule remains clear "+str(x))
		actor.free()
	print("VERTICE_PACKING checks=",checks," failures=",failures)
	stage.free()
	quit(0 if failures.is_empty() else 1)
