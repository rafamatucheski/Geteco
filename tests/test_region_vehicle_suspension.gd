extends SceneTree
class RegionProbe extends "res://world/regions/NativeRegion.gd":
	func _ready() -> void: pass
var failures:=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func car(point:Vector3)->CharacterBody3D:
	var body:=CharacterBody3D.new()
	body.position=point
	root.add_child(body)
	body.add_to_group("drivable")
	body.set_physics_process(true)
	return body
func run():
	var harbor:=RegionProbe.new();harbor.region_id="harbor";root.add_child(harbor)
	var mountain:=RegionProbe.new();mountain.region_id="mountain";root.add_child(mountain)
	# Same chunk key, opposite sides of the logical region seam.
	var west:=car(Vector3(455,0,-285))
	var east:=car(Vector3(457,0,-285))
	var key:=harbor._cell(west.position)
	check(key==mountain._cell(east.position),"Fixture uses overlapping regional cells")
	harbor._suspend_chunk_vehicles(key)
	check(not west.is_physics_processing() and west.has_meta("awaiting_ground"),"Harbor suspends its own unsupported vehicle")
	check(east.is_physics_processing() and not east.has_meta("awaiting_ground"),"Harbor eviction preserves Mountain vehicle physics")
	west.remove_meta("awaiting_ground");west.set_physics_process(true)
	mountain._suspend_chunk_vehicles(key)
	check(not east.is_physics_processing() and east.has_meta("awaiting_ground"),"Mountain suspends its own unsupported vehicle")
	check(west.is_physics_processing() and not west.has_meta("awaiting_ground"),"Mountain eviction preserves Harbor vehicle physics")
	for node in [west,east,harbor,mountain]:node.free()
	print("REGION_VEHICLE_SUSPENSION failures=",failures)
	quit(1 if failures else 0)
