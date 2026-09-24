extends Node2D
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
var actor: Node2D
var endpoint := Vector2.ZERO
var contact := false
var beam_color := Color.RED
func _ready() -> void:
	actor = get_parent()
	z_index = 21
	configure()
func configure() -> void:
	if not is_instance_valid(actor): return
	var part := CUSTOM.selected(actor.weapon_customization,actor.active_weapon_id,"laser")
	beam_color = Color("62ef87") if part == "laser_green" else Color("ff4e45")
	hide()
	set_physics_process(part != "none")
func _physics_process(_delta: float) -> void:
	if not actor._reload_allowed() or not Input.is_action_pressed("aim"):
		hide()
		return
	global_position = actor.get_weapon_muzzle_position()
	global_rotation = 0.0
	var target: Vector2 = get_node("/root/GameInput").aim_target(actor)
	var direction := global_position.direction_to(target)
	var reach: float = WeaponCatalog.get_weapon(actor.active_weapon_id).get("max_range",420.0)
	var end := global_position + direction * reach
	var hit := preload("res://guns/combat/ShotQuery.gd").cast(actor,global_position,end,7,[actor.get_rid()],true)
	contact = not hit.is_empty()
	endpoint = to_local(hit.get("position",end))
	show()
	queue_redraw()
func _draw() -> void:
	var faint := beam_color
	faint.a = .24
	draw_line(Vector2.ZERO,endpoint,faint,.7,true)
	if contact:
		draw_circle(endpoint,2.2,beam_color)
		draw_circle(endpoint,.75,Color.WHITE)
