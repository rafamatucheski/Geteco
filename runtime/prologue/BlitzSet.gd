extends RefCounted
## Montagem do cenário da blitz (pista, beira da rodovia, viatura, caminhão, elenco, colegas, prisão, quarto,
## trânsito, som), o fim do aquecimento e as peças vivas (giroflex, chuva, motor, mãos, rosto e frente dos
## bonecos, porta e freio do caminhão), separados da BlitzScene em 01/11 só para ela caber na leitura.
## O estado continua na BlitzScene: testes e a captura leem `truck`, `dante`, `_prison`, `_set`... lá, e
## cada função antiga ficou lá como delegação de uma linha (quem chama por nome não muda).
## `g` fica sem preload do dono (evita preload cíclico) e sem tipo: o dono tem `var _set`, que num tipo
## nativo o analisador confundiria com o virtual Object._set. Chamadas entre funções passam por `g.`.
## `_material`, `_light_truck` e `_build_rain` ficaram no dono: mexem nas variáveis estáticas dele
## (materiais retidos entre o prólogo e o flashback).
const BANK := preload("res://audio/FireflyBank.gd")
const BROTHER := preload("res://runtime/prologue/BlitzBrother.gd")
const COBRA_MODEL := preload("res://gameplay/CobraModel.gd")
const COLLEAGUE := preload("res://runtime/prologue/BlitzColleague.gd")
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")
const OPEN_TRUCK := preload("res://runtime/prologue/BlitzTruck.gd")
const POLICE_MODEL := preload("res://gameplay/PoliceModel.gd")
const TRUCK := preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd")

var g

