extends SceneTree
class Region extends RefCounted:
	var entries := [{"place_id":"harbor_clothing","id":"internal_01","position":Vector3(10,0,10)}]
	func map_routes() -> Array: return [{"points":PackedVector3Array([Vector3.ZERO,Vector3(40,0,40)])}]
class Mission extends RefCounted:
	func target_position() -> Vector3: return Vector3.ZERO
class Session extends RefCounted:
	var modal := true
	var freight_active := false
	var mission_world := Mission.new()
	func close_menu() -> void: modal=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var player := Node3D.new(); root.add_child(player)
	var map := preload("res://ui/hud/MapUI.gd").new()
	map.controller={"region":Region.new(),"state":{"region_id":"test","intro":{"stage":"complete"},"campaign":{"active_id":""}},"world":{"player":player},"session":Session.new()}
	root.add_child(map); await process_frame
	assert(map._objective_button.disabled,"free exploration must not fabricate an objective")
	assert(map._markers.size()==1 and map._markers[0].title=="Union","map uses authored place name, never internal ID")
	map.select_marker(0)
	assert(map.sidebar.visible and map.marker_title.text=="Union","selected marker publishes correct name")
	assert(not map.detail.visible,"empty descriptions do not occupy sidebar")
	assert(map._markers[0].kind=="clothing","clothing uses its own pictogram")
	map._mark_selected()
	assert(map._waypoint==Vector2(10,10),"marking selects actual world coordinate")
	map._clear_waypoint()
	assert(not map._waypoint.is_finite(),"clear removes destination")
	map._set_filter("clothing")
	assert(map._filter=="clothing","legend filters by category")
	map._set_filter("clothing")
	assert(map._filter.is_empty(),"pressing filter again restores all categories")
	map.change_zoom(1000)
	assert(map.target_zoom==50,"zoom has a finite upper bound")
	map.change_zoom(.00001)
	assert(map.target_zoom==.65,"zoom has a finite lower bound")
	var original := Vector2(24,31)
	assert(map.unproject(map.project(original)).distance_to(original)<.001,"screen picking inverts projection")
	map._drawn_markers.clear()
	assert(map._nearest(map.project(Vector2(10,10)))==-1,"suppressed symbols cannot steal a click")
	var double_click := InputEventMouseButton.new()
	double_click.button_index=MOUSE_BUTTON_LEFT; double_click.pressed=true; double_click.double_click=true; double_click.position=Vector2(20,20)
	map._insets.append({"region":"harbor","rect":Rect2(0,0,80,80)})
	map.map_input(double_click)
	assert(not map._waypoint.is_finite(),"inset interaction does not mark the hidden map below it")
	map._insets.clear(); map.map_input(double_click)
	assert(map._waypoint.distance_to(map.unproject(double_click.position))<.001,"double click marks its world coordinate")
	map.queue_free(); player.queue_free(); await process_frame
	print("MAP_UI_CONTRACT PASS 15 checks")
	quit()
