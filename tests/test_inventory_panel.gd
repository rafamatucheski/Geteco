extends SceneTree
const ECONOMY=preload("res://systems/economy/Economy.gd")
const PANEL=preload("res://systems/inventory/ui/InventoryPanel.gd")
const GRID=preload("res://systems/inventory/GridInventory.gd")
class StateStub extends RefCounted:
	func weapons_allowed() -> bool: return true
class Adapter extends RefCounted:
	var wallet=ECONOMY.new()
	var ui
	var session={"state":StateStub.new()}
	var near:=false
	var dropped:=0
	func economy(): return wallet
	func trunk_access() -> bool: return near
	func can_edit(container: String) -> bool: return container!="trunk" or near
	func close() -> void: ui.hide()
	func drop_bag() -> bool:
		dropped=wallet.grid_drop_bag("harbor","",Vector3(2,0,0)); ui.refresh(); return dropped>0
	func consume(container: String,index: int) -> void:
		wallet.consume_item(wallet.grid_snapshot()[container][index].id); ui.refresh()
	func equip(container: String,index: int,id:="") -> void:
		if id.is_empty(): wallet.grid_equip_weapon(container,index)
		else: wallet.equip_weapon(id)
		ui.refresh()
	func store_weapon(id: String,target: String) -> void: wallet.grid_store_weapon(id,target); ui.refresh()
	func move(source: String,index: int,target: String,cell:=Vector2i(-1,-1)) -> bool:
		if not can_edit(source) or not can_edit(target): return false
		var ok: bool=wallet.grid_move(source,index,target,cell); ui.refresh(); return ok
	func rotate(source: String,index: int) -> void:
		var entry: Dictionary=wallet.grid_snapshot()[source][index]
		wallet.grid_move(source,index,source,Vector2i(entry.x,entry.y),true); ui.refresh()
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PANEL ","PASS " if ok else "FAIL ",label)
func frames() -> void:
	for i in 4: await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/inventory-ux-20260928/"+label+".png")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/inventory-ux-20260928"))
	root.size=Vector2i(1280,720)
	root.get_node("V2Settings").show_fps=false; root.get_node("V2Settings")._update_fps_overlay()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--icon-out="):
			preload("res://systems/inventory/InventoryIcons.gd").get_icon("pistol").get_image().save_png(arg.trim_prefix("--icon-out="))
	var backdrop:=ColorRect.new(); backdrop.color=Color("48514b"); backdrop.size=Vector2(1280,720); root.add_child(backdrop)
	var ad:=Adapter.new(); var e=ad.wallet
	e.enable_grid_inventory(); e.grid_equip_bag("backpack")
	e.grant_weapon("pistol"); e.grant_weapon("hunting_rifle"); e.grant_item("apple",3); e.grant_item("garage_part"); e.grant_item("water",2)
	e.grid_store_weapon("hunting_rifle","storage")
	var ui:=PANEL.new(); ad.ui=ui; ui.adapter=ad; root.add_child(ui); ui.show(); ui.refresh(); await frames()
	check(ui.drop_button.visible and ui.drop_button.text.contains("Soltar mochila"),"drop action is explicit and always visible")
	check(ui.drop_button.get_global_rect().end.y<720,"drop button stays inside screen")
	check(ui.card.size.x<450 and ui.card.size.y<680,"compact main panel")
	await shot("mochila")
	var source:="storage"
	var index:=-1
	for i in e.grid_snapshot().storage.size():
		if e.grid_snapshot().storage[i].id=="water": index=i
	var entry
	for board in ui.boards:
		if board.container_id==source:
			for child in board.get_children():
				if child.index==index: entry=child
	var right:=InputEventMouseButton.new(); right.button_index=MOUSE_BUTTON_RIGHT; right.pressed=true
	entry._gui_input(right); await frames()
	check(GRID.count(e.grid_snapshot(),"water")==1,"right-click consumes one selected item")
	ui.trunk_visible=true; ui.refresh(); await frames()
	check(ui.card.size.x<900 and ui.card.get_rect().end.y<=720,"trunk panel remains inside screen")
	await shot("monaliza-remota")
	var trunk
	for board in ui.boards:
		if board.container_id=="trunk": trunk=board
	var payload={"owner":ad,"container":"pockets","index":0}
	check(not trunk._can_drop_data(Vector2(5,5),payload),"remote trunk refuses drag")
	ad.near=true; ui.refresh(); await frames()
	for board in ui.boards:
		if board.container_id=="trunk": trunk=board
	check(not trunk._can_drop_data(Vector2(5,5),payload),"near trunk refuses food drag")
	for i in e.grid_snapshot().storage.size():
		if e.grid_snapshot().storage[i].id=="weapon:hunting_rifle": index=i
	payload={"owner":ad,"container":"storage","index":index}
	check(trunk._can_drop_data(Vector2(5,5),payload),"near trunk accepts rifle footprint")
	trunk._drop_data(Vector2(5,5),payload); await frames()
	check(e.grid_snapshot().trunk.size()==1,"drag moves rifle into trunk")
	await shot("monaliza-aberta")
	ui.drop_button.pressed.emit(); await frames()
	check(ad.dropped>0 and not ui.visible and e.grid_snapshot().bag=="","visible drop button drops bag and closes HUD")
	e.grid_recover_bag(ad.dropped); ui.show(); ui.refresh(); await frames()
	var key:=InputEventKey.new(); key.physical_keycode=KEY_G; key.pressed=true
	Input.parse_input_event(key); await frames()
	check(not ui.visible and e.grid_snapshot().bag=="","G drops only while inventory is open")
	print("PANEL_RESULT checks=",checks," failures=",failures)
	ui.free(); backdrop.free(); ad.ui=null
	quit(1 if failures else 0)