func _init(host: CanvasLayer) -> void:
	g = host

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Fundo e névoa na mesma cor: o fim da estrada some na noite, sem borda.
	environment.background_color = Color("0b1220")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("6f86a3")
	environment.ambient_light_energy = .45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("0b1220")
	environment.fog_density = .03
	# A câmera do jogo fica a ~36 m do foco: a névoa começa depois disso e apaga o fim da estrada.
	environment.fog_depth_begin = 32.0
	environment.fog_depth_end = 150.0
	environment.glow_enabled = true
	environment.glow_intensity = .7
	environment.glow_bloom = .05
	g._environment = environment
	var world := WorldEnvironment.new()
	world.environment = environment
	g._set.add_child(world)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("8fa7c6")
	moon.light_energy = .32
	moon.rotation_degrees = Vector3(-52, 28, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 45.0
	g._set.add_child(moon)
	g.camera = Camera3D.new()
	g.camera.fov = 55.0
	g.camera.near = .05
	g.camera.far = 260.0
	g._set.add_child(g.camera)
	g.camera.current = true

func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = center
	parent.add_child(node)
	return node

func _strip(parent: Node3D, mesh_size: Vector3, material: Material, transforms: Array[Transform3D]) -> void:
	# Faixas, tachões e balizas repetidos: uma chamada de desenho por tipo.
	var mesh := BoxMesh.new()
	mesh.size = mesh_size
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func _build_road() -> void:
	# Molhado, mas não espelho: com rugosidade .16 cada farol virava um pilar branco no asfalto.
	var wet: StandardMaterial3D = g._material("blitz_wet_asphalt", Color("202327"), .32, .5)
	g._box(g._set, Vector3(0, -.03, -60), Vector3(11.8, .06, 1100), wet)
	# De cima a câmera vê mais mato que pista: verde-escuro com valor, não preto.
	var verge: StandardMaterial3D = g._material("blitz_verge", Color("26301f"), .92, .2)
	for side in [-1, 1]:
		g._box(g._set, Vector3(side * 160.0, -.09, -60), Vector3(308, .06, 1100), verge)
	var white: StandardMaterial3D = g._material("blitz_paint_white", Color("c9ccc8"), .35, .5)
	var yellow: StandardMaterial3D = g._material("blitz_paint_yellow", Color("c7a33a"), .35, .5)
	var dashes: Array[Transform3D] = []
	for index in 140: dashes.append(Transform3D(Basis.IDENTITY, Vector3(0, .004, 480.0 - index * 8.0)))
	g._strip(g._set, Vector3(.14, .01, 4.0), yellow, dashes)
	var edges: Array[Transform3D] = []
	for side in [-1, 1]: edges.append(Transform3D(Basis.IDENTITY, Vector3(side * 3.6, .004, -60)))
	g._strip(g._set, Vector3(.16, .01, 1100), white, edges)
	# Balizas refletivas na beira: dão leitura de velocidade no escuro.
	var posts: Array[Transform3D] = []
	for index in 56:
		for side in [-1, 1]: posts.append(Transform3D(Basis.IDENTITY, Vector3(side * 6.4, .45, 480.0 - index * 20.0)))
	g._strip(g._set, Vector3(.1, .9, .1), g._material("blitz_post", Color("d8dad6"), .4, .5), posts)
	var reflectors: Array[Transform3D] = []
	for transform in posts: reflectors.append(transform.translated(Vector3(0, .32, 0)))
	g._strip(g._set, Vector3(.11, .12, .11), g._material("blitz_reflector", Color("e0a43a"), .3, .5, Color("b97a22")), reflectors)
	# Cavaletes estreitando a faixa: listras vermelhas e brancas, sem cone de perto.
	var red: StandardMaterial3D = g._material("blitz_barrier_red", Color("a3221d"), .5, .4)
	for spot in [Vector3(2.4, 0, -13.2), Vector3(4.4, 0, -11.6), Vector3(1.3, 0, -14.6)]:
		var barrier := Node3D.new()
		barrier.position = spot
		barrier.rotation.y = .35
		g._set.add_child(barrier)
		for stripe in 4:
			g._box(barrier, Vector3(-.6 + stripe * .4, .92, 0), Vector3(.4, .22, .05), red if stripe % 2 == 0 else white)
		for leg in [-1, 1]:
			g._box(barrier, Vector3(leg * .7, .45, 0), Vector3(.06, .9, .45), white)

## Mesma malha repetida (árvores, guarda-corpo): uma chamada de desenho por tipo, escala por instância.
func _instances(mesh: PrimitiveMesh, material: Material, transforms: Array[Transform3D], shadows := false) -> void:
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._set.add_child(node)

## Beira da rodovia: de cima, sem isto a pista era uma faixa num vazio preto. Mato alto e árvores dos dois
## lados (sorteio fixo) e guarda-corpo metálico com postes.
func _build_roadside() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var crowns: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	for index in 170:
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(9.5, 36.0)
		var z := rng.randf_range(-180.0, 180.0)
		var size := rng.randf_range(2.4, 5.0)
		crowns.append(Transform3D(Basis.from_scale(Vector3(size, size * rng.randf_range(.8, 1.15), size)), Vector3(x, 1.5 + size * .45, z)))
		trunks.append(Transform3D(Basis.from_scale(Vector3(.22, 1.9, .22)), Vector3(x, .95, z)))
	for index in 260:
		var side := -1.0 if index % 2 == 0 else 1.0
		var size := rng.randf_range(.6, 1.5)
		bushes.append(Transform3D(Basis.from_scale(Vector3(size * 1.4, size * .7, size * 1.2)), Vector3(side * rng.randf_range(7.4, 40.0), size * .25, rng.randf_range(-180.0, 180.0))))
	var crown := SphereMesh.new()
	crown.radius = .5
	crown.height = 1.0
	crown.radial_segments = 10
	crown.rings = 6
	g._instances(crown, g._material("blitz_tree", Color("1f2b1b"), .95, .15), crowns, true)
	g._instances(BoxMesh.new(), g._material("blitz_trunk", Color("2b231b"), .95, .1), trunks)
	var bush := SphereMesh.new()
	bush.radius = .5
	bush.height = 1.0
	bush.radial_segments = 8
	bush.rings = 4
	g._instances(bush, g._material("blitz_bush", Color("29331f"), .95, .1), bushes)
	var rails: Array[Transform3D] = []
	var rail_posts: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		rails.append(Transform3D(Basis.from_scale(Vector3(.06, .3, 360.0)), Vector3(side * 6.95, .62, 0)))
		for index in 90: rail_posts.append(Transform3D(Basis.from_scale(Vector3(.1, .7, .1)), Vector3(side * 7.02, .35, -178.0 + index * 4.0)))
	var steel: StandardMaterial3D = g._material("blitz_rail", Color("7d8287"), .45, .6)
	g._instances(BoxMesh.new(), steel, rails)
	g._instances(BoxMesh.new(), steel, rail_posts)

func _build_police() -> void:
	g.police = FLEET.create("police_cruiser")
	if g.police == null: g.police = Node3D.new()
	g.police.process_mode = Node.PROCESS_MODE_DISABLED
	g.police.position = g.POLICE_SPOT
	g.police.rotation.y = .22
	g._set.add_child(g.police)
	var spec := FLEET.spec("police_cruiser")
	var roof := float(spec.get("bounds_size", [0, 1.55, 0])[1]) + .05
	var side := -1.0
	for color in [Color(1, .12, .1), Color(.15, .35, 1)]:
		var glow := Sprite3D.new()
		glow.name = "BlitzBeaconGlow"
		glow.texture = EQUIPMENT._lens_glow_texture()
		glow.pixel_size = .6 / 64.0
		glow.modulate = color
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Em cima das lentes da barra (medidas na malha da viatura), não flutuando sobre ela.
		glow.position = Vector3(side * .29, roof - .06, .05)
		g.police.add_child(glow)
		g._glows.append(glow)
		side = -side
	g.halo = OmniLight3D.new()
	g.halo.name = "BlitzBeaconHalo"
	g.halo.omni_range = 9.0
	g.halo.omni_attenuation = 1.8
	# No asfalto molhado o reflexo do giroflex virava uma faixa vermelha no chão.
	g.halo.light_specular = 0.0
	g.halo.shadow_enabled = false
	g.halo.position = Vector3(0, roof + .3, 0)
	g.halo.set_meta("budget_energy", 2.6)
	g._beacon_lenses()
	g.halo.light_energy = 2.6
	g.police.add_child(g.halo)

func _build_truck() -> void:
	g.truck = OPEN_TRUCK.create_open()
	g._set.add_child(g.truck)
	# A cabine original é uma peça só: esta porta (chapa e vidro) é a que abre.
	g.truck_door = Node3D.new()
	g.truck_door.name = "BlitzCabDoor"
	g.truck_door.position = Vector3(-1.16, 2.0, -3.96)
	g.truck.add_child(g.truck_door)
	# A chapa desce até o estribo: fechada, cobre o vão inteiro da cabine aberta (BlitzTruck).
	g._box(g.truck_door, Vector3(0, -.52, .56), Vector3(.05, 1.08, 1.1), g._material("blitz_truck_paint", g.TRUCK_PAINT, .45, .5))
	g._box(g.truck_door, Vector3(0, .5, .56), Vector3(.03, .72, 1.02), g._material("blitz_truck_glass", Color(.32, .4, .45, .35), .05, .9))
	g._box(g.truck_door, Vector3(-.04, -.1, .95), Vector3(.05, .05, .18), g._material("blitz_truck_handle", Color("9a9c9e"), .3, .7))
	# A do passageiro, espelhada: abre para fora do lado direito.
	g.passenger_door = Node3D.new()
	g.passenger_door.name = "BlitzPassengerDoor"
	g.passenger_door.position = Vector3(1.16, 2.0, -3.96)
	g.truck.add_child(g.passenger_door)
	g._box(g.passenger_door, Vector3(0, -.52, .56), Vector3(.05, 1.08, 1.1), g._material("blitz_truck_paint", g.TRUCK_PAINT, .45, .5))
	g._box(g.passenger_door, Vector3(0, .5, .56), Vector3(.03, .72, 1.02), g._material("blitz_truck_glass", Color(.32, .4, .45, .35), .05, .9))
	g._box(g.passenger_door, Vector3(.04, -.1, .95), Vector3(.05, .05, .18), g._material("blitz_truck_handle", Color("9a9c9e"), .3, .7))
	g._light_truck()
	var cardboard: StandardMaterial3D = g._material("blitz_cardboard", Color("b08a5c"), .9, .2)
	for part in g.truck.find_children("Freight_case", "MeshInstance3D", true, false): (part as MeshInstance3D).material_override = cardboard
	TRUCK.set_loot_visible(g.truck, false)
	var wheel := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .16
	ring.outer_radius = .2
	ring.rings = 24
	ring.ring_segments = 8
	wheel.mesh = ring
	wheel.material_override = g._material("blitz_wheel", Color("1b1c1e"), .5, .4)
	wheel.position = Vector3(-.55, 2.02, -3.75)
	# Aro inclinado para o motorista, como volante de caminhão.
	wheel.rotation = Vector3(-1.05, 0, 0)
	g.truck.add_child(wheel)
	g.cab_light = OmniLight3D.new()
	g.cab_light.name = "BlitzCabLight"
	g.cab_light.position = Vector3(0, 2.85, -3.25)
	g.cab_light.light_color = Color("ffd7a6")
	g.cab_light.omni_range = 2.6
	g.cab_light.omni_attenuation = 1.2
	g.cab_light.shadow_enabled = false
	g.cab_light.set_meta("budget_energy", 0.0)
	g.cab_light.light_energy = 0.0
	g.truck.add_child(g.cab_light)
	# O irmão: o mesmo dante.glb, com a roupa, o cabelo e os acessórios dele (BlitzBrother), ao volante.
	g.vicente = BROTHER.new()
	g.vicente.identity_id = "vicente"
	g.vicente.name = "VicenteYoung"
	g.truck.add_child(g.vicente)

func _lantern_node(node_name: String, beam: bool) -> Node3D:
	var item := Node3D.new()
	item.name = node_name
	# O tubo segue o antebraço (-Z do objeto = direção dos dedos): a mão fecha no corpo, a lente passa
	# dos nós dos dedos.
	g._box(item, Vector3(0, 0, -.03), Vector3(.045, .045, .19), g._material("blitz_lantern_body", Color("6a6e72"), .45, .5))
	g._box(item, Vector3(0, 0, -.13), Vector3(.05, .05, .01), g._material("blitz_lantern_lens", Color("fff3d8"), .2, .5, Color("fff0cc")))
	if beam:
		g.lantern_light = SpotLight3D.new()
		g.lantern_light.name = "BlitzLanternBeam"
		g.lantern_light.position = Vector3(0, 0, -.15)
		g.lantern_light.light_color = Color("fff1d6")
		g.lantern_light.spot_range = 22.0
		g.lantern_light.spot_angle = 16.0
		g.lantern_light.shadow_enabled = false
		g.lantern_light.set_meta("budget_energy", 4.0)
		g.lantern_light.light_energy = 4.0
		item.add_child(g.lantern_light)
	return item

## Colega com as mãos do Dante no corpo da patrulha (BlitzColleague).
func _colleague(node_name: String, appearance: int, body: String, point: Vector3, facing: Vector3) -> Node3D:
	var officer: Node3D = COLLEAGUE.new()
	officer.body_path = "res://assets/prologue/police/%s.glb" % body
	officer.name = node_name
	officer.appearance_index = appearance
	officer.position = point
	g._set.add_child(officer)
	g._face(officer, facing)
	return officer

func _build_cast() -> void:
	# O Dante do jogo (dante.glb, BlitzBrother) de farda: rosto, mãos, caminhada e pegada de pistola do
	# jogador, conduzido como marionete pela cena.
	g.dante = BROTHER.new()
	g.dante.identity_id = "dante"
	g.dante.name = "DanteYoung"
	g.dante.position = g.DANTE_POST
	g._set.add_child(g.dante)
	g._face(g.dante, Vector3.BACK)
	g.dante.equip("pistol")
	g.lantern = g._lantern_node("BlitzLantern", true)
	g._set.add_child(g.lantern)

func _build_colleagues() -> void:
	g.bastos = g._colleague("BlitzBastos", 3, "patrol_heavy_hands", Vector3(3.75, 0, -14.9), Vector3(-1, 0, .35))
	g.lima = g._colleague("BlitzLima", 6, "patrol_m_hands", Vector3(2.9, 0, -14.3), Vector3.BACK)
	# A pistola dele fica no coldre até a emboscada.
	if g.pov == "dante":
		g.lima.equip("pistol")
		g.lima.weapon.hide()
	g.colleagues.assign([g.bastos, g.lima])
	g.colleague_lantern = g._lantern_node("BlitzColleagueLantern", false)
	g._set.add_child(g.colleague_lantern)
	g.bastos_radio = Node3D.new()
	g.bastos_radio.name = "BlitzRadio"
	g._box(g.bastos_radio, Vector3(0, 0, -.02), Vector3(.06, .035, .12), g._material("blitz_radio", Color("1b1c1e"), .55, .3))
	g._set.add_child(g.bastos_radio)
	# O Rato vai no banco do passageiro nas duas versões da noite (no flashback ele só fica ali).
	g.shooter = COBRA_MODEL.new()
	g.shooter.name = "BlitzShooter"
	# Desde o começo no banco do passageiro, pistola escondida: ninguém olhou para ele.
	g.shooter.seated = true
	g.shooter.seat_armed = true
	# Sem sorteio de aparência: a roupa padrão da gangue, para ler "Cobra" à primeira vista.
	g.shooter.cobra_uniform = true
	g.shooter.position = Vector3(.55, 1.15, -3.35)
	g.truck.add_child(g.shooter)
	# Biblioteca dos clipes de morte, sob a cortina (só o prólogo tem mortes).
	if g.pov == "dante": MIXAMO_DEATH.library()

## Prende um objeto na palma: filho do antebraço do rig, na ponta (onde o IK põe a mão). Assim a lanterna,
## o rádio e a algema andam com a mão de verdade, em vez de flutuar perto dela.
func _hold(model, index: int, item: Node3D) -> bool:
	if model.has_method("blitz_hold_item"): return model.blitz_hold_item(item)
	var body = model.get("body") if model is POLICE_MODEL else model
	if not is_instance_valid(body) or not is_instance_valid(item) or body.forearms.size() <= index: return false
	var fore: Node3D = body.forearms[index]
	if item.get_parent() != fore: item.reparent(fore, false)
	item.position = Vector3(0, -float(body._arm_measure(index).y) + .03, .015)
	item.rotation = Vector3(-PI * .5, 0, 0)
	return true

func _body(model):
	return model.get("body") if model is POLICE_MODEL else model

## Alvos fixos das mãos (null = braço livre). Desliga o provedor de arma do PoliceModel, que reescreveria.
func _hands(model, right: Variant, left: Variant) -> void:
	var body = g._body(model)
	if not is_instance_valid(body): return
	body.hand_provider = Callable()
	body.hand_targets = [right, left]

func _colleagues_tick() -> void:
	if not is_instance_valid(g.lima) or not is_instance_valid(g.bastos): return
	g._hold(g.lima, 0, g.colleague_lantern)
	g._hold(g.bastos, 1, g.bastos_radio)
	g._hold(g.dante, 0, g.lantern)
	if g.stage in ["dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_black"]: return
	# Lima manda os carros para a outra faixa: a lanterna varre da faixa fechada para a aberta.
	var forward: Vector3 = g._forward(g.lima)
	var right := forward.cross(Vector3.UP).normalized()
	var waving: bool = g._traffic_near()
	var sweep: float = (.5 + .5 * sin(g.stage_time * 3.4)) if waving else .15
	# Cotovelo dobrado: com o alvo no limite do alcance o braço ficava travado e reto como um bastão.
	g._hands(g.lima, g.lima.global_position + Vector3.UP * (1.12 + .10 * sweep) + forward * .28 + right * lerpf(.20, -.25, sweep), null)
	# Bastos no rádio até ir com Dante: a mão esquerda leva o rádio à boca (a junta da cabeça é o pescoço).
	if g.stage in ["dante_open", "vicente_drive", "vicente_stop", "vicente_wait", "vicente_face"]:
		var mouth: Vector3 = g._head(g.bastos) + Vector3.UP * .14 + g._forward(g.bastos) * .13 - g._forward(g.bastos).cross(Vector3.UP).normalized() * .05
		g._hands(g.bastos, null, mouth)

## Depois da pose do quadro (process_priority): o facho aponta para onde o policial olha, não para onde o
## antebraço aponta (seguia o braço: chão aos pés em repouso, céu ao sinalizar).
func _aim_lanterns() -> void:
	if is_instance_valid(g.lantern) and g.lantern.is_visible_in_tree():
		var aim: Vector3 = g.dante.global_position + g._forward(g.dante) * 4.0
		if g.stage == "dante_ask" or g.stage == "vicente_face": aim = g.truck.to_global(Vector3(-.55, 2.3, -3.4))
		elif g._swing > .05 and g.truck.position.z < 800.0: aim = g.truck.to_global(Vector3(-.5, 2.5, -5.0))
		g._point(g.lantern, aim)
		var raised: bool = g._swing > .05 or g.stage in ["dante_ask", "vicente_wait", "vicente_face"]
		g.lantern_light.set_meta("budget_energy", 4.0 if raised else 1.5)
		if not LIGHT_BUDGET.enabled: g.lantern_light.light_energy = g.lantern_light.get_meta("budget_energy")
	if is_instance_valid(g.colleague_lantern) and g.colleague_lantern.is_visible_in_tree():
		# Lima ilumina a faixa aberta por onde os carros devem passar.
		g._point(g.colleague_lantern, Vector3(-g.LANE_X, 0, g.lima.global_position.z + 12.0))

func _point(item: Node3D, target: Vector3) -> void:
	var direction := target - item.global_position
	if direction.length() < .1: return
	item.global_basis = Basis.looking_at(direction.normalized(), Vector3.UP).scaled(item.global_basis.get_scale())

func _set_light(light: Light3D, parent: Node3D, energy: float) -> void:
	light.shadow_enabled = false
	light.set_meta("budget_energy", energy)
	light.light_energy = energy
	parent.add_child(light)
	g._set_lights.append(light)

## A prisão para onde a viatura leva Vicente: muralha de concreto com portão de aço, duas guaritas com
## holofote, blocos de celas com janelas acesas, postes na via de acesso. Só no prólogo.
func _build_prison() -> void:
	if g.pov != "dante": return
	g._prison = Node3D.new()
	g._prison.name = "BlitzPrison"
	g._prison.position = g.PRISON
	g._prison.hide()
	g._set.add_child(g._prison)
	var concrete: StandardMaterial3D = g._material("blitz_concrete", Color("6d6c66"), .92, .3)
	var dark: StandardMaterial3D = g._material("blitz_gate_steel", Color("2c3034"), .5, .6)
	var window: StandardMaterial3D = g._material("blitz_prison_window", Color("e8c98e"), .4, .3, Color("e2b866"))
	g._box(g._prison, Vector3(0, -.03, -20), Vector3(260, .06, 260), g._material("blitz_gravel", Color("2e2f2c"), .95, .2))
	g._box(g._prison, Vector3(1.8, -.01, 40), Vector3(8, .06, 110), g._material("blitz_wet_asphalt", Color("202327"), .32, .5))
	for x in [-24.0, 24.0]: g._box(g._prison, Vector3(x, 3.5, -10), Vector3(40, 7, .7), concrete)
	for x in [-44.0, 44.0]: g._box(g._prison, Vector3(x, 3.5, -45), Vector3(.7, 7, 70), concrete)
	g._box(g._prison, Vector3(0, 3.5, -80), Vector3(88, 7, .7), concrete)
	for x in [-24.0, 24.0]: g._box(g._prison, Vector3(x, 7.25, -10), Vector3(40, .5, .9), dark)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * 2.0, 0, -10)
		g._prison.add_child(leaf)
		g._box(leaf, Vector3(0, 3.0, 0), Vector3(4.0, 6.0, .25), dark)
		g._gate.append(leaf)
	g._box(g._prison, Vector3(-8, 2, -6), Vector3(5, 4, 4), concrete)
	g._box(g._prison, Vector3(-8, 2.2, -3.98), Vector3(2.2, 1, .05), window)
	for x in [-44.0, 44.0]:
		g._box(g._prison, Vector3(x, 5, -10), Vector3(2.2, 10, 2.2), concrete)
		g._box(g._prison, Vector3(x, 11.3, -10), Vector3(4, 2.6, 4), concrete)
		g._box(g._prison, Vector3(x, 11.4, -7.97), Vector3(3, .9, .05), window)
	for spec in [[Vector3(-14, 6, -40), Vector3(30, 12, 14)], [Vector3(18, 9, -52), Vector3(26, 18, 12)]]:
		g._box(g._prison, spec[0], spec[1], concrete)
		var rows := int(spec[1].y / 3.0)
		for row in rows:
			for column in int(spec[1].x / 3.0):
				if (row * 7 + column * 3) % 5 == 0: continue
				g._box(g._prison, spec[0] + Vector3(-spec[1].x * .5 + 1.5 + column * 3.0, -spec[1].y * .5 + 1.6 + row * 3.0, spec[1].z * .5 + .02), Vector3(.7, .9, .05), window)
	for z in [0.0, 15.0, 30.0, 45.0, 60.0]:
		g._box(g._prison, Vector3(6.8, 3.5, z), Vector3(.18, 7, .18), dark)
		g._box(g._prison, Vector3(6.0, 7.0, z), Vector3(1.6, .14, .4), window)
	g._flood = SpotLight3D.new()
	g._flood.name = "BlitzPrisonFlood"
	g._flood.position = Vector3(44, 12.6, -8)
	g._flood.light_color = Color("dfe8ff")
	g._flood.spot_range = 70.0
	g._flood.spot_angle = 14.0
	g._flood.rotation = Vector3(-.32, -.35, 0)
	g._set_light(g._flood, g._prison, 6.0)
	var gate_lamp := OmniLight3D.new()
	gate_lamp.position = Vector3(0, 6.6, -8.4)
	gate_lamp.light_color = Color("ffcf8c")
	gate_lamp.omni_range = 16.0
	g._set_light(gate_lamp, g._prison, 2.2)

