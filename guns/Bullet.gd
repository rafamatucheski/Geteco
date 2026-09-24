extends Area2D
signal impact_resolved(target: Node, point: Vector2, material: StringName, damage_applied: bool)
const IMPACT_AUDIO := preload("res://audio/combat/CombatImpactAudio.gd")
const IMPACT_MATERIAL := preload("res://audio/combat/ImpactMaterial.gd")
const ROCKET_TEXTURE := preload("res://assets/combat/projectile_rocket.svg")

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
var _danger_reported := false
var _rocket_exhaust: Polygon2D
var _flight_age := 0.0
var max_range := 420.0
var falloff_start := 170.0
var min_damage_ratio := 0.25
var distance_travelled := 0.0

func configure_range(data: Dictionary) -> void:
	max_range = float(data.get("max_range", 420.0))
	falloff_start = float(data.get("falloff_start", 170.0))
	min_damage_ratio = float(data.get("min_damage_ratio", 0.25))
	explosion_radius = float(data.get("blast_radius", explosion_radius))

func damage_at_distance(distance: float) -> int:
	return WeaponCatalog.distance_damage(damage, distance, falloff_start, max_range, min_damage_ratio)


func _ready():
	z_index = 20
	# Player and some NPCs assign the shot parameters after add_child().
	# Configure once at the end of spawning, before the first rendered frame.
	_configure_visuals.call_deferred()
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_expire)

func _configure_visuals() -> void:
	rotation = direction.angle()
	var tracer := get_node_or_null("Tracer") as Sprite2D
	var core := get_node_or_null("Core") as Sprite2D
	if tracer == null or core == null:
		return
	core.scale = Vector2.ONE * .125
	core.position = Vector2.ZERO
	# Two shared sprites only: no per-frame drawing, lights or trail particles.
	tracer.modulate = Color.WHITE.lerp(tracer_color, 0.55)
	var trail_length := clampf(speed * 0.025, 18.0, 40.0)
	tracer.scale = Vector2(trail_length / 256.0, 0.105)
	tracer.position.x = -3.0 - trail_length * 0.5
	if is_explosive:
		core.texture = ROCKET_TEXTURE
		if not has_meta("rocket_trail_started"):
			set_meta("rocket_trail_started",true)
			preload("res://guns/combat/RocketTrail.gd").attach(self)
		core.scale = Vector2(0.1625, 0.1625)
		# Align the rocket nose with the same collision front as ordinary rounds.
		core.position.x = -11.0
		tracer.position.x = -36.0
		tracer.scale = Vector2(0.1375, 0.1625)
		tracer.modulate = Color(1.0, 0.62, 0.28, 0.45)
		# Attached to the motor: visible on the first frame and behind the
		# projectile at every heading. One tiny polygon, no light/emitter.
		if _rocket_exhaust == null:
			_rocket_exhaust = Polygon2D.new()
			_rocket_exhaust.name = "RocketExhaust"
			_rocket_exhaust.position.x = -17.0
			_rocket_exhaust.polygon = PackedVector2Array([Vector2(0,-2), Vector2(-9,-4), Vector2(-24,0), Vector2(-9,4), Vector2(0,2), Vector2(-5,0)])
			_rocket_exhaust.vertex_colors = PackedColorArray([Color(1,1,0.8), Color(1,0.6,0.08,0.9), Color(1,0.16,0.01,0), Color(1,0.6,0.08,0.9), Color(1,1,0.8), Color(1,0.95,0.5)])
			add_child(_rocket_exhaust)
	var interior := is_instance_valid(owner_body) and owner_body.has_meta("interior_actor_presentation")
	# Ordinary rounds use the same compact size on streets and indoors.
	# Rockets retain their separate exterior presentation.
	if not is_explosive or interior:
		for graphic in [tracer, core, _rocket_exhaust]:
			if is_instance_valid(graphic):
				graphic.scale *= .25
				graphic.position *= .25
	if interior:
		var shape := get_node_or_null("Collision") as CollisionShape2D
		if shape: shape.scale = Vector2.ONE * .25

func _physics_process(delta):
	if _spent:
		return
	_flight_age += delta
	if _rocket_exhaust:
		_rocket_exhaust.scale = Vector2(1.0 + sin(_flight_age * 73.0) * 0.18, 0.85 + sin(_flight_age * 91.0) * 0.15)
	if not _danger_reported:
		_danger_reported = true
		preload("res://characters/PedestrianDanger.gd").report(self, global_position, direction, owner_body)
	var from = global_position
	var step := minf(speed * delta, maxf(0.0, max_range - distance_travelled))
	var to = from + direction.normalized() * step
	var excluded: Array[RID] = []
	if is_instance_valid(owner_body):
		excluded.append(owner_body.get_rid())
		var body_area := owner_body.get_node_or_null("InteriorBallisticBody") as Area2D
		if body_area: excluded.append(body_area.get_rid())
	var result = preload("res://guns/combat/ShotQuery.gd").cast(self, from, to, collision_mask, excluded, true)
	if not result.is_empty():
		distance_travelled += from.distance_to(result.get("position", to))
		_hit(result.get("collider"), result.get("position", to), result.get("normal", Vector2.ZERO))
		return
	global_position = to
	distance_travelled += step
	rotation = direction.angle()
	if distance_travelled >= max_range: _expire()

