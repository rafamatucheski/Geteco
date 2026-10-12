extends SceneTree
const PLACE := preload("res://world/places/amusement_park/HauntedHousePlace.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []
var room: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("UMBRA ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Umbra test deadline"); quit(3))
	room = PLACE.new()
	room.definition = PLACE.definition_data()
	root.add_child(room)
	for i in 4: await physics_frame
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		actor.collision_mask = 1
		root.add_child(actor)
		actor.speed = 4.0
		actor.teleport(Vector3(0,.04,-9.7))
		for i in 8: await physics_frame
		for point in [Vector3(-6,0,-10),Vector3(-6,3.5,-20),Vector3(0,3.5,-23),Vector3(6,3.5,-20),Vector3(6,0,-10),Vector3(0,0,-10),Vector3(3,0,-12),Vector3(3,0,-21),Vector3(0,0,-22)]:
			var deadline := Time.get_ticks_msec()+9000
			while Time.get_ticks_msec()<deadline:
				var offset: Vector3 = point-actor.position
				offset.y = 0
				if offset.length()<.18: break
				actor.automatic_direction = offset.normalized()
				await physics_frame
			actor.automatic_direction = Vector3.ZERO
			for i in 3: await physics_frame
			check(Vector2(actor.position.x-point.x,actor.position.z-point.z).length()<.3,"walk player=%s point=%s actual=%s"%[player,point,actor.position])
			check(absf(actor.position.y-point.y)<.20,"supported on correct floor player=%s at=%s"%[player,point])
		actor.set_physics_process(false)
		for row in [[Vector3(0,0,-12),Vector3(0,0,-5)],[Vector3(0,3.5,-23),Vector3(0,0,-4)],[Vector3(0,3.5,-20),Vector3(0,0,5)],[Vector3(-6,1.8,-14.5),Vector3(3,0,0)],[Vector3(-3.1,3.5,-23),Vector3(0,0,-3)]]:
			var pose := actor.global_transform
			pose.origin = row[0]
			check(actor.test_move(pose,row[1]),"full capsule blocked by table/hearth/balustrade/stair rail/crib player=%s"%player)
		actor.free()
	var annex = room.model.annex
	check(annex.scares.size()==5,"five independent scare stations")
	for station in annex.scares:
		var start: Transform3D = station.rig.transform
		annex.update_visitor(station.trigger,.12)
		check(station.count==1 and station.rig.transform!=start,"proximity animates "+str(station.rig.name))
		for i in 160: annex.update_visitor(station.trigger,.1)
		check(station.count==1,"standing still does not spam "+str(station.rig.name))
		annex.update_visitor(Vector3(40,0,40),.1)
		annex.update_visitor(station.trigger,.1)
		check(station.count==2,"leaving and returning rearms "+str(station.rig.name))
	check(room.model.find_children("*","SubViewport",true,false).is_empty(),"native shared renderer")
	print("UMBRA_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