## O quarto de oito anos depois, alugado e sem vida: cama de solteiro desfeita, caixas da mudança que nunca
## foram abertas, a jaqueta na cadeira, garrafa no chão, a foto dos dois irmãos na mesa, janela de chuva.
func _build_room() -> void:
	if g.pov != "dante": return
	g._room = Node3D.new()
	g._room.name = "BlitzRoom"
	g._room.position = g.ROOM
	g._room.hide()
	g._set.add_child(g._room)
	var wall: StandardMaterial3D = g._material("blitz_room_wall", Color("5b5850"), .9, .2)
	var wood: StandardMaterial3D = g._material("blitz_room_wood", Color("4a3b2e"), .7, .3)
	var floor: StandardMaterial3D = g._material("blitz_room_floor", Color("3d3026"), .6, .35)
	var trim: StandardMaterial3D = g._material("blitz_room_trim", Color("2e2721"), .7, .3)
	var cloth: StandardMaterial3D = g._material("blitz_room_curtain", Color("4f4637"), .95, .1)
	var metal: StandardMaterial3D = g._material("blitz_room_metal", Color("8a8d90"), .4, .6)
	var black: StandardMaterial3D = g._material("blitz_room_black", Color("15161a"), .5, .4)
	var card: StandardMaterial3D = g._material("blitz_cardboard", Color("b08a5c"), .9, .2)
	# Piso, paredes, teto e rodapé.
	g._box(g._room, Vector3(0, -.03, 0), Vector3(5, .06, 5), floor)
	g._box(g._room, Vector3(0, 1.4, -1.6), Vector3(5, 2.8, .1), wall)
	g._box(g._room, Vector3(-2.5, 1.4, 0), Vector3(.1, 2.8, 5), wall)
	g._box(g._room, Vector3(2.5, 1.4, 0), Vector3(.1, 2.8, 5), wall)
	g._box(g._room, Vector3(0, 2.83, 0), Vector3(5, .06, 5), wall)
	for spec in [[Vector3(0, .06, -1.54), Vector3(5, .12, .02)], [Vector3(-2.44, .06, 0), Vector3(.02, .12, 5)], [Vector3(2.44, .06, 0), Vector3(.02, .12, 5)]]:
		g._box(g._room, spec[0], spec[1], trim)
	g._box(g._room, Vector3(0, 2.76, -.2), Vector3(.32, .06, .32), g._material("blitz_room_ceiling_lamp", Color("d8d2c4"), .6, .3))
	# Janela na parede esquerda: vidro escuro de noite, caixilho em cruz, peitoril e cortinas meio abertas.
	g._box(g._room, Vector3(-2.44, 1.55, -.3), Vector3(.03, 1.0, 1.2), g._material("blitz_room_night", Color("101a28"), .15, .9, Color("0f1a2a")))
	for spec in [[Vector3(-2.42, 2.08, -.3), Vector3(.08, .06, 1.3)], [Vector3(-2.42, 1.02, -.3), Vector3(.08, .06, 1.3)], [Vector3(-2.42, 1.55, -.93), Vector3(.08, 1.12, .06)],
			[Vector3(-2.42, 1.55, .33), Vector3(.08, 1.12, .06)], [Vector3(-2.41, 1.55, -.3), Vector3(.05, 1.0, .03)], [Vector3(-2.41, 1.55, -.3), Vector3(.05, .03, 1.2)]]:
		g._box(g._room, spec[0], spec[1], trim)
	g._box(g._room, Vector3(-2.36, 1.0, -.3), Vector3(.2, .04, 1.4), wood)
	g._box(g._room, Vector3(-2.38, 1.5, -1.05), Vector3(.05, 2.2, .5), cloth)
	g._box(g._room, Vector3(-2.38, 1.5, .42), Vector3(.05, 2.2, .36), cloth)
	g._box(g._room, Vector3(-2.36, 2.62, -.3), Vector3(.04, .04, 1.9), metal)
	# Cama de solteiro: estrado, cabeceira, colchão, lençol, cobertor jogado e dois travesseiros.
	g._box(g._room, Vector3(0, .21, -.95), Vector3(2.0, .42, .95), wood)
	g._box(g._room, Vector3(-.98, .55, -.95), Vector3(.06, 1.1, .95), wood)
	g._box(g._room, Vector3(0, .49, -.95), Vector3(1.95, .14, .9), g._material("blitz_room_sheet", Color("8c877b"), .95, .1))
	var blanket: MeshInstance3D = g._box(g._room, Vector3(.45, .58, -1.05), Vector3(1.0, .06, .78), g._material("blitz_room_blanket", Color("3e4a57"), .95, .1))
	blanket.rotation = Vector3(0, .18, .04)
	g._box(g._room, Vector3(-.7, .62, -1.2), Vector3(.5, .12, .32), g._material("blitz_room_pillow", Color("b5afa1"), .95, .1))
	g._box(g._room, Vector3(-.72, .64, -.85), Vector3(.48, .1, .3), g._material("blitz_room_pillow", Color("b5afa1"), .95, .1))
	# Envelope aberto sobre a cama, ao lado dele.
	g._box(g._room, Vector3(.42, .57, -.6), Vector3(.24, .01, .14), g._material("blitz_letter", Color("e9e4d6"), .9, .1)).rotation.y = .4
	# Mesa de cabeceira: abajur (base e cúpula), copo, celular, a foto dos dois.
	g._box(g._room, Vector3(1.4, .35, -.9), Vector3(.6, .7, .5), wood)
	g._box(g._room, Vector3(1.4, .5, -.66), Vector3(.5, .14, .02), trim)
	g._box(g._room, Vector3(1.4, .2, -.66), Vector3(.5, .14, .02), trim)
	g._box(g._room, Vector3(1.32, .74, -1.0), Vector3(.1, .08, .1), black)
	g._box(g._room, Vector3(1.32, .84, -1.0), Vector3(.03, .2, .03), metal)
	g._box(g._room, Vector3(1.32, 1.0, -1.0), Vector3(.26, .2, .26), g._material("blitz_room_lamp", Color("f2d9a8"), .5, .3, Color("ffd59a")))
	g._box(g._room, Vector3(1.55, .76, -.78), Vector3(.07, .12, .07), g._material("blitz_room_glass", Color(.75, .8, .82, .45), .1, .9))
	g._box(g._room, Vector3(1.6, .705, -.98), Vector3(.08, .01, .15), black)
	var photo: MeshInstance3D = g._box(g._room, Vector3(1.18, .8, -.78), Vector3(.16, .2, .02), trim)
	photo.rotation = Vector3(-.2, .5, 0)
	g._box(photo, Vector3(0, 0, .012), Vector3(.12, .15, .005), g._material("blitz_room_photo", Color("6b6152"), .6, .3))
	# Guarda-roupa no canto, com duas portas e puxadores.
	g._box(g._room, Vector3(2.05, 1.0, -1.25), Vector3(.8, 2.0, .6), wood)
	g._box(g._room, Vector3(2.05, 1.0, -.94), Vector3(.01, 1.9, .02), trim)
	for x in [1.98, 2.12]: g._box(g._room, Vector3(x, 1.05, -.93), Vector3(.02, .12, .02), metal)
	# Cadeira com a jaqueta pendurada e as botas no chão.
	g._box(g._room, Vector3(1.75, .45, .45), Vector3(.45, .05, .45), wood)
	g._box(g._room, Vector3(1.75, .75, .66), Vector3(.45, .6, .04), wood)
	for leg in [Vector3(1.55, .22, .25), Vector3(1.95, .22, .25), Vector3(1.55, .22, .65), Vector3(1.95, .22, .65)]: g._box(g._room, leg, Vector3(.04, .45, .04), wood)
	var jacket: MeshInstance3D = g._box(g._room, Vector3(1.75, .8, .7), Vector3(.5, .55, .12), g._material("blitz_room_jacket", Color("2c2f33"), .85, .2))
	jacket.rotation.x = -.15
	for x in [.55, .72]: g._box(g._room, Vector3(x, .07, .35), Vector3(.12, .14, .3), black)
	# Caixas da mudança empilhadas, uma aberta; tapete gasto; garrafa ao pé da cama.
	for spec in [[Vector3(-1.9, .25, 1.2), Vector3(.6, .5, .5)], [Vector3(-1.85, .7, 1.15), Vector3(.5, .4, .45)], [Vector3(-1.3, .2, 1.6), Vector3(.55, .4, .45)]]:
		g._box(g._room, spec[0], spec[1], card)
	g._box(g._room, Vector3(.2, .006, .25), Vector3(1.6, .012, 1.0), g._material("blitz_room_rug", Color("5a3d33"), .95, .1))
	g._box(g._room, Vector3(-.55, .14, .18), Vector3(.08, .28, .08), g._material("blitz_room_bottle", Color(.22, .3, .2, .7), .1, .9))
	# Na parede: um quadro, um calendário, uma estante com livros, a porta e o interruptor.
	g._box(g._room, Vector3(.1, 1.75, -1.54), Vector3(.7, .5, .03), trim)
	g._box(g._room, Vector3(.1, 1.75, -1.525), Vector3(.62, .42, .01), g._material("blitz_room_painting", Color("5d6a6a"), .7, .2))
	g._box(g._room, Vector3(1.25, 1.55, -1.54), Vector3(.28, .38, .01), g._material("blitz_room_calendar", Color("cfc7b5"), .9, .1))
	g._box(g._room, Vector3(-1.6, 1.6, -1.42), Vector3(.9, .03, .24), wood)
	var books := ["5a2f2a", "2f3f52", "6b5a3a", "36463a", "4b3b52", "7a6b52"]
	for index in books.size():
		g._box(g._room, Vector3(-1.95 + index * .1, 1.73, -1.42), Vector3(.07, .23 - (index % 3) * .03, .18), g._material("blitz_room_book_%d" % index, Color(books[index]), .8, .2))
	g._box(g._room, Vector3(2.44, 1.05, 1.4), Vector3(.04, 2.1, .9), trim)
	g._box(g._room, Vector3(2.4, 1.0, 1.05), Vector3(.05, .05, .05), metal)
	g._box(g._room, Vector3(2.44, 1.3, .8), Vector3(.02, .1, .07), g._material("blitz_room_switch", Color("d8d2c4"), .6, .3))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(1.3, 1.05, -.9)
	lamp.light_color = Color("ffcf94")
	lamp.omni_range = 4.2
	lamp.light_specular = .3
	g._set_light(lamp, g._room, 1.4)
	var night := OmniLight3D.new()
	night.position = Vector3(-2.0, 1.7, -.3)
	night.light_color = Color("7f9cc4")
	night.omni_range = 3.4
	# Sem especular: o reflexo da luz da janela no vidro virava uma "lua" de televisão.
	night.light_specular = 0.0
	g._set_light(night, g._room, .45)
	g.letter = MeshInstance3D.new()
	var paper := BoxMesh.new()
	paper.size = Vector3(.2, .004, .27)
	g.letter.mesh = paper
	g.letter.material_override = g._material("blitz_letter", Color("e9e4d6"), .9, .1)
	g.letter.hide()
	g._set.add_child(g.letter)

