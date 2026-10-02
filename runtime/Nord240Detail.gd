extends RefCounted
## Nord-only offline finish pass, used by tools/fleet_fixups/bake_nord240.gd.
## The game loads the baked scene: no texture generation, raycasts or merge at spawn.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
static var _materials: Dictionary = {}
static var _textures: Dictionary = {}
static var _glazing: Dictionary = {}

static func decorate(model: Node3D) -> void:
	if model.has_meta("nord240_detail"): return
	model.set_meta("nord240_detail",true)
	var body_faces := PackedVector3Array()
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var original := part.get_active_material(0) as StandardMaterial3D
		if original == null: continue
		var role := ROLES.key(part,0)
		var color := original.albedo_color.to_html(false)
		var bounds: AABB = part.transform * part.get_aabb()
		var center := bounds.get_center()
		var finish := ""
		if role == "paint":
			finish = "paint"
			if bounds.size.x > 1.5 and bounds.size.y > .2 and center.y < .95:
				for vertex in part.mesh.get_faces(): body_faces.append(part.transform * vertex)
		elif color == "44616b" or role == "glass":
			finish = "glass"
			part.mesh = _glass_uv(part.mesh)
		elif color == "fff0ca": finish = "headlight"
		elif color == "d32d36": finish = "tail_light"
		elif color == "ec9639": finish = "indicator"
		elif part.has_meta("wheel_center"):
			if color == "151a20": finish = "tire"
			elif color == "d1cbbd": finish = "wheel_metal"
			elif color == "555d64": finish = "brake_metal"
			else: finish = "wheel_recess"
		elif color == "b9c3c8" or color == "dcdde1": finish = "satin_metal"
		elif color == "262c32":
			finish = "bumper" if bounds.size.x > 1.8 or bounds.size.z > 4.0 else "trim"
		elif color == "151a20": finish = "underbody"
		if finish.is_empty(): continue
		var semantic := finish
		if finish == "tail_light": semantic = "tail"
		if finish in ["bumper","wheel_recess","underbody"]: semantic = "rubber"
		if finish == "tire": semantic = "rubber"
		if finish in ["wheel_metal","brake_metal","satin_metal"]: semantic = "metal"
		part.set_meta("nord_material_key",semantic)
		part.material_override = _material(finish,original)
		if finish == "headlight":
			# A recessed reflector surrounded by a black gasket, within the original size.
			_box(model,"LampGasket",Vector3(center.x,center.y,center.z+.012),Vector3(.408,.246,.032),"trim")
		elif finish == "tail_light":
			_box(model,"TailGasket",Vector3(center.x,center.y,center.z-.008),Vector3(.142,.566,.048),"trim")
	_add_panel_detail(model,body_faces)
	preload("res://runtime/Nord240Geometry.gd").optimize(model)

