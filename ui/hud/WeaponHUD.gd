extends VBoxContainer
const STYLE := preload("res://ui/GameStyle.gd")
const ICON := preload("res://ui/v1/WeaponIcon3D.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
var weapon_icon: Control
var ammo_label: Label
var carousel: HBoxContainer
var equipped: PanelContainer
var _id := ""
var _switch_tween: Tween
var _carousel_tween: Tween
func _ready() -> void:
	name="WeaponHUD"; mouse_filter=MOUSE_FILTER_IGNORE; add_theme_constant_override("separation",8)
	carousel=HBoxContainer.new(); carousel.name="WeaponSwitch"; carousel.size_flags_horizontal=SIZE_SHRINK_END; add_child(carousel); carousel.hide()
	equipped=PanelContainer.new(); equipped.size_flags_horizontal=SIZE_SHRINK_END; equipped.add_theme_stylebox_override("panel",STYLE.compact(false,10)); add_child(equipped)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",0); equipped.add_child(column)
	weapon_icon=ICON.new(); weapon_icon.frameless=true; weapon_icon.custom_minimum_size=Vector2(112,38); column.add_child(weapon_icon)
	ammo_label=STYLE.label("",18); ammo_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; column.add_child(ammo_label)
func update_weapon(state, allow_switch := true) -> void:
	var id := str(state.equipped_weapon)
	var ammo: Dictionary=state.get_ammo(id)
	var magazine := int(ammo.get("magazine",-1))
	ammo_label.text="%d  |  %d"%[magazine,maxi(0,int(ammo.get("reserve",0)))] if magazine>=0 else ""
	ammo_label.visible=magazine>=0
	if id==_id: return
	var changed := not _id.is_empty()
	_id=id; weapon_icon.set_weapon(id)
	if _switch_tween: _switch_tween.kill()
	equipped.modulate.a=.2; _switch_tween=create_tween(); _switch_tween.tween_property(equipped,"modulate:a",1.0,.16)
	if changed and allow_switch and state.weapons_allowed(): _show_switch(state)
	else: carousel.hide()
func _show_switch(state) -> void:
	for child in carousel.get_children(): carousel.remove_child(child); child.queue_free()
	var ids: Array[String]=[]
	for id in WEAPONS.ORDER:
		if state.owns_weapon(id) and state.economy.can_carry_weapon(id): ids.append(id)
	if not ids.has(_id): ids.push_front(_id)
	var index := ids.find(_id)
	for offset in [-1,0,1]:
		if ids.size()<3 and offset==-1: continue
		if ids.size()<2 and offset==1: continue
		var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel",STYLE.compact(offset==0,8,Vector2(5,4)))
		var icon := ICON.new(); icon.frameless=true; icon.weapon_id=ids[posmod(index+offset,ids.size())]; icon.custom_minimum_size=Vector2(52,24)
		panel.add_child(icon); carousel.add_child(panel)
	if _carousel_tween: _carousel_tween.kill()
	carousel.show(); carousel.modulate.a=1
	_carousel_tween=create_tween(); _carousel_tween.tween_interval(1); _carousel_tween.tween_property(carousel,"modulate:a",0.0,STYLE.FADE); _carousel_tween.tween_callback(carousel.hide)
