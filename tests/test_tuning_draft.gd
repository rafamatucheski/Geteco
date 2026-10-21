extends SceneTree
## Drafts never spend or mutate the authoritative loadout. Only Apply emits intent.
const PANEL := preload("res://gameplay/desert_cars/DesertTuningPanel.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	await process_frame
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var panel := PANEL.new()
	root.add_child(panel)
	var car := CharacterBody3D.new()
	root.add_child(car)
	panel.set_live_vehicle(car)
	var requests: Array = []
	var previews: Array = []
	var closes: Array = []
	var legacy: Array = []
	panel.loadout_requested.connect(func(parts): requests.append(parts))
	panel.preview_requested.connect(func(parts): previews.append(parts))
	panel.preview_closed.connect(func(): closes.append(true))
	panel.purchase_requested.connect(func(id): legacy.append(id))
	panel.show_vehicle("desert_coyote",{"paint":"paint_rosso"},["paint_rosso","wheels_bronze"],4,15000,{"archetype":"desert_coyote"})
	await process_frame
	check(not panel._showroom.has_model(),"Live service must not spawn a duplicate vehicle")
	check(panel._menu_level == 0 and not panel._tabs.visible,"Service starts in the visual menu without tabs")
	var roof_menu: Button
	for child in panel._cards.get_children():
		if child is Button and child.text.begins_with("Teto"): roof_menu = child
	check(roof_menu != null,"The initial visual menu offers Teto directly")
	if roof_menu != null: roof_menu.pressed.emit()
	check(panel._menu_level == 2 and panel._slot == "sunroof","Teto opens only its options")
	for frame in 2: await process_frame
	var first_option := root.gui_get_focus_owner()
	check(first_option != null and str(first_option.get_meta("original_slot","")) == "sunroof","An unchanged slot initially focuses Original instead of Back")
	check(panel._draft_parts == panel._parts,"Opening options must not change the draft")
	panel.request_cancel()
	check(panel.visible and panel._menu_level == 0 and not panel._exit_prompt.visible,"Back from Teto returns to the previous visual menu")
	for frame in 2: await process_frame
	var returned_focus := root.gui_get_focus_owner()
	check(returned_focus != null and str(returned_focus.get_meta("menu_key","")) == "sunroof","Returning from Teto restores focus to its originating menu item")
	panel._choose_part("paint","paint_ocean")
	panel._choose_part("wheels","wheels_bronze")
	panel._choose_part("wheel_model","wheel_mesh")
	check(panel._parts == {"paint":"paint_rosso"},"Selecting options changed installed state")
	check(requests.is_empty() and legacy.is_empty(),"Selecting a part emitted a purchase")
	check(panel._draft_cost() == 4000,"Total must charge new paint and wheel model, not owned rim colour")
	panel._compare.button_pressed = true
	check(previews.back() == panel._parts,"Original comparison must preview authoritative loadout")
	panel._compare.button_pressed = false
	check(previews.back() == panel._draft_parts,"Leaving comparison must restore complete draft")
	panel._apply_draft()
	check(requests.size() == 1 and requests[0] == panel._draft_parts,"Apply must emit one complete loadout")
	check(panel._parts == {"paint":"paint_rosso"},"UI must wait for authoritative confirmation")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	panel._unhandled_input(cancel)
	check(panel.visible and panel._menu_level == 1 and not panel._exit_prompt.visible,"Cancel from a wheel option returns to the wheel menu")
	panel._unhandled_input(cancel)
	check(panel.visible and panel._menu_level == 0 and not panel._exit_prompt.visible,"Cancel from the wheel menu returns to Visuais")
	panel._unhandled_input(cancel)
	check(panel.visible and panel._exit_prompt.visible,"Remapped cancel must protect a pending draft")
	panel._unhandled_input(cancel)
	check(panel.visible and not panel._exit_prompt.visible,"Second cancel must return to preparation")
	panel.discard_and_close()
	check(not panel.visible and not closes.is_empty(),"Forced close must restore preview without a confirmation modal")
	check(panel._draft_parts == panel._parts,"Discard must forget temporary choices")
	panel.show_vehicle("desert_coyote",{},[],0,1,{"archetype":"desert_coyote"})
	panel._choose_part("paint","paint_ocean")
	check(panel._apply.disabled,"Unaffordable draft must disable Apply")
	var request_count := requests.size()
	panel._apply_draft()
	check(requests.size() == request_count,"Unaffordable draft emitted a transaction")
	panel._choose_part("turbo","turbo_large")
	check(not panel._draft_parts.has("turbo"),"Locked part entered the draft")
	panel.discard_and_close()
	panel.owned_only = true
	panel.show_vehicle("desert_coyote",{},["ecu_3"],0,15000,{"archetype":"desert_coyote"})
	panel._choose_part("paint","paint_ocean")
	check(not panel._draft_parts.has("paint"),"Race preparation must never add an unowned purchase")
	panel._choose_part("ecu","ecu_3")
	check(panel._draft_parts.get("ecu","") == "ecu_3" and panel._draft_cost() == 0,"Owned preparation remains free without re-earning its unlock")
	panel.discard_and_close()
	panel.owned_only = false
	panel.show_vehicle("desert_coyote",{},[],0,15000,{"archetype":"desert_coyote"})
	panel._choose_part("paint","paint_ocean")
	var reject := func(_parts): panel.set_message("Compra não concluída")
	panel.loadout_requested.connect(reject)
	panel.close_panel()
	var exit_actions := panel._exit_prompt.find_children("*","Button",true,false)
	var apply_and_exit := exit_actions[1] as Button
	var continue_preparing := exit_actions[0] as Button
	apply_and_exit.pressed.emit()
	check(panel.visible and not panel._exit_after_apply,"Authority rejection must clear the pending exit intent")
	continue_preparing.pressed.emit()
	check(panel.visible and not panel._exit_prompt.visible,"Continue must return to the retained draft")
	panel.loadout_requested.disconnect(reject)
	var confirmed: Dictionary = panel._draft_parts.duplicate(true)
	panel._apply.pressed.emit()
	panel.show_vehicle("desert_coyote",confirmed,confirmed.values(),0,13800,{"archetype":"desert_coyote"})
	for frame in 2: await process_frame
	check(panel.visible and panel._parts == confirmed,"A normal apply after rejection and Continue must not exit the workshop")
	panel._open_slot("paint")
	for frame in 2: await process_frame
	check(root.gui_get_focus_owner() == panel.button_for_part("paint_ocean"),"An installed option receives initial focus")
	var before_accept := requests.size()
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept = InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = false
	Input.parse_input_event(accept)
	for frame in 2: await process_frame
	check(panel.visible and panel._menu_level == 2 and panel._draft_parts == confirmed and requests.size() == before_accept,"Enter keeps the selected option without navigating back or purchasing")
	for repeat in 3: panel._select_slot("wheel_model")
	panel.discard_and_close()
	panel.free()
	car.free()
	for frame in 3: await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphan_after <= orphan_baseline,"Repeated wheel page rebuilds must release every temporary Control")
	print("TUNING_DRAFT_ORPHANS before=",orphan_baseline," after=",orphan_after)
	print("TUNING_DRAFT ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
