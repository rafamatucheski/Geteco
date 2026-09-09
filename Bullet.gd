extends Area2D
const IMPACT_AUDIO := preload("res://audio/combat/CombatImpactAudio.gd")

@export var speed: float = 950.0
@export var damage: int = 15
@export var lifetime: float = 2.0
@export var tracer_color: Color = Color(1.0, 0.9, 0.2, 1.0)
@export var is_explosive: bool = false
@export var is_flame: bool = false
@export var explosion_radius: float = 140.0

var direction: Vector2 = Vector2.RIGHT
var owner_body: CollisionObject2D
var _spent := false

func _ready():
	if has_node("Tracer"):
		$Tracer.color = tracer_color
	if has_node("Core"):
		$Core.color = Color.WHITE.lerp(tracer_color, 0.18)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_expire)

func _physics_process(delta):
	if _spent:
		return
	var from = global_position
	var to = from + direction.normalized() * speed * delta
	var query = PhysicsRayQueryParameters2D.create(from, to, collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	if owner_body != null:
		query.exclude = [owner_body.get_rid()]
	var result = get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		_hit(result.get("collider"), result.get("position", to), result.get("normal", Vector2.ZERO))
		return
	global_position = to
	rotation = direction.angle()

func _on_body_entered(body):
	if body != owner_body:
		_hit(body, global_position, Vector2.ZERO)

func _hit(target, hit_position: Vector2, hit_normal: Vector2) -> void:
	if _spent:
		return
	_spent = true
	
	if is_explosive:
		_trigger_explosion(hit_position)
		queue_free()
		return
		
	var is_metal = target != null and (target.is_in_group("vehicle") or target.is_in_group("ambient_traffic") or target.is_in_group("emergency_vehicle") or target.is_in_group("metal_prop"))
	var is_flesh = target != null and (target.is_in_group("city_pedestrian") or target.is_in_group("pedestrian") or target.is_in_group("police_officer") or target.is_in_group("player") or target.is_in_group("gang_member"))
	
	if target != null and target.has_method("take_damage"):
		var is_player = owner_body != null and owner_body.is_in_group("player")
		target.take_damage(damage, is_player)
	
	var material: StringName = &"flesh" if is_flesh else (&"metal" if is_metal else &"concrete")
	if target != null and not is_flesh and not is_metal:
		var authored := StringName(target.get_meta("impact_material", "concrete"))
		if authored in [&"wood", &"glass", &"metal", &"concrete"]:
			material = authored
	IMPACT_AUDIO.play_hit(self, hit_position, material)
		
	var effects := get_tree().get_first_node_in_group("weapon_effects")
	if effects:
		if is_flesh:
			effects.spawn_blood(hit_position, direction, damage)
		elif is_metal:
			effects.spawn_impact(hit_position, hit_normal, &"metal", damage)
		else:
			effects.spawn_impact(hit_position, hit_normal, &"concrete", damage)
	queue_free()

func _trigger_explosion(pos: Vector2) -> void:
	var audio := AudioStreamPlayer2D.new()
	audio.bus = &"SFX"
	audio.stream = ProceduralAudio.get_explosion_stream()
	audio.volume_db = 3.0
	audio.max_distance = 1600.0
	get_tree().current_scene.add_child(audio)
	audio.global_position = pos
	audio.play()
	audio.finished.connect(audio.queue_free)
	
	var is_player = owner_body != null and owner_body.is_in_group("player")
	
	# Dano em área em veículos e pedestres
	for body in get_tree().get_nodes_in_group("damageable"):
		if is_instance_valid(body) and body != owner_body:
			var dist: float = pos.distance_to(body.global_position)
			if dist <= explosion_radius:
				var falloff: float = 1.0 - (dist / explosion_radius)
				var splash_dmg: int = int(damage * falloff)
				if body.has_method("take_damage"):
					body.take_damage(splash_dmg, is_player)
				if body.has_method("get_run_over"):
					var blast_dir: Vector2 = (body.global_position - pos).normalized()
					body.get_run_over(blast_dir * 500.0, is_player)
					
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle):
			var dist: float = pos.distance_to(vehicle.global_position)
			if dist <= explosion_radius:
				if vehicle.has_method("take_damage"):
					vehicle.take_damage(damage, is_player)
					
	# Efeito visual de explosão com expansão de fogo e fumaça
	var blast_node := Node2D.new()
	blast_node.global_position = pos
	blast_node.z_index = 25
	get_tree().current_scene.add_child(blast_node)
	
	var fireball := Polygon2D.new()
	fireball.polygon = PackedVector2Array([
		Vector2(-24, -12), Vector2(-12, -26), Vector2(14, -22),
		Vector2(26, -8), Vector2(24, 16), Vector2(10, 26),
		Vector2(-14, 22), Vector2(-26, 8)
	])
	fireball.color = Color(1.0, 0.65, 0.15, 0.95)
	blast_node.add_child(fireball)
	
	var shock_ring := Line2D.new()
	shock_ring.points = PackedVector2Array([
		Vector2(-35, 0), Vector2(-25, -25), Vector2(0, -35), Vector2(25, -25),
		Vector2(35, 0), Vector2(25, 25), Vector2(0, 35), Vector2(-25, 25), Vector2(-35, 0)
	])
	shock_ring.width = 4.0
	shock_ring.default_color = Color(1.0, 0.9, 0.5, 0.9)
	blast_node.add_child(shock_ring)
	
	var tw := blast_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast_node, "scale", Vector2(2.5, 2.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(blast_node, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(blast_node.queue_free)

func _expire() -> void:
	if is_instance_valid(self):
		if is_explosive:
			_trigger_explosion(global_position)
		queue_free()
