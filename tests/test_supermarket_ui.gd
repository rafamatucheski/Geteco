extends SceneTree
const PANEL := preload("res://ui/SupermarketPanel.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
class Room extends RefCounted:
	func threatened() -> bool: return false
class Session extends Node:
	var state: Dictionary
	var world: Dictionary
	var room := Room.new()
	var modal := true
	var panel := Control.new()
	func close_menu() -> void: modal = false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	var session := Session.new()
	session.panel.hide()
	root.add_child(session)
	var economy := ECONOMY.new()
	economy.enable_grid_inventory()
	economy.grant_reward("ui_fixture",2000)
	session.state = {"economy":economy,"place_id":"harbor_supermarket"}
	session.world = {"gameplay":{"health":50,"armor":0}}
	var ui := PANEL.new()
	ui.session = session
	root.add_child(ui)
	var failed := false
	for size in [Vector2i(1280,720),Vector2i(960,540),Vector2i(640,480)]:
		root.size = size
		for i in 10: await process_frame
		ui._layout()
		for i in 5: await process_frame
		print("MARKET_UI viewport=",size," shell=",ui.shell.get_global_rect()," min=",ui.shell.get_combined_minimum_size()," close=",ui.close_button.get_global_rect()," grid=",ui.grid.size)
		if not Rect2(Vector2.ZERO,Vector2(size)).encloses(ui.shell.get_global_rect()): failed = true
		if not ui.shell.get_global_rect().encloses(ui.close_button.get_global_rect()): failed = true
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/supermarket-20261002/ui-%dx%d.png"%[size.x,size.y])
	ui.free()
	session.panel.free()
	session.free()
	quit(1 if failed else 0)
