extends CharacterBody3D
## Decoration with scenery collision. No combat groups, damage or death handlers.
const MODEL = preload("res://runtime/cats/CatModel.gd")
const AUDIO = preload("res://runtime/cats/CatAudio.gd")
var cat_id := ""
var coat := 0
var adopted := false
var runtime
var model: Node3D
var voice: AudioStreamPlayer3D
var destination := Vector3.ZERO
var intent := "sit"
var activity := "sit"
var rest := 0.0
var near_player := false
var meow_cooldown := 0.0
var second_meow := -1.0
var rng := RandomNumberGenerator.new()
var toy: Node3D
var use_after_approach := Vector3.INF

func configure(id: String, index: int, resident: bool, owner_runtime) -> void:
	cat_id = id
	coat = index
	adopted = resident
	runtime = owner_runtime
	rng.seed = 7026+index*131
	name = id
	collision_layer = 0
	collision_mask = 1
	floor_snap_length = .16
	safe_margin = .008
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .23
	capsule.height = .52
	shape.shape = capsule
	shape.position.y = .29
	add_child(shape)
	# The narrow torso capsule alone does not cover the nose and haunches.
	for offset in [Vector3(0,.32,-.24),Vector3(0,.23,.23)]:
		var end_shape := CollisionShape3D.new()
		var end_ball := SphereShape3D.new()
		end_ball.radius = .13
		end_shape.shape = end_ball
		end_shape.position = offset
		add_child(end_shape)
	model = MODEL.new()
	model.configure(index)
	add_child(model)
	voice = AudioStreamPlayer3D.new()
	voice.stream = AUDIO.make_meow(index)
	voice.max_distance = 11.0
	voice.unit_size = 2.2
	voice.volume_db = -13
	add_child(voice)
	rest = rng.randf_range(1,4)
	rotation.y = rng.randf_range(-PI,PI)
	set_meta("adoptable_cat",true)
	set_meta("cat_id",id)

func _process(delta: float) -> void:
	if runtime == null or not runtime.can_animate(): return
	model.animate(delta,Vector2(velocity.x,velocity.z).length())
	meow_cooldown = maxf(0,meow_cooldown-delta)
	var distance: float = runtime.session.world.player.global_position.distance_to(global_position)
	if distance < 4.2 and not near_player and meow_cooldown <= 0:
		voice.play()
		second_meow = .8 if coat%2 == 0 else -1.0
		meow_cooldown = 24.0
	if distance < 4.2: near_player = true
	elif distance > 6.5: near_player = false
	if second_meow > 0:
		second_meow -= delta
		if second_meow <= 0 and distance < 6: voice.play()
	if activity == "play" and is_instance_valid(toy):
		preload("res://runtime/cats/CatFurniture.gd").animate(toy,delta,true)

func _physics_process(delta: float) -> void:
	if not adopted or runtime == null or not runtime.can_animate(): return
	rest -= delta
	if activity != "walk":
		velocity = Vector3.ZERO
		if rest <= 0: runtime.choose_activity(self)
		return
	var offset := destination-global_position
	offset.y = 0
	if offset.length() < .10:
		velocity = Vector3.ZERO
		if use_after_approach.is_finite():
			var target := use_after_approach
			use_after_approach = Vector3.INF
			if runtime._walk_clear(self,target):
				walk_to(target,"sleep",toy)
				return
		set_activity(intent)
		if is_instance_valid(toy):
			var facing: Vector3 = toy.global_position-global_position
			if facing.length_squared()>.01: rotation.y=atan2(-facing.x,-facing.z)
		rest = rng.randf_range(4.0,9.0) if intent != "sleep" else rng.randf_range(10.0,18.0)
		return
	var direction := offset.normalized()
	rotation.y = lerp_angle(rotation.y,atan2(-direction.x,-direction.z),minf(1,delta*8))
	var speed := .65 if coat%3 else .95
	velocity.x = direction.x*speed
	velocity.z = direction.z*speed
	velocity.y = -1.0
	move_and_slide()
	if is_on_wall() or rest < -12:
		velocity = Vector3.ZERO
		set_activity("sit")
		rest = 1.5

func set_activity(next: String) -> void:
	activity = next
	model.set_activity(next)

func walk_to(point: Vector3, next := "sit", prop: Node3D = null) -> void:
	use_after_approach = Vector3.INF
	destination = point
	intent = next
	toy = prop
	rest = 0.0
	set_activity("walk")