func _on_body_entered(body):
	# Ordinary rounds use their swept segment as the sole contact authority;
	# sprite overlap otherwise reports an impact before reaching the surface.
	if not is_explosive: return
	if body != owner_body:
		var actor = body.get_meta("combat_actor") if is_instance_valid(body) and body.has_meta("combat_actor") else body
		if is_instance_valid(actor) and (actor.get("is_dead") == true or actor.get("is_incapacitated") == true):
			return
		# Explosions instantiate physical fragments. Area signals are emitted
		# during query flushing, when adding collision shapes is forbidden.
		if is_explosive: _hit.call_deferred(body, global_position, Vector2.ZERO)
		else: _hit(body, global_position, Vector2.ZERO)

func _hit(target, hit_position: Vector2, hit_normal: Vector2) -> void:
	if not is_instance_valid(target): target = null
	if is_instance_valid(target) and target.is_in_group("medical_rescue_work_zone"): return
	if is_instance_valid(target) and target.has_meta("combat_actor"):
		target = target.get_meta("combat_actor")
	if target == owner_body: return
	if is_instance_valid(target) and (target.get("is_dead") == true or target.get("is_incapacitated") == true):
		return
	if _spent:
		return
	_spent = true
	
	if is_explosive:
		_trigger_explosion(hit_position)
		queue_free()
		return
		
	var original_damage := damage
	damage = damage_at_distance(distance_travelled)
	var impact_strength := float(damage) / maxf(original_damage, 1.0)
	var impact_mat: StringName = IMPACT_MATERIAL.resolve(target)
	var damage_applied := false
	
	if target != null and target.has_method("take_damage"):
		var is_player = owner_body != null and owner_body.is_in_group("player")
		if impact_mat == &"flesh":
			target.set_meta("bullet_impulse", direction.normalized() * clampf(original_damage * 4.0, 65.0, 260.0) * impact_strength)
		if target.has_method("receive_bullet_impact"):
			target.receive_bullet_impact(direction, damage)
		var previous_health: Variant = target.get("health")
		target.set_meta("combat_attacker", owner_body)
		target.take_damage(damage, is_player)
		damage_applied = previous_health != null and target.get("health") != null and target.get("health") < previous_health
		if impact_mat == &"flesh" and damage_applied:
			preload("res://guns/combat/WoundedPose.gd").apply(target, float(previous_health) - float(target.health), direction, float(previous_health))
		if impact_mat == &"flesh" and previous_health != null and target.get("health") < previous_health:
			preload("res://guns/combat/BodyWound.gd").apply(target, direction)
			if not target.is_in_group("player"):
				preload("res://audio/reactions/PainReaction.gd").react(target, float(previous_health - target.get("health")))
		if impact_mat == &"flesh" and damage_applied:
			preload("res://guns/combat/BulletReaction.gd").apply(target)
		if impact_mat == &"flesh":
			target.remove_meta("bullet_impulse")
	
	var subject_id: int = target.get_instance_id() if impact_mat == &"flesh" and is_instance_valid(target) else 0
	IMPACT_AUDIO.play_hit(self, hit_position, impact_mat, damage, subject_id)
	preload("res://guns/combat/ShotFeedback.gd").contact(self, hit_position, hit_normal, impact_mat, damage_applied)
	impact_resolved.emit(target, hit_position, impact_mat, damage_applied)
		
	var effects := preload("res://guns/combat/CombatWorld.gd").effects_for(self)
	if effects == null:
		effects = preload("res://guns/combat/WeaponEffects.gd").new()
		get_parent().add_child(effects)
	if effects:
		if impact_mat == &"flesh":
			effects.spawn_blood(hit_position, direction, damage)
		else:
			effects.spawn_impact(hit_position, hit_normal, impact_mat, damage)
	queue_free()

func _trigger_explosion(pos: Vector2) -> void:
	var audio := AudioStreamPlayer2D.new()
	audio.bus = &"SFX"
	audio.stream = ProceduralAudio.get_explosion_stream()
	audio.volume_db = 3.0
	audio.max_distance = 1600.0
	get_parent().add_child(audio)
	audio.global_position = pos
	audio.play()
	audio.finished.connect(audio.queue_free)
	
	# Share the fatal blast response with grenades. One hit per actor, with
	# cover and distance falloff; knockback must not apply run-over damage.
	var subjects := {}
	for group in ["damageable", "vehicle", "pedestrian", "police_officer", "firefighter", "paramedic", "mortician"]:
		for body in get_tree().get_nodes_in_group(group):
			if body is Node2D: subjects[body.get_instance_id()] = body
	for body: Node2D in subjects.values():
		if body == owner_body or not is_instance_valid(body) or not body.is_visible_in_tree(): continue
		var dist := pos.distance_to(body.global_position)
		if dist >= explosion_radius or not body.has_method("take_damage"): continue
		if not preload("res://guns/combat/WeaponBlastDamage.gd").exposed(self, body, pos): continue
		var splash_dmg := int(damage * (1.0 - dist / explosion_radius))
		preload("res://guns/combat/WeaponBlastDamage.gd").apply(body, splash_dmg, pos, self, owner_body as Node2D)
					
	preload("res://guns/combat/ExplosionVisual.gd").spawn(get_parent(), pos, explosion_radius, false, direction)

func _expire() -> void:
	if is_instance_valid(self):
		if is_explosive and not _spent:
			_spent = true
			_trigger_explosion(global_position)
		queue_free()
