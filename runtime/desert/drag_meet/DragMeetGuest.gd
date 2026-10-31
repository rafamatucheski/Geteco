extends "res://scripts/Actor.gd"
## Civil comum que leva dano, pertencente ao encontro escrito e não ao
## teto de população ambiente. Caminhos curtos, recuo diante de ameaça e retorno usam física real.
var specification: Dictionary = {}
var host: Node3D
var person: Node3D
var _home := Vector3.ZERO
var _destination := Vector3.ZERO
var _end := Vector3.ZERO
var _elapsed := 0.0
var _rest := 3.0
var _panic := 0.0
var _refuge := Vector3.ZERO
var _at_end := false
var _travelling := false
var social_paused := false

func _ready() -> void:
	# Cuida da construção do corpo escrito mantendo a locomoção, o dano
	# e o contrato de testemunha do Actor. O Actor._ready montaria um corpo descartado.
	set_meta("gameplay_role","civilian")
	add_to_group("police_witness")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	person = _create_person()
	person.appearance_locked = true
	person.appearance_variant = identity
	person.coat_color = specification.coat
	person.pants_color = Color("30353e")
	person.wardrobe_overrides = {"female":identity%3==0,"top":2,"bottom":0,"shoe":0,"backpack":false,"bag":0,
		"body_profile":{"bust":false},"head_scale":Vector3.ONE*.94,
		"hair":4 if identity%3==0 else identity%3,"beard":0 if identity%3==0 else identity%2,
		"inner":Color("a7a398"),"accent":specification.coat.darkened(.2),"hat":1 if identity%5==0 else 0}
	person.rotation.y = PI
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").apply(person)
	visual.add_child(person)
	last_position = global_position
	_home = global_position
	_end = specification.walk_end+Vector3.UP*_home.y
	_destination = _home
	_refuge = _end
	set_meta("drag_meet_team",specification.team)
	set_meta("authored_population_owner","desert_drag_meet")
	set_meta("civilian_reaction_lod",true)
	add_to_group("desert_drag_guest")
	# O controle local de ameaça usa os sinais produtivos do Gameplay; este ator
	# nunca entra em world.people nem é cortado de forma independente pela densidade ambiente.
	controlled_automatically = true

func _create_person() -> Node3D:
	return CIVILIAN.new()

func _physics_process(delta: float) -> void:
	if dead: return
	_elapsed += delta
	_panic = maxf(0.0,_panic-delta)
	_rest = maxf(0.0,_rest-delta)
	var destination := _refuge if _panic>0.0 else _destination
	var offset := destination-global_position
	offset.y = 0.0
	if offset.length()<.2:
		if _travelling:
			_rest=4.0+float(identity%4)
			_travelling=false
		if _panic<=0.0 and bool(specification.roamer) and _rest<=0.0:
			_at_end = not _at_end
			_destination = _end if _at_end else _home
			_travelling = true
		automatic_direction = Vector3.ZERO
	else:
		automatic_direction = offset.normalized()
	if social_paused: automatic_direction=Vector3.ZERO
	speed = 2.6 if _panic>0.0 else .9
	var standing := automatic_direction.length_squared()<.01
	person.activity = "talk" if standing and _panic<=0.0 and int(_elapsed/3.8)%2==identity%2 else ""
	super._physics_process(delta)
	if standing and _panic<=0.0:
		var face: Vector3 = specification.focus-global_position
		visual.rotation.y = atan2(-face.x,-face.z)
	if _panic<=0.0 and not bool(specification.roamer): _destination=_home

func alert(origin: Vector3) -> void:
	if dead: return
	_panic = 8.0+float(identity%5)
	# O refúgio fica dentro do bolsão escrito. Sem fuga às cegas entre carros nem
	# atravessando a pista; uma multidão ameaçada recua e volta depois que assenta.
	var away := _home-origin
	away.y=0
	if away.length_squared()<.01: away=Vector3.RIGHT
	_refuge = _home+away.normalized()*1.25
	if is_instance_valid(host) and not host.retreat_clear(self,_refuge): _refuge=_home
	_destination = _home
	_rest = 4.0
	_travelling = false
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(person,true)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount<=0: return
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(person,true)
	var origin: Vector3 = source.global_position if source is Node3D else global_position
	super.receive_damage(amount,source)
	if is_instance_valid(host): host.alert_crowd(origin,22.0)
	if dead:
		set_meta("drag_meet_dead_since",Time.get_ticks_msec())
	else: alert(origin)
