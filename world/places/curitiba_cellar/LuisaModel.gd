extends "res://assets/CivilianModel.gd"
## Luisa works at the accounts desk, seated at human scale in the native world.
## The occupied compact chair belongs to the resident: its footprint is covered
## by her physical Actor capsule, rather than blocking her authored admission.
var character_name := "Luísa"
var work_chair: Node3D
var chair_body: StaticBody3D
var _workstation_position := Vector3.ZERO
var _workstation_ready := false

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 10602
	lod_enabled = false
	coat_color = Color("9caa94")
	pants_color = Color("44483f")
	wardrobe_overrides = {"female":true,"height":.96,"build":0,"top":1,"bottom":0,"shoe":2,
		"hair":4,"hair_color":Color("4d3427"),"skin":Color("dfb091"),"beard":0,"hat":0,
		"glasses":false,"backpack":false,"bag":0,"inner":Color("e4d9bf"),"accent":Color("c1a46a")}
	sit_amount = 1.0
	seat_height = .45
	hand_provider = _typing_hands
	super._ready()
	_chair()
	_workstation_position = global_position
	_workstation_ready = true
	set_meta("work_activity","financial_computer")

func _pose(delta: float) -> void:
	if _workstation_ready:
		var threatened: bool = is_instance_valid(_owner_actor) and _owner_actor.get_meta("workplace_threatened",false)
		var distance := Vector2(global_position.x-_workstation_position.x,global_position.z-_workstation_position.z).length()
		# The real reaction calls _pose before moving: stand up immediately and
		# let its hand provider own the shielding pose until physical return.
		sit_amount = 1.0 if not threatened and distance <= .08 else 0.0
		if threatened and not is_instance_valid(chair_body): _anchor_empty_chair()
	super._pose(delta)

func _anchor_empty_chair() -> void:
	if not is_instance_valid(work_chair): return
	var settled := work_chair.global_transform
	work_chair.top_level = true
	work_chair.global_transform = settled
	chair_body = StaticBody3D.new()
	chair_body.name = "OfficeChairCollision"
	chair_body.collision_layer = 1
	chair_body.collision_mask = 0
	chair_body.set_meta("interior_solid_id","LuisaOfficeChair")
	var shape := BoxShape3D.new()
	shape.size = Vector3(.435,.96,.39)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0,.48,-.035)
	chair_body.add_child(collision)
	work_chair.add_child(chair_body)
	if _owner_actor is PhysicsBody3D: chair_body.add_collision_exception_with(_owner_actor)

func _typing_hands() -> Array:
	if is_instance_valid(_owner_actor) and (_owner_actor.get("dead") == true or _owner_actor.get_meta("workplace_threatened",false)):
		return [null,null]
	# The desk keyboard is .54 m in front of the actor's feet. Fine vertical
	# motion makes the task visible, without per-key nodes or a UI viewport.
	return [to_global(Vector3(-.17,.95+sin(clock*7.4)*.008,.56)),
		to_global(Vector3(.12,.95+sin(clock*6.8+1.2)*.008,.56))]

func _place_leg(index: int, pelvis_basis: Basis, pelvis_position: Vector3, ankle: Vector3, pitch: float) -> void:
	# Draw the feet a little closer to the chair, clear of the desk's full
	# solid footprint. Native two-bone IK still owns knees, shins and shoes.
	if sit_amount > .99: ankle.z -= .08
	super._place_leg(index,pelvis_basis,pelvis_position,ankle,pitch)

func _chair() -> void:
	var kit = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	var chair := Node3D.new()
	work_chair = chair
	chair.name = "OccupiedOfficeChair"
	chair.scale = Vector3.ONE/.96
	add_child(chair)
	kit.piece(chair,Vector3(.40,.085,.38),Vector3(0,.43,-.03),Color("45373b"))
	kit.piece(chair,Vector3(.36,.46,.05),Vector3(0,.73,-.205),Color("533b43"))
	kit.piece(chair,Vector3(.058,.34,.058),Vector3(0,.23,-.04),Color("676c60"))
	for side in [-1,1]:
		kit.piece(chair,Vector3(.03,.36,.03),Vector3(side*.17,.24,-.17),Color("656759"))
		kit.piece(chair,Vector3(.03,.36,.03),Vector3(side*.17,.24,.12),Color("656759"))
		kit.piece(chair,Vector3(.035,.04,.30),Vector3(side*.20,.64,-.035),Color("53483e"))
		kit.piece(chair,Vector3(.023,.18,.023),Vector3(side*.20,.55,.08),Color("a3997c"))
