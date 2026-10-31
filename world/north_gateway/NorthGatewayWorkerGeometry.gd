extends RefCounted
## Roupas de trabalho e ferramentas em cache reaproveitam o shader e o kit de malhas civis existentes.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
static var _cache: Dictionary = {}

static func mesh(kind: String, female := false) -> ArrayMesh:
	var key := kind+("_female" if female else "_male")
	if _cache.has(key): return _cache[key]
	var builder = KIT._builder()
	match kind:
		"helmet": _helmet(builder)
		"vest": _vest(builder,female)
		"breaker": _breaker(builder)
		"hammer": _hammer(builder)
		"clipboard": _clipboard(builder)
		"pencil": _pencil(builder)
		"wrench": _wrench(builder)
		"bench": _bench(builder,false)
		"brace": _bench(builder,true)
	_cache[key] = builder.commit()
	return _cache[key]

static func add(parent: Node3D, kind: String, point := Vector3.ZERO, female := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = kind.capitalize()
	part.mesh = mesh(kind,female)
	part.position = point
	part.set_instance_shader_parameter("accent_color",Color("e8872e"))
	part.set_instance_shader_parameter("top_color",Color("dcb746"))
	part.set_instance_shader_parameter("inner_color",Color("f3cf48"))
	part.set_instance_shader_parameter("bottom_color",Color("866540"))
	part.set_instance_shader_parameter("shoe_color",Color("282e32"))
	parent.add_child(part)
	return part

static func _box(b, center: Vector3, size: Vector3, slot: int, basis := Basis.IDENTITY) -> void:
	# Cantos arredondados, uma superfície compartilhada em vez de um nó para cada peça pequena.
	b.loft([[size.y*.5,size.x*.5,size.z*.5,slot,0,20.0],[-size.y*.5,size.x*.5,size.z*.5,slot,0,20.0]],
		slot,Transform3D(basis,center),8)

static func _rod(b, center: Vector3, radius: float, length: float, slot: int, basis := Basis.IDENTITY) -> void:
	b.loft([[length*.5,radius,radius,slot],[-length*.5,radius,radius,slot]],slot,Transform3D(basis,center),10)

static func _helmet(b) -> void:
	# Coordenadas neutras de espaço do modelo; ancoradas na junta existente da cabeça.
	b.ellipsoid(Vector3(0,1.776,-.012),Vector3(.137,.095,.152),KIT.SLOT_INNER,Basis.IDENTITY,16,8)
	b.ellipsoid(Vector3(0,1.719,.008),Vector3(.171,.012,.189),KIT.SLOT_INNER,Basis.IDENTITY,16,4)
	_box(b,Vector3(0,1.863,-.014),Vector3(.023,.012,.21),KIT.SLOT_INNER)
	for side in [-1.0,1.0]:
		_box(b,Vector3(side*.135,1.773,-.035),Vector3(.008,.018,.055),KIT.SLOT_LENS)
		_box(b,Vector3(side*.08,1.741,.135),Vector3(.055,.022,.007),KIT.SLOT_SOLE)

static func _vest(b, female: bool) -> void:
	var profile := KIT.build_profile(female,1)
	var waist: Vector2 = profile.waist+Vector2(.024,.023)
	var chest: Vector2 = profile.chest+Vector2(.021,.052 if female else .027)
	# Local à coluna: barra ajustada, faixa refletiva na cintura e painéis do peito.
	b.loft([[-.115,waist.x,waist.y,KIT.SLOT_ACCENT,0,2.6],
		[.005,waist.x,waist.y,KIT.SLOT_SOLE,0,2.6],
		[.050,waist.x+.004,waist.y+.005,KIT.SLOT_ACCENT,0,2.6],
		[.18,chest.x,chest.y,KIT.SLOT_ACCENT,0,2.7],
		[.31,profile.shoulder-.015,chest.y-.012,KIT.SLOT_ACCENT,0,2.5]],
		KIT.SLOT_ACCENT,Transform3D.IDENTITY,14,false,false)
	for side in [-1.0,1.0]:
		for front in [-1.0,1.0]:
			_box(b,Vector3(side*.078,.19,front*(chest.y+.004)),Vector3(.034,.23,.008),KIT.SLOT_SOLE)
		_box(b,Vector3(side*.104,-.03,waist.y+.009),Vector3(.076,.075,.013),KIT.SLOT_ACCENT)
	_box(b,Vector3(0,.17,chest.y+.006),Vector3(.009,.28,.008),KIT.SLOT_LENS)

static func _breaker(b) -> void:
	_box(b,Vector3(0,.13,0),Vector3(.19,.44,.18),KIT.SLOT_TOP)
	_box(b,Vector3(0,.36,0),Vector3(.24,.11,.19),KIT.SLOT_LENS)
	_rod(b,Vector3(0,-.26,0),.023,.58,KIT.SLOT_METAL)
	_box(b,Vector3(0,-.55,0),Vector3(.038,.05,.026),KIT.SLOT_METAL)
	_rod(b,Vector3(0,.53,0),.023,.35,KIT.SLOT_METAL,Basis(Vector3.FORWARD,PI*.5))
	for side in [-1.0,1.0]:
		_rod(b,Vector3(side*.148,.53,0),.033,.085,KIT.SLOT_LENS,Basis(Vector3.FORWARD,PI*.5))
		_rod(b,Vector3(side*.088,.44,0),.022,.16,KIT.SLOT_METAL)
	for index in 4:
		_box(b,Vector3(.096,.03+float(index)*.065,.025),Vector3(.005,.024,.10),KIT.SLOT_LENS)

static func _hammer(b) -> void:
	_rod(b,Vector3(0,0,.12),.019,.28,KIT.SLOT_BOTTOM,Basis(Vector3.RIGHT,PI*.5))
	_rod(b,Vector3(0,0,.027),.024,.10,KIT.SLOT_LENS,Basis(Vector3.RIGHT,PI*.5))
	_box(b,Vector3(0,0,.30),Vector3(.19,.105,.09),KIT.SLOT_METAL)
	_box(b,Vector3(-.106,0,.30),Vector3(.028,.09,.08),KIT.SLOT_LENS)

static func _clipboard(b) -> void:
	_box(b,Vector3.ZERO,Vector3(.33,.018,.40),KIT.SLOT_BOTTOM)
	_box(b,Vector3(0,.012,0),Vector3(.28,.005,.345),KIT.SLOT_SOLE)
	_box(b,Vector3(0,.020,-.15),Vector3(.11,.015,.04),KIT.SLOT_METAL)
	# Drawn plan: strokes only, no decorative explanatory labels.
	for x in [-.072,.075]: _box(b,Vector3(x,.016,.025),Vector3(.003,.002,.22),KIT.SLOT_LENS)
	for z in [-.08,.005,.11]: _box(b,Vector3(0,.016,z),Vector3(.15,.002,.003),KIT.SLOT_LENS)

static func _pencil(b) -> void:
	_rod(b,Vector3(0,.055,0),.007,.12,KIT.SLOT_TOP,Basis(Vector3.RIGHT,-.34))
	_rod(b,Vector3(0,0,.02),.004,.025,KIT.SLOT_LENS)

static func _wrench(b) -> void:
	_box(b,Vector3(0,0,-.14),Vector3(.037,.024,.28),KIT.SLOT_METAL)
	_box(b,Vector3(0,0,-.225),Vector3(.045,.031,.11),KIT.SLOT_LENS)
	for side in [-1.0,1.0]:
		_box(b,Vector3(side*.056,0,.012),Vector3(.032,.038,.095),KIT.SLOT_METAL)
	_box(b,Vector3(0,0,-.025),Vector3(.09,.038,.035),KIT.SLOT_METAL)

static func _bench(b, tall: bool) -> void:
	var height := .95 if tall else .72
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			_box(b,Vector3(side*.24,height*.5,.6+end*.14),Vector3(.045,height,.045),KIT.SLOT_BOTTOM)
		_box(b,Vector3(side*.24,height*.37,.6),Vector3(.047,.05,.36),KIT.SLOT_BOTTOM)
	_box(b,Vector3(0,height,.6),Vector3(.64,.065,.40),KIT.SLOT_BOTTOM)
	if tall:
		_box(b,Vector3(0,height+.065,.6),Vector3(.43,.075,.12),KIT.SLOT_METAL)
		_rod(b,Vector3(0,1.055,.60),.039,.065,KIT.SLOT_LENS)
	else:
		_box(b,Vector3(0,.795,.59),Vector3(.36,.085,.20),KIT.SLOT_METAL)
