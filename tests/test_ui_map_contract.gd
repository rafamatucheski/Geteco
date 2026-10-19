extends SceneTree
## Map navigation contracts. Visual composition and rendered performance have
## separate checks in tests/measure/measure_world_map.gd.
class Region extends RefCounted:
	var entries := [
		{"place_id":"harbor_clothing","id":"internal_01","position":Vector3(10,0,10)},
		{"place_id":"harbor_bank","id":"internal_02","position":Vector3(180,0,40)},
		{"place_id":"harbor_clothing","id":"internal_03","position":Vector3(20,0,180)},
		{"place_id":"harbor_bank","id":"internal_04","position":Vector3(10,0,10)},
	]
	func map_routes() -> Array:
		return [{"points":PackedVector3Array([Vector3.ZERO,Vector3(220,0,220)])}]
class Mission extends RefCounted:
	func target_position() -> Vector3: return Vector3.ZERO
class Session extends RefCounted:
	var modal := true
	var freight_active := false
	var mission_world := Mission.new()
	func close_menu() -> void: modal=false

var checks := 0
var failures: Array[String]=[]

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)

func redraw(map) -> void:
	map.canvas.queue_redraw()
	await process_frame
	await process_frame

func double_click(point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.double_click=true
	event.position=point
	return event

func run() -> void:
	root.size=Vector2i(1280,720)
	var player := Node3D.new(); root.add_child(player)
	var map := preload("res://ui/hud/MapUI.gd").new()
	map.controller={"region":Region.new(),"state":{"region_id":"test","intro":{"stage":"complete"},"campaign":{"active_id":""}},"world":{"player":player},"session":Session.new()}
	root.add_child(map); await process_frame
	check(map._region=="test","opening the map focuses the current available region")
	check(not map._legend.visible,"filters start collapsed so the map has room")
	check(map._filter_button.visible,"collapsed filters have a discoverable control")
	check(map._objective_button.disabled,"free exploration must not fabricate an objective")
	check(map._markers.size()==4 and map._markers[0].title=="Union","map uses authored place names, never internal IDs")
	var titles: Array[String]=[]
	for label in map.find_children("*","Label",true,false): titles.append(label.text)
	check("HARBOR" in titles and "GETECO" not in titles,"the map uses the selected HARBOR identity")
	map.select_marker(0)
	await redraw(map)
	check(map.sidebar.visible and map.marker_title.text=="Union","selected marker publishes correct name")
	check(not map.detail.visible,"empty descriptions do not occupy the selection card")
	check(map.sidebar.size.y<=100,"the first short selection stays compact after containers settle")
	check(map._markers[0].kind=="clothing","clothing uses its own pictogram")
	map._mark_selected()
	check(map._waypoint==Vector2(10,10),"marking selects the actual world coordinate")
	root.content_scale_size=Vector2i(800,600); root.size=Vector2i(800,600)
	await redraw(map)
	check(map.size==Vector2(800,600),"compact footer regression uses an actual 800 by 600 canvas")
	check(map._clear_button.is_visible_in_tree() and map._footer.get_global_rect().encloses(map._clear_button.get_global_rect()),"clear destination fits wholly inside the compact footer")
	root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	await redraw(map)
	map._clear_waypoint()
	check(not map._waypoint.is_finite(),"clear removes the destination")

	# Exercise the actual controls, including an explicit escape from a filter.
	map._filter_button.pressed.emit(); await process_frame
	check(map._legend.visible and map._all_filter_button.is_visible_in_tree(),"Filters exposes a visible Todos action")
	map._legend_buttons.clothing.pressed.emit()
	check(map._filter=="clothing","category controls filter map markers")
	check(not map.sidebar.visible,"changing filters clears the old selection")
	await redraw(map)
	check(not map._drawn_markers.is_empty(),"the active category retains its visible markers")
	for index in map._drawn_markers:
		check(map._markers[index].kind=="clothing" or map._markers[index].objective,"filtered markers cannot draw an unrelated category")
	map._all_filter_button.pressed.emit()
	check(map._filter.is_empty(),"Todos restores every category explicitly")
	map._set_filter("clothing"); map._set_filter("clothing")
	check(map._filter.is_empty(),"pressing the active category again still restores all categories")

	# Overlay input must never leak a double-click to the world beneath it.
	var overlay_point: Vector2=map._legend.get_global_rect().get_center()-map.canvas.global_position
	check(map._pointer_blocked(overlay_point),"an open filter panel owns its map-space footprint")
	map.map_input(double_click(overlay_point))
	check(not map._waypoint.is_finite(),"clicking UI cannot mark the hidden world beneath it")
	map._all_filter_button.grab_focus()
	map._filter_button.pressed.emit(); await process_frame
	var recovered: Control=root.gui_get_focus_owner()
	check(not map._legend.visible,"Filters can collapse the panel")
	check(recovered!=null and recovered.is_visible_in_tree() and recovered.focus_mode!=Control.FOCUS_NONE,"collapsing filters restores usable visible focus")

	# Cover the regression where moving the selected icon to the front of draw
	# order caused the controller to alternate between two icons forever. One
	# additional destination shares a point and must also remain reachable.
	map.select_marker(-1)
	map.focus_region("test"); map.center=map.target_center; map.zoom=map.target_zoom
	await redraw(map)
	check(map._drawn_markers.size()==3,"the navigation fixture exposes three distinct markers")
	var reached: Array[int]=[]
	for _step in 4:
		map._cycle_marker()
		check(map._selected>=0 and map._selected not in reached,"controller selection reaches each marker before repeating")
		reached.append(map._selected)
		await redraw(map)
	map._cycle_marker()
	check(map._selected==reached[0],"controller selection wraps after every visible marker")
	map._filter_button.grab_focus()
	var focused_selection: int=map._selected
	var accept := InputEventJoypadButton.new()
	accept.button_index=JOY_BUTTON_A; accept.pressed=true
	map._input(accept)
	check(map._selected==focused_selection and root.gui_get_focus_owner()==map._filter_button,"map navigation does not steal A from a focused button")
	map._filter_button.release_focus(); map._input(accept)
	check(map._selected!=focused_selection,"A navigates destinations when no button owns focus")
	map.select_marker(0); await process_frame
	var selection_point: Vector2=map.sidebar.get_global_rect().get_center()-map.canvas.global_position
	check(map._pointer_blocked(selection_point),"the selection card owns its map-space footprint")
	map.map_input(double_click(selection_point))
	check(not map._waypoint.is_finite(),"clicking the selection card cannot place a destination underneath it")
	map.select_marker(-1)

	map.change_zoom(1000)
	check(map.target_zoom==50,"zoom has a finite upper bound")
	map.change_zoom(.00001)
	check(map.target_zoom==.65,"zoom has a finite lower bound")
	var original := Vector2(24,31)
	check(map.unproject(map.project(original)).distance_to(original)<.001,"screen picking inverts projection")
	map._drawn_markers.clear()
	check(map._nearest(map.project(Vector2(10,10)))==-1,"suppressed symbols cannot steal a click")
	var open_point: Vector2=map.canvas.size*.5
	check(not map._pointer_blocked(open_point),"the center of an unobstructed map remains interactive")
	map.map_input(double_click(open_point))
	check(map._waypoint.distance_to(map.unproject(open_point))<.001,"double-clicking the map marks its world coordinate")
	map._clear_waypoint()
	map.queue_free(); player.queue_free(); await process_frame
	if failures.is_empty(): print("MAP_UI_CONTRACT PASS ",checks," checks")
	else: print("MAP_UI_CONTRACT FAIL ",failures.size()," of ",checks," checks")
	quit(0 if failures.is_empty() else 1)
