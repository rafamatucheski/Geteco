extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const GROUND := preload("res://world/editing/WorldGroundFactory.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func grounds(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.get_meta("editor_ground",false): result.append(node)
	for child in node.get_children(): result.append_array(grounds(child))
	return result
func area(node: MeshInstance3D) -> float:
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var total := 0.0
	for i in range(0,vertices.size(),3):
		var a := Vector2(vertices[i].x,vertices[i].z)
		var b := Vector2(vertices[i+1].x,vertices[i+1].z)
		var c := Vector2(vertices[i+2].x,vertices[i+2].z)
		total += absf((b-a).cross(c-a))*.5
	return total
func hit(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*2,1)
	return root.world_3d.direct_space_state.intersect_ray(query)
func run() -> void:
	var doc := DATA.empty_document()
	for index in GROUND.SURFACES.size():
		var row := DATA.new_entity("ground",Vector2(2500+index*20,2500))
		row.id = "new/ground_test_"+str(index)
		row.surface = GROUND.SURFACES[index]
		row.rotation = 31.0
		doc.regions.harbor[row.id] = row
		check(DATA.validate_entity(row).is_empty(),"Accept ground: "+row.surface)
		check(GROUND.material(row.surface) == GROUND.material(row.surface),"Shared material: "+row.surface)
	var crossing := DATA.new_entity("ground",Vector2(2560,2560))
	crossing.id = "new/ground_boundary"
	crossing.size = [32.0,24.0]
	crossing.rotation = 37.0
	doc.regions.harbor[crossing.id] = crossing
	var invalid := crossing.duplicate(true)
	invalid.size = [65.0,5.0]
	check(not DATA.validate_entity(invalid).is_empty(),"Oversized ground rejected")
	invalid.size = [0.0,5.0]
	check(not DATA.validate_entity(invalid).is_empty(),"Empty ground rejected")
	invalid.size = [8.0,8.0]
	invalid.surface = "unknown"
	check(not DATA.validate_entity(invalid).is_empty(),"Unknown surface rejected")
	var path := "res://evidence/world-editor-20260925/ground_test_"+str(OS.get_process_id())+".json"
	check(DATA.save_document(doc,"",path).is_empty(),"Save ground document")
	var loaded := DATA.read_document(path)
	check(loaded.error.is_empty() and loaded.document.regions.harbor.size() == 8,"Reload all surfaces")
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var region := REGION.build_region("harbor",Vector3(2560,0,2560))
	root.add_child(region)
	region.set_process(false)
	for key in region.records:
		for row in region.records[key]:
			if row.kind == "editor_ground": region._ensure_chunk(key); break
	await physics_frame
	await process_frame
	for row in loaded.document.regions.harbor.values():
		var sum := 0.0
		for mesh in grounds(region):
			if mesh.get_meta("editor_id") == row.id: sum += area(mesh)
		check(absf(sum-float(row.size[0])*float(row.size[1])) < .02,"Exact footprint without chunk overlap: "+row.id)
		var result := hit(DATA.xyz(row.position))
		check(not result.is_empty() and result.collider.get_meta("editor_id","") == row.id,"Walkable floor: "+row.id)
	for dx in [-.2,.2]:
		for dz in [-.2,.2]:
			var result := hit(Vector3(2560+dx,0,2560+dz))
			check(not result.is_empty() and result.collider.get_meta("editor_id","") == crossing.id,"Collision across chunk boundary")
	region.release_chunks()
	await process_frame
	check(grounds(region).is_empty(),"Ground unloads with chunks")
	check(hit(Vector3(2560,0,2560)).is_empty(),"No ghost collision after unloading")
	region._ensure_chunk(Vector2i(40,40))
	check(grounds(region).size() == 1,"Only requested ground fragment reloads")
	region.free()
	var old_floor := DATA.new_entity("ground",Vector2.ZERO)
	old_floor.id = "new/overlap_0"
	old_floor.size = [16,12]
	var new_floor := DATA.new_entity("ground",Vector2.ZERO)
	new_floor.id = "new/overlap_1"
	new_floor.size = [4,4]
	new_floor.rotation = 17
	new_floor.surface = "concrete"
	var lower := GROUND.create(old_floor,Rect2(-32,-32,64,64),Callable(),[GROUND.footprint(new_floor)])
	var upper := GROUND.create(new_floor,Rect2(-32,-32,64,64))
	root.add_child(lower)
	root.add_child(upper)
	check(absf(area(lower)-176) < .01 and absf(area(upper)-16) < .01,"Overlapping ground has no duplicate triangles, including enclosed holes")
	check(GROUND.create(old_floor,Rect2(-32,-32,64,64),Callable(),[GROUND.footprint(old_floor)]) == null,"Fully covered ground creates no hidden mesh or collider")
	await physics_frame
	await process_frame
	check(hit(Vector3.ZERO).collider.get_meta("editor_id") == new_floor.id,"New surface owns physical support in overlap")
	check(hit(Vector3(6,0,0)).collider.get_meta("editor_id") == old_floor.id,"Original surface remains outside overlap")
	lower.free()
	upper.free()
	var mountain_row := DATA.new_entity("ground",Vector2(850,-450))
	mountain_row.rotation = 23.0
	mountain_row.size = [27.0,21.0]
	var mountain_doc := DATA.empty_document()
	mountain_doc.regions.mountain[mountain_row.id] = mountain_row
	Engine.set_meta("geteco_world_edit_document",mountain_doc)
	var mountain := REGION.build_region("mountain",DATA.xyz(mountain_row.position))
	root.add_child(mountain)
	mountain.set_process(false)
	for key in mountain.records:
		for row in mountain.records[key]:
			if row.kind == "editor_ground": mountain._ensure_chunk(key); break
	var follows := true
	var minimum := INF
	var maximum := -INF
	for mesh in grounds(mountain):
		for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			minimum = minf(minimum,vertex.y)
			maximum = maxf(maximum,vertex.y)
			if absf(vertex.y-mountain.terrain.surface_height_at(Vector2(vertex.x,vertex.z))-.08) > .0001: follows = false
	check(follows and minimum < INF,"Ground follows exact mountain triangles")
	check(maximum-minimum > .1,"Mountain fixture exercises non-flat relief")
	await physics_frame
	await process_frame
	for offset in [Vector2.ZERO,Vector2(3.2,1.1),Vector2(-4.7,-2.9)]:
		var point: Vector2 = DATA.point(mountain_row.position)+offset
		var height: float = mountain.terrain.surface_height_at(point)
		var result := hit(Vector3(point.x,height,point.y))
		check(not result.is_empty() and result.collider.get_meta("editor_id","") == mountain_row.id and absf(result.position.y-height-.08) < .001,"Mountain collision conforms between vertices")
	mountain.free()
	Engine.remove_meta("geteco_world_edit_document")
	var ui := UI.new()
	ui.edits_path = path+"_ui.json"
	ui.draft_path = path+"_draft.json"
	root.add_child(ui)
	ui.asset_filter.select(7)
	ui.asset_search.text = "terreno"
	ui._filter_assets()
	check(ui.visible_assets.size() == 7,"Search exposes all seven ground materials")
	ui._arm_asset(0)
	ui._place("ground",Vector2(-190,100))
	var id: String = ui.canvas.selected_id
	check(ui.document.regions.harbor.has(id),"Place grass in editor")
	ui._set_array("size",0,24)
	ui._set_array("size",1,12)
	ui._set_value("rotation",45)
	ui._set_value("surface","pavers")
	check(ui._copy(),"Copy ground")
	ui._paste()
	ui._place("ground",Vector2(-160,100))
	var copy: String = ui.canvas.selected_id
	check(copy != id and DATA.point(ui.document.regions.harbor[copy].size).is_equal_approx(Vector2(24,12)) and ui.document.regions.harbor[copy].rotation == 45 and ui.document.regions.harbor[copy].surface == "pavers","Pasted ground retains size rotation and material")
	ui.undo()
	check(not ui.document.regions.harbor.has(copy),"Undo ground placement")
	ui.redo()
	check(ui.document.regions.harbor.has(copy),"Redo ground placement")
	ui.save()
	check(DATA.read_document(ui.edits_path).document.regions.harbor.size() == 2,"Editor saves ground for runtime")
	ui._delete()
	check(ui.document.regions.harbor[copy].get("deleted",false),"Delete ground")
	ui.free()
	print("WORLD_GROUND checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
