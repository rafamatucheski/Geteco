extends RefCounted
## Reaproveita o chassi nativo da van, acrescentando os acessórios fixos do transporte tático.
##
## Playtest 29/10: letreiro e faixa "voando" ~18 cm fora da lataria. Eles estavam em x = ±1,166/1,18,
## medidos na van antiga; a frota redesenhada (tools/fleet_fixups/build_service_batch.gd, tactical())
## fecha a lateral em ±0,978 (chapa), ±0,981 (portinholas) e ±1,012 (parafusos). A faixa encosta na
## chapa e o letreiro fica logo à frente dos parafusos.
const STRIPE_X := .99
const MARK_X := 1.035
static func decorate(root: Node3D) -> void:
	_box(root,"LightbarBase",Vector3(0,2.25,-.8),Vector3(1.4,.09,.24),Color("171c23"))
	_box(root,"LightbarRed",Vector3(-.4,2.36,-.8),Vector3(.55,.15,.21),Color("e83c42"),"bar_left")
	_box(root,"LightbarBlue",Vector3(.4,2.36,-.8),Vector3(.55,.15,.21),Color("3689ef"),"bar_right")
	for side in [-1,1]:
		_box(root,"TacticalStripe",Vector3(side*STRIPE_X,1.05,.45),Vector3(.018,.12,3.1),Color("b8c4ce"))
		var label := Label3D.new()
		label.name = "PoliceTransportMark"
		label.set_meta("hide_when_wrecked", true)
		label.text = "POLÍCIA"
		label.font_size = 48
		label.pixel_size = .008
		label.outline_size = 0
		label.position = Vector3(side*MARK_X,1.52,.55)
		label.rotation.y = side*PI*.5
		root.add_child(label)
	# Proteção da janela dianteira, acima da linha de visão do motorista e longe das rodas.
	for x in [-.62,0,.62]:
		_box(root,"WindshieldGuard",Vector3(x,1.72,-1.66),Vector3(.025,.55,.035),Color("333b43"))

## O modelo assado (assets/fleet/redesigned/police_transport.scn) guardou o letreiro em ±1,18. Corrige
## na criação, sem refazer o bake: só dois Label3D por van. A faixa clara foi fundida na malha assada e
## só volta para a chapa refazendo o bake com o decorate() acima.
static func fit_marks(root: Node3D) -> void:
	for label in root.find_children("PoliceTransportMark*", "Label3D", true, false):
		var mark := label as Label3D
		mark.position.x = signf(mark.position.x) * MARK_X

static func _box(root: Node3D, id: String, point: Vector3, size: Vector3, color: Color, key := "") -> void:
	var part := MeshInstance3D.new()
	part.name = id
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .45
	if not key.is_empty():
		part.set_meta("vehicle_material_key",key)
		mat.emission_enabled = true
		mat.emission = color
	part.material_override = mat
	part.position = point
	root.add_child(part, true)
