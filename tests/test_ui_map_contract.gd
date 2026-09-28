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
	map.queue_free(); player.queue_free(); await process_frame
	print("MAP_UI_CONTRACT PASS 4 checks")
	quit()
