extends RefCounted
const BOX_BATCH := preload("res://runtime/transit/StaticBoxBatch.gd")
const TRANSIT_WORK := preload("res://runtime/StallWorkTrace.gd")
const LETTERING_FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
## Metric three-section low-floor bus; shared materials and separate sliding doors.
static var materials: Dictionary = {}
static var wheel_tire: TorusMesh
static var wheel_hub: ArrayMesh
static func texture(file: String) -> Texture2D:
	return load("res://assets/transit/"+file+".svg") as Texture2D

static func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	if key == "roof":
		var roof := preload("res://assets/urban_detail/ExteriorFinish.gd").material("roof", Color("dedbd1"), false)
		roof.resource_name = "roof"
		materials[key] = roof
		return roof
	var m := StandardMaterial3D.new()
	m.resource_name = "paint" if key=="body" else key
	m.albedo_color = Color({"body":"b92732","cream":"dedbd1","glass":"ffffff","rubber":"24272a","metal":"727b80","light":"fff0cb","tail":"f43333","floor":"44494b","ad":"ffffff","ad_lume":"ffffff","ad_aurora":"ffffff","tire":"181b1d","alloy":"c6cdd1","amber":"dc933a","plate":"dedfd5"}[key])
	m.roughness = .32 if key=="glass" else .72
	if key in ["body","cream"]: m.albedo_texture = texture("paint")
	if key=="glass": m.albedo_texture = texture("glazing"); m.metallic = .25
	if key=="metal": m.metallic = .65; m.roughness = .38
	if key=="ad": m.albedo_texture = texture("maciota-ad")
	if key=="ad_lume": m.albedo_texture = texture("lume-ad")
	if key=="ad_aurora": m.albedo_texture = texture("aurora-ad")
	if key=="alloy": m.metallic = .75; m.roughness = .4
	if key=="tire": m.roughness = .96
	if key in ["light","tail"]: m.emission_enabled = true; m.emission = m.albedo_color; m.emission_energy_multiplier = 1.2
	materials[key] = m
	return m

