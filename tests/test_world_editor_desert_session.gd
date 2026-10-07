extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func find_id(node: Node,id: String) -> Node:
	if node.get_meta("editor_id","")==id: return node
	for child in node.get_children():
		var result := find_id(child,id)
		if result!=null: return result
	return null
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("EDITOR_DESERT_SESSION timeout"); quit(3))
	var official := DATA.disk_hash()
	var folder := FIXTURE.output_dir("editor-desert-session")
	var at := Vector3(-390,.08,-940)
	var snapshot := FIXTURE.full_snapshot(at,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(folder,"save.json",snapshot)
	var doc := DATA.empty_document()
	var prop := DATA.new_entity("prop",Vector2(-393,-942))
	prop.model = "crate"
	prop.id = "new/desert_session_crate"
	doc.regions.desert[prop.id] = prop
	var edits := folder.path_join("world_edits.json")
	check(DATA.save_document(doc,"",edits).is_empty(),"World edit document saved separately from player save")
	Engine.set_meta("geteco_world_edit_document",DATA.read_document(edits).document)
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"Main runs the C# routing path")
	var region: Node3D = world.production.regions.get("desert")
	check(region!=null and region.get_script().resource_path.ends_with("EditableDesertRegion.gd"),"Gameplay uses the editor adapter")
	for frame in 3: await physics_frame
	var art := find_id(region,prop.id)
	check(art!=null,"Saved editor object appears in gameplay")
	var query := PhysicsRayQueryParameters3D.create(Vector3(-393,3,-942),Vector3(-393,-1,-942),1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and art!=null and art.is_ancestor_of(hit.collider),"Edited object's collision is active in the real world")
	region.release_chunks()
	await process_frame
	region.set_focus(at)
	while not region.is_streaming_idle(): await process_frame
	check(find_id(region,prop.id)!=null,"Saved object returns after unloading and reentering")
	check(DATA.disk_hash()==official,"Official editor document untouched")
	print("EDITOR_DESERT_SESSION ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
