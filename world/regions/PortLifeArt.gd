extends Node3D
## Static authored details: one MultiMesh per finish, shared box geometry, no frame loop.
var batches: Dictionary = {}
var materials: Dictionary = {}
var solids: StaticBody3D
var anchored := false
var anchored_materials: Array = []
var _anchor_position := Vector3.INF

func anchor_textures() -> void:
	anchored = true
	set_process(true)

func _process(_delta: float) -> void:
	if anchored_materials.is_empty() or global_position == _anchor_position: return
	_anchor_position = global_position
	for entry in anchored_materials:
		var material: StandardMaterial3D = entry["material"]
		material.uv1_offset = entry["base"] - global_position*material.uv1_scale

const SURFACES := preload("res://world/regions/PortSurfaces.gd")

func mat(color: String, metal := 0.0) -> StandardMaterial3D:
	if materials.has(color): return materials[color]
	# Chaves "pier_*" são superfícies procedurais compartilhadas; hex é cor chapada.
	if SURFACES.has(color):
		var shared: StandardMaterial3D = SURFACES.material(color)
		if anchored and shared.uv1_triplanar:
			# Objeto que se move (balsa): material próprio cujo offset anula o deslocamento,
			# senão a textura em coordenadas de mundo "escorrega" no casco.
			shared = shared.duplicate()
			anchored_materials.append({"material":shared,"base":shared.uv1_offset})
		materials[color] = shared
		return shared
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = .72
	material.metallic = metal
	if color in ["886e50", "a79777"]:
		material.albedo_texture = preload("res://world/places/ShopInteriorMaterials.gd").texture("wood")
		material.uv1_triplanar = true
	else:
		# Rampas, travessas e peças pintadas eram cor lisa: relevo e rugosidade em
		# espaço de mundo, mesmo tom.
		var tint := material.albedo_color
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, "metal" if metal > 0.1 else "plaster", 2.0, .7)
		material.albedo_color = Color(minf(tint.r * material.albedo_color.r, 1.0), minf(tint.g * material.albedo_color.g, 1.0), minf(tint.b * material.albedo_color.b, 1.0))
		material.roughness = 1.0
	materials[color] = material
	return material

func box(point: Vector3, size: Vector3, color: String, solid := false, p_basis := Basis.IDENTITY) -> void:
	if not batches.has(color): batches[color] = []
	batches[color].append(Transform3D(p_basis.scaled_local(size),point))
	if solid: collider(point,size,p_basis)

func collider(point: Vector3, size: Vector3, p_basis := Basis.IDENTITY) -> void:
	if solids == null:
		solids = StaticBody3D.new()
		solids.name = "PortLifeSolids"
		solids.collision_layer = 1
		solids.collision_mask = 0
		add_child(solids)
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = size
	shape.shape = volume
	shape.transform = Transform3D(p_basis,point)
	solids.add_child(shape)

func rail(a: Vector3, b: Vector3, solid := true) -> void:
	var span := b-a
	var mid := (a+b)*.5
	var turn := Basis(Vector3.UP,atan2(span.x,span.z))
	for h in [.5,1.05]: box(mid+Vector3.UP*h,Vector3(.065,.065,span.length()),"546467",false,turn)
	var count := maxi(1,ceili(span.length()/1.8))
	for i in count+1:
		var post := a.lerp(b,float(i)/count)
		box(post+Vector3.UP*.53,Vector3(.09,1.06,.09),"546467")
		box(post+Vector3.UP*1.1,Vector3(.13,.05,.13),"34494c")
	if solid: collider(mid+Vector3.UP*.54,Vector3(.10,1.08,span.length()),turn)

