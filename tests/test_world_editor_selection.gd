extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures := 0
var canvas
var commits := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func mouse(at: Vector2,pressed: bool,alt := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	event.alt_pressed = alt
	canvas._gui_input(event)
func move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	canvas._gui_input(event)
func run() -> void:
	canvas = CANVAS.new()
	root.add_child(canvas)
	canvas.size = Vector2(1000,700)
	canvas.center = Vector2(443.125,83.75)
	canvas.zoom = 24
	canvas.grid = 0
	canvas.committed.connect(func(_row): commits += 1)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/geteco_world_editor/base_catalog.json")).regions.harbor
	canvas.objects = catalog.objects.duplicate(true)
	canvas.objects.merge(catalog.context.duplicate(true))
	canvas.rebuild_context()
	var house: Dictionary = canvas.objects["building/PorchHouse"].duplicate(true)
	for offset in [Vector2.ZERO,Vector2(-5,-3),Vector2(5,3)]:
		check(canvas.pick(canvas.screen(DATA.point(house.position)+offset)) == house.id,"House roof selects house, including near edges")
	canvas.selected_id = "piece/cobra/cobra_footpath/2"
	var at: Vector2 = canvas.screen(DATA.point(house.position))
	mouse(at,true)
	move(at+Vector2(48,24))
	mouse(at+Vector2(48,24),false)
	check(canvas.selected_id == house.id,"Click changes from path to house")
	check(DATA.point(canvas.objects[house.id].position).is_equal_approx(DATA.point(house.position)+Vector2(2,1)),"Roof drag moves whole house")
	check(commits == 1,"Roof drag commits once")
	var current: Dictionary = canvas.objects[house.id]
	at = canvas.screen(DATA.point(current.position))
	mouse(at+CANVAS.RESIZE_OFFSET,true)
	move(at+CANVAS.RESIZE_OFFSET*.5)
	mouse(at+CANVAS.RESIZE_OFFSET*.5,false)
	check(DATA.point(canvas.objects[house.id].size).is_equal_approx(DATA.point(house.size)*.5),"Visible size handle shrinks house")
	var shape := {"id":"piece/test","type":"piece","position":[443.125,83.75],"rotation":90.0,"size":[4.0,4.0],"stretch":[2.0,1.0],"shape_editable":true,"outline":[[-2.0,-2.0],[2.0,-2.0],[2.0,2.0],[-2.0,2.0]]}
	canvas.objects = {shape.id:shape}
	canvas.selected_id = shape.id
	canvas.edit_points = true
	var initial: PackedVector2Array = canvas.corners(shape)
	at = canvas.screen(initial[0])
	mouse(at,true)
	check(canvas.selected_point == 0,"Polygon vertex can be selected")
	move(at+Vector2(24,0))
	mouse(at+Vector2(24,0),false)
	var changed: Dictionary = canvas.objects[shape.id]
	check(canvas.corners(changed)[0].is_equal_approx(initial[0]+Vector2(1,0)),"Point moves in world coordinates under rotated stretched shape")
	check(changed.position == shape.position and changed.outline[1] == shape.outline[1],"Point drag preserves center and other points")
	var overlap := {"id":"building/overlap","type":"building","position":shape.position,"rotation":0,"size":[6,6],"height":8}
	canvas.objects[overlap.id] = overlap
	at = canvas.screen(DATA.point(shape.position))
	check(canvas.pick(at) == overlap.id,"Visible building wins over decoration")
	canvas.selected_id = overlap.id
	mouse(at,true,true)
	mouse(at,false,true)
	check(canvas.selected_id == shape.id,"Alt click cycles overlapping objects")
	check(not canvas.edit_points,"Selecting another object leaves point editing")
	# A road endpoint on the X axis must win over its transform handle.
	var road := {"id":"road/test","type":"road","points":[[0,0],[4,0]],"width":2.0}
	canvas.objects = {road.id:road}
	canvas.selected_id = road.id
	canvas.center = Vector2(2,0)
	at = canvas.screen(Vector2(4,0))
	mouse(at,true)
	check(canvas.selected_point == 1 and canvas.drag_axis.is_empty(),"Road endpoint wins over overlapping axis")
	canvas.cancel_drag()
	# Actual terminal furniture and paving shown in the editor screenshot.
	canvas.zoom = 8
	canvas.selected_id = ""
	canvas.objects = catalog.context.duplicate(true)
	var floor := {"id":"paving/test","type":"ground","position":[107,72],"size":[35,15],"rotation":0,"surface":"concrete"}
	canvas.objects[floor.id] = floor
	var bin: Dictionary = canvas.objects["piece/route/rodoviaria/9"]
	canvas.center = DATA.point(bin.position)
	at = canvas.screen(DATA.point(bin.position))+Vector2(5,0)
	check(canvas.pick(at) == bin.id,"Small terminal bin is selectable with a forgiving click target")
	mouse(at,true)
	move(at+Vector2(16,8))
	mouse(at+Vector2(16,8),false)
	check(DATA.point(canvas.objects[bin.id].position).is_equal_approx(DATA.point(bin.position)+Vector2(2,1)),"Terminal bin drags independently of paving")
	canvas.objects[bin.id] = bin
	canvas.selected_id = ""
	var slab: Dictionary = canvas.objects["piece/route/rodoviaria/0"]
	check(canvas.pick(canvas.screen(DATA.point(slab.position))) == slab.id,"Raised sidewalk slab can be selected over broad paving")
	canvas.objects.merge(catalog.objects.duplicate(true))
	for id in ["piece/route/rodoviaria/1","piece/route/rodoviaria/6","piece/route/rodoviaria/10","piece/route/rodoviaria/15"]:
		var object: Dictionary = canvas.objects[id]
		var picked: String = canvas.pick(canvas.screen(DATA.point(object.position)))
		check(picked == id,"Road does not intercept curb, ramp or lamp: "+id+" got "+picked)
	canvas.free()
	await process_frame
	print("WORLD_SELECTION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
