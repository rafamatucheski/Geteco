extends RefCounted
## Identidade compartilhada pelos guardas, encontros e ocupantes dos carros.
static var ink: StandardMaterial3D
static var shirt: StandardMaterial3D
static func insignia(size: float) -> MeshInstance3D:
	if ink == null:
		ink = StandardMaterial3D.new()
		ink.vertex_color_use_as_albedo = true
		ink.vertex_color_is_srgb = true
		ink.cull_mode = BaseMaterial3D.CULL_DISABLED
		ink.roughness = .95
	var result := MeshInstance3D.new()
	result.name = "CobraInsignia"
	result.mesh = preload("res://world/urban_detail/CobraMaterials.gd").emblem()
	result.material_override = ink
	result.scale = Vector3.ONE*size/5.5
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result

static func dress(model: Node3D) -> void:
	if model.has_meta("cobra_uniform"): return
	model.set_meta("cobra_uniform",true)
	if model.has_meta("rig_body"):
		var body = model.get_meta("rig_body")
		var profile := preload("res://assets/civilians/CivilianMeshKit.gd").build_profile(false, body.wardrobe.build)
		for side in [-1.0, 1.0]:
			var badge := insignia(.22)
			badge.name = "CobraInsigniaFront" if side > 0 else "CobraInsigniaBack"
			badge.position = Vector3(0, .22, side * (profile.chest.y + .005))
			badge.rotation = Vector3(PI*.5, PI if side < 0 else 0, 0)
			body.spine.add_child(badge)
		return
	if shirt == null:
		shirt = StandardMaterial3D.new()
		shirt.albedo_color = Color("23302a")
		shirt.roughness = .95
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.name in ["BodyShell","Sleeve"]: mesh.material_override = shirt
	var torso := model.find_child("torso_node",true,false) as Node3D
	if torso:
		var front := -.155
		var back := .138
		for mesh in torso.get_children():
			if not mesh is MeshInstance3D or mesh.name=="Waist": continue
			mesh.material_override = shirt
			var bounds: AABB = mesh.transform*mesh.mesh.get_aabb()
			front = minf(front,bounds.position.z)
			back = maxf(back,bounds.end.z)
		if torso.scale.x>1.1:
			torso.scale.x *= .82
			torso.scale.z *= .82
			for side in ["left","right"]:
				var arm := model.find_child(side+"_upper_arm",true,false) as Node3D
				if arm: arm.position.x *= .82
		for side in [-1.0,1.0]:
			var badge := insignia(.28)
			badge.name = "CobraInsigniaFront" if side<0 else "CobraInsigniaBack"
			badge.position = Vector3(0,.025,front-.004 if side<0 else back+.004)
			badge.rotation = Vector3(PI*.5,PI if side>0 else 0,0)
			torso.add_child(badge)

static func arms(model: Node3D, aiming: bool) -> void:
	if model.has_method("update_pose"):
		model.update_pose(1.0, aiming, false, 0.0, 0.0)
		return
	for side in ["left","right"]:
		var upper := model.find_child(side+"_upper_arm",true,false) as Node3D
		var lower := model.find_child(side+"_lower_arm",true,false) as Node3D
		# Cabeça e pés olham para -Z. Um osso pendurado em -Y precisa de
		# rotação X positiva para levar o cotovelo à frente, não às costas.
		if upper: upper.rotation = Vector3(1.35 if aiming else .08,0,-.08 if side=="left" else .08)
		if lower: lower.rotation = Vector3(.15 if aiming else .12,0,0)
		if lower:
			for part in lower.get_children():
				# Palm contém o antebraço inteiro nesta exportação: girá-lo
				# como se fosse só o punho dobrava a malha para o lado errado.
				if part is Node3D and part.name=="Palm": part.rotation = Vector3.ZERO
				if part is Node3D and part.name=="WeaponMount":
					part.rotation = Vector3(-1.5 if aiming else -PI*.5-.2,0,0)

static func livery(car) -> void:
	if not is_instance_valid(car.visual) or car.visual.has_node("CobraLivery"): return
	var root := Node3D.new()
	root.name = "CobraLivery"
	car.visual.add_child(root)
	# O capô do Cobra V8 recebe a marca; preserva a carroceria e portas originais.
	var badge := insignia(.85)
	badge.position = Vector3(0,.907,-1.5)
	root.add_child(badge)

static var _hood_heights: Dictionary = {}
static func race_livery(car) -> void:
	if car.visual.has_node("CobraLivery"): return
	var z: float=-car.half_length*.57
	if not _hood_heights.has(car.archetype):
		var height:=0.0
		for part in car.visual.find_children("*","MeshInstance3D",true,false):
			if part.mesh==null or part.has_meta("wheel_center"): continue
			var a: Vector3=part.to_local(car.to_global(Vector3(0,4,z)))
			var b: Vector3=part.to_local(car.to_global(Vector3(0,0,z)))
			var faces: PackedVector3Array=part.mesh.get_faces()
			for index in range(0,faces.size(),3):
				var hit=Geometry3D.segment_intersects_triangle(a,b,faces[index],faces[index+1],faces[index+2])
				if hit is Vector3: height=maxf(height,car.to_local(part.to_global(hit)).y)
		_hood_heights[car.archetype]=height
	var root:=Node3D.new()
	root.name="CobraLivery"
	car.visual.add_child(root)
	var badge:=insignia(.85)
	root.add_child(badge)
	badge.global_position=car.to_global(Vector3(0,float(_hood_heights[car.archetype])+.012,z))
