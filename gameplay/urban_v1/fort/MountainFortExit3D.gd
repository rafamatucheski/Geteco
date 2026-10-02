extends Node3D
## Discreet natural rock entrance; the moving slab and rocks own native 3D depth.
const WORLD_POSITION := Vector3(762.0,0.0,-493.0)
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
var _materials := {}

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

func activate_now() -> void:
	_clock = 0.0
	_active = false
	_set_active(true)

func _set_active(value: bool) -> void:
	if _active == value: return
	_active = value
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0

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
	# Seven compact, faceted masses leave a 1.9 m opening and its approach clear.
	for spec in [
		[Vector3(-2.05,1.3,-1.65),Vector3(2.65,2.6,2.7),.22],
		[Vector3(2.15,1.38,-1.7),Vector3(2.7,2.76,2.6),-.25],
		[Vector3(0,1.08,-2.85),Vector3(3.8,2.16,1.8),.08],
		[Vector3(-1.82,1.12,-.22),Vector3(1.6,2.24,1.8),.12],
		[Vector3(2.05,1.05,-.26),Vector3(1.9,2.1,1.8),-.15],
		[Vector3(0,2.7,-.45),Vector3(3.5,.7,1.85),.04],
		[Vector3(-3.22,.4,-1.4),Vector3(1.3,.8,1.45),.43],
	]:
		_rock(spec[0],spec[1],spec[2])
	# Dark recess belongs to the rear wall, so it occludes rather than overlays actors.
	_box(self,Vector3(0,1.1,-1.83),Vector3(1.9,2.2,.04),"0a0d0f")
	_box(self,Vector3(-1.01,1.16,-.18),Vector3(.10,2.32,.18),"394340",Vector3.ZERO,true)
	_box(self,Vector3(1.01,1.16,-.18),Vector3(.10,2.32,.18),"394340",Vector3.ZERO,true)
	_box(self,Vector3(0,2.36,-.18),Vector3(2.12,.10,.18),"394340",Vector3.ZERO,true)
	# Recessed sliding track remains below the foot plane; no raised curb at the exit.
	_box(self,Vector3(1.28,-.028,.04),Vector3(4.6,.045,.34),"454d49")
	slab = Node3D.new()
	slab.name = "StoneSlab"
	add_child(slab)
	_box(slab,Vector3(0,1.14,.045),Vector3(2.02,2.28,.34),"6f7470",Vector3.ZERO,true)
	_box(slab,Vector3(0,2.31,.025),Vector3(2.07,.06,.35),"dde4e5")
	for crack in [[-.52,1.75,-.24],[.28,.74,.18],[.63,1.66,.35]]:
		_box(slab,Vector3(crack[0],crack[1],.222),Vector3(.025,.65,.009),"48514b",Vector3(0,0,crack[2]))
	for x in [-.78,.78]:
		_box(slab,Vector3(x,.18,.223),Vector3(.11,.14,.02),"48514b")
	dust = CPUParticles3D.new()
	dust.name = "SlabDust"
	dust.position = Vector3(0,.12,.35)
	dust.amount = 20
	dust.lifetime = 1.4
	dust.emitting = false
	dust.direction = Vector3(0,1,.4)
	dust.spread = 50.0
	dust.initial_velocity_min = .3
	dust.initial_velocity_max = 1.1
	dust.gravity = Vector3(0,.3,0)
	dust.scale_amount_min = .4
	dust.scale_amount_max = .8
	var puff := SphereMesh.new()
	puff.radius = .17
	puff.height = .34
	puff.radial_segments = 6
	puff.rings = 3
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color(.93,.96,1.0,.5)
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = puff_material
	dust.mesh = puff
	add_child(dust)

func _rock(at: Vector3,size: Vector3,yaw: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for level in 3:
		var ring := PackedVector3Array()
		var height: float = [-.5,.12,.43][level]*size.y
		var reach: float = [.88,1.0,.63][level]
		for i in 8:
			var angle := TAU*float(i)/8.0
			var irregular := 1.0+.07*sin(float(i)*2.3+at.x)
			ring.append(Vector3(sin(angle)*size.x*.5*reach*irregular,height,cos(angle)*size.z*.5*reach))
		rings.append(ring)
	var stone := Color(STONE[int(absf(at.x*3.0+at.y))%STONE.size()])
	for i in 8:
		var next := (i+1)%8
		for level in 2:
			_face(surface,rings[level][i],rings[level][next],rings[level+1][i],stone)
			_face(surface,rings[level+1][i],rings[level][next],rings[level+1][next],stone)
		_face(surface,rings[2][i],rings[2][next],Vector3(0,size.y*.5,0),Color("dde4e5"))
		_face(surface,rings[0][next],rings[0][i],Vector3(0,-size.y*.5,0),stone)
	var display := MeshInstance3D.new()
	display.name = "NaturalExitRock"
	display.mesh = surface.commit()
	var material := _material("ffffff")
	material.vertex_color_use_as_albedo = true
	display.material_override = material
	display.position = at
	display.rotation.y = yaw
	display.set_meta("interior_solid_id",StringName("exit_rock_"+str(solids.size())))
	add_child(display)
	_solid_from_mesh(display)

func _face(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	# Clockwise vertices face out in Godot; explicit flat normals keep the facets legible.
	var normal := (b-a).cross(c-a).normalized()
	surface.set_normal(normal)
	surface.set_color(color)
	for point in [a,c,b]: surface.add_vertex(point)

func _box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO,solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(color)
	display.position = at
	display.rotation = angles
	parent.add_child(display)
	if solid:
		display.set_meta("interior_solid_id",StringName("exit_detail_"+str(solids.size())))
		_solid_from_mesh(display)
	return display

func _solid_from_mesh(display: MeshInstance3D) -> void:
	display.create_convex_collision()
	for child in display.get_children():
		if child is StaticBody3D:
			child.collision_layer = 1
			child.collision_mask = 0
			solids.append(child)

func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .95
		_materials[color] = material
	return _materials[color]
