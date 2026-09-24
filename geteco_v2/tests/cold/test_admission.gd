extends SceneTree
class SessionStub extends Node:
	var ready_for_play := false
	var state := {"region_id":"mountain"}
const COLD = preload("res://runtime/ColdSurvival.gd")
const HEAT = preload("res://runtime/cold/OriginalHeatSources.gd")
var errors: Array[String] = []
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: errors.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var session := SessionStub.new()
	world.add_child(session)
	var cold = COLD.new()
	cold.configure(session)
	world.add_child(cold)
	cold.set_process(false)
	var first := HEAT.to_world(Vector2(5980,715))
	check(not cold.prepare_collision_at(first),"first admission rejected while installing solid")
	check(cold.presentation.visuals.size()==1,"only source within8m installed")
	check(not cold.prepare_collision_at(first),"same physics frame still rejected")
	await physics_frame
	await physics_frame
	check(cold.prepare_collision_at(first),"admission proceeds after physics sync")
	var query := PhysicsShapeQueryParameters3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.3,1.5,5)
	query.shape = hull
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,first+Vector3.UP*.85)
	check(not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"saved car hull sees brazier solid")
	var second := HEAT.to_world(Vector2(7650,-1553))
	check(not cold.prepare_collision_at(second),"second source requires physical sync")
	check(cold.presentation.visuals.has("outfitters_heater") and cold.presentation.visuals.has("transit_village"),"ensure retains previously installed source")
	await physics_frame
	await physics_frame
	check(cold.prepare_collision_at(second),"second source ready")
	check(cold.prepare_collision_at(Vector3.ZERO),"no source needs no installation")
	check(not cold.prepare_collision_at(Vector3(NAN,0,0)),"invalid position rejected")
	session.state.region_id = "harbor"
	check(cold.prepare_collision_at(first),"Harbor has no mountain admission dependency")
	world.free()
	print("COLD_ADMISSION checks=",checks," failures=",errors)
	quit(0 if errors.is_empty() else 1)
