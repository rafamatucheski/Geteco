extends CharacterBody3D
## Alucinação autorada, sem grupo de combate nem API de dano. A física nativa
## varrida mantém todo corpo no piso e fora da arquitetura em ruínas.
const GEO := preload("res://world/places/upside_world/UpsideGeometry.gd")
var appearance_index := 0
var variant := 0
var visitor_local := Vector3(0,.08,7)
var elapsed := 0.0
var traveled := 0.0
var blocked_frames := 0
var art: Node3D
var limbs: Array[Node3D] = []
var head: Node3D
var _materials: Dictionary = {}

func _ready() -> void:
	name = "IllusionMonster%d"%appearance_index
	set_meta("illusion_only",true)
	set_meta("gameplay_damage",false)
	collision_layer = 0
	collision_mask = 1
	floor_snap_length = .5
	var collision := CollisionShape3D.new()
	if variant == 1:
		# Uma área circular contém o rastejador inteiro em qualquer direção;
		# girar a arte não pode varrer garras longas através de uma ruína vizinha.
		var shape := CapsuleShape3D.new()
		shape.radius = .98
		shape.height = 1.96
		collision.shape = shape
		collision.position.y = .98
	else:
		var shape := CapsuleShape3D.new()
		shape.radius = .73
		shape.height = 3.35 if variant == 0 else 2.75
		collision.shape = shape
		collision.position.y = shape.height*.5
	add_child(collision)
	art = Node3D.new()
	art.name = "AuthoredSilhouette"
	add_child(art)
	if variant == 1: _crawler()
	elif variant == 2: _veiled()
	else: _watcher()

func _surface(color: String, glow := false) -> StandardMaterial3D:
	var key := color+str(glow)
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = .9
	if glow:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = 1.1
	_materials[key] = material
	return material