static func _material(kind: String, source: StandardMaterial3D = null) -> StandardMaterial3D:
	if _materials.has(kind): return _materials[kind]
	var mat := StandardMaterial3D.new()
	mat.resource_name = kind
	mat.roughness = .72
	mat.metallic_specular = .25
	match kind:
		"paint":
			mat.albedo_color = source.albedo_color
			mat.metallic = .22
			mat.roughness = .56
			mat.roughness_texture = _texture("paint_roughness")
			mat.clearcoat_enabled = true
			mat.clearcoat = .24
			mat.clearcoat_roughness = .32
			# No albedo/normal map: retain paint changes, damage and roof/door cutting.
		"glass":
			mat.albedo_color = Color("829aa6")
			mat.albedo_texture = _texture("glass")
			mat.metallic = .24
			mat.roughness = .18
			mat.clearcoat_enabled = true
			mat.clearcoat = .45
			mat.clearcoat_roughness = .18
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"headlight", "tail_light", "indicator":
			mat.albedo_color = Color("e4e6da") if kind == "headlight" else (Color("b61d29") if kind == "tail_light" else Color("ce7824"))
			mat.albedo_texture = _texture("lens")
			mat.roughness = .26
			mat.metallic = .18
			# Equipment owns the on/off state and brightness of the real lamps.
			mat.emission_enabled = false
			mat.emission = source.emission if source != null else mat.albedo_color
			mat.emission_energy_multiplier = source.emission_energy_multiplier if source != null else .15
			mat.emission_texture = mat.albedo_texture
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		"tire":
			mat.albedo_color = Color("25282b")
			mat.albedo_texture = _texture("tire")
			mat.roughness = .88
		"bumper":
			mat.albedo_color = Color("34393d")
			mat.albedo_texture = _texture("rubber")
			mat.roughness_texture = _texture("rubber_roughness")
			mat.roughness = .82
		"trim", "wheel_recess", "underbody", "seam":
			mat.albedo_color = Color("1d2226") if kind != "seam" else Color("302526")
			mat.roughness = .84
		"satin_metal", "wheel_metal", "brake_metal":
			mat.albedo_color = Color("aeb5b4") if kind == "satin_metal" else (Color("bdbbae") if kind == "wheel_metal" else Color("626a6d"))
			mat.metallic = .7
			mat.roughness = .38 if kind != "brake_metal" else .64
			mat.roughness_texture = _texture("metal_roughness")
	_materials[kind] = mat
	return mat

