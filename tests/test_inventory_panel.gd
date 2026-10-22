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
	func travel_bag_available() -> bool: return false
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
func labels_contain(node: Node,text: String) -> bool:
	if node is Label and text in node.text: return true
	for child in node.get_children():
		if labels_contain(child,text): return true
	return false
func actions_disabled(node: Node) -> bool:
	var found:=false
	for button in node.find_children("*","Button",true,false):
		found=true
		if not button.disabled: return false
	return found
func selected_actions_fit(ui) -> bool:
	if ui.screen_scroll.is_ancestor_of(ui.details): return false
	for action in ui.details.find_children("*","Button",true,false):
		if not ui.card.get_global_rect().encloses(action.get_global_rect()): return false
		if not Rect2(Vector2.ZERO,Vector2(root.size)).encloses(action.get_global_rect()): return false
	return true
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
	check(ui.find_child("ToggleTrunk",true,false) == null,"TAB has no Monaliza toggle")
	check(ui.drop_button.visible and ui.drop_button.text.contains(String(TranslationServer.translate("Soltar mochila"))),"drop action is explicit and always visible in the selected language")
	check(ui.drop_button.get_global_rect().end.y<720,"drop button stays inside screen")
	check(ui.card.size.x<450 and ui.card.size.y<680,"compact main panel")
	await shot("mochila")
	ui._select("pockets",0); await frames()
	check(ui.details.visible and ui.details.get_parent()==ui.content_column,"item details share the panel footer")
	check(ui.card.get_rect().end.y<=720 and ui.card.size.x<450,"selected actions fit compact 720p inventory")
	ui._select_equipment("pistol"); await frames()
	check(ui.boards.all(func(board): return board.selection==-1),"equipment selection clears grid highlights")
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
	var centred_x: float=ui.card.get_rect().get_center().x
	check(absf(centred_x-640.0)<2.0,"field inventory stays centred outside the trunk")
	check(ui.trunk_view_focus()==null,"no trunk camera area outside the trunk")
	ui.trunk_visible=true; ui.refresh(); await frames()
	check(ui.card.size.x<900 and ui.card.get_rect().end.y<=720,"trunk panel remains inside screen")
	# Porta-malas: painel encostado à direita com margem; a área livre à esquerda é da bandeja.
	var trunk_rect: Rect2=ui.card.get_rect()
	check(trunk_rect.end.x<=1280.0-16.0 and trunk_rect.end.x>=1280.0-48.0 and trunk_rect.position.x>=16.0,"trunk panel anchored right with margin at 720p")
	var focus: Variant=ui.trunk_view_focus()
	check(focus is Vector2 and absf(focus.x-trunk_rect.position.x*.5/1280.0)<.001 and focus.x<.5,"trunk camera area is the free space left of the panel")
	await shot("monaliza-remota")
	check(labels_contain(ui.card,"Armas e munição") and labels_contain(ui.card,"6 pilhas"),"trunk restrictions remain visible without a tooltip")
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
	ui._select("trunk",0); await frames()
	check(selected_actions_fit(ui),"selected trunk rifle actions remain fully visible outside the grid scroll at 720p")
	ad.near=false; ui.refresh(); ui._select("trunk",0); await frames()
	check(actions_disabled(ui.details),"remote trunk selected-item actions are disabled")
	ad.near=true; ui.refresh(); await frames()
	await shot("monaliza-aberta")
	ui.drop_button.pressed.emit(); await frames()
	check(ad.dropped>0 and not ui.visible and e.grid_snapshot().bag=="","visible drop button drops bag and closes HUD")
	e.grid_recover_bag(ad.dropped); ui.show(); ui.refresh(); await frames()
	var key:=InputEventKey.new(); key.physical_keycode=KEY_G; key.pressed=true
	Input.parse_input_event(key); await frames()
	check(not ui.visible and e.grid_snapshot().bag=="","G drops only while inventory is open")
	check(e.grid_equip_bag("handbag"),"handbag fixture equips after dropping backpack")
	ui.show(); ui.refresh(); await frames()
	check(labels_contain(ui.card,"armas longas bloqueadas"),"handbag exposes its weapon restriction")
	ui._select("trunk",0); await frames()
	var equip_actions:=ui.details.find_children("*","Button",true,false).filter(func(button): return button.text=="Equipar")
	check(equip_actions.size()==1 and equip_actions[0].disabled,"handbag disables equipping a stored long weapon")
	check(selected_actions_fit(ui),"handbag selected long-weapon actions remain fully visible at 720p")
	check(ui.drop_button.text.contains(String(TranslationServer.translate("Soltar mala"))),"handbag drop uses the correct container name")
	check(ui.card.get_rect().end.y<=720 and ui.card.size.x<900,"handbag and trunk remain bounded at 720p")
	await shot("mala-720p")
	root.size=Vector2i(1920,1080); await frames()
	var view_1080: Vector2=ui.get_viewport_rect().size
	check(ui.card.position.x>=0 and ui.card.position.y>=0 and ui.card.get_rect().end.x<=view_1080.x and ui.card.get_rect().end.y<=view_1080.y,"inventory remains inside 1080p viewport")
	check(ui.card.get_rect().end.x>=view_1080.x-view_1080.x*.05,"trunk panel stays right-anchored at 1080p")
	await shot("mala-1080p")
	# 3440x1440 (21:9): canvas_items reduz para 1720x720 lógicos; o painel vai à borda direita.
	root.size=Vector2i(3440,1440); await frames()
	var view_wide: Vector2=ui.get_viewport_rect().size
	check(ui.card.get_rect().end.x<=view_wide.x and ui.card.get_rect().end.x>=view_wide.x-view_wide.x*.05 and ui.card.get_rect().end.y<=view_wide.y,"trunk panel right-anchored and inside 21:9 viewport")
	var wide_focus: Variant=ui.trunk_view_focus()
	check(wide_focus is Vector2 and wide_focus.x>.25 and wide_focus.x<.5,"21:9 trunk camera area sits left of the panel")
	print("PANEL_RESULT checks=",checks," failures=",failures)
	ui.free(); backdrop.free(); ad.ui=null
	quit(1 if failures else 0)
