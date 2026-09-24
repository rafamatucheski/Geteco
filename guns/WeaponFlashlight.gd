extends Node2D
## One reusable short-range canvas light. No per-frame texture allocation or idle processing.
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
const HEADLIGHT_TEXTURE = preload("res://legacy/city_demo/scripts/HeadlightTextureGenerator.gd")
const BEAM_SCALE := 0.55
const BEAM_OFFSET := 92.0
var actor: Node2D
var lamp: PointLight2D
var enabled := false
var weapon_id := ""

func _ready() -> void:
	actor = get_parent()
	lamp = PointLight2D.new()
	lamp.name = "WeaponBeam"
	lamp.color = Color(1.0, 0.97, 0.86)
	lamp.energy = 1.2
	lamp.shadow_enabled = false
	lamp.range_z_min = -4096
	lamp.range_z_max = 4096
	lamp.texture = HEADLIGHT_TEXTURE.get_conical_headlight_texture()
	lamp.texture_scale = BEAM_SCALE
	lamp.offset = Vector2(BEAM_OFFSET, 0.0)
	lamp.hide()
	add_child(lamp)
	set_physics_process(false)
	actor.visibility_changed.connect(func():
		if not actor.is_visible_in_tree(): switch_off())

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("weapon_flashlight") or event.is_echo(): return
	var input := get_node("/root/GameInput")
	var focus := get_viewport().gui_get_focus_owner()
	if get_tree().paused or input.remapping or focus is LineEdit or focus is TextEdit: return
	if not actor._reload_allowed(): return
	if not CUSTOM.installed(actor.weapon_customization, actor.active_weapon_id):
		actor._show_weapon_notice("Instale uma lanterna nesta arma na Ammu-Nation.")
	else:
		toggle()
	get_viewport().set_input_as_handled()

func toggle() -> void:
	if enabled:
		switch_off()
		return
	if not actor._reload_allowed() or not CUSTOM.installed(actor.weapon_customization, actor.active_weapon_id): return
	weapon_id = actor.active_weapon_id
	enabled = true
	lamp.show()
	set_physics_process(true)
	_physics_process(0.0)

func switch_off() -> void:
	enabled = false
	if is_instance_valid(lamp): lamp.hide()
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	if not actor._reload_allowed() or actor.active_weapon_id != weapon_id or not CUSTOM.installed(actor.weapon_customization, weapon_id):
		switch_off()
		return
	global_position = actor.get_weapon_muzzle_position()
	# Follow the rendered weapon heading, including its smoothed turn.
	global_rotation = -actor.model_root.rotation.y - PI * 0.5