func lamp(point: Vector3) -> void:
	box(point+Vector3.UP*1.7,Vector3(.13,3.4,.13),"34494c",true)
	box(point+Vector3.UP*.08,Vector3(.36,.16,.36),"53615f")
	box(point+Vector3.UP*.3,Vector3(.19,.28,.19),"34494c")
	box(point+Vector3.UP*3.3,Vector3(.2,.1,.2),"53615f")
	box(point+Vector3.UP*3.5,Vector3(.65,.12,.55),"34494c")
	box(point+Vector3.UP*3.42,Vector3(.48,.06,.4),"ffd69a")
	var glow := mat("ffd69a")
	glow.emission_enabled = true
	glow.emission = Color("ffc47e")
	glow.emission_energy_multiplier = .65
	var source := Node3D.new()
	source.position = point
	source.add_to_group("city_local_light_source")
	source.set_meta("local_light",{"offset":Vector3.UP*3.3,"range":11.0,"energy":6.0,"color":Color("ffc078"),"camera_safe":true})
	add_child(source)

func flush() -> void:
	for color in batches:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		multimesh.mesh = cube
		multimesh.instance_count = batches[color].size()
		for i in batches[color].size(): multimesh.set_instance_transform(i,batches[color][i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "PortFinish_"+color
		visual.multimesh = multimesh
		visual.material_override = mat(color)
		add_child(visual)
	batches.clear()

func merge_static_boxes(owners: Array) -> void:
	# Consolidate the static quay and moored boats. Keep the ferry separate because it moves.
	var inverse := global_transform.affine_inverse()
	for source_owner in owners:
		for child in source_owner.get_children():
			if not child is MultiMeshInstance3D or not child.name.begins_with("PortFinish_"): continue
			var color: String = child.name.trim_prefix("PortFinish_")
			if not batches.has(color): batches[color]=[]
			materials[color]=child.material_override
			var local_transform: Transform3D = inverse*child.global_transform
			for index in child.multimesh.instance_count:
				batches[color].append(local_transform*child.multimesh.get_instance_transform(index))
			child.queue_free()
	flush()

func hull(width: float, length: float, color: String) -> void:
	var outline := PackedVector2Array([Vector2(-.38,.5),Vector2(.38,.5),Vector2(.5,.32),Vector2(.5,-.30),Vector2(.32,-.46),Vector2(0,-.56),Vector2(-.32,-.46),Vector2(-.5,-.30),Vector2(-.5,.32)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a := outline[i]*Vector2(width,length)
		var b := outline[(i+1)%outline.size()]*Vector2(width,length)
		var upper_a := Vector3(a.x,.38,a.y)
		var upper_b := Vector3(b.x,.38,b.y)
		var lower_a := Vector3(a.x*.7,-.55,a.y*.9)
		var lower_b := Vector3(b.x*.7,-.55,b.y*.9)
		for vertex in [upper_a,lower_a,lower_b,upper_a,lower_b,upper_b,Vector3(0,.38,0),upper_a,upper_b]: surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = mat(color)
	(mesh.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh)

func boat(passenger: bool, variant := 0) -> void:
	if not passenger:
		fishing_boat(variant)
		return
	var w := 4.6 if passenger else 2.25
	var l := 12.0 if passenger else 5.5
	hull(w,l,"294e5a" if passenger else ["366c73","8f5949"][variant%2])
	box(Vector3(0,.42,0),Vector3(w*.82,.12,l*(.98 if passenger else .85)),"pier_deck_light",passenger)
	for side in [-1.0,1.0]:
		box(Vector3(side*w*.46,.65,0),Vector3(.13,.50,l*.75),"e0d6b9",passenger)
		for z in [-l*.31,0,l*.31]:
			box(Vector3(side*w*.5,.20,z),Vector3(.18,.65,.4),"253238")
	if passenger:
		for side in [-1.0,1.0]: box(Vector3(side*1.35,.7,l*.44),Vector3(1.1,.65,.12),"e0d6b9",true)
	else: box(Vector3(0,.7,l*.44),Vector3(w*.83,.65,.12),"e0d6b9")
	if passenger:
		box(Vector3(0,1.4,-1.7),Vector3(3.35,1.9,5.5),"d7d0b9",true)
		box(Vector3(0,2.43,-1.7),Vector3(3.75,.16,5.9),"pier_roof")
		for side in [-1.0,1.0]:
			box(Vector3(side*1.86,2.39,-1.7),Vector3(.09,.3,5.9),"29404e")
			box(Vector3(0,2.39,-1.7+side*2.95),Vector3(3.75,.3,.09),"29404e")
			box(Vector3(side*1.55,2.56,-3.2),Vector3(.12,.1,.12),"546467")
		box(Vector3(.7,2.62,-.9),Vector3(.55,.18,.55),"546467")
		box(Vector3(.7,2.73,-.9),Vector3(.68,.04,.68),"29404e")
		for side in [-1.0,1.0]: _ring(Vector3(side*1.72,1.55,.95),.2,.07,"d65a3c" if side<0 else "e0d6b9",true)
		box(Vector3(0,2.44,1.28),Vector3(.1,.1,.1),"pier_bulb")
		for z in [-4.3,.9]: box(Vector3(0,2.3,z),Vector3(.1,.1,.1),"pier_bulb")
		for side in [-1.0,1.0]:
			for z in [-3.7,-2.3,-.9,.5]: box(Vector3(side*1.69,1.7,z),Vector3(.035,.65,1.0),"29404e")
		box(Vector3(0,1.8,-4.47),Vector3(2.9,.66,.04),"29404e")
		box(Vector3(0,1.3,1.07),Vector3(.95,1.65,.035),"29404e")
		box(Vector3(.36,1.17,1.10),Vector3(.04,.18,.04),"c4c4af")
		for z in [2.0,3.3]:
			for x in [-.85,.85]:
				for slat in 3: box(Vector3(x,.75,z-.2+slat*.2),Vector3(.65,.16,.17),"pier_bench")
				for slat in 3: box(Vector3(x,.86+slat*.16,z+.25),Vector3(.65,.1,.1),"pier_bench")
				for leg in [-.28,.28]: box(Vector3(x+leg,.5,z),Vector3(.06,.5,.5),"34494c")
		box(Vector3(0,3.05,-2.3),Vector3(.08,1.1,.08),"c4c4af")
		box(Vector3(0,3.5,-2.3),Vector3(.85,.06,.06),"c4c4af")
	else:
		for z in [-1.6,0,1.6]: box(Vector3(0,.65,z),Vector3(1.9,.12,.42),"8b7556")
		box(Vector3(0,.5,2.65),Vector3(.48,.9,.55),"253238")
		box(Vector3(.45,.78,.9),Vector3(.55,.5,.55),"66776a")
		for i in 7: box(Vector3(-.52,.53,-1.3+i*.22),Vector3(.6,.04,.04),"b49d73")
	flush()

func _beam(a: Vector3, b: Vector3, thickness: float, color: String) -> void:
	var delta := b-a
	box((a+b)*.5,Vector3(thickness,thickness,delta.length()),color,false,Basis.looking_at(delta.normalized(),Vector3.UP))

func _ring(center: Vector3, radius: float, thickness: float, color: String, upright := false) -> void:
	for i in 16:
		var a := TAU*i/16.0
		var b := TAU*(i+1)/16.0
		var p := Vector3(cos(a),0,sin(a)) if not upright else Vector3(0,cos(a),sin(a))
		var q := Vector3(cos(b),0,sin(b)) if not upright else Vector3(0,cos(b),sin(b))
		_beam(center+p*radius,center+q*radius,thickness,color)

func fishing_boat(variant: int) -> void:
	# An open, double-sided hull: no rectangular slab hiding the pointed bow.
	var outline := PackedVector2Array([Vector2(-.73,2.5),Vector2(.73,2.5),Vector2(.97,1.6),Vector2(1.08,.4),Vector2(.98,-.9),Vector2(.66,-2),Vector2(0,-2.95),Vector2(-.66,-2),Vector2(-.98,-.9),Vector2(-1.08,.4),Vector2(-.97,1.6)])
	var paint := Color("366c73" if variant%2==0 else "8f5949")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var top_a := Vector3(a.x,.72,a.y)
		var top_b := Vector3(b.x,.72,b.y)
		var chine_a := Vector3(a.x*.78,-.05,a.y*.94)
		var chine_b := Vector3(b.x*.78,-.05,b.y*.94)
		var bottom_a := Vector3(a.x*.32,-.43,a.y*.80)
		var bottom_b := Vector3(b.x*.32,-.43,b.y*.80)
		var inner_a := Vector3(a.x*.65,.12,a.y*.82)
		var inner_b := Vector3(b.x*.65,.12,b.y*.82)
		for quad in [[top_a,chine_a,chine_b,top_b,paint],[chine_a,bottom_a,bottom_b,chine_b,paint.darkened(.18)],[top_a,top_b,inner_b,inner_a,Color("c0b496")]]:
			surface.set_color(quad[4])
			for j in [0,1,2,0,2,3]: surface.add_vertex(quad[j])
		surface.set_color(Color("827156"))
		for vertex in [Vector3(0,.12,0),inner_b,inner_a]: surface.add_vertex(vertex)
		_beam(top_a,top_b,.105,"e0d6b9")
		_beam(top_a-Vector3.UP*.18,top_b-Vector3.UP*.18,.045,"34494c")
	surface.generate_normals()
	var hull_mesh := MeshInstance3D.new()
	hull_mesh.name="OpenFishingHull"
	hull_mesh.mesh=surface.commit()
	var finish := StandardMaterial3D.new()
	finish.vertex_color_use_as_albedo=true
	finish.roughness=.82
	finish.cull_mode=BaseMaterial3D.CULL_DISABLED
	hull_mesh.material_override=finish
	add_child(hull_mesh)
	# Floorboards, curved ribs and seats follow the available width of the hull.
	for z in [-1.8,-1.2,-.6,0.0,.6,1.2,1.8]:
		var width := .75 if absf(z)>1.5 else 1.15
		box(Vector3(0,.14,z),Vector3(width,.035,.43),"pier_deck_light")
		for side in [-1.0,1.0]: _beam(Vector3(side*width*.5,.15,z),Vector3(side*(width*.5+.23),.59,z),.045,"pier_deck")
	for row in [{"z":-1.55,"w":1.35},{"z":.35,"w":1.94},{"z":1.8,"w":1.5}]:
		for offset in [-.12,.12]: box(Vector3(0,.56,row.z+offset),Vector3(row.w,.09,.21),"pier_deck_light")
		for side in [-1.0,1.0]: box(Vector3(side*row.w*.33,.35,row.z),Vector3(.075,.4,.32),"pier_deck")
	# Rounded tire fenders, lashings, a rope coil and oar secured inside the gunwale.
	for side in [-1.0,1.0]:
		for z in [-.9,1.3]:
			_ring(Vector3(side*1.03,.3,z),.22,.105,"253238",true)
			_beam(Vector3(side*.98,.75,z),Vector3(side*1.03,.51,z),.024,"b49d73")
	for radius in [.12,.17,.22]: _ring(Vector3(-.20,.63,1.8),radius,.03,"b49d73")
	_beam(Vector3(.81,.76,-1.6),Vector3(.81,.76,.95),.055,"pier_deck")
	box(Vector3(.81,.76,-1.76),Vector3(.18,.065,.45),"pier_deck_light")
	# Outboard with hood, clamp, leg, tiller and propeller (no animated decoration).
	box(Vector3(0,.70,2.65),Vector3(.46,.46,.46),"253238")
	box(Vector3(0,.95,2.64),Vector3(.39,.08,.4),"607c82")
	box(Vector3(0,.39,2.51),Vector3(.26,.23,.26),"34494c")
	box(Vector3(0,.0,2.68),Vector3(.12,.7,.14),"53615f")
	box(Vector3(0,-.28,2.8),Vector3(.38,.07,.08),"607c82")
	_beam(Vector3(.10,.65,2.57),Vector3(.35,.68,2.03),.055,"253238")
	for i in 3: box(Vector3(.238,.72,2.52+i*.10),Vector3(.014,.07,.055),"53615f")
	# Small cooler, lid, handles and folded fishing net.
	box(Vector3(-.35,.33,-.65),Vector3(.52,.36,.54),"66776a")
	box(Vector3(-.35,.53,-.65),Vector3(.56,.06,.58),"b2b3a0")
	for side in [-1.0,1.0]: box(Vector3(-.35+side*.28,.39,-.65),Vector3(.06,.07,.20),"34494c")
	for i in 7:
		box(Vector3(.25+i*.065,.23,-1.1),Vector3(.022,.025,.55),"b49d73")
		box(Vector3(.45,.25,-1.36+i*.08),Vector3(.48,.025,.022),"b49d73")
	# Lanterna de proa e cunhos de amarração.
	box(Vector3(0,.82,-2.35),Vector3(.12,.12,.12),"pier_bulb")
	box(Vector3(0,.74,-2.35),Vector3(.05,.1,.05),"34494c")
	for side in [-1.0,1.0]: box(Vector3(side*.55,.78,-2.0),Vector3(.2,.06,.07),"34494c")
	flush()

func terminal() -> void:
	# Laje elevada sobre a água; não altera máscaras do oceano. Juntas e serra-corte estão na
	# textura (pier_concrete), alinhadas às bordas pelo offset do material.
	box(Vector3(228,-.20,197),Vector3(20,.64,11),"pier_concrete",true)
	# Faixa amarela de segurança no lado da água, aberta no embarque da balsa e na passagem leste.
	for span in [[218.9,231.4],[234.6,237.2]]:
		box(Vector3((span[0]+span[1])*.5,.127,192.55),Vector3(span[1]-span[0],.012,.14),"d6aa55")
	box(Vector3(218.9,.127,197.2),Vector3(.14,.012,9.4),"d6aa55")
	for span in [[192.55,194.0],[196.8,201.8]]:
		box(Vector3(237.2,.127,(span[0]+span[1])*.5),Vector3(.14,.012,span[1]-span[0]),"d6aa55")
	# Estacas sob a laje, travadas por vigas: aparecem para quem olha pelo lado da água.
	for x in [218.4,223,228,233,237.6]:
		for z in [192,201.8]:
			box(Vector3(x,-1.6,z),Vector3(.55,3.2,.55),"pier_pile")
			box(Vector3(x,-.5,z),Vector3(.7,.14,.7),"34494c")
	for z in [192,201.8]: box(Vector3(228,-.82,z),Vector3(19.6,.2,.26),"pier_pile")
	for x in [220,225,230,235]:
		box(Vector3(x,.16,191.7),Vector3(1.3,.075,.24),"d6aa55")
		box(Vector3(x,.35,192.15),Vector3(.22,.45,.22),"34494c",true)
		box(Vector3(x,.52,192.15),Vector3(.65,.12,.18),"34494c")
		box(Vector3(x,.6,192.15),Vector3(.3,.05,.3),"53615f")
	# Rampa no nível da popa aberta da balsa, com travessas antiderrapantes.
	box(Vector3(233,.25,190.7),Vector3(1.6,.24,2.4),"pier_deck_light",true)
	for i in 5: box(Vector3(233,.378,189.75+i*.45),Vector3(1.5,.02,.07),"34494c")
	for side in [-.82,.82]: box(Vector3(233+side,.21,190.7),Vector3(.09,.34,2.5),"pier_pile")
	rail(Vector3(232.23,.37,189.6),Vector3(232.23,.37,191.8))
	rail(Vector3(233.77,.37,189.6),Vector3(233.77,.37,191.8))
	rail(Vector3(218.1,.12,191.5),Vector3(221.2,.12,191.5))
	rail(Vector3(224.8,.12,191.5),Vector3(231.8,.12,191.5))
	rail(Vector3(234.2,.12,191.5),Vector3(237.9,.12,191.5))
	rail(Vector3(237.9,.12,191.5),Vector3(237.9,.12,194.2))
	rail(Vector3(237.9,.12,196.6),Vector3(237.9,.12,202.4))
	rail(Vector3(218.1,.12,191.5),Vector3(218.1,.12,202.4))
	_shelter()
	_fish_landing()
	# Placa de horários em dois postes, longe do caminho dos passageiros e do embarque.
	for x in [220.4,222.2]: box(Vector3(x,.95,195.4),Vector3(.1,1.9,.1),"34494c",true)
	box(Vector3(221.3,1.5,195.4),Vector3(2.1,.95,.07),"e0d6b9")
	box(Vector3(221.3,1.5,195.44),Vector3(1.94,.8,.05),"29404e")
	for i in 4: box(Vector3(221.3,1.75-i*.17,195.47),Vector3(1.6-(i%2)*.3,.05,.02),"d6aa55" if i==0 else "b2b3a0")
	box(Vector3(221.3,1.98,195.4),Vector3(2.3,.07,.17),"325760")
	for x in [219,220.3]:
		box(Vector3(x,.49,200.9),Vector3(.85,.72,.70),"b2b3a0",true)
		box(Vector3(x,.87,200.9),Vector3(.9,.08,.75),"607c82")
		box(Vector3(x,.58,201.27),Vector3(.3,.05,.03),"34494c")
	for i in 3:
		var p := Vector3(219.2+i*.82,.42,193)
		box(p,Vector3(.68,.55,.7),"pier_deck",true)
		for slat in 5: box(p+Vector3(-.27+slat*.13,.29,0),Vector3(.04,.04,.74),"pier_deck_light")
		for corner in [-.31,.31]: box(p+Vector3(corner,0,0),Vector3(.05,.57,.72),"pier_pile")
	for p in [Vector3(218.6,.12,199),Vector3(237.1,.12,193),Vector3(227,.12,196)]: lamp(p)
	flush()

func _shelter() -> void:
	# Abrigo aberto em escala humana. Do alto só o telhado é visto, então é ele que leva o detalhe.
	for x in [229,236]:
		for z in [197.4,200.4]:
			box(Vector3(x,1.5,z),Vector3(.16,2.8,.16),"34494c",true)
			box(Vector3(x,.07,z),Vector3(.34,.14,.34),"53615f")
			box(Vector3(x,2.86,z),Vector3(.3,.1,.3),"53615f")
	# Pavimento de blocos marca a área de espera sem criar degrau físico.
	box(Vector3(232.5,2.97,198.9),Vector3(7.7,.18,3.6),"pier_roof",true)
	# Fáscia e platibanda: a espessura do telhado passa a ler como beiral de verdade.
	for side in [-1.0,1.0]:
		box(Vector3(232.5,2.9,198.9+side*1.84),Vector3(7.9,.32,.09),"29404e")
		box(Vector3(232.5,3.11,198.9+side*1.7),Vector3(7.7,.08,.1),"29404e")
		box(Vector3(232.5+side*3.9,2.9,198.9),Vector3(.09,.32,3.7),"29404e")
		box(Vector3(232.5+side*3.75,3.11,198.9),Vector3(.1,.08,3.4),"29404e")
	# Calha e tubo de descida no poste do canto, junto ao pavimento.
	box(Vector3(232.5,2.78,200.77),Vector3(7.6,.1,.11),"546467")
	box(Vector3(236.2,1.4,200.77),Vector3(.1,2.8,.1),"546467")
	# Painéis solares inclinados e saída de ventilação no telhado.
	for x in [230.2,234.3]:
		var tilt := Basis(Vector3.RIGHT,-.2)
		box(Vector3(x,3.33,198.5),Vector3(2.58,.04,1.58),"546467",false,tilt)
		box(Vector3(x,3.345,198.5),Vector3(2.5,.05,1.5),"pier_solar",false,tilt)
		for leg in [-1.0,1.0]: box(Vector3(x+leg*1.0,3.19,198.5),Vector3(.06,.2,.06),"546467")
	box(Vector3(232.3,3.28,199.9),Vector3(.5,.32,.5),"546467")
	box(Vector3(232.3,3.46,199.9),Vector3(.64,.05,.64),"29404e")
	# Lâmpadas em cordão na beirada dos dois lados: acendem o abrigo sem luz dinâmica extra.
	for i in 9:
		var x := 229.0+i*.94
		var sag := sin(float(i)/8.0*PI)*.12
		box(Vector3(x,2.68-sag,198.9-1.82),Vector3(.1,.1,.1),"pier_bulb")
		box(Vector3(x,2.68-sag,198.9+1.82),Vector3(.1,.1,.1),"pier_bulb")
	# Bancos: assento de tábuas de teca, encosto de ripas e laterais de ferro.
	for x in [230.4,234.4]:
		for slat in 4:
			box(Vector3(x,.59,199.75625+slat*.1625),Vector3(2,.10,.1495),"pier_bench")
		collider(Vector3(x,.58,200),Vector3(2,.9,.78))
		for i in 5: box(Vector3(x,.65+i*.12,200.35),Vector3(2,.065,.08),"pier_bench")
		for side in [-.7,.7]: box(Vector3(x+side,.3,200),Vector3(.09,.4,.55),"34494c")
		for side in [-.97,.97]:
			box(Vector3(x+side,.56,200.15),Vector3(.07,.04,.52),"34494c")
			box(Vector3(x+side,.78,200.38),Vector3(.07,.5,.06),"34494c")
	# Lixeira ao lado do banco leste.
	box(Vector3(236.7,.36,199.2),Vector3(.46,.72,.46),"29404e",true)
	box(Vector3(236.7,.75,199.2),Vector3(.52,.07,.52),"546467")

func _fish_landing() -> void:
	# Píer de pesca: tábuas, longarinas e estacas de amarração que passam do nível do deck.
	box(Vector3(239,.0,188),Vector3(1.7,.30,16),"pier_deck",true)
	box(Vector3(238,.0,195.4),Vector3(3.4,.30,2),"pier_deck",true)
	box(Vector3(239.82,.19,188),Vector3(.12,.08,16),"pier_pile")
	for z in [180.4,184.6,188.8,193.0]:
		box(Vector3(239.95,-.2,z),Vector3(.24,2.5,.24),"pier_pile")
		box(Vector3(239.95,1.0,z),Vector3(.3,.07,.3),"34494c")
	for z in [184.6,193.0]: box(Vector3(239.95,1.12,z),Vector3(.13,.13,.13),"pier_bulb")
	for z in [182.5,186.7,190.9]: box(Vector3(239,-.35,z),Vector3(1.9,.22,.26),"pier_pile")
	rail(Vector3(238.18,.16,180),Vector3(238.18,.16,194.3))
	# Rolo de corda enrolada e caixa de peixes sobre o deck.
	for radius in [.12,.19,.26,.33]: _ring(Vector3(238.75,.2,183.2),radius,.05,"b49d73")
	box(Vector3(238.75,.17,183.2),Vector3(.1,.04,.1),"8b7556")
	box(Vector3(239.15,.2,190.2),Vector3(.5,.08,.9),"pier_deck_light")
	box(Vector3(239.15,.27,190.2),Vector3(.45,.06,.8),"607c82")

func quay_details() -> void:
	# Keep the freight lane and worker circuits clear; cluster details at the water edge.
	for x in [245.0,261.0,279.0,299.0,321.0,344.0]:
		lamp(Vector3(x,0,202.3))
		box(Vector3(x+1,.23,200.8),Vector3(.24,.46,.24),"34494c",true)
		box(Vector3(x+1,.43,200.8),Vector3(.72,.13,.22),"34494c")
		for i in 12:
			var angle := i*TAU/12.0
			box(Vector3(x+2.0+cos(angle)*.36,.06,201.2+sin(angle)*.36),Vector3(.2,.065,.065),"b49d73",false,Basis(Vector3.UP,-angle-PI*.5))
	for x in [248.0,274.0,312.0,339.0]:
		box(Vector3(x,.45,204.2),Vector3(1.4,.9,1.0),"pier_deck",true)
		for slat in 6: box(Vector3(x-.6+slat*.24,.94,204.2),Vector3(.16,.075,1.08),"pier_deck_light")
		for side in [-.58,.58]: box(Vector3(x+side,.45,204.2),Vector3(.08,1,.99),"pier_pile")
	for x in range(245,350,4): box(Vector3(x,.022,200.25),Vector3(1.4,.035,.20),"d6aa55")
	flush()
