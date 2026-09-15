extends Node2D
## Short-lived ground stain; geometry is generated once and retained while fading.
const LIFETIME := 18.0
const FADE_DURATION := 6.0
var pattern_seed: int = -1
var droplets: Array[Vector3] = []
var age := 0.0
var radius := 15.0
var outline := PackedVector2Array()
var settling_actor: WeakRef
var _inner: Polygon2D
var is_drip := false

static func spawn_drip(actor: Node2D, strength: float) -> Node2D:
	var stain := _allocate(actor)
	stain.is_drip = true
	stain.radius = lerpf(1.3, 2.5, strength) * randf_range(0.88, 1.12)
	actor.get_parent().add_child(stain)
	stain.global_position = actor.global_position + Vector2(randf_range(-1.5, 1.5), 3)
	return stain

static func _allocate(actor: Node2D) -> Node2D:
	var stains := actor.get_tree().get_nodes_in_group("ground_blood")
	# Remove from the registry immediately: queue_free alone lets a same-frame
	# burst evict the same oldest node repeatedly and exceed the cap.
	while stains.size() >= 64:
		var oldest: Node = stains.pop_front()
		oldest.remove_from_group("ground_blood")
		oldest.hide()
		oldest.queue_free()
	var stain := new()
	stain.set_meta("blood_owner_id",actor.get_instance_id())
	return stain

static func spawn(actor: Node2D, lethal := true) -> Node2D:
	var stain := _allocate(actor)
	stain.radius = 17.0 if lethal else 6.0
	actor.get_parent().add_child(stain)
	stain.global_position = actor.global_position + Vector2(0, 3)
	if actor.get("is_flying") == true: stain.settling_actor = weakref(actor)
	return stain

func _ready() -> void:
	get_node("/root/WorldRenewal").watch_transient(self, LIFETIME)
	add_to_group("ground_blood")
	preload("res://guns/combat/BloodTransferSystem.gd").ensure.call_deferred(self)
	z_as_relative = false
	z_index = 5
	_build_pattern()
	# Keep the polygon commands and their triangulation. Only the inner tint
	# changes with age; transforms and modulation do not require redrawing.
	var outer := Polygon2D.new()
	outer.polygon = outline
	outer.color = Color("681b20")
	outer.show_behind_parent = true
	add_child(outer)
	_inner = Polygon2D.new()
	_inner.polygon = outline
	_inner.position = Vector2(-1, -1)
	_inner.scale = Vector2(0.76, 0.76)
	_inner.self_modulate = Color("8c2529").lerp(Color("45151b"), minf(age / 12.0, 1.0))
	_inner.show_behind_parent = true
	add_child(_inner)

func _build_pattern() -> void:
	var rng := RandomNumberGenerator.new()
	if pattern_seed < 0:
		rng.randomize()
	else:
		rng.seed = pattern_seed
	outline.clear()
	droplets.clear()
	# Compact pools, elongated smears, scattered splashes and uneven puddles.
	var profile := rng.randi_range(0, 3)
	var squash := rng.randf_range(0.48, 0.82)
	var stretch := rng.randf_range(0.85, 1.12)
	if profile == 1:
		squash = rng.randf_range(0.30, 0.46)
		stretch = rng.randf_range(1.12, 1.30)
	var orientation := rng.randf_range(-PI, PI)
	var phase := rng.randf_range(0.0, TAU)
	var lobes := rng.randi_range(3, 7)
	var roughness := 0.18 if profile == 3 else 0.10
	for i in 32:
		var angle := TAU * float(i) / 32.0
		var edge := 0.82 + roughness * sin(angle * lobes + phase) + 0.08 * cos(angle * 3.0 - phase) + rng.randf_range(-0.04, 0.04)
		outline.append((Vector2(cos(angle) * stretch, sin(angle) * squash) * radius * edge).rotated(orientation))
	var drop_count := rng.randi_range(7, 11) if profile == 2 else rng.randi_range(2, 6)
	if is_drip: drop_count = rng.randi_range(0, 1)
	for i in drop_count:
		var angle := rng.randf_range(0.0, TAU)
		var point := (Vector2(cos(angle) * stretch, sin(angle) * squash) * radius * rng.randf_range(1.0, 1.65)).rotated(orientation)
		droplets.append(Vector3(point.x, point.y, rng.randf_range(0.55, minf(2.4, radius * 0.16))))

func _process(delta: float) -> void:
	age += delta
	if settling_actor != null:
		var actor = settling_actor.get_ref()
		if is_instance_valid(actor): global_position = actor.global_position + Vector2(0, 3)
		if not is_instance_valid(actor) or actor.get("is_flying") != true or age > 1.5: settling_actor = null
	if age >= LIFETIME:
		queue_free()
		return
	scale = Vector2.ONE * lerpf(0.3, 1.0, smoothstep(0.0, 0.2 if is_drip else 2.2, age))
	modulate.a = clampf((LIFETIME - age) / FADE_DURATION, 0.0, 1.0)
	_inner.self_modulate = Color("8c2529").lerp(Color("45151b"), minf(age / 12.0, 1.0))

func _draw() -> void:
	for drop in droplets:
		draw_circle(Vector2(drop.x, drop.y), drop.z, Color("701e24"))
