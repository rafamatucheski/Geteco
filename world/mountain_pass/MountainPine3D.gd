extends "res://world/mountain_pass/MountainPineTree.gd"
## O mesmo modelo projetado e a mesma escala dos atores. Renders estáticos
## são compartilhados pela floresta inteira, sem um viewport por árvore.
static var _views: Dictionary = {}
var presentation: Sprite2D
var _last_ice_impact := -10000

func _ready() -> void:
	super._ready()
	var variant := posmod(variant_seed, 8)
	# Low conifer boughs occupy space at bonnet height. Keep the original
	# single static shape, but include these solid branches in its footprint.
	# Bare trunks and trees with raised crowns retain a narrower passage.
	if enable_collision:
		var clearance: float = [32.0,24.0,22.0,10.0,12.0,7.0,18.0,25.0][variant]
		get_node("TrunkCol").shape.radius = clearance * tree_scale
	var key := "%s_%d_%d" % [get_parent().get_instance_id(), int(is_snowy), variant]
	var data: Dictionary = _views.get(key, {})
	if data.is_empty() or not is_instance_valid(data.viewport.get_ref()):
		data = _build_shared_view(variant)
		_views[key] = data
	var sprite := Sprite2D.new()
	presentation = sprite
	sprite.texture = data.texture
	sprite.scale = Vector2.ONE * float(data.scale) * tree_scale
	sprite.position = Vector2(data.offset) * tree_scale
	add_child(sprite)
	# A copa projetada sobe muito acima da base. Sem repintá-la sobre quem
	# passa atrás do tronco, o ator (z 10) aparecia em pé em cima da árvore.
	# Margem curta: na floresta densa a área encosta em muitos troncos vizinhos.
	if enable_collision:
		preload("res://systems/interiors/ExteriorOcclusion.gd").attach(sprite, 3.0 * tree_scale, 80.0)
	set_meta("forest_species",["pine","fir","young_pine","birch","rowan","bare_tree","old_pine","leaning_fir"][variant])
	if posmod(variant_seed,3)==0 or variant==4:
		var details := preload("res://world/mountain_pass/ForestFloorDetails.gd").new()
		details.variant_seed = variant_seed
		details.fruiting = variant==4 and not is_snowy
		details.snowy = is_snowy
		details.scale = Vector2.ONE*tree_scale
		add_child(details)

func receive_vehicle_contact(speed: float, direction: Vector2, vehicle: CharacterBody2D) -> void:
	if not is_snowy or speed<35.0: return
	var now := Time.get_ticks_msec()
	if now-_last_ice_impact<2200: return
	_last_ice_impact = now
	preload("res://world/mountain_pass/TreeIceFall.gd").spawn(self,vehicle,direction,speed)
	if is_instance_valid(presentation):
		var origin := presentation.position
		var shake := create_tween()
		shake.tween_property(presentation,"position",origin+direction*2.5,.08)
		shake.tween_property(presentation,"position",origin-direction*1.5,.12)
		shake.tween_property(presentation,"position",origin,.22)

func _draw() -> void:
	if not _shadow_poly.is_empty():
		draw_colored_polygon(_shadow_poly, Color(0.02,0.035,0.045,0.25))

