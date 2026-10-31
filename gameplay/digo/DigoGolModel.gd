extends Node3D
## Gol quadrado igual à foto: nariz curto e reto, cabine longa de duas portas e tampa traseira inclinada.
## Painéis estáticos agrupados por material; cada roda continua separada para os pivôs de Vehicle.
static var _cached: Array[Dictionary] = []
var _batches: Dictionary = {}
var _materials: Dictionary = {}

func _init() -> void:
	if _cached.is_empty():
		_build()
		for key: String in _batches:
			var tool: SurfaceTool = _batches[key]
			var mesh := tool.commit()
			var material_key := key.get_slice("@",0).get_slice("#",0)
			_cached.append({"name": key, "mesh": mesh, "material": _materials[material_key], "key": material_key})
	for entry in _cached:
		var part := MeshInstance3D.new()
		part.name = entry.name
		part.mesh = entry.mesh
		part.material_override = entry.material
		part.set_meta("coupe_damage_material_key", entry.key)
		if "#fixed" in str(entry.name): part.set_meta("door_cut_exempt",true)
		if "@" in str(entry.name):
			var bits := str(entry.name).split("@")
			part.set_meta("wheel_center", Vector3(float(bits[1]), .305, float(bits[2])))
		add_child(part)
	_batches.clear()
	_materials.clear()
	set_meta("model_identity", "Gol quadrado 1993")
	set_meta("rim_inches", 15)
	set_meta("body_doors", 2)
	# Lentes agrupadas também contêm luzes de neblina/ré; o centro combinado delas não é um farol.
	set_meta("headlight_mounts", [Vector3(-.576, .794, -1.856), Vector3(.576, .794, -1.856)])