static func _texture(kind: String) -> ImageTexture:
	if _textures.has(kind): return _textures[kind]
	var image := Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var u := x/127.0
			var v := y/127.0
			var grain := fmod(float(x*73+y*179+x*y*11),101.0)/100.0
			var value := 1.0
			var color := Color.WHITE
			match kind:
				"paint_roughness": value = .89+grain*.08
				"metal_roughness": value = .80+sin(v*100.0)*.025+grain*.05
				"rubber_roughness": value = .85+grain*.14
				"rubber": value = .72+grain*.16
				"tire":
					# Fine circumferential tread and a subdued sidewall; mipmaps remove distant shimmer.
					var groove := pow(absf(sin(u*TAU*12.0+sin(v*TAU*4.0)*.5)),14.0)
					value = .72+grain*.10-groove*.14
				"lens":
					var rib := .04*cos(u*TAU*18.0)
					var edge := smoothstep(0.0,.10,minf(minf(u,1.0-u),minf(v,1.0-v)))
					value = (.51+.26*sin(v*PI)+rib)*(.7+.3*edge)
				"glass":
					var band := exp(-pow((u*.42+v-.57)/.18,2.0))*.18
					var edge := smoothstep(0.0,.045,minf(minf(u,1.0-u),minf(v,1.0-v)))
					value = (.25+(1.0-v)*.24+band)*(.62+.38*edge)
					color = Color(.86,.94,1.0)
			image.set_pixel(x,y,Color(color.r*value,color.g*value,color.b*value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[kind] = texture
	return texture

static func _glass_uv(source: Mesh) -> ArrayMesh:
	if _glazing.has(source): return _glazing[source]
	var mesh := ArrayMesh.new()
	var bounds := source.get_aabb()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv := PackedVector2Array()
		for vertex in vertices:
			var horizontal := (vertex.z-bounds.position.z)/maxf(bounds.size.z,.001) if bounds.size.x < bounds.size.z else (vertex.x-bounds.position.x)/maxf(bounds.size.x,.001)
			uv.append(Vector2(horizontal,1.0-(vertex.y-bounds.position.y)/maxf(bounds.size.y,.001)))
		arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_glazing[source] = mesh
	return mesh

static func _add_panel_detail(model: Node3D, faces: PackedVector3Array) -> void:
	for side in [-1.0,1.0]:
		# Door shut lines follow the actual body, including its lower taper.
		for z in [-.95,.23,1.055]:
			var low := .70 if z > 1.0 else .46
			var previous := _on_body(faces,Vector3(side*2.0,low,z),Vector3(-side,0,0))
			for y in [low+.1,low+.2,.905]:
				if y <= previous.y: continue
				var current := _on_body(faces,Vector3(side*2.0,y,z),Vector3(-side,0,0))
				_line(model,"DoorGap",previous,current,.006,"seam")
				previous = current
		var lower_a := _on_body(faces,Vector3(side*2.0,.455,-.95),Vector3(-side,0,0))
		var lower_b := _on_body(faces,Vector3(side*2.0,.455,.93),Vector3(-side,0,0))
		_line(model,"DoorSillGap",lower_a,lower_b,.005,"seam")
		# Window seals and the lower polished strip give the glazing thickness.
		_line(model,"WindowSeal",Vector3(side*.867,.949,-1.09),Vector3(side*.867,.949,2.30),.026,"trim")
		_line(model,"RoofSeal",Vector3(side*.812,1.544,-.68),Vector3(side*.812,1.544,2.20),.023,"trim")
		_line(model,"RoofGutter",Vector3(side*.817,1.574,-.65),Vector3(side*.817,1.574,2.19),.009,"satin_metal")
		# Hood shut line projected onto the authored panel, with a small physical offset.
		var previous := _on_body(faces,Vector3(side*.70,2.0,-2.30),Vector3.DOWN)
		for z in [-2.05,-1.8,-1.55,-1.25]:
			var current := _on_body(faces,Vector3(side*.70,2.0,z),Vector3.DOWN)
			_line(model,"HoodGap",previous,current,.006,"seam")
			previous = current
		# Wipers sit just above the windshield and cast no noisy thin shadows.
		_line(model,"Wiper",Vector3(side*.42,.989,-1.111),Vector3(side*.24,1.079,-1.044),.014,"trim")
		_line(model,"WiperBlade",Vector3(side*.24-.19,1.079,-1.049),Vector3(side*.24+.19,1.079,-1.049),.018,"trim")
		_line(model,"HatchGap",Vector3(side*.716,.64,2.488),Vector3(side*.716,.911,2.488),.006,"seam")
	for z in [-2.30,-1.25]:
		var a := _on_body(faces,Vector3(-.70,2.0,z),Vector3.DOWN)
		var b := _on_body(faces,Vector3(.70,2.0,z),Vector3.DOWN)
		_line(model,"HoodEndGap",a,b,.004,"seam")
	_line(model,"HatchLowerGap",Vector3(-.716,.64,2.488),Vector3(.716,.64,2.488),.006,"seam")
	_line(model,"GrilleDiagonal",Vector3(-.258,.605,-2.55),Vector3(.253,.792,-2.55),.014,"satin_metal")
	_box(model,"GrilleBadge",Vector3(0,.700,-2.561),Vector3(.075,.050,.011),"trim")
	_box(model,"HatchPlateRecess",Vector3(0,.713,2.487),Vector3(.37,.105,.014),"trim")
	_box(model,"HatchPlate",Vector3(0,.713,2.498),Vector3(.302,.069,.008),"satin_metal")

static func _on_body(faces: PackedVector3Array, start: Vector3, direction: Vector3) -> Vector3:
	var best: Variant = null
	var distance := INF
	for i in range(0,faces.size(),3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(start,direction,faces[i],faces[i+1],faces[i+2])
		if hit != null and start.distance_squared_to(hit) < distance:
			best = hit
			distance = start.distance_squared_to(hit)
	return best-direction*.004 if best != null else start+direction*1.12

static func _box(model: Node3D, label: String, at: Vector3, size: Vector3, kind: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = _material(kind)
	part.set_meta("nord_material_key","metal" if kind == "satin_metal" else "trim")
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(part)
	return part

static func _line(model: Node3D, label: String, a: Vector3, b: Vector3, width: float, kind: String) -> void:
	var direction := b-a
	if direction.length() < .0001: return
	var part := _box(model,label,(a+b)*.5,Vector3(width,direction.length(),width),kind)
	var axis := direction.normalized()
	var cross_axis := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < .9 else Vector3.FORWARD
	var z := cross_axis.cross(axis).normalized()
	part.basis = Basis(axis.cross(z).normalized(),axis,z)