static func hub_cylinder(surface: SurfaceTool, radius: float, depth: float, at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = depth
	mesh.radial_segments = 16 if radius < .05 else 32
	surface.append_from(mesh,0,Transform3D(Basis.IDENTITY,at))

static func prepare_wheels() -> void:
	if wheel_tire != null: return
	# Shared rounded sidewalls and recessed truck rims; still two moving nodes per wheel.
	wheel_tire = TorusMesh.new()
	wheel_tire.inner_radius = .28; wheel_tire.outer_radius = .48
	wheel_tire.rings = 32; wheel_tire.ring_segments = 12
	var alloy := SurfaceTool.new()
	var recess := SurfaceTool.new()
	alloy.begin(Mesh.PRIMITIVE_TRIANGLES); recess.begin(Mesh.PRIMITIVE_TRIANGLES)
	hub_cylinder(alloy,.273,.146,Vector3.ZERO)
	hub_cylinder(alloy,.105,.215,Vector3.ZERO)
	for side in [-1,1]:
		var rim := TorusMesh.new()
		rim.inner_radius = .245; rim.outer_radius = .30
		rim.rings = 32; rim.ring_segments = 8
		alloy.append_from(rim,0,Transform3D(Basis.IDENTITY,Vector3(0,side*.075,0)))
		for index in 8:
			var angle := TAU*index/8.0
			hub_cylinder(recess,.032,.012,Vector3(cos(angle)*.206,side*.079,sin(angle)*.206))
			hub_cylinder(alloy,.016,.022,Vector3(cos(angle)*.137,side*.085,sin(angle)*.137))
		# Um anel estreito em relevo na lateral do pneu pega luz sem um disco chapado.
		var bead := TorusMesh.new()
		bead.inner_radius = .359; bead.outer_radius = .373
		bead.rings = 32; bead.ring_segments = 6
		recess.append_from(bead,0,Transform3D(Basis.IDENTITY,Vector3(0,side*.098,0)))
	wheel_hub = alloy.commit()
	wheel_hub.surface_set_material(0,material("alloy"))
	recess.commit(wheel_hub)
	wheel_hub.surface_set_material(1,material("tire"))

static func box(parent: Node3D, at: Vector3, size: Vector3, key: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material(key)
	part.position = at
	parent.add_child(part)
	return part

static func panel(parent: Node3D, at: Vector3, size: Vector2, yaw: float, key: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	part.mesh = mesh; part.material_override = material(key)
	part.position = at; part.rotation.y = yaw
	parent.add_child(part)
	return part

static func lettering(parent: Node3D, text: String, at: Vector3, yaw: float, pixel: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text; label.font_size = 48; label.pixel_size = pixel
	label.font = LETTERING_FONT
	label.position = at; label.rotation.y = yaw; label.modulate = color
	label.outline_size = 0; label.no_depth_test = false; label.shaded = true
	parent.add_child(label)

static func exterior_details(model: Node3D, length: float, section: int, door_z: float) -> void:
	# O detalhe estático é fundido nos lotes de material existentes abaixo.
	for side in [-1,1]:
		var spans := [[-length*.5,length*.5]] if side<0 else [[-length*.5,door_z-.7],[door_z+.7,length*.5]]
		for span in spans:
			var midpoint: float = (span[0]+span[1])*.5
			var width: float = span[1]-span[0]
			for height in [.68,2.76]:
				box(model,Vector3(side*1.281,height,midpoint),Vector3(.024,.055,width),"rubber")
			box(model,Vector3(side*1.275,2.42,midpoint),Vector3(.025,.035,width),"rubber")
		# Juntas de painel, tampas de acesso e refletores abaixo do vidro.
		for z in [-length*.5+.45,length*.5-.55]:
			box(model,Vector3(side*1.277,1.03,z),Vector3(.022,.64,.025),"rubber")
			box(model,Vector3(side*1.293,.74,z),Vector3(.035,.075,.19),"amber")
		for z in range(ceili(length/1.2)):
			var at: float = -length*.5+.1+z*1.2
			if side>0 and absf(at-door_z)<.7: continue
			box(model,Vector3(side*1.29,2.17,at),Vector3(.022,1.12,.085),"rubber")
		# Seis cartazes, acima das caixas de roda e atrás da folga da porta deslizante.
		var ad_z := .72
		var ad_width := 3.9 if section==0 else 3.4
		var ad_key: String = ["ad_lume","ad","ad_aurora"][section]
		var brand: String = ["LUME","MACIOTA","AURORA"][section]
		var ink := Color("fff1c3") if section==0 else Color("182f36") if section==1 else Color("873d34")
		box(model,Vector3(side*1.289,1.25,ad_z),Vector3(.024,.49,ad_width+.12),"rubber")
		panel(model,Vector3(side*1.31,1.25,ad_z),Vector2(ad_width,.43),side*PI*.5,ad_key)
		lettering(model,brand,Vector3(side*1.318,1.28,ad_z),side*PI*.5,.0052,ink)
		lettering(model,"510",Vector3(side*1.30,2.57,length*.5-.58),side*PI*.5,.0025,Color("e8dfbf"))
	# Equipamento de teto: aletas e escotilha de manutenção, sem luzes novas nem trabalho por quadro.
	box(model,Vector3(0,3.28,.3),Vector3(1.32,.025,2.12),"metal")
	for vent in 10:
		box(model,Vector3(0,3.3,-.62+vent*.2),Vector3(1.19,.024,.065),"rubber")
	box(model,Vector3(0,3.09,-length*.5+1.05),Vector3(.82,.035,.66),"metal")
	var end_z: float = -length*.5 if section==0 else length*.5
	if section not in [0,2]: return
	var facing := -1.0 if section==0 else 1.0
	box(model,Vector3(0,.55,end_z+facing*.07),Vector3(2.42,.2,.14),"rubber")
	box(model,Vector3(0,.65,end_z+facing*.15),Vector3(2.18,.035,.025),"metal")
	box(model,Vector3(0,.86,end_z+facing*.11),Vector3(.49,.17,.035),"plate")
	lettering(model,"GTC 0510",Vector3(0,.86,end_z+facing*.135),PI if section==0 else 0.0,.00085,Color("253038"))
	if section==0:
		# Windshield gasket, central divider, wipers and recessed headlamp surrounds.
		for side in [-1,1]:
			box(model,Vector3(side*1.14,2.1,end_z-.077),Vector3(.055,1.18,.035),"rubber")
			box(model,Vector3(side*.87,.94,end_z-.077),Vector3(.51,.27,.035),"rubber")
			box(model,Vector3(side*.87,.94,end_z-.104),Vector3(.4,.15,.023),"light")
			box(model,Vector3(side*1.12,.94,end_z-.103),Vector3(.075,.15,.025),"amber")
			var wiper := box(model,Vector3(side*.5,1.82,end_z-.096),Vector3(.035,.5,.024),"rubber")
			wiper.rotation.z = side*.32
		box(model,Vector3(0,2.1,end_z-.08),Vector3(.034,1.1,.025),"rubber")
		for height in [1.53,2.66]: box(model,Vector3(0,height,end_z-.08),Vector3(2.32,.055,.03),"rubber")
		box(model,Vector3(0,1.2,end_z-.068),Vector3(.86,.17,.025),"rubber")
		for row in 3: box(model,Vector3(0,1.15+row*.048,end_z-.085),Vector3(.78,.012,.018),"metal")
	else:
		box(model,Vector3(0,2.24,end_z+.065),Vector3(2.08,.84,.025),"rubber")
		panel(model,Vector3(0,2.24,end_z+.1),Vector2(1.96,.72),0,"glass")
		box(model,Vector3(0,1.4,end_z+.065),Vector3(1.35,.36,.025),"rubber")
		for row in 6: box(model,Vector3(0,1.25+row*.058,end_z+.085),Vector3(1.28,.023,.02),"metal")
		for side in [-1,1]:
			box(model,Vector3(side*.95,1,end_z+.075),Vector3(.24,.57,.028),"rubber")
			box(model,Vector3(side*.95,1.18,end_z+.098),Vector3(.15,.15,.025),"tail")
			box(model,Vector3(side*.95,1,end_z+.098),Vector3(.15,.11,.025),"amber")
			box(model,Vector3(side*.95,.84,end_z+.098),Vector3(.15,.1,.025),"plate")
		lettering(model,"510",Vector3(0,2.8,end_z+.09),0,.0025,Color("ede3cb"))

static func build(parent: Node3D, length: float, section: int) -> Dictionary:
	var stall_began := TRANSIT_WORK.begin()
	var result := _stall_build(parent,length,section)
	if stall_began != 0: TRANSIT_WORK.finish("urban.model.build",stall_began,{"parent":str(parent.name),"section":section,"length":length})
	return result

static func _stall_build(parent: Node3D, length: float, section: int) -> Dictionary:
	var primitives_began := TRANSIT_WORK.begin()
	var model := Node3D.new()
	model.name = "BiarticulatedSection%d" % section
	parent.add_child(model)
	box(model,Vector3(0,.27,0),Vector3(2.42,.18,length),"body")
	box(model,Vector3(0,2.95,0),Vector3(2.5,.24,length),"roof")
	box(model,Vector3(0,3.16,.3),Vector3(1.5,.22,2.4),"cream")
	box(model,Vector3(0,.39,0),Vector3(2.3,.06,length-.15),"floor")
	var door_z := -length * .08 if section == 0 else -length * .28
	var wheels: Array[Node3D] = []
	prepare_wheels()
	for side in [-1,1]:
		var intervals := [[-length*.5,length*.5]] if side<0 else [[-length*.5,door_z-.7],[door_z+.7,length*.5]]
		for span in intervals:
			var middle: float = (span[0]+span[1])*.5
			var span_length: float = span[1]-span[0]
			box(model,Vector3(side*1.23,1.14,middle),Vector3(.08,.84,span_length),"body")
			panel(model,Vector3(side*1.267,2.17,middle),Vector2(maxf(.05,span_length-.1),1.12),side*PI*.5,"glass")
		for z in range(ceili(length/1.2)):
			if side>0 and absf(-length*.5+.1+z*1.2-door_z)<.7: continue
			box(model,Vector3(side*1.27,2.15,-length*.5+.1+z*1.2),Vector3(.055,1.23,.06),"metal")
		for span in intervals: box(model,Vector3(side*1.28,1.5,(span[0]+span[1])*.5),Vector3(.04,.10,span[1]-span[0]),"cream")
		var axles := [-length*.3,length*.31] if section==0 else [length*.26]
		for z in axles:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_tire
			wheel.material_override = material("tire")
			wheel.rotation.z = PI*.5
			wheel.position = Vector3(side*1.24,.49,z)
			model.add_child(wheel)
			wheels.append(wheel)
			var hub := MeshInstance3D.new()
			hub.mesh = wheel_hub
			hub.position = wheel.position; hub.rotation = wheel.rotation
			model.add_child(hub)
			wheels.append(hub)
	box(model,Vector3(0,1.55,-length*.5),Vector3(2.44,2.55,.08),"body")
	box(model,Vector3(0,1.55,length*.5),Vector3(2.44,2.55,.08),"body")
	if section==0:
		panel(model,Vector3(0,2.1,-length*.5-.075),Vector2(2.22,1.1),PI,"glass")
		box(model,Vector3(0,2.78,-length*.5-.06),Vector3(2,.22,.04),"rubber")
		var sign_node := Label3D.new()
		sign_node.text = "510  CIRCULAR"
		sign_node.font_size = 36; sign_node.pixel_size = .004
		sign_node.position = Vector3(0,2.78,-length*.5-.09)
		sign_node.rotation.y = PI
		sign_node.modulate = Color("ffd275")
		model.add_child(sign_node)
	for side in [-1,1]:
		if section==0:
			box(model,Vector3(side*.87,.94,-length*.5-.06),Vector3(.42,.19,.06),"light")
			box(model,Vector3(side*1.4,2.35,-length*.5+.1),Vector3(.15,.35,.3),"rubber")
		if section==2: box(model,Vector3(side*.95,1,length*.5+.06),Vector3(.18,.5,.06),"tail")
	var doors: Array[Node3D] = []
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(1.31,0,door_z+side*.32)
		model.add_child(leaf)
		box(leaf,Vector3(0,1.54,0),Vector3(.08,2.4,.62),"rubber")
		panel(leaf,Vector3(.065,1.92,0),Vector2(.49,1.57),PI*.5,"glass")
		box(leaf,Vector3(.066,1.16,0),Vector3(.012,.035,.5),"metal")
		box(leaf,Vector3(.067,1.5,side*.2),Vector3(.014,.24,.027),"metal")
		doors.append(leaf)
	exterior_details(model,length,section,door_z)
	if primitives_began != 0: TRANSIT_WORK.finish("urban.model.primitives",primitives_began,{"section":section,"children":model.get_child_count()})
	# Bakeia as partes estáticas por material uma vez. Folhas de porta e transformações das rodas continuam móveis.
	var batch_began := TRANSIT_WORK.begin()
	var append_usec := 0
	var append_max_usec := 0
	var append_count := 0
	var free_usec := 0
	var free_max_usec := 0
	var free_count := 0
	var batches := {}
	var batch_vertex_counts := {}
	for child in model.get_children():
		if not child is MeshInstance3D or child in wheels: continue
		var mat: Material = child.material_override
		if not batches.has(mat):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[mat]=surface
			batch_vertex_counts[mat] = 0
		for index in child.mesh.get_surface_count():
			var append_began := Time.get_ticks_usec() if batch_began != 0 else 0
			batch_vertex_counts[mat] = BOX_BATCH.append_from(batches[mat],child.mesh,index,child.transform,batch_vertex_counts[mat])
			if append_began != 0:
				var duration := Time.get_ticks_usec()-append_began
				append_usec += duration; append_max_usec = maxi(append_max_usec,duration); append_count += 1
		var free_began := Time.get_ticks_usec() if batch_began != 0 else 0
		child.free()
		if free_began != 0:
			var duration := Time.get_ticks_usec()-free_began
			free_usec += duration; free_max_usec = maxi(free_max_usec,duration); free_count += 1
	if batch_began != 0: TRANSIT_WORK.finish("urban.model.batch.append_free_loop",batch_began,{"append_usec":append_usec,"append_max_usec":append_max_usec,"append_count":append_count,"free_usec":free_usec,"free_max_usec":free_max_usec,"free_count":free_count,"batches":batches.size()})
	var commit_began := TRANSIT_WORK.begin()
	for mat in batches:
		var part := MeshInstance3D.new()
		part.mesh=batches[mat].commit(); part.material_override=mat
		model.add_child(part)
	if commit_began != 0: TRANSIT_WORK.finish("urban.model.batch.commit_upload",commit_began,{"batches":batches.size()})
	return {"model":model,"doors":doors,"door_z":door_z,"wheels":wheels}
