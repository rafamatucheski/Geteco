extends RefCounted
## Parada externa, pertencente ao ciclo de vida de chunks existente do deserto e descarregada por ele.
const G := preload("res://world/desert/DesertGeometry.gd")
const M := preload("res://world/desert/DesertTownMaterials.gd")
const POSITION := Vector3(-185,0,-549)

static func build() -> Node3D:
	var stop := Node3D.new()
	stop.name="CobreCoachStop"
	stop.position=POSITION
	# Fundação rente; o pátio dianteiro livre contém a chegada autorada.
	# Só visual: o tampo fica 1,5 cm acima do chão e, sólido, a quina vertical segurava o casco do carro
	# (caixa sem subida de degrau) na beira do ponto (sonda probe_desert_invisible_walls, 27/10). O chão
	# do deserto já apoia carro e jogador aqui.
	_part(stop,"Apron",Vector3(0,-.045,1),Vector3(8,.12,6),"stone",false)
	for x in [-3.25,3.25]:
		for z in [-1.25,1.25]:
			_part(stop,"Post",Vector3(x,1.45,z),Vector3(.14,2.9,.14),"steel")
	_part(stop,"RearScreen",Vector3(0,1.1,-1.4),Vector3(6.5,2.2,.16),"adobe")
	_part(stop,"Roof",Vector3(0,2.98,0),Vector3(7.1,.18,3.35),"roof")
	for x in [-3.5,3.5]:
		_part(stop,"RoofEdge",Vector3(x,3.02,0),Vector3(.10,.24,3.45),"rust")
	_part(stop,"Gutter",Vector3(0,2.99,-1.69),Vector3(7.1,.15,.12),"rust")
	for x in [-1.3,1.3]:
		_part(stop,"BenchLeg",Vector3(x,.22,-.72),Vector3(.15,.44,.60),"steel")
	_part(stop,"BenchSeat",Vector3(0,.49,-.72),Vector3(3.1,.14,.66),"wood")
	_part(stop,"BenchBack",Vector3(0,.9,-1.01),Vector3(3.1,.7,.12),"wood")
	_part(stop,"NameBoard",Vector3(0,2.72,1.7),Vector3(2.9,.47,.10),"steel")
	G.sign_name(stop,"COBRE",Vector3(0,2.73,1.765),38)
	# Sem luzes locais novas nem trabalho por quadro; a iluminação de estrada existente chega até ela.
	M.batch_visuals(stop)
	return stop

static func _part(parent: Node3D, label: String, point: Vector3, size: Vector3, material: String, solid := true) -> void:
	var mesh := G.box(parent,label,point,size,Color.WHITE,solid)
	mesh.material_override=M.material(material)
