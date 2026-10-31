extends CharacterBody3D
## Corpo de exibição dormente. A física/áudio completos do veículo só são criados na interação.
var archetype := ""
var paint := Color.WHITE
var health := 100.0
var speed := 0.0
var half_width := 1.0
var half_length := 2.0
var traffic := false
var external_input := false
var activated: CharacterBody3D
var world: Node3D
var reset_pending := false
var initial_health := 100.0

func _ready() -> void:
	initial_health = health
	set_physics_process(false)
	set_meta("impact_material","metal")
	add_to_group("stealable_meet_cars")
	add_to_group("v2_damageable")
	var ancestor := get_parent()
	while ancestor != null:
		var script = ancestor.get_script()
		if script != null and script.resource_path == "res://scripts/World.gd":
			world = ancestor
			break
		ancestor = ancestor.get_parent()
	_bind_gameplay.call_deferred() # Initial region construction precedes Gameplay.

func _bind_gameplay() -> void:
	if is_instance_valid(world) and is_instance_valid(world.gameplay):
		world.gameplay.player_died.connect(_on_death)
		world.gameplay.changed.connect(_on_changed)

func boarding_sides() -> Array: return [-1,1]
func driver_door_anchor(side: int) -> Vector3:
	return to_global(Vector3(float(side)*(half_width+.51),0,.15))

func materialize_vehicle() -> CharacterBody3D:
	if is_instance_valid(activated): return activated
	if not is_instance_valid(world) or not is_instance_valid(world.production): return null
	var old_layer := collision_layer
	collision_layer = 0
	# A superfície do estacionamento fica um pouco acima da origem do mapa. Um casco de exibição tem
	# altura livre escrita; o casco do veículo vivo começa exatamente na origem.
	var point := global_position
	for across in [-half_width*.8,half_width*.8]:
		for along in [-half_length*.8,half_length*.8]:
			var support := to_global(Vector3(across,0,along))
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1,[get_rid()])
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not floor_hit.is_empty(): point.y = maxf(point.y,float(floor_hit.position.y)+.025)
	activated = world.production.spawn_vehicle(archetype,point,global_rotation.y)
	if not is_instance_valid(activated):
		collision_layer = old_layer
		return null
	activated.paint_color = paint
	activated.set_meta("ambient_parked",true)
	activated.set_meta("track_visit_vehicle",true)
	activated.restore_health(minf(health,activated.max_health))
	hide()
	return activated

func receive_damage(amount: float, source: Node = null) -> void:
	if not is_finite(amount) or amount <= 0: return
	# O dano pode chegar durante um callback de consulta de física; a admissão é adiada.
	_apply_damage.call_deferred(amount,source)

func _apply_damage(amount: float, source: Node) -> void:
	var car := materialize_vehicle()
	if is_instance_valid(car): car.receive_damage(amount,source if is_instance_valid(source) else null)

func _on_death() -> void: reset_pending = true
func _on_changed() -> void:
	if world.gameplay.health <= 0: reset_pending = true
	if reset_pending and world.gameplay.health > 0:
		reset_pending = false
		_reset_display.call_deferred()

func _reset_display() -> void:
	if is_instance_valid(activated):
		if world.driving.occupied and world.driving.car == activated: return
		activated.hide()
		activated.collision_layer = 0
		activated.queue_free()
	activated = null
	health = initial_health
	collision_layer = 1
	show()
