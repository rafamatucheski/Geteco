extends SceneTree
const REGION=preload("res://world/desert/DesertRegion.gd")
const SCENERY=preload("res://world/desert/DragScenery.gd")
const FORMS=preload("res://world/desert/DesertHorizonRelief.gd")
const AMBIENT=preload("res://world/desert/DesertAmbientLife.gd")
var failures: Array[String]=[]
var checks := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("SCENERY_UNIT watchdog"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var region=REGION.new()
	region.prepare_data()
	var scenery=SCENERY.new()
	root.add_child(scenery)
	scenery.configure(region)
	print("SCENERY_CATALOG ",scenery.outcrop_cells.keys()," formations=",scenery.formations)
	check(scenery.outcrop_cells.size()+scenery.formations.size()>=5,"middle distance has formations along the course")
	check(scenery.find_children("*","StaticBody3D",true,false).is_empty(),"persistent visual layer adds no distant physics bodies")
	for key in scenery.outcrop_cells:
		var center := (Vector2(key)+Vector2.ONE*.5)*96.0
		check(region._decoration_clear(center,34.0),"existing roads and authored locations remain clear")
		var at := Vector3(center.x,region._ground_height(center),center.y)
		var original=FORMS.create_outcrop(scenery,at,28,23,absi(key.x*771+key.y*331),true)
		var streamed=FORMS.create_outcrop(scenery,at,28,23,absi(key.x*771+key.y*331),true,false)
		check(streamed.find_children("*","MeshInstance3D",true,false).is_empty(),"streamed solid cannot duplicate the resident silhouette")
		var shapes=original.find_children("*","CollisionShape3D",true,false)
		var matching=streamed.find_children("*","CollisionShape3D",true,false)
		check(shapes.size()==3 and matching.size()==3,"irregular rock retains all three physical volumes")
		for i in shapes.size(): check(shapes[i].shape.points==matching[i].shape.points,"streamed collision matches original generated rock exactly")
		original.free()
		streamed.free()
	for record in scenery.formations:
		var at: Vector3=record.position
		check(preload("res://world/desert/DesertLayout.gd").road_clear(Vector2(at.x,at.z),record.radius+4.0),"new formation preserves every road and its shoulder")
		var chunk := Node3D.new()
		root.add_child(chunk)
		scenery.build_collision(chunk,Rect2(Vector2(at.x,at.z)-Vector2.ONE,Vector2.ONE*2))
		check(chunk.find_children("*","MeshInstance3D",true,false).is_empty() and chunk.find_children("*","CollisionShape3D",true,false).size()==3,"approaching a formation installs its exact solid without a second visible mesh")
		chunk.free()
	region.prepare_drag_view(true)
	check(not region.drag_view_ready() and is_zero_approx(region.drag_view_progress()),"unbuilt course cannot start its countdown")
	for key in region.drag_view_cells: region.chunks[key]=Node3D.new()
	region.drag_view_pending.clear()
	region.build_jobs.append({"key":region.drag_view_cells.keys()[0]})
	check(not region.drag_view_ready(),"surface support alone cannot declare scenery ready")
	region.build_jobs.clear()
	check(region.drag_view_ready() and is_equal_approx(region.drag_view_progress(),1.0),"readiness requires all retained cells and dressing complete")
	region.prepare_drag_view(false)
	check(not region._drag_preparing,"ending preparation releases the extra build budget")
	for chunk in region.chunks.values(): chunk.free()
	region.chunks.clear()
	var ambient=AMBIENT.new()
	root.add_child(ambient)
	ambient.set_focus(Vector3(-900,0,-1320))
	ambient._physics_process(.1)
	ambient.set_focus(Vector3(-650,0,-1320))
	check(ambient._drag_view and ambient._birds.multimesh.visible_instance_count==9 and not ambient._reset_flock,"course birds stay in world thermals when car crosses cells")
	ambient.set_focus(Vector3(-200,0,-900))
	check(not ambient._drag_view and ambient._birds.multimesh.visible_instance_count==3,"ordinary desert retains its original flock budget")
	ambient.suspend()
	check(not ambient.is_physics_processing() and not ambient._wind.emitting,"leaving the area suspends ambient simulation")
	print("DRAG_SCENERY checks=",checks," outcrops=",scenery.outcrop_cells.size()," formations=",scenery.formations.size()," failures=",failures)
	ambient.free()
	scenery.free()
	region.free()
	quit(0 if failures.is_empty() else 1)
