extends SceneTree
const SHOP := preload("res://activities/desert_drag/DragInstrumentShop.gd")
const STYLES := preload("res://activities/desert_drag/DragInstrumentStyles.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print("INSTRUMENT_SHOP ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	RenderingServer.set_default_clear_color(Color("080c11"))
	root.get_node("BuildWatermark").hide()
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	var shop := SHOP.new()
	root.add_child(shop)
	shop.position = Vector2(190,40)
	var state := STYLES.defaults()
	var original := JSON.stringify(state)
	var requested: Array[String] = []
	shop.style_requested.connect(func(id: String): requested.append(id))
	shop.show_styles(state,0,5000)
	check(shop.rows.size()==5 and shop.action_button.disabled,"five styles with equipped classic")
	shop.select_style("street")
	check(shop.action_button.disabled and shop.preview.style_id=="street","locked style is previewable but cannot be purchased")
	shop.show_styles(state,1,1000)
	shop.select_style("street")
	check(shop.action_button.disabled and "500" in shop.action_button.text,"missing funds prevent purchase")
	shop.show_styles(state,1,5000)
	shop.select_style("street")
	shop.action_button.pressed.emit()
	check(requested.is_empty() and "CONFIRMAR" in shop.action_button.text,"first activation only asks confirmation")
	shop.select_style("bar")
	shop.select_style("street")
	shop.action_button.pressed.emit()
	check(requested.is_empty(),"changing styles clears purchase confirmation")
	shop.action_button.pressed.emit()
	check(requested==["street"],"second activation emits selected purchase intent once")
	check(JSON.stringify(state)==original and shop.money==5000 and "street" not in shop.owned,"shop never mutates wallet or ownership itself")
	shop.select_style("bar")
	shop.action_button.pressed.emit()
	check(requested==["street","bar"],"already owned bar equips with one activation")
	var purchased := STYLES.defaults()
	purchased.owned.append("street")
	purchased.selected = "street"
	shop.show_styles(purchased,1,3500)
	check(shop.action_button.disabled and shop.action_button.text=="EQUIPADO","authoritative result updates equipped state")
	shop.select_style("pro")
	check(shop.action_button.disabled,"three distinct wins remain required for pro")
	shop.rows[1].grab_focus()
	check(shop.selected=="bar" and shop.rows[1].focus_neighbor_right==shop.rows[1].get_path_to(shop.action_button),"keyboard and gamepad focus selects style and reaches action")
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	root.push_input(right)
	await process_frame
	check(root.gui_get_focus_owner()==shop.action_button,"right arrow moves native focus to the action")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	accept.pressed = true
	root.push_input(accept)
	accept = accept.duplicate()
	accept.pressed = false
	root.push_input(accept)
	await process_frame
	check(requested==["street","bar","bar"],"gamepad accept activates the focused equip action")
	var closes: Array[bool] = []
	shop.close_requested.connect(func(): closes.append(true))
	shop.back_button.pressed.emit()
	check(closes.size()==1,"back button emits close intention")
	if DisplayServer.get_name()!="headless":
		var folder := "res://evidence/desert-drag-instruments"
		DirAccess.make_dir_recursive_absolute(folder)
		shop.show_styles(state,3,5000)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/shop-classic-1280.png")
		shop.select_style("street")
		shop.action_button.grab_focus()
		shop.action_button.pressed.emit()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/shop-confirm-1280.png")
		root.size=Vector2i(960,640)
		shop.scale=Vector2.ONE*.96
		shop.position=(Vector2(root.size)-Vector2(900,640)*shop.scale)*.5
		shop.select_style("bar")
		shop.rows[1].grab_focus()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/shop-bar-960.png")
	shop.free()
	print("INSTRUMENT_SHOP_DONE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
