extends SceneTree
## A restored dune position must have matching support before deferred dressing.
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var region:=REGION.new()
	region.initial_prewarm_only=true
	root.add_child(region)
	region.set_process(false)
	var point:=Vector3(-25,0,-622)
	for cycle in 2:
		check(region.prepare_collision_at(point),"admission accepts dune cell")
		check(not region.is_streaming_idle(),"deferred dressing deliberately remains pending")
		for i in 3: await physics_frame
		var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*8,point+Vector3.DOWN*2,1)
		var hit: Dictionary=region.get_world_3d().direct_space_state.intersect_ray(ray)
		var expected:=LAND.surface_height(Vector2(point.x,point.z),region._ground_height)
		check(not hit.is_empty() and absf(float(hit.get("position",Vector3.ZERO).y)-expected)<.035,"visible dune support is physically ready before dressing cycle%d"%cycle)
		check(expected>1.5,"probe really exercises raised dune instead of flat fallback")
		region.release_chunks()
		for i in 3: await physics_frame
	region.free()
	print("DESERT_EXPANSION_ADMISSION checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
