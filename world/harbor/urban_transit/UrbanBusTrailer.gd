extends "res://world/shared/traffic/TrafficVehicle.gd"
var lead_bus: CharacterBody2D
## A real collision body; its pose is owned by the leading bus's travelled path.
func _ready() -> void:
	target_length = 108.0
	super._ready()
	active_archetype_id = "route_city"
	_detached_from_lane = true
	_setup_3d_model({"model_class":"res://world/harbor/urban_transit/UrbanBusTrailerModel.gd","target_length":108.0,"target_width":38.0},Color("c82d32"))
	body_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(106,38)
	collision_layer = 2
	collision_mask = 7
	add_to_group("urban_bus_section")
	pedestrian_hitbox.monitoring = false
func enter_vehicle(actor: CharacterBody2D) -> void:
	if is_instance_valid(lead_bus): lead_bus.enter_vehicle(actor)
func _physics_process(_delta: float) -> void: pass
func _process(delta: float) -> void:
	_update_3d_orientation(delta)
	# Trailers carry red/amber running lamps, never forward-facing headlight beams.
	if headlight: headlight.hide()
	if second_headlight: second_headlight.hide()

func set_headlights(active: bool) -> void:
	is_night_or_storm = active
	if headlight: headlight.hide()
	if second_headlight: second_headlight.hide()
	if is_instance_valid(body_model): body_model.set_running_lights(active and not is_broken)
	_body_render_visible = false