func _build() -> void:
	for row in [["paint", "bcc2c4", .68, .26], ["rubber", "15181a", .0, .93], ["trim", "414447", .1, .65], ["glass", "243d45", .35, .13], ["alloy", "c8cccd", .85, .20], ["headlight", "dce3d2", .25, .18], ["amber", "d88123", .15, .25], ["tail", "a52d27", .15, .25], ["plate", "101213", .15, .5], ["speaker", "25292b", .15, .7]]:
		var material := StandardMaterial3D.new()
		material.resource_name = row[0]
		material.albedo_color = Color(row[1])
		material.metallic = row[2]
		material.roughness = row[3]
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[row[0]] = material
	# O assoalho fica dentro das caixas de roda, deixando recortes de verdade em volta dos pneus.
	_box("rubber", Vector3(0, .28, 0), Vector3(1.37, .12, 3.5))
	# Compartimento de passageiros oco: a antiga laje da largura inteira na altura da cintura
	# atravessava os assentos e ficava visível assim que as janelas abriam.
	_box("paint#fixed",Vector3(0,.80,-1.22),Vector3(1.61,.16,1.13))
	_box("paint#fixed",Vector3(0,.80,1.685),Vector3(1.61,.16,.20))
	_box("rubber#fixed",Vector3(0,.18,.46),Vector3(1.50,.05,2.16))
	_quad("paint", Vector3(-.81,.86,-1.82),Vector3(.81,.86,-1.82),Vector3(.79,.94,-.64),Vector3(-.79,.94,-.64))
	_quad("paint#fixed", Vector3(-.64,1.43,-.13),Vector3(.64,1.43,-.13),Vector3(.65,1.42,.87),Vector3(-.65,1.42,.87))
	# Fecha a borda do teto acima do vidro; uma emenda aberta de 3 cm expunha a calha do outro lado.
	_quad("paint#fixed",Vector3(-.64,1.43,-.13),Vector3(.64,1.43,-.13),Vector3(.611,1.399,-.136),Vector3(-.611,1.399,-.136))
	_quad("paint#fixed",Vector3(-.65,1.42,.87),Vector3(.65,1.42,.87),Vector3(.612,1.391,.91),Vector3(-.612,1.391,.91))
	_quad("glass", Vector3(-.744,.96,-.617),Vector3(.744,.96,-.617),Vector3(.611,1.399,-.136),Vector3(-.611,1.399,-.136))
	_quad("glass", Vector3(-.612,1.391,.91),Vector3(.612,1.391,.91),Vector3(.743,.967,1.587),Vector3(-.743,.967,1.587))
	# Colunas A/C, calhas e borrachas de janela seguem a fotografia de propósito.
	for side in [-1.0,1.0]:
		var x: float = side*.817
		for z in [-1.22, 1.19]:
			_wheel(side,z)
		# A chapa lateral tem a borda inferior elevada sobre cada arco; o friso prateado a acompanha.
		var samples: Array[float] = [-1.80,-1.60,-1.57,-1.50,-1.39,-1.22,-1.05,-.94,-.87,-.84,-.62,.61,.81,.84,.91,1.02,1.19,1.36,1.47,1.54,1.57,1.78]
		for i in samples.size()-1:
			var za := samples[i]
			var zb := samples[i+1]
			var ya := _arch_height(za)
			var yb := _arch_height(zb)
			_quad("paint",Vector3(x,ya,za),Vector3(x,yb,zb),Vector3(x,.906,zb),Vector3(x,.906,za))
			if ya>.32 or yb>.32: _beam("paint",Vector3(x*1.014,ya+.013,za),Vector3(x*1.014,yb+.013,zb),.025)
		# O friso preto de proteção é interrompido nos arcos de roda, nunca passa por cima do pneu.
		for span in [Vector2(-1.78,-1.57),Vector2(-.84,.81),Vector2(1.57,1.78)]:
			_box("trim",Vector3(x,.50,(span.x+span.y)*.5),Vector3(.024,.105,span.y-span.x))
		var a := Vector3(side*.78,.955,-.60)
		var b := Vector3(side*.646,1.408,-.115)
		var c := Vector3(side*.653,1.403,.57)
		var d := Vector3(side*.80,.955,.61)
		_quad("glass",a,b,c,d)
		var e := Vector3(side*.661,1.397,.665)
		var f := Vector3(side*.661,1.383,.865)
		var g := Vector3(side*.782,.958,1.54)
		var h := Vector3(side*.802,.955,.705)
		_quad("glass",e,f,g,h)
		for line in [[a,b],[b,c],[c,d],[d,a],[e,f],[f,g],[g,h],[h,e]]: _beam("rubber",line[0],line[1],.024)
		_beam("paint#fixed",Vector3(side*.79,.92,-.65),Vector3(side*.646,1.402,-.135),.054)
		_beam("paint#fixed",Vector3(side*.65,1.422,.89),Vector3(side*.80,.92,1.66),.070)
		_beam("paint#fixed",Vector3(side*.651,1.421,-.13),Vector3(side*.655,1.417,.89),.027)
		_quad("paint#fixed",Vector3(side*.64,1.43,-.13),Vector3(side*.65,1.42,.87),Vector3(side*.661,1.383,.865),Vector3(side*.646,1.408,-.115))
		_beam("paint#fixed",Vector3(side*.65,1.409,.631),Vector3(side*.812,.906,.658),.060)
		# One long front door per side, original handles and black mirrors.
		_beam("trim",Vector3(x+.002*side,.32,-.60),Vector3(x+.002*side,.90,-.60),.009)
		_beam("trim",Vector3(x+.002*side,.32,.63),Vector3(x+.002*side,.90,.63),.009)
		_box("rubber",Vector3(side*.833,.845,.49),Vector3(.025,.048,.15))
		_box("trim",Vector3(side*.84,1.002,-.40),Vector3(.11,.025,.06))
		_box("rubber",Vector3(side*.925,1.040,-.395),Vector3(.16,.125,.20))
		_box("glass",Vector3(side*.925,1.043,-.290),Vector3(.125,.085,.008))
	# Front fascia: narrow horizontal grille, outboard amber lenses and rectangular lights.
	_box("paint",Vector3(0,.808,-1.803),Vector3(1.63,.254,.052))
	_box("rubber",Vector3(0,.792,-1.840),Vector3(.82,.212,.020))
	for i in 6: _box("trim",Vector3(0,.708+i*.033,-1.857),Vector3(.80,.012,.012))
	for side in [-1.0,1.0]:
		_box("trim",Vector3(side*.582,.79,-1.836),Vector3(.346,.215,.030))
		_box("headlight",Vector3(side*.576,.794,-1.856),Vector3(.298,.177,.025))
		_box("amber",Vector3(side*.765,.794,-1.840),Vector3(.080,.177,.033))
		for k in 8: _box("alloy",Vector3(side*.576-.132+k*.037,.794,-1.872),Vector3(.003,.159,.003))
		_box("headlight",Vector3(side*.573,.365,-1.887),Vector3(.270,.095,.024))
	_box("trim",Vector3(0,.525,-1.824),Vector3(1.704,.260,.150))
	_box("rubber",Vector3(0,.57,-1.905),Vector3(1.69,.035,.008))
	_box("trim",Vector3(0,.357,-1.810),Vector3(1.57,.123,.15))
	_box("rubber",Vector3(0,.372,-1.890),Vector3(.77,.087,.015))
	for i in 3: _box("trim",Vector3(0,.339+i*.028,-1.902),Vector3(.76,.009,.010))
	# VW monogram drawn as geometry, no oversized text decals.
	_ring_z("alloy",Vector3(0,.798,-1.879),.061,.053)
	for line in [[Vector2(-.033,.033),Vector2(0,-.008)],[Vector2(0,-.008),Vector2(.033,.033)],[Vector2(-.044,.003),Vector2(-.022,-.035)],[Vector2(-.022,-.035),Vector2(0,-.010)],[Vector2(0,-.010),Vector2(.022,-.035)],[Vector2(.022,-.035),Vector2(.044,.003)]]:
		_beam("alloy",Vector3(line[0].x,.798+line[0].y,-1.883),Vector3(line[1].x,.798+line[1].y,-1.883),.007)
	_plate(-1.925)
	# Hatch and rear lamps.
	_quad("paint",Vector3(-.81,.89,1.78),Vector3(.81,.89,1.78),Vector3(.78,.96,1.60),Vector3(-.78,.96,1.60))
	_box("paint",Vector3(0,.733,1.776),Vector3(1.63,.28,.060))
	_box("trim",Vector3(0,.47,1.808),Vector3(1.70,.19,.150))
	for side in [-1.0,1.0]:
		_box("tail",Vector3(side*.640,.758,1.818),Vector3(.31,.17,.025))
		_box("amber",Vector3(side*.734,.80,1.833),Vector3(.11,.073,.015))
		_box("headlight",Vector3(side*.555,.735,1.834),Vector3(.10,.052,.015))
	_plate(1.825)
	# Intercooler do turbo atrás da entrada de ar baixa; escapamento polido e caixa de som visível no tampão.
	_box("alloy",Vector3(0,.37,-1.879),Vector3(.55,.062,.016))
	_box("rubber",Vector3(0,.927,1.18),Vector3(1.12,.07,.35))
	for side in [-1.0,1.0]:
		_cylinder("speaker",Vector3(side*.31,.972,1.18),.135,.015,Vector3.ZERO,24)
		_cylinder("rubber",Vector3(side*.31,.983,1.18),.062,.010,Vector3.ZERO,16)
	_cylinder("alloy",Vector3(-.57,.27,1.81),.039,.22,Vector3(PI*.5,0,0),16)
	_cylinder("rubber",Vector3(-.57,.27,1.925),.029,.008,Vector3(PI*.5,0,0),16)
	# Dois limpadores descansam na borda inferior do para-brisa.
	for side in [-1.0,1.0]: _beam("rubber",Vector3(side*.36,.968,-.626),Vector3(side*.07,1.023,-.565),.012)

