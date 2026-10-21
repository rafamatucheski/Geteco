extends SceneTree
const SNAPSHOTS := preload("res://world/editing/WorldStaticSnapshots.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var official := DATA.disk_hash()
	var source := Node3D.new()
	source.name = "SnapshotFixture_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	source.position = Vector3(12,0,24)
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar gameplay_only := true\n"
	check(script.reload() == OK,"Fixture script compiles")
	source.set_script(script)
	root.add_child(source)
	source.add_to_group("gameplay_fixture")
	source.set_meta("editor_id","building/special_fixture")
	var mesh := MeshInstance3D.new()
	mesh.name = source.name
	mesh.mesh = BoxMesh.new()
	mesh.layers = 0
	mesh.set_meta("world_snapshot_visual_layers",1)
	mesh.position.y = .5
	source.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_meta("world_snapshot_collision_layer",1)
	body.set_meta("world_snapshot_collision_mask",0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.position.y = .5
	body.add_child(shape)
	source.add_child(body)
	var trigger := Area3D.new()
	trigger.name = "GameplayTrigger"
	source.add_child(trigger)
	var capture := SNAPSHOTS.capture([source,mesh],source.global_position)
	check(str(capture.get("error","missing")).is_empty(),"Special scenery captures to a draft")
	if not str(capture.get("error","missing")).is_empty(): source.free(); quit(1); return
	var id: String = capture.snapshot_id
	var staged := SNAPSHOTS.STAGING+id+".scn"
	var published := SNAPSHOTS.PUBLISHED+id+".scn"
	check(SNAPSHOTS.valid_id(id) and not SNAPSHOTS.valid_id("../../map"),"Only content-addressed snapshot IDs accepted")
	check(FileAccess.file_exists(staged) and not FileAccess.file_exists(published),"Copy only stages geometry before Save")
	check(source.get_script() == script and source.get_groups().has("gameplay_fixture"),"Capture preserves source behavior and identity")
	var row := DATA.new_entity("prop",Vector2(-350,-900))
	row.model = "static_snapshot"
	row.snapshot_id = id
	row.size = capture.size
	row.rotation = 90.0
	var doc := DATA.empty_document()
	doc.regions.desert[row.id] = row
	check(DATA.validate_document(doc).is_empty(),"Snapshot has a normal persistent editor row in another map")
	var instance := SNAPSHOTS.instantiate(row)
	check(instance != null,"Draft geometry instantiates before publishing")
	if instance != null:
		root.add_child(instance)
		check(instance.find_children("*","MeshInstance3D",true,false).size() == 1,"Nested selection is captured once")
		check(instance.find_children("*","MeshInstance3D",true,false)[0].layers == 1,"Copy restores authored visual layers when distant preview detail is suppressed")
		var bodies := instance.find_children("*","StaticBody3D",true,false)
		check(bodies.size() == 1 and bodies[0].collision_layer == 1,"Original physical collision survives passive preview capture")
		check(instance.find_children("*","Area3D",true,false).is_empty(),"Copied scenery never duplicates gameplay triggers")
		var copied := instance.get_child(0)
		check(copied.get_script() == null and copied.get_groups().is_empty() and not copied.has_meta("editor_id"),"Copy strips scripts, gameplay groups and source identities")
		check(is_equal_approx(instance.rotation.y,PI/2),"New copy supports independent rotation")
		await physics_frame
		await physics_frame
		var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2,.5,0),Vector3(2,.5,0),1))
		check(not hit.is_empty(),"Copied static collider blocks a real physics ray")
		instance.free()
	check(SNAPSHOTS.promote_document(doc).is_empty() and FileAccess.file_exists(published),"Only explicit promotion publishes immutable geometry")
	source.free()
	# Remove the draft and source to prove that the saved copy is independent.
	DirAccess.remove_absolute(staged)
	instance = SNAPSHOTS.instantiate(row)
	check(instance != null,"Published geometry reloads without original preview or draft")
	if instance != null: instance.free()
	var bad := doc.duplicate(true)
	bad.regions.desert[row.id].snapshot_id = "0".repeat(64)
	check(not SNAPSHOTS.promote_document(bad).is_empty(),"Missing geometry blocks publication")
	check(DATA.disk_hash() == official,"Official world document stays untouched")
	DirAccess.remove_absolute(published)
	print("WORLD_STATIC_SNAPSHOTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
