extends Node3D
## Saída secreta do forte na área de esqui: um afloramento de rocha com uma laje que se
## arrasta de lado sobre a face, como uma pedra empurrando outra. Fica no mundo real da
## serra (não é um lugar), então só liga colisão e desenho quando o jogador está por
## perto na serra.
const WORLD_POSITION := Vector3(744.5,0.0,-481.0)
const ACTIVE_DISTANCE := 170.0
const SLIDE := 2.6
const STONE := ["5f6664","6b706c","555b58","747a75"]

var session
var slab: Node3D
var dust: CPUParticles3D
var solids: Array[StaticBody3D] = []
var slab_open := false
var _tween: Tween
var _clock := 0.0
var _active := true

func configure(owner_session) -> void:
	session = owner_session
	name = "MountainFortExit"
	top_level = true
	global_position = WORLD_POSITION
	_build()
	_set_active(false)

func interaction_global() -> Vector3:
	return to_global(Vector3(0,.04,1.9))

func arrival_global() -> Vector3:
	return to_global(Vector3(0,.04,3.3))

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0 or session == null: return
	_clock = .5
	var player: Node3D = session.world.player
	var near: bool = is_instance_valid(player) and session.state.region_id == "mountain" \
		and session.state.place_id.is_empty() and player.global_position.distance_to(global_position) <= ACTIVE_DISTANCE
	_set_active(near)

## Usado logo após a viagem: não espera o próximo teste periódico de distância.
func activate_now() -> void:
	_clock = 0.0
	_active = false
	_set_active(true)

func _set_active(value: bool) -> void:
	if _active == value: return
	_active = value
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0

## A laje corre 2,6 m sobre a face, com poeira de neve na base.
func set_open(open: bool,animate := true) -> void:
	slab_open = open
	var target := SLIDE if open else 0.0
	if _tween != null and _tween.is_valid(): _tween.kill()
	if not animate:
		slab.position.x = target
		return
	dust.emitting = true
	_tween = create_tween()
	_tween.tween_property(slab,"position:x",target,2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func(): dust.emitting = false)

func _build() -> void:
	# Massa de rocha atrás e dois blocos laterais formam o vão; a laje fecha o vão.
	for spec in [
		{"at":Vector3(-2.5,1.9,-2.9),"size":Vector3(4.4,3.8,3.0),"yaw":.32,"solid":true},
		{"at":Vector3(2.7,2.2,-3.1),"size":Vector3(4.6,4.4,3.2),"yaw":-.38,"solid":true},
		{"at":Vector3(0,1.3,-4.0),"size":Vector3(5.6,2.6,2.6),"yaw":.06,"solid":true},
		{"at":Vector3(-3.0,1.8,-.6),"size":Vector3(3.0,3.6,2.0),"yaw":.22,"solid":true},
		{"at":Vector3(3.1,1.6,-.7),"size":Vector3(2.9,3.2,1.8),"yaw":-.2,"solid":true},
		{"at":Vector3(0,3.45,-.6),"size":Vector3(3.6,1.2,1.9),"yaw":0.0,"solid":true},
		{"at":Vector3(-5.3,.9,-1.6),"size":Vector3(2.2,1.8,2.2),"yaw":.6,"solid":true},
		{"at":Vector3(5.5,.8,-1.4),"size":Vector3(2.0,1.6,2.0),"yaw":-.7,"solid":true},
	]:
		_rock(spec.at,spec.size,spec.yaw,spec.solid)
	# Vão escuro visível quando a laje sai.
	_box(self,Vector3(0,1.4,-.75),Vector3(2.3,2.8,.5),"0a0d0f")
	slab = Node3D.new()
	slab.name = "StoneSlab"
	add_child(slab)
	_box(slab,Vector3(0,1.4,.05),Vector3(2.5,2.8,.5),"6f7470")
	_box(slab,Vector3(0,2.86,.05),Vector3(2.62,.14,.58),"eef3f6")
	for crack in [[-.5,1.9,.05],[.4,.9,-.06],[.7,2.2,.08]]:
		_box(slab,Vector3(crack[0],crack[1],.31),Vector3(.05,1.0,.02),"3e4341",Vector3(0,0,crack[2]))
	_box(slab,Vector3(0,.5,.31),Vector3(2.1,.06,.02),"3e4341")
	solids.append(_solid_box("SlabBlock",Vector3(0,1.4,.05),Vector3(2.5,2.8,.5),slab))
	dust = CPUParticles3D.new()
	dust.name = "SlabDust"
	dust.position = Vector3(0,.2,.5)
	dust.amount = 36
	dust.lifetime = 1.4
	dust.emitting = false
	dust.direction = Vector3(0,1,.4)
	dust.spread = 50.0
	dust.initial_velocity_min = .3
	dust.initial_velocity_max = 1.1
	dust.gravity = Vector3(0,.3,0)
	dust.scale_amount_min = .5
	dust.scale_amount_max = 1.1
	var puff := SphereMesh.new()
	puff.radius = .22
	puff.height = .44
	puff.radial_segments = 6
	puff.rings = 3
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color(.93,.96,1.0,.5)
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = puff_material
	dust.mesh = puff
	add_child(dust)

func _rock(at: Vector3,size: Vector3,yaw: float,solid: bool) -> void:
	var body := Node3D.new()
	body.position = at
	body.rotation = Vector3(.03*sin(at.x),yaw,.04*cos(at.z))
	add_child(body)
	# Bloco principal com faces em degraus irregulares para não parecer uma caixa.
	_box(body,Vector3.ZERO,size,STONE[int(absf(at.x*3.0+at.y))%STONE.size()])
	_box(body,Vector3(size.x*.12,size.y*.5+.09,-size.z*.1),Vector3(size.x*.82,.2,size.z*.85),"eef3f6")
	_box(body,Vector3(-size.x*.5,-size.y*.2,size.z*.12),Vector3(.6,size.y*.5,size.z*.6),STONE[1],Vector3(0,0,.12))
	_box(body,Vector3(size.x*.5,-size.y*.15,-size.z*.1),Vector3(.5,size.y*.55,size.z*.5),STONE[2],Vector3(0,0,-.1))
	if solid: solids.append(_solid_box("RockBlock",at,size,self,Vector3(0,yaw,0)))

func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(color)
	display.position = at
	display.rotation = angles
	parent.add_child(display)
	return display

var _materials := {}
func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .95
		_materials[color] = material
	return _materials[color]

func _solid_box(id: String,at: Vector3,size: Vector3,parent: Node3D,angles := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.rotation = angles
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	if parent == slab:
		# A colisão da laje acompanha a laje.
		parent.add_child(body)
	else:
		add_child(body)
	return body