func _arch_height(z: float) -> float:
	for center in [-1.22,1.19]:
		var offset := absf(z-center)
		if offset < .335: return .305+sqrt(maxf(0.0,.335*.335-offset*offset))
	return .30

func _wheel(side: float,z: float) -> void:
	var center := Vector3(side*.785,.305,z)
	var suffix := "@%s@%s" % [str(center.x),str(z)]
	_cylinder("rubber"+suffix,center,.300,.195,Vector3(0,0,PI*.5),32)
	_cylinder("alloy"+suffix,center+Vector3(side*.103,0,0),.1905,.017,Vector3(0,0,PI*.5),32)
	_cylinder("rubber"+suffix,center+Vector3(side*.115,0,0),.168,.009,Vector3(0,0,PI*.5),32)
	_cylinder("alloy"+suffix,center+Vector3(side*.127,0,0),.067,.020,Vector3(0,0,PI*.5),20)
	# Seis raios usinados largos, com recortes escuros abertos iguais às rodas de referência.
	for i in 6:
		var angle := TAU*i/6.0
		var p := center+Vector3(side*.124,sin(angle)*.122,cos(angle)*.122)
		_box("alloy"+suffix,p,Vector3(.022,.086,.130),Vector3(-angle,0,0))
	for i in 4:
		var angle := TAU*i/4.0+.5
		_cylinder("trim"+suffix,center+Vector3(side*.142,sin(angle)*.043,cos(angle)*.043),.009,.005,Vector3(0,0,PI*.5),8)