func _part(parent: Node3D, shape: String, at: Vector3, size: Vector3, color: String, rotation := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = GEO.primitive(shape)
	node.scale = size
	node.position = at
	node.rotation = rotation
	node.material_override = _surface(color,glow)
	parent.add_child(node)
	return node

func _joint(at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	art.add_child(joint)
	limbs.append(joint)
	return joint

func _watcher() -> void:
	_part(art,"taper",Vector3(0,1.91,0),Vector3(.48,1.35,.31),"252333")
	_part(art,"rock",Vector3(0,1.64,.025),Vector3(.48,.53,.35),"3e344b")
	for index in 7:
		_part(art,"box",Vector3(0,1.61+index*.11,.17),Vector3(.41-index*.025,.025,.055),"8a738b")
		_part(art,"box",Vector3(0,1.67+index*.11,.20),Vector3(.025,.066,.025),"ab60c1",Vector3.ZERO,true)
	head = Node3D.new()
	head.position = Vector3(0,2.88,.015)
	art.add_child(head)
	_part(head,"rock",Vector3.ZERO,Vector3(.34,.50,.30),"b5a4bb")
	_part(head,"box",Vector3(0,.012,.145),Vector3(.21,.065,.03),"190e27")
	for side in [-1,1]:
		_part(head,"box",Vector3(side*.068,.021,.167),Vector3(.035,.032,.012),"b964e3",Vector3.ZERO,true)
		_part(head,"taper",Vector3(side*.155,.32,-.015),Vector3(.058,.48,.075),"4b3656",Vector3(0,0,side*-.25))
		var leg := _joint(Vector3(side*.16,1.29,0))
		_part(leg,"taper",Vector3(0,-.51,0),Vector3(.13,1.06,.16),"343044")
		_part(leg,"box",Vector3(0,-1.17,.10),Vector3(.16,.11,.34),"272130")
		var arm := _joint(Vector3(side*.39,2.38,0))
		_part(arm,"round",Vector3(side*.055,-.65,.02),Vector3(.105,1.38,.11),"6c5a73",Vector3(0,0,side*.09))
		for finger in 3:
			_part(arm,"taper",Vector3(side*.1+(finger-1)*.045,-1.46,.06),Vector3(.025,.28,.035),"b09db8",Vector3(.2,0,0))

func _crawler() -> void:
	_part(art,"rock",Vector3(0,.66,-.10),Vector3(.81,.65,1.12),"353047")
	for rib in 6: _part(art,"box",Vector3(0,.85,-.52+rib*.16),Vector3(.71,.035,.04),"73617d",Vector3(.12,0,0))
	head = Node3D.new()
	head.position = Vector3(0,.63,.62)
	art.add_child(head)
	_part(head,"taper",Vector3(0,0,.10),Vector3(.47,.42,.47),"b0a0b1",Vector3(PI*.5,0,0))
	_part(head,"box",Vector3(0,-.08,.28),Vector3(.28,.12,.14),"1c1327")
	for side in [-1,1]:
		_part(head,"box",Vector3(side*.14,.075,.23),Vector3(.04,.05,.035),"d085ed",Vector3.ZERO,true)
		for index in 3:
			var leg := _joint(Vector3(side*.36,.65,-.50+index*.44))
			_part(leg,"round",Vector3(side*.12,-.24,.03),Vector3(.09,.56,.10),"5b4868",Vector3(0,0,side*.55))
			_part(leg,"taper",Vector3(side*.24,-.48,.16),Vector3(.07,.36,.10),"b9a1ba",Vector3(1.1,0,0))
		_part(head,"taper",Vector3(side*.10,-.13,.31),Vector3(.055,.20,.055),"d1c0c8",Vector3(PI*.2,0,0))

func _veiled() -> void:
	_part(art,"taper",Vector3(0,1.27,0),Vector3(.92,2.28,.55),"302139")
	for strip in 7: _part(art,"taper",Vector3(-.36+strip*.12,.41,.09),Vector3(.11,.68,.09),"48354e",Vector3(0,0,sin(strip)*.07))
	_part(art,"rock",Vector3(0,2.38,0),Vector3(.61,.69,.51),"49354f")
	head = Node3D.new()
	head.position = Vector3(0,2.39,.25)
	art.add_child(head)
	_part(head,"rock",Vector3.ZERO,Vector3(.31,.39,.13),"c4a9c6")
	_part(head,"box",Vector3(0,-.08,.066),Vector3(.12,.22,.015),"23142f")
	for side in [-1,1]:
		_part(head,"box",Vector3(side*.085,.05,.071),Vector3(.035,.024,.018),"ba7dde",Vector3.ZERO,true)
		var arm := _joint(Vector3(side*.37,1.92,0))
		_part(arm,"taper",Vector3(side*.075,-.55,.04),Vector3(.18,1.1,.22),"56405e",Vector3(0,0,side*.10))
		_part(arm,"box",Vector3(side*.12,-1.13,.08),Vector3(.085,.31,.065),"ba99bb",Vector3(.20,0,0))
	for mark in 5: _part(art,"box",Vector3(0,1.01+mark*.15,.23),Vector3(.035,.075,.02),"876097",Vector3.ZERO,true)

func _physics_process(delta: float) -> void:
	elapsed += delta
	var angle := appearance_index*TAU/4.0
	var target := visitor_local+Vector3(sin(angle)*2.3,0,cos(angle)*2.3)
	target.x = clampf(target.x,-11.5,11.5)
	target.z = clampf(target.z,-11.5,11.5)
	var desired := target-position
	desired.y = 0
	var heading := desired.normalized() if desired.length() > .25 else Vector3.ZERO
	var away := position-visitor_local
	away.y = 0
	if away.length() < 2.5 and away.length() > .01 and heading.dot(away.normalized()) < 0.0:
		# Aproxima-se do perímetro do jogador em vez de cruzar a câmera em primeira
		# pessoa a caminho da posição de órbita do lado oposto do monstro.
		away = away.normalized()
		heading -= away*heading.dot(away)
		if heading.length_squared() < .01: heading = away.rotated(Vector3.UP,PI*.5 if appearance_index%2 == 0 else -PI*.5)
		heading = heading.normalized()
	if not heading.is_zero_approx() and test_move(global_transform,heading*.6):
		blocked_frames += 1
		var found := false
		for turn in [-.8,.8,-1.4,1.4]:
			var alternative := heading.rotated(Vector3.UP,turn)
			if not test_move(global_transform,alternative*.65): heading = alternative; found = true; break
		if not found: heading = Vector3.ZERO
	var walk_speed := .95 if variant == 1 else .73
	velocity.x = heading.x*walk_speed
	velocity.z = heading.z*walk_speed
	velocity.y = -1.0 if is_on_floor() else velocity.y-18.0*delta
	var before := position
	move_and_slide()
	traveled += Vector2(position.x-before.x,position.z-before.z).length()
	if heading.length_squared() > .01: art.rotation.y = lerp_angle(art.rotation.y,atan2(heading.x,heading.z),1.0-exp(-2.5*delta))
	var moving := Vector2(velocity.x,velocity.z).length() > .1
	for index in limbs.size(): limbs[index].rotation.x = sin(elapsed*(4.0 if variant == 1 else 2.4)+index*PI*.73)*(.18 if moving else .025)
	if is_instance_valid(head): head.rotation.z = sin(elapsed*.75+appearance_index)*.07
	art.position.y = sin(elapsed*1.4+appearance_index)*.024
