extends RefCounted
## Acabamento do salão; coordenadas em metros, compartilhadas com a planta física.
const PART = preload("res://world/shared/pedestrians/CitizenDetails.gd")
const INK = Color("263f43")
const BRASS = Color("b7975d")

static func build(model: Node3D) -> void:
	var decor := Node3D.new()
	decor.name = "LobbyDetails"
	model.add_child(decor)
	# Passadeira central conduz do acesso ao cofre sem obstruir circulação.
	PART.piece(decor,Vector3(2.5,.018,4.4),Vector3(0,.032,1.5),INK)
	for x in [-1.20,1.20]: PART.piece(decor,Vector3(.025,.008,4.3),Vector3(x,.044,1.5),BRASS)
	var seal := _label(decor,"NP",Vector3(0,.058,1.7),110,.009,BRASS)
	seal.rotation_degrees.x=-90
	var welcome := _label(decor,"NORTH PIER",Vector3(0,.058,2.5),48,.009,Color("d6c5a4"))
	welcome.rotation_degrees.x=-90
	# Identidade e orientação colocadas na própria arquitetura.
	var signs := Node3D.new()
	signs.name="VaultFrontSigns"
	decor.add_child(signs)
	for x in [-4.05,4.05]:
		PART.piece(signs,Vector3(3.6,.63,.05),Vector3(x,2.03,-3.055),INK)
		_label(signs,"NORTH PIER" if x<0 else "ATENDIMENTO",Vector3(x,2.05,-3.01),42,.008,Color("eadcbf"))
	for x in [-4.5,4.5]:
		PART.piece(decor,Vector3(.5,.012,.34),Vector3(x+.8,1.192,-.85),Color("e1dbc9"))
		PART.piece(decor,Vector3(.33,.025,.25),Vector3(x-.85,1.20,-.78),INK)
		PART.piece(decor,Vector3(.035,.23,.035),Vector3(x-.85,1.32,-.78),BRASS)
	# Caixas eletrônicos e floreiras ficam nas laterais, fora do percurso central.
	for x in [-6.3,6.3]:
		var atm := Node3D.new()
		atm.position=Vector3(x,0,.8)
		decor.add_child(atm)
		PART.piece(atm,Vector3(.68,1.45,.9),Vector3(0,.73,0),INK)
		PART.piece(atm,Vector3(.49,.36,.035),Vector3(0,1.1,.465),Color("72a6a1"))
		PART.piece(atm,Vector3(.4,.1,.025),Vector3(0,.56,.465),Color("16282d"))
		PART.piece(atm,Vector3(.42,.055,.25),Vector3(0,.81,.51),BRASS)
		_label(atm,"24h",Vector3(0,1.64,.2),32,.007,INK)
		_plant(decor,Vector3(x,0,4.1))
	# Soleira legível alinhada exatamente ao gatilho da saída automática.
	PART.piece(decor,Vector3(2.2,.025,.95),Vector3(0,.033,4.3),INK)
	for x in [-1.15,1.15]: PART.piece(decor,Vector3(.09,.62,.16),Vector3(x,.31,4.65),BRASS)
	var exit_sign := _label(decor,"SAÍDA  ↓",Vector3(0,.058,4.3),52,.009,Color("e8e4cd"))
	exit_sign.rotation_degrees.x=-90

static func _label(parent: Node3D, text: String, point: Vector3, size: int, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text=text
	label.position=point
	label.font_size=size
	label.pixel_size=pixel
	label.modulate=color
	label.outline_size=0
	parent.add_child(label)
	return label

static func _plant(parent: Node3D, point: Vector3) -> void:
	PART.piece(parent,Vector3(.58,.48,.58),point+Vector3(0,.24,0),Color("8f7860"))
	PART.piece(parent,Vector3(.45,.02,.45),point+Vector3(0,.49,0),Color("343b30"))
	PART.piece(parent,Vector3(.06,.65,.06),point+Vector3(0,.78,0),Color("66543c"))
	for i in 7:
		var a := i*TAU/7
		var leaf := PART.piece(parent,Vector3(.36,.5,.32),point+Vector3(cos(a)*.22,1.0+(i%2)*.2,sin(a)*.22),Color("526b51") if i%2 else Color("718064"),true)
		leaf.rotation.z=cos(a)*.6
