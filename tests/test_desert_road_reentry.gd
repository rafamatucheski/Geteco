extends SceneTree
## Production road/ground geometry and actual vehicle movement across both edges.
const ROAD := preload("res://world/desert/DesertRoadGeometry.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): quit(3))
	run.call_deferred()

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var region := REGION.new()
	var roads := ROAD.new()
	roads.configure(LAYOUT.roads())
	for cell in [Vector2i(3,-12),Vector2i(3,-11)]:
		var rect := Rect2(Vector2(cell)*96,Vector2.ONE*96)
		region._surface(scene,"DesertGround",rect,0,preload("res://world/desert/DesertGeometry.gd").material(Color("b9a079"),true),true)
		roads.build_chunk(scene,rect)
	await physics_frame
	for id in ["desert_coyote","desert_bison"]:
		for side in [-1.0,1.0]:
			var car := VEHICLE.new()
			car.archetype=id
			car.position=Vector3(342.5+side*14,.1,-1100)
			car.rotation.y=side*PI*.5
			scene.add_child(car)
			car.set_external_driver(true)
			for i in 30: await physics_frame
			car.throttle_input=.55
			car.brake_input=false
			var walls: Array[String]=[]
			for i in 360:
				await physics_frame
				for j in car.get_slide_collision_count():
					var hit := car.get_slide_collision(j)
					if absf(hit.get_normal().y)<.65:
						var path := str(hit.get_collider().get_path())
						if not walls.has(path): walls.append(path)
				if (car.position.x-342.5)*side < -10: break
			var ok: bool = (car.position.x-342.5)*side < -10 and walls.is_empty() and car.position.y>-.1
			var label := "%s side=%s end=%s walls=%s"%[id,side,car.position,walls]
			print("ROAD_REENTRY ","PASS " if ok else "FAIL ",label)
			if not ok: failures.append(label)
			car.queue_free()
			await physics_frame
	region.free()
	scene.free()
	quit(0 if failures.is_empty() else 1)
