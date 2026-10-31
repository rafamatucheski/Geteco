extends SceneTree
## Regressão nativa de código/física; as checagens visuais e de tempo de quadro pertencem ao jogo.
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const HOIST := preload("res://world/regions/NorthstarCargoHoist3D.gd")
const AMBIENCE := preload("res://audio/v1_ambience/AmbienceProfile.gd")
var failures: Array[String] = []
class ImpactDirector extends Node:
	func play_prop_hit(_point: Vector3, _sound: String, _speed: float) -> void: pass
	func spawn_glass(_point: Vector3, _direction: Vector3) -> void: pass
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("WORLD_FEEDBACK ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var mix := AMBIENCE.targets("harbor","maciota",Vector3.ZERO,false,1.0)
	check(mix.values().all(func(weight): return is_zero_approx(float(weight))),"Maciota has no local ambience layers")
	check(AMBIENCE.activity_context("harbor","maciota",Vector3.ZERO).is_empty(),"Maciota suppresses random workshop activity sounds")
	check(AMBIENCE.targets("desert","desert_digo",Vector3.ZERO,false,1.0).workshop > 0,"Other workshops retain their sound")
	var hoist := HOIST.new()
	root.add_child(hoist)
	hoist.set_process(false)
	var bounds := AABB()
	var first := true
	var textured := false
	for part: MeshInstance3D in hoist.load_mesh.get_children():
		var local: AABB = part.transform*part.get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
		if part.material_override is StandardMaterial3D and part.material_override.albedo_texture != null: textured = true
	check(bounds.size.x > 2.3 and bounds.size.y > 2.8 and bounds.size.z > 12.0,"Hoisted cargo has full 40-foot ISO dimensions")
	check(textured,"Hoisted cargo reuses detailed textured shipping container")
	for sample in [0.0,6.0,15.0,21.0,27.0]:
		hoist.clock = sample
		hoist._update_pose()
		check(hoist.load_mesh.position.y >= 0 and hoist.cable.scale.y > 0,"Cargo stays above deck with positive cable length at "+str(sample))
	var chunk := Node3D.new()
	chunk.name = "Chunk_Feedback"
	chunk.set_meta("vegetation_ready_frame",0)
	root.add_child(chunk)
	var tree := PROP.new()
	tree.configure(PROP._tree_record(Vector2.ZERO,1,1.0,"446b53","feedback"))
	chunk.add_child(tree)
	for i in 5: await process_frame
	check(tree.has_meta("street_fragile_item"),"Harbor tree registers for swept vehicle impact")
	var item: Dictionary = tree.get_meta("street_fragile_item",{})
	check(item.get("kind","") == "harbor_tree","Tree uses falling wood profile")
	var director := ImpactDirector.new()
	root.add_child(director)
	check(FRAGILE.hit(item,5.0,Vector3.RIGHT,director),"Vehicle impact breaks trunk anchorage")
	for i in 80: await physics_frame
	check(tree.global_basis.y.dot(Vector3.UP)<.2,"Struck tree falls over from its base")
	check(not tree.has_meta(PROP.INSTANCING.FURNITURE_STATE),"First fall restores individual tree geometry from chunk batching")
	check(tree.solids.collision_layer == 0,"Fallen tree releases the standing trunk collider")
	chunk.free()
	hoist.free()
	director.free()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
