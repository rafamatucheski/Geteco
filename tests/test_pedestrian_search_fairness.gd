extends SceneTree
const NAV := preload("res://emergency/ResponderNavigation.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var actor := CharacterBody2D.new()
	root.add_child(actor)
	var first := NAV.new()
	var second := NAV.new()
	first._search_pending = true
	second._search_pending = true
	assert(first._begin_search_work(actor))
	NAV._work_usec = NAV.SEARCH_FRAME_USEC
	assert(not second._begin_search_work(actor))
	await process_frame
	await process_frame
	var first_cut_queue: bool = first._begin_search_work(actor)
	var second_served: bool = second._begin_search_work(actor)
	print("SEARCH_FAIRNESS first_cut_queue=", first_cut_queue, " second_served=", second_served)
	actor.free()
	quit(1 if first_cut_queue or not second_served else 0)