func _plate(z: float) -> void:
	_box("alloy",Vector3(0,.535,z),Vector3(.414,.147,.008))
	_box("plate",Vector3(0,.535,z+signf(z)*.006),Vector3(.401,.135,.007))
	# Small plate numerals in geometry avoid extra font texture/draw calls.
	var digits := [[1,2],[0,1,2,3,5,6],[0,1,2,3,5,6],[0,1,2,3,6]]
	var segments := [[Vector2(-.015,.030),Vector2(.015,.030)],[Vector2(.015,.030),Vector2(.015,0)],[Vector2(.015,0),Vector2(.015,-.030)],[Vector2(-.015,-.030),Vector2(.015,-.030)],[Vector2(-.015,0),Vector2(-.015,-.030)],[Vector2(-.015,.030),Vector2(-.015,0)],[Vector2(-.015,0),Vector2(.015,0)]]
	for i in 4:
		for index in digits[i]:
			var line: Array = segments[index]
			_beam("alloy",Vector3(signf(z)*(-.09+i*.06+line[0].x),.535+line[0].y,z+signf(z)*.012),Vector3(signf(z)*(-.09+i*.06+line[1].x),.535+line[1].y,z+signf(z)*.012),.006)

func _tool(key: String) -> SurfaceTool:
	if not _batches.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = tool
	return _batches[key]

func _box(key: String,point: Vector3,size: Vector3,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_tool(key).append_from(mesh,0,Transform3D(Basis.from_euler(angles),point))

func _cylinder(key: String,point: Vector3,radius: float,height: float,angles: Vector3,segments: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	_tool(key).append_from(mesh,0,Transform3D(Basis.from_euler(angles),point))

func _beam(key: String,a: Vector3,b: Vector3,width: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = width*.5
	mesh.bottom_radius = width*.5
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	var axis := (b-a).normalized()
	var basis := Basis(Quaternion(Vector3.UP,axis))
	_tool(key).append_from(mesh,0,Transform3D(basis,(a+b)*.5))

func _quad(key: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	# As primitivas de append_from já usam índices. Os quads também precisam contribuir
	# com índices próprios; senão triângulos soltos de add_vertex somem do lote.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a,b,c,d])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal,normal,normal,normal])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_tool(key).append_from(mesh,0,Transform3D.IDENTITY)

func _ring_z(key: String,center: Vector3,outer: float,inner: float) -> void:
	for i in 32:
		var a := TAU*i/32.0
		var b := TAU*(i+1)/32.0
		_quad(key,center+Vector3(cos(a)*outer,sin(a)*outer,0),center+Vector3(cos(b)*outer,sin(b)*outer,0),center+Vector3(cos(b)*inner,sin(b)*inner,0),center+Vector3(cos(a)*inner,sin(a)*inner,0))