func _build_traffic() -> void:
	# Os dois carros que passam antes do "terceiro" (só no prólogo).
	if g.pov != "dante": return
	for id in ["station_wagon", "sedan_classic"]:
		var car: Node3D = FLEET.create(id)
		if car == null: continue
		car.process_mode = Node.PROCESS_MODE_DISABLED
		car.position = Vector3(g.LANE_X, 0, 900)
		g._set.add_child(car)
		g.cars.append(car)
		g._car_speed.append(0.0)

func _player(bus: String, stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	player.stream = stream
	player.volume_db = volume
	g.add_child(player)
	return player

func _build_audio() -> void:
	g._rain_audio = g._player("Ambient", BANK.loop("weather", "rain_bed.wav"), -9.0)
	g._engine_audio = g._player("SFX", BANK.loop("acoustic", "engine_truck_1.wav"), -80.0)
	g._police_audio = g._player("SFX", BANK.loop("acoustic", "engine_police_0.wav"), -80.0)
	g._sfx = g._player("SFX", null, -4.0)
	g._radio_click = g._player("SFX", g._sound("res://audio/menu/click_0.wav"), -14.0)

func _sound(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null

func _play(path: String, volume := -4.0) -> void:
	var stream: AudioStream = g._sound(path)
	if stream == null or not is_instance_valid(g._sfx): return
	# Um efeito por vez basta aqui: porta, freio e metal nunca se sobrepõem.
	g._sfx.stream = stream
	g._sfx.volume_db = volume
	g._sfx.play()

func _warm() -> void:
	if DisplayServer.get_name() != "headless" and g._warm_draws < g.WARM_DRAWS: return
	if RenderingServer.frame_post_draw.is_connected(g._count_draw): RenderingServer.frame_post_draw.disconnect(g._count_draw)
	g.truck_door.rotation.y = 0.0
	for car in g.cars: car.position = Vector3(g.LANE_X, 0, 900)
	g.dante.weapon.hide()
	g.dante.muzzle_flash_3d.hide()
	if is_instance_valid(g.shooter): g.shooter.muzzle_flash_3d.hide()
	if g.pov == "dante": g._dante_begin()
	else: g._vicente_begin()
	var tween: Tween = g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(g.curtain, "color:a", 0.0, .9 / g.pace)

func _beacons() -> void:
	# Vermelho e azul alternando em pares rápidos, como o giroflex das viaturas.
	var phase: float = fposmod(g.stage_time * 2.2, 1.0)
	var red := phase < .5
	var flash: bool = fposmod(g.stage_time * 8.8, 1.0) < .55
	if g._glows.size() == 2:
		g._glows[0].visible = red and flash
		g._glows[1].visible = not red and flash
	for lens in g._red_lenses: lens.emission_energy_multiplier = 2.8 if red and flash else 0.0
	for lens in g._blue_lenses: lens.emission_energy_multiplier = 2.8 if not red and flash else 0.0
	if is_instance_valid(g.halo):
		g.halo.light_color = Color(1, .15, .12) if red else Color(.2, .38, 1)
		g.halo.set_meta("budget_energy", 1.5 if flash else .35)
		if not LIGHT_BUDGET.enabled: g.halo.light_energy = g.halo.get_meta("budget_energy")

func _follow_rain() -> void:
	if not is_instance_valid(g.rain) or not is_instance_valid(g.camera): return
	# Na câmera alta a chuva cai sobre o foco; nos closes, na frente da lente.
	if g.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and g._high_focus.is_finite(): g.rain.global_position = g._high_focus + Vector3.UP * 9.0
	else: g.rain.global_position = g.camera.global_position + Vector3.UP * 7.0 - g.camera.global_basis.z * 5.0

func _engine(distance: float) -> void:
	if not is_instance_valid(g._engine_audio) or g._engine_audio.stream == null: return
	if not g._engine_audio.playing: g._engine_audio.play()
	g._engine_audio.volume_db = lerpf(-6.0, -40.0, clampf(distance / 160.0, 0.0, 1.0))
	g._engine_audio.pitch_scale = .8 + clampf(g.truck_speed / 20.0, 0.0, 1.0) * .45

func _budget_request() -> Dictionary:
	var lights: Array[Light3D] = []
	var wanted: Array[Dictionary] = []
	for light in [g.halo, g.lantern_light, g.cab_light] + g.headlights + g._set_lights:
		if not is_instance_valid(light): continue
		lights.append(light)
		# Pela visibilidade do dono: a luz escondida pelo próprio orçamento continua pedindo.
		if light.get_parent().is_visible_in_tree(): wanted.append({"light": light, "headlight": false})
	# "player": a cena é a única coisa na tela; o mundo pausado embaixo não disputa.
	return {"lights": lights, "wanted": wanted, "player": true, "camera": g.camera.global_position if is_instance_valid(g.camera) else Vector3.ZERO}

func _face(model: Node3D, direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < .001: return
	if model.has_method("blitz_face"):
		model.blitz_face(direction)
		return
	# PoliceModel olha para -z (o corpo vai girado em PI dentro dele); o rig civil solto olha para +z.
	if model is POLICE_MODEL: model.rotation.y = atan2(-direction.x, -direction.z)
	else: model.rotation.y = atan2(direction.x, direction.z)

func _forward(model: Node3D) -> Vector3:
	if model.has_method("blitz_forward"): return model.blitz_forward()
	if model is POLICE_MODEL: return -model.global_basis.z.normalized()
	return model.global_basis.z.normalized()

## Base do pescoço do rig (é onde fica a junta "cabeça"; a pose sentada/em pé muda a altura).
## Rosto e boca ficam ~12-14 cm acima: use _eyes para câmera e mãos na cabeça.
func _head(model) -> Vector3:
	var body = g._body(model)
	var head = body.get("head_node") if is_instance_valid(body) else null
	if head is Node3D and is_instance_valid(head): return head.global_position
	return model.global_position + Vector3.UP * 1.62

func _eyes(model) -> Vector3:
	return g._head(model) + Vector3.UP * .12

## Mão direita de Dante com a lanterna: baixa e livre, ou erguida balançando (`swing` 0..1) para o
## caminhão parar.
func _dante_hands(swing: float) -> void:
	if swing <= .01:
		g._hands(g.dante, null, null)
		return
	var forward: Vector3 = g._forward(g.dante)
	var right := forward.cross(Vector3.UP).normalized()
	var wave: float = sin(g.stage_time * 7.0) * .34 * swing
	g._hands(g.dante, g.dante.global_position + Vector3.UP * (1.2 + .32 * swing) + forward * (.38 + .12 * swing) + right * (.22 + wave), null)

## Vicente ao volante: quadril no banco, pés nos pedais e as duas mãos no aro, pela pose de motorista do
## jogo (a mesma dos carros). Refeita a cada quadro porque o caminhão anda.
func _vicente_hands() -> void:
	if not is_instance_valid(g.vicente) or g.vicente.get_parent() != g.truck: return
	var wheel: Vector3 = g.truck.to_global(Vector3(-.55, 2.02, -3.75))
	var rim: Vector3 = g.truck.global_basis.x.normalized()
	var grip: Basis = g.truck.global_basis.orthonormalized()
	g.vicente.seat(g.truck.to_global(Vector3(-.55, 1.7, -3.28)),
		{"Left": g.truck.to_global(Vector3(-.72, 1.22, -3.92)), "Right": g.truck.to_global(Vector3(-.38, 1.22, -3.92))},
		{"Left": Transform3D(grip, wheel - rim * .17), "Right": Transform3D(grip, wheel + rim * .17)})

func _door_point() -> Vector3:
	return g.truck.to_global(Vector3(-1.85, 0, -3.4))

## Olhos de Vicente debruçado no vão da porta: do banco, a linha até o rosto de Dante (mais baixo,
## no asfalto) cortaria a lataria da cabine.
## Olhos de Vicente no banco, um pouco à frente: vê o para-brisa e a janela, sem a coluna da porta no meio.
func _cab_lean() -> Vector3:
	return g.truck.to_global(Vector3(-.88, g.truck.to_local(g._eyes(g.vicente)).y, -3.78))

func _move_truck(step: float) -> void:
	g.truck.position.z -= g.truck_speed * step

## Abre a porta do motorista: chapa girando, som e a luz de teto acendendo.
func _open_door() -> void:
	# Escancarada (86°): meio aberta, a chapa ficava entre o asfalto e o rosto de quem está ao volante.
	g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(g.truck_door, "rotation:y", -1.5, 1.0 / g.pace)
	g._play("res://audio/vehicle_fx/door_open_0.wav", -5.0)
	g.cab_light.set_meta("budget_energy", 1.4)
	if not LIGHT_BUDGET.enabled: g.cab_light.light_energy = 1.4

## Desacelera para parar exatamente em `stop_z`; devolve true ao parar.
func _brake_to(stop_z: float, step: float, crawl := 0.0) -> bool:
	var distance: float = g.truck.position.z - stop_z
	if distance <= .05:
		g.truck.position.z = stop_z
		g.truck_speed = 0.0
		return true
	# Até `crawl` ele ainda anda (parado longe, volta a rodar); perto, a curva de frenagem manda.
	if crawl > 0.0 and g.truck_speed < crawl: g.truck_speed = minf(crawl, g.truck_speed + 2.0 * step)
	g.truck_speed = minf(g.truck_speed, sqrt(2.0 * 2.4 * distance))
	g.truck_speed = minf(g.truck_speed, distance / maxf(step, .001))
	g._move_truck(step)
	return false
