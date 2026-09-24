extends "res://world/mountain_pass/MountainWeaponPickup.gd"

var prompt: Label

func install_model(parent: Node3D, point: Vector3) -> void:
	model = Node3D.new()
	model.name = "SecretRPGModel"
	model.position = point
	_floor_height = point.y
	parent.add_child(model)
	var weapon := Node3D.new()
	weapon.name = "FloorWeapon"
	weapon.rotation.z = PI*0.5
	weapon.position.y = hover_height
	model.add_child(weapon)
	preload("res://scripts/player/ArsenalWeapon3D.gd").build(weapon,"rpg")
	_install_halo()

func _ready() -> void:
	weapon_id = "rpg"
	pickup_id = "mountain_waterfall_secret_rpg_01"
	ammo = 4
	load_on_pickup = true
	animate_on_floor = true
	hover_height = 0.55
	super._ready()
	prompt = Label.new()
	prompt.position = Vector2(-140,-78)
	prompt.size = Vector2(280,42)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size",16)
	prompt.add_theme_color_override("font_color",Color("f8d889"))
	prompt.add_theme_color_override("font_outline_color",Color("172220"))
	prompt.add_theme_constant_override("outline_size",5)
	prompt.hide()
	add_child(prompt)

func _process(delta: float) -> void:
	super._process(delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	prompt.visible = can_collect(player)
	if prompt.visible:
		prompt.text = "E"

func can_collect(player: Node2D) -> bool:
	var reach := 42.0 if is_instance_valid(render_host) and render_host.get("inline_mode") == true else 74.0
	return not collected and is_instance_valid(player) and player.is_visible_in_tree() and player.get("is_dead") != true and player.get("is_in_dialogue") != true and player.get("is_control_disabled") != true and render_host.contains_actor(player) and global_position.distance_to(player.global_position) < reach

func _collect(body: Node2D) -> void:
	request_pickup(body)

func request_pickup(player: Node2D) -> bool:
	if not can_collect(player): return false
	super._collect(player)
	prompt.hide()
	if collected:
		get_node("/root/SaveManager").request_autosave("Arma secreta da cachoeira")
	return collected

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		if request_pickup(get_tree().get_first_node_in_group("player") as Node2D):
			get_viewport().set_input_as_handled()

func _hide_collected() -> void:
	super._hide_collected()
	if is_instance_valid(prompt): prompt.hide()
