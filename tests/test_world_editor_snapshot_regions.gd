extends SceneTree
## A staged static asset must reconstruct through each production region adapter.
const DATA := preload("res://world/editing/WorldEditData.gd")
const SNAPSHOTS := preload("res://world/editing/WorldStaticSnapshots.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var official := DATA.disk_hash()
	var source := Node3D.new()
	source.name = "RegionSnapshot_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	root.add_child(source)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position.y = .5
	source.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.position.y = .5
	body.add_child(shape)
	source.add_child(body)
	var captured := SNAPSHOTS.capture([source],Vector3.ZERO)
	check(str(captured.get("error","missing")).is_empty(), "Static source captures without publishing")
	source.free()
	if not str(captured.get("error","missing")).is_empty(): quit(1); return
	for spec in [["harbor",Vector2(45,110)],["mountain",Vector2(850,-450)],["desert",Vector2(354,-740)]]:
		var area: String = spec[0]
		var at: Vector2 = spec[1]
		var row := DATA.new_entity("prop",at)
		row.model = "static_snapshot"
		row.snapshot_id = captured.snapshot_id
		row.size = captured.size
		row.rotation = 30.0
		row.scale = 1.5
		var document := DATA.empty_document()
		document.regions[area][row.id] = row
		Engine.set_meta("geteco_world_edit_document",document)
		var region: Variant = REGION.build_region(area)
		region.prepare_data()
		Engine.remove_meta("geteco_world_edit_document")
		var holder := Node3D.new()
		root.add_child(holder)
		for records: Array in region.records.values():
			for record: Dictionary in records:
				if record.get("kind","") in ["editor_prop","editor_added"] and record.get("data",{}).get("id","") == row.id:
					region._build_record(holder,record)
		var copy: Node3D = holder.get_child(0) if holder.get_child_count() == 1 else null
		check(copy != null, area+": production adapter creates exactly one pasted snapshot")
		if copy != null:
			check(copy.get_meta("editor_id","") == row.id and Vector2(copy.position.x,copy.position.z).is_equal_approx(at), area+": copy restores independent identity and destination")
			check(is_equal_approx(copy.rotation.y,deg_to_rad(30)) and copy.scale.is_equal_approx(Vector3.ONE*1.5), area+": copy restores scale and rotation once")
			await physics_frame
			await physics_frame
			var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(copy.position+Vector3(-2,.5,0),copy.position+Vector3(2,.5,0),1))
			check(not hit.is_empty(), area+": copied physical solid blocks a real ray at destination")
		holder.free()
		region.free()
	DirAccess.remove_absolute(SNAPSHOTS.STAGING+str(captured.snapshot_id)+".scn")
	check(DATA.disk_hash() == official, "Cross-map runtime reconstruction preserves the official world")
	print("WORLD_EDITOR_SNAPSHOT_REGIONS checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
