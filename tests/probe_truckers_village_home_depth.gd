extends SceneTree
## Authored actor positions around visible furniture for rendered depth QA.
const HOMES := preload("res://gameplay/urban_v1/TruckersVillageHomes.gd")
const LAYOUT := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").HOME_LAYOUT
const POSES := [
	{"furniture":Vector3(-4.4,.6,1.6),"front":Vector3(-4.4,0,2.6),"behind":Vector3(-4.4,0,.6),"side":Vector3(-2.8,0,1.6)},
	{"furniture":Vector3(4.5,.6,1.8),"front":Vector3(4.5,0,2.8),"behind":Vector3(4.5,0,.8),"side":Vector3(2.9,0,1.8)},
	{"furniture":Vector3(4.2,.45,1.6),"front":Vector3(4.9,0,2.8),"behind":Vector3(4.9,0,.4),"side":Vector3(2.7,0,1.6)},
	{"furniture":Vector3(4.9,.85,1.8),"front":Vector3(4.9,0,2.8),"behind":Vector3(4.9,0,.8),"side":Vector3(3.65,0,1.8)},
	{"furniture":Vector3(-4.1,.45,1.4),"front":Vector3(-3.4,0,2.6),"behind":Vector3(-3.4,0,.2),"side":Vector3(-2.5,0,1.4)},
	{"furniture":Vector3(-4.5,.6,1.7),"front":Vector3(-4.5,0,2.7),"behind":Vector3(-4.5,0,.7),"side":Vector3(-2.9,0,1.7)}]
func _initialize(): run.call_deferred()
func run() -> void:
	var village:=Node3D.new()
	root.add_child(village)
	var homes:=HOMES.new()
	village.add_child(homes)
	homes.build(village,LAYOUT)
	for i in 3: await physics_frame
	var failures:=[]
	for index in 6:
		var home:Node3D=homes.homes[index].root
		for key in ["front","behind","side"]:
			var shape:=CapsuleShape3D.new()
			shape.radius=.32
			shape.height=1.8
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=shape
			query.transform.origin=home.to_global(POSES[index][key]+Vector3.UP*.94)
			query.collision_mask=1
			var hits:=village.get_world_3d().direct_space_state.intersect_shape(query)
			if not hits.is_empty(): failures.append("home%d/%s %s"%[index,key,hits])
	print("HOME_DEPTH_POSES checked=18 failures=",failures)
	village.free()
	quit(0 if failures.is_empty() else 1)