func _build_shared_view(variant: int) -> Dictionary:
	var view := SubViewport.new()
	view.name = "PineAtlas_%d_%d" % [int(is_snowy), variant]
	view.size = Vector2i(160,224)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Nasce sob a raiz da árvore de cena, adiada por um quadro -- mesmo padrão
	# de StreetLamp._get_shared_lamp_data() (tree.root.call_deferred). O pai
	# desta árvore de memorial pode estar "ocupado montando filhos" quando
	# várias nascem juntas dentro de uma subárvore pré-montada (cena
	# congelada pelo bake de distrito), e o Godot recusa add_child síncrono
	# nesse instante. Por isso a câmera abaixo usa look_at_from_position() e
	# a projeção é calculada à mão em vez de unproject_position(): nenhuma
	# das duas pode depender da câmera já estar dentro da árvore.
	get_tree().root.call_deferred("add_child", view)
	var tree := Node3D.new()
	view.add_child(tree)
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color("554333")
	var needles := StandardMaterial3D.new()
	needles.albedo_color = [Color("294337"),Color("345140"),Color("3e5544"),Color("2c4a40")][variant%4]
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("dde9ec")
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color("aacdd9")
	ice.roughness = .22
	ice.metallic = .10
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913+variant*89
	if variant==3: trunk.albedo_color=Color("acb5aa")
	_cylinder(tree,Vector3(0,1.65,0),.10,.24,3.3,trunk,9)
	for root_side in 5:
		var angle := root_side*TAU/5
		_branch(tree,Vector3(0,.22,0),Vector3(cos(angle)*.48,.035,sin(angle)*.48),.06,trunk)
	for mark in 9:
		var scar := _cylinder(tree,Vector3(.01,.22+mark*.23,.0),.245-mark*.007,.24-mark*.007,.025,trunk if variant!=3 else needles,7)
		scar.rotation.z = .08*sin(mark*2.1)
	if variant in [3,4,5]:
		for limb in 9:
			var angle := limb*2.4
			var start := Vector3(0,1.4+limb*.20,0)
			var end := start+Vector3(cos(angle)*rng.randf_range(.7,1.2),.65,sin(angle)*rng.randf_range(.7,1.2))
			_branch(tree,start,end,.07,trunk)
			_branch(tree,end,start.lerp(end,1.35)+Vector3(0,.25,0),.035,trunk)
			if variant!=5:
				_crown(tree,end+Vector3(0,.18,0),Vector3(.78,.80,.70) if variant==4 else Vector3(.65,1.05,.62),needles)
			if is_snowy:
				var cap_height := .96 if variant==4 else (1.20 if variant==3 else .10)
				var cap_size := Vector3(.63,.18,.54) if variant!=5 else Vector3(.24,.07,.19)
				_crown(tree,end+Vector3(0,cap_height,0),cap_size,snow)
				_icicle(tree,end,ice,.20+limb%3*.06)
	else:
		var tall := 1.13 if variant in [1,6,7] else (.77 if variant==2 else 1.0)
		for tier in 5:
			if variant==6 and tier==0: continue
			var radius := (1.25-tier*.22)*(.73 if variant in [1,2,7] else 1.0)
			var center := (1.35+tier*.72)*tall
			var drift := Vector3(.055*tier if variant==7 else 0,0,0)
			_cylinder(tree,Vector3(0,center+.20,0)+drift,.015,radius*.75,1.4*tall,needles,9)
			for bough in 5:
				var angle := bough*TAU/5+tier*.61+variant*.4
				var tip := Vector3(cos(angle)*radius,center-.18,sin(angle)*radius)+drift
				_branch(tree,Vector3(0,center,0),tip,.035,trunk)
				var tuft := _cylinder(tree,tip*.72+Vector3(0,center*.28+.15,0),.02,radius*.53,.70*tall,needles,7)
				tuft.rotation.z = cos(angle)*.18
				tuft.rotation.x = sin(angle)*.18
				if is_snowy and (bough+tier)%3!=0:
					_crown(tree,tuft.position+Vector3(0,.20,0),Vector3(radius*.52,.20,radius*.45),snow)
					if tier<3: _icicle(tree,tip,ice,.18+(bough%3)*.08)
	var camera_position := Vector3(0,10,6)
	var camera_target := Vector3(0,2.0,0)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = camera_position
	camera.look_at_from_position(camera_position, camera_target)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = 1.1
	view.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b5cbd5")
	env.environment.ambient_light_energy = 0.65
	view.add_child(env)
	# Equivalente analítico do que unproject_position() daria, sem exigir que
	# a câmera esteja dentro da árvore (ela nasce adiada, ver acima). Câmera
	# ortogonal: a escala (pixels por unidade de mundo) é uniforme e não
	# depende de rotação -- só de view.size/camera.size. O deslocamento
	# depende da orientação, calculada com a mesma convenção que
	# Basis.looking_at() usa por baixo de look_at_from_position() (a câmera
	# olha ao longo do -Z local).
	var basis_z := -(camera_target - camera_position).normalized()
	var basis_x := Vector3.UP.cross(basis_z).normalized()
	var basis_y := basis_z.cross(basis_x).normalized()
	var pixels_per_unit := float(view.size.y) / camera.size
	var display_scale := 18.0/pixels_per_unit
	var origin_relative_to_camera := -camera_position
	var offset := Vector2(
		-origin_relative_to_camera.dot(basis_x),
		origin_relative_to_camera.dot(basis_y)
	) * 18.0
	# Limpa a referência quando a região é descarregada, inclusive após load.
	var key := "%s_%d_%d" % [get_parent().get_instance_id(), int(is_snowy), variant]
	view.tree_exiting.connect(func(): _views.erase(key))
	return {"viewport":weakref(view),"texture":view.get_texture(),"scale":display_scale,"offset":offset}

func _branch(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var limb := _cylinder(parent,(start+end)*.5,radius*.55,radius,start.distance_to(end),mat,6)
	var axis := (end-start).normalized()
	var across := axis.cross(Vector3.FORWARD).normalized()
	limb.basis = Basis(across,axis,across.cross(axis))

func _crown(parent: Node3D, point: Vector3, size: Vector3, mat: Material) -> void:
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments=7
	sphere.rings=3
	sphere.radius=1
	sphere.height=2
	crown.mesh=sphere
	crown.material_override=mat
	crown.position=point
	crown.scale=size
	parent.add_child(crown)

func _icicle(parent: Node3D, point: Vector3, mat: Material, length: float) -> void:
	_cylinder(parent,point-Vector3(0,length*.5,0),.045,0,length,mat,5)

func _cylinder(parent: Node3D, point: Vector3, top: float, bottom: float, height: float, material: Material, sides: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = sides
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)
	return mesh
