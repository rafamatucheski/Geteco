extends RefCounted
## Snowmobile próprio (bike_snow). Antes era a moto urbana antiga com caixas coladas por cima: escapamento e
## amortecedor atravessavam a esteira, o farol furava a carenagem, sobrava a placa e nenhuma peça tinha o
## papel "paint", então a pintura (catálogo e garagem) não pegava em nada.
## Mantém o contrato da moto que o Vehicle usa: banco do piloto em `motorcycle_seat`, manoplas com
## `motorcycle_grip` e peças de direção com `wheel_center` + `wheel_spins = false` (guidão e esquis esterçam).
## Duas rodas escondidas dão o eixo do empinar e o assentamento no chão (`_seat_wheels_on_ground`).
## Só materiais padrão (cor, rugosidade, metal; a lente com emissão como as dos carros): nenhuma variante
## de shader nova para compilar no jogo.
const SEAT := Vector3(0, -.05, .30)
const STEER_AXLE := Vector3(0, .98, -.305)
const SKI_X := .52
const SKI_Z := -.72

static func create() -> Node3D:
	var model := Node3D.new()
	model.name = "Snowmobile"
	model.set_meta("motorcycle_seat", SEAT)
	var paint := _material("c33c30", .38, .25, "paint")
	var rubber := _material("1d2024", .92)
	var plastic := _material("2a2e34", .7)
	var metal := _material("6d777e", .45, .7)
	var seat := _material("17191d", .85)
	var screen := _material("2c3f4f", .12, .35)
	var vinyl_light := _material("efeee2", .45)
	var vinyl_dark := _material("131e27", .45)
	var grip := _material("161b20", .8)
	var lens := _material("f5f6fa", .1)
	lens.emission_enabled = true
	lens.emission = Color("fff4d6")
	lens.emission_energy_multiplier = .6
	var tail := _material("e74c3c", .1)
	tail.emission_enabled = true
	tail.emission = Color("e74c3c")
	tail.emission_energy_multiplier = .65
	# Esteira, rodas-guia e a aba de neve atrás.
	_box(model, "Track", Vector3(0, .2, .48), Vector3(.46, .34, 1.32), rubber)
	for z: float in [-.16, 1.12]:
		_cylinder(model, "TrackIdler%d" % int(z > 0.0), Vector3(0, .17, z), .17, .48, metal)
	for row in 12:
		_box(model, "TrackLug%d" % row, Vector3(0, .012, -.06 + row * .105), Vector3(.48, .024, .05), rubber)
	_box(model, "SnowFlap", Vector3(0, .17, 1.27), Vector3(.44, .22, .015), rubber)
	# Túnel pintado sobre a esteira, estribos dos pés e banco.
	_box(model, "Tunnel", Vector3(0, .43, .6), Vector3(.5, .08, 1.22), paint)
	for side: float in [-1.0, 1.0]:
		# Nome por lado: nome repetido vira "@MeshInstance3D@n" no Godot e some das buscas por nome.
		var tag := "Left" if side < 0.0 else "Right"
		_box(model, "TunnelSkirt" + tag, Vector3(side * .245, .32, .6), Vector3(.03, .2, 1.22), paint)
		_box(model, "RunningBoard" + tag, Vector3(side * .37, .30, .2), Vector3(.22, .03, .8), metal)
		_box(model, "BoardEdge" + tag, Vector3(side * .485, .32, .2), Vector3(.025, .06, .8), plastic)
	_box(model, "SeatBase", Vector3(0, .56, .5), Vector3(.44, .16, .9), plastic)
	_box(model, "Seat", Vector3(0, .71, .48), Vector3(.40, .15, .82), seat)
	_box(model, "GrabBar", Vector3(0, .63, 1.04), Vector3(.48, .04, .04), metal)
	_box(model, "TailLight", Vector3(0, .5, 1.215), Vector3(.28, .07, .03), tail).set_meta("material_key", "tail")
	# Carenagem pintada: panela, nariz inclinado e capô subindo até o para-brisa.
	_box(model, "BellyPan", Vector3(0, .2, -.6), Vector3(.9, .14, .78), plastic)
	_box(model, "Hood", Vector3(0, .42, -.6), Vector3(.92, .3, .74), paint)
	var nose := _box(model, "Nose", Vector3(0, .33, -1.02), Vector3(.84, .24, .3), paint)
	# Negativo: o topo sobe da ponta até o capô.
	nose.rotation.x = -.45
	var deck := _box(model, "HoodDeck", Vector3(0, .62, -.52), Vector3(.8, .12, .56), paint)
	deck.rotation.x = -.28
	_box(model, "Dash", Vector3(0, .74, -.2), Vector3(.42, .12, .26), plastic)
	var windscreen := _box(model, "Windscreen", Vector3(0, .84, -.47), Vector3(.62, .26, .02), screen)
	# Inclinado para trás, mas à frente das manoplas: as mãos do piloto não atravessam o vidro.
	windscreen.rotation.x = .4
	windscreen.set_meta("material_key", "windscreen")
	for side: float in [-1.0, 1.0]:
		var tag := "Left" if side < 0.0 else "Right"
		# Faróis no topo inclinado do nariz, virados para frente e para cima como a peça.
		var light := _box(nose, "Headlight" + tag, Vector3(side * .2, .125, -.02), Vector3(.22, .02, .09), lens)
		light.set_meta("material_key", "headlight")
		# Adesivo de corrida: faixas duplas sobre o capô e placa de número nas laterais. Material próprio,
		# fora do papel "paint", então a repintura não cobre o desenho.
		var stripe := _box(deck, "RaceStripe" + tag, Vector3(side * .12, .061, 0), Vector3(.08, .004, .56), vinyl_light)
		stripe.set_meta("material_key", "race_livery")
		_box(deck, "RacePinstripe" + tag, Vector3(side * .175, .061, 0), Vector3(.018, .004, .56), vinyl_dark).set_meta("material_key", "race_livery")
		_box(model, "RaceNumberBoard" + tag, Vector3(side * .462, .44, -.6), Vector3(.004, .17, .32), vinyl_light).set_meta("material_key", "race_livery")
		_box(model, "RaceNumberBar" + tag, Vector3(side * .465, .44, -.6), Vector3(.004, .045, .24), vinyl_dark).set_meta("material_key", "race_livery")
		_box(model, "RaceTunnelStripe" + tag, Vector3(side * .261, .36, .62), Vector3(.004, .035, 1.1), vinyl_light).set_meta("material_key", "race_livery")
		# Braço da suspensão (fixo) e esqui com montante (esterçam no eixo do próprio esqui).
		_box(model, "SkiArm" + tag, Vector3(side * .41, .3, SKI_Z), Vector3(.24, .035, .05), metal)
		var axle := Vector3(side * SKI_X, .3, SKI_Z)
		_steer(_box(model, "Ski" + tag, Vector3(side * SKI_X, .03, SKI_Z), Vector3(.14, .05, .95), rubber), axle)
		var tip := _box(model, "SkiTip" + tag, Vector3(side * SKI_X, .085, SKI_Z - .55), Vector3(.14, .05, .2), rubber)
		tip.rotation.x = .6
		_steer(tip, axle)
		_steer(_box(model, "SkiSpindle" + tag, Vector3(side * SKI_X, .2, SKI_Z), Vector3(.05, .3, .06), metal), axle)
		var hand := _box(model, "Grip" + tag, Vector3(side * .32, STEER_AXLE.y, STEER_AXLE.z), Vector3(.1, .045, .045), grip)
		hand.set_meta("motorcycle_grip", "Left" if side < 0.0 else "Right")
		_steer(hand, STEER_AXLE)
	_steer(_box(model, "SteeringPost", Vector3(0, .87, STEER_AXLE.z), Vector3(.06, .22, .06), metal), STEER_AXLE)
	_steer(_box(model, "Handlebar", STEER_AXLE, Vector3(.56, .035, .035), metal), STEER_AXLE)
	# Rodas escondidas: eixo traseiro do empinar e contato com o chão; a esteira não gira.
	for z: float in [SKI_Z, .9]:
		# Largura = diâmetro: o assentamento lê o AABB sem a rotação, e assim a base fica no chão.
		var proxy := _cylinder(model, "ContactProxy%d" % int(z > 0.0), Vector3(0, .17, z), .17, .34, rubber)
		proxy.visible = false
		proxy.set_meta("wheel_center", Vector3(0, .17, z))
	return model

static func _steer(part: MeshInstance3D, axle: Vector3) -> void:
	part.set_meta("wheel_center", axle)
	part.set_meta("wheel_spins", false)

static func _material(color: String, roughness: float, metallic := 0.0, role := "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	if not role.is_empty(): material.resource_name = role
	return material

static func _box(parent: Node3D, label: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(parent, label, point, mesh, material)

static func _cylinder(parent: Node3D, label: String, point: Vector3, radius: float, width: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 12
	var part := _part(parent, label, point, mesh, material)
	part.rotation.z = PI * .5
	return part

static func _part(parent: Node3D, label: String, point: Vector3, mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = point
	parent.add_child(part)
	return part
