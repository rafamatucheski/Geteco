extends SceneTree
const EDITS := preload("res://world/editing/WorldInteriorEdits.gd")
const CATALOG := preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func hit(at: Vector3) -> bool:
	return not root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*4,at-Vector3.UP*2,1)).is_empty()
func run() -> void:
	Engine.set_meta("geteco_live_preview_build",true)
	Engine.set_meta("geteco_world_edit_document",DATA.empty_document())
	var official := DATA.disk_hash()
	var fixture := Node3D.new()
	fixture.name = "InteriorFixture"
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar definition = {\"size\":Vector2(20,20),\"spawn\":Vector3.ZERO,\"exit\":Vector3(0,0,8)}\nvar solid_bounds: Array = []\nvar interaction_points = {\"service\":Vector3(4,0,1.5)}\n"
	check(script.reload() == OK,"Fixture compiles")
	fixture.set_script(script)
	root.add_child(fixture)
	var body := StaticBody3D.new()
	body.name = "DeskSolid"
	body.position = Vector3(4,.5,0)
	body.set_meta("interior_solid_id","desk")
	fixture.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2,1,1)
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	mesh.name = "DeskVisual"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = shape.size
	mesh.position = body.position
	mesh.set_meta("interior_solid_id","desk")
	fixture.add_child(mesh)
	var actor := CharacterBody3D.new()
	actor.name = "ProtectedResident"
	actor.position = Vector3(6,0,5)
	var actor_collider := CollisionShape3D.new()
	actor_collider.shape = CapsuleShape3D.new()
	actor_collider.shape.radius = .3
	actor_collider.shape.height = 1.6
	actor_collider.position.y = .8
	actor.add_child(actor_collider)
	fixture.add_child(actor)
	var initial := EDITS.prepare(fixture,"fixture",DATA.empty_document())
	check(initial.rows.size() == 1,"Furniture mesh and physical solid form one selectable object; actor excluded")
	var row: Dictionary = initial.rows[0].duplicate(true)
	var source_id: String = row.id
	check(row.interior_floor == 0,"Authored objects identify their floor")
	var change := {"id":source_id,"type":"piece","source_record":row.source_record,"position":[-4.0,0.0],"rotation":90.0,"stretch":[2.0,1.0],"height_stretch":1.5,"lift":0.0,"interior_floor":0}
	var doc := DATA.empty_document()
	doc.interiors = {"fixture":{source_id:change}}
	check(DATA.validate_document(doc).is_empty(),"Interior transforms share validated persistent document")
	var moved := EDITS.prepare(fixture,"fixture",doc)
	check(str(moved.error).is_empty(),"Free furniture placement is accepted")
	check(mesh.position.distance_to(Vector3(-4,.75,0)) < .01,"Visual translation and height scale apply")
	check(body.position.distance_to(Vector3(-4,.75,0)) < .01,"Physical solid follows visual")
	check(body.scale.is_equal_approx(Vector3.ONE),"Physical body remains rigid; scale baked into shape")
	check(fixture.interaction_points.service.distance_to(Vector3(-2.5,0,0)) < .01,"Service interaction follows its moved and rotated furniture")
	check(is_instance_valid(actor) and actor.get_parent() == fixture,"Editing preserves original actor and gameplay references")
	await physics_frame
	await physics_frame
	check(hit(Vector3(-4,0,1.5)) and not hit(Vector3(4,0,0)),"Ray sees enlarged rotated collider at new location and no ghost at old location")
	check(actor.test_move(Transform3D(Basis.IDENTITY,Vector3(-4,0,3)),Vector3(0,0,-4)),"A resident-sized capsule cannot cross moved furniture")
	check(not actor.test_move(Transform3D(Basis.IDENTITY,Vector3(4,0,3)),Vector3(0,0,-4)),"A resident-sized capsule can cross the old furniture position")
	doc.interiors.fixture[source_id].deleted = true
	EDITS.prepare(fixture,"fixture",doc)
	await physics_frame
	await physics_frame
	check(not mesh.visible and not hit(Vector3(-4,0,0)),"Deletion removes visible furniture and physical collision together")
	check(not actor.test_move(Transform3D(Basis.IDENTITY,Vector3(-4,0,3)),Vector3(0,0,-4)),"Removing furniture restores physical passage")
	check(not fixture.interaction_points.service.is_finite(),"Deleted service furniture has no ghost interaction")
	EDITS.prepare(fixture,"fixture",DATA.empty_document())
	check(mesh.visible and mesh.position.is_equal_approx(Vector3(4,.5,0)) and collider.shape.size.is_equal_approx(shape.size),"Undo restores original mesh and collider without accumulating scale")
	check(fixture.interaction_points.service.is_equal_approx(Vector3(4,0,1.5)),"Undo restores original service interaction")
	doc.interiors.fixture[source_id].erase("deleted")
	doc.interiors.fixture[source_id].position = [0.0,0.0]
	check(not str(EDITS.prepare(fixture,"fixture",doc).error).is_empty(),"Placement over entrance is refused with actionable error")
	doc.interiors.fixture[source_id].position = [6.0,5.0]
	check(not str(EDITS.prepare(fixture,"fixture",doc).error).is_empty(),"Furniture cannot be saved over a protected resident")
	fixture.free()
	for id in ["westgate_garden","harbor_clothing","mountain_cabin","maciota"]:
		var host := Node3D.new()
		root.add_child(host)
		var built := CATALOG.build_preview(host,id)
		check(str(built.error).is_empty(),"Actual interior builds: "+id)
		if str(built.error).is_empty():
			var result := EDITS.prepare(built.place,id,DATA.empty_document())
			check(result.rows.size() > 5,"Actual house/business furniture is inventoried: "+id)
			var repeated := EDITS.manifest(built.place,id)
			check(repeated == result.rows,"Interior object IDs stay stable on repeated indexing: "+id)
			var second_host := Node3D.new()
			root.add_child(second_host)
			var second := CATALOG.build_preview(second_host,id)
			var rebuilt := EDITS.manifest(second.place,id)
			check(rebuilt.map(func(value): return value.id) == repeated.map(func(value): return value.id),"Object identities survive independent runtime construction: "+id)
			second_host.free()
		host.free()
	check(DATA.disk_hash() == official,"Preview and draft never save the official world document")
	Engine.remove_meta("geteco_live_preview_build")
	Engine.remove_meta("geteco_world_edit_document")
	print("INTERIOR EDITOR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
