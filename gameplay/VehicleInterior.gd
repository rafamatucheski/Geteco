extends RefCounted
## Interior visível e motorista sentado ao volante.
##
## Até aqui quem dirigia sumia (`world.player.hide()`) e os vidros dos modelos eram opacos:
## o carro andava "vazio" e a empilhadeira nem tinha piloto. Este módulo dá ao veículo que o
## jogador conduz (a) um interior de uma malha só (volante, painel, bancos, console, pedais,
## retrovisor, forro, cintos), (b) vidros translúcidos nesse veículo e (c) a pose de
## motorista sentado com as mãos no volante.
##
## Custo: uma `MeshInstance3D` por veículo conduzido, malha em cache por arquétipo, sem
## colisão, sem nó por peça e sem script por quadro. O corpo do motorista acompanha o
## veículo com uma atribuição de transform por tique de física (`follow`).
##
## Só o veículo que o jogador entra recebe interior e vidro translúcido: o trânsito segue
## com os modelos achatados, de vidro opaco, como antes.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")

## Altura do quadril (junta da coxa) do Dante de pé sobre a sola. Medido no esqueleto.
const STANDING_HIP := 0.77
## Opacidade do vidro do veículo conduzido. Abaixo de ~0,3 o vidro deixa de parecer vidro;
## acima de ~0,5 o piloto some atrás do para-brisa na câmera a 45°.
const GLASS_ALPHA := 0.36
## Opacidade do teto do veículo conduzido (textura constante, ver `_roof_alpha_texture`).
const ROOF_ALPHA := 0.30

# --- Classes de cabine -------------------------------------------------------------------
# hip / hip_min: altura preferida e mínima da junta do quadril sobre o piso; rec: reclinação do
# tronco (rad); dy: quanto o centro do volante fica abaixo do ombro; r/tilt: raio e inclinação
# do aro (0 = vertical, 1,57 = deitado); foot: quanto o tornozelo fica à frente do quadril;
# clear: folga entre o centro do volante e a base do para-brisa; floor: piso da cabine sobre o
# chão quando o modelo não diz outra coisa; rows: banco traseiro; grip: posição da mão no aro
# (graus, 180 = nove horas).
# O Dante mede ~1,65 m e o teto do sedã fica a 1,32 m: o banco desce até `hip_min` e, se ainda
# não couber, o corpo diminui (até 82 %, ver `_fit`) em vez de a cabeça vazar pelo teto.
const KINDS := {
	"car": {"hip": .34, "hip_min": .22, "rec": .34, "dy": -.05, "r": .19, "tilt": .45, "foot": .60, "clear": .26, "floor": .12, "rows": true, "grip": 150.0},
	"sport": {"hip": .30, "hip_min": .20, "rec": .48, "dy": -.05, "r": .17, "tilt": .50, "foot": .64, "clear": .22, "floor": .08, "rows": false, "grip": 155.0},
	"suv": {"hip": .44, "hip_min": .28, "rec": .28, "dy": -.06, "r": .21, "tilt": .62, "foot": .56, "clear": .30, "floor": .28, "rows": true, "grip": 150.0},
	"pickup": {"hip": .44, "hip_min": .28, "rec": .28, "dy": -.06, "r": .21, "tilt": .62, "foot": .56, "clear": .30, "floor": .26, "rows": true, "grip": 150.0},
	"van": {"hip": .50, "hip_min": .34, "rec": .16, "dy": -.08, "r": .23, "tilt": .90, "foot": .52, "clear": .36, "floor": .32, "rows": false, "grip": 160.0},
	"truck": {"hip": .56, "hip_min": .40, "rec": .14, "dy": -.10, "r": .27, "tilt": .85, "foot": .50, "clear": .40, "floor": .85, "rows": false, "grip": 160.0},
	"bus": {"hip": .50, "hip_min": .36, "rec": .10, "dy": -.10, "r": .25, "tilt": 1.15, "foot": .50, "clear": .40, "floor": .50, "rows": false, "grip": 165.0},
	"buggy": {"hip": .30, "hip_min": .30, "rec": .30, "dy": -.10, "r": .17, "tilt": .70, "foot": .56, "clear": .20, "floor": .66, "rows": false, "grip": 150.0},
	"forklift": {"hip": .28, "hip_min": .28, "rec": .08, "dy": -.16, "r": .16, "tilt": .90, "foot": .56, "clear": .20, "floor": .64, "rows": false, "grip": 160.0},
}

const KIND_OF := {
	"union_sedan": "car", "sedan_classic": "car", "taxi_yellow": "car", "police_cruiser": "car", "aurora_executive": "car",
	"metro_hatch": "car", "orbita_micro": "car", "nordic_estate": "car", "station_wagon": "car", "sport_estate": "car",
	"sport_coupe": "sport", "cobra_v8": "sport", "muscle_classic": "sport", "monaliza": "sport", "vertice_midengine": "sport",
	"porto_rosso": "sport", "beach_cabriolet": "sport",
	"arctic_jeep": "suv", "desert_jeep_4x4": "suv", "vale_crossover": "suv", "summit_suv": "suv", "winter_suv_heavy": "suv",
	"police_suv": "suv", "surf_woody_wagon": "suv",
	"lumber_pickup_4x4": "pickup", "ranch_pickup": "pickup", "ranch_single": "pickup", "atlas_crew_pickup": "pickup",
	"bravio_crew": "pickup", "sertao_trail_pickup": "pickup",
	"courier_van": "van", "polar_van": "van", "police_transport": "van", "dock_delivery_van": "van", "nimbus_minivan": "van",
	"medic_box": "van",
	"american_dump_truck": "truck", "american_tanker_truck": "truck", "cargo_flatbed_truck": "truck", "boxrunner": "truck",
	"towmaster": "truck", "rescue_pumper": "truck", "snow_plow_truck": "truck",
	"route_city": "bus", "beach_buggy": "buggy", "dune_buggy": "buggy", "port_forklift": "forklift",
}

## Ajustes por arquétipo sobre o que se mede no modelo: piso da cabine, cabine aberta (sem
## teto: o piloto é visto de cima inteiro), e lugares onde o vidro não dá pista (buggy,
## empilhadeira). Valores em coordenadas do veículo (−Z é a frente, o motorista fica em −X).
const OVERRIDES := {
	"beach_cabriolet": {"open_top": true},
	"porto_rosso": {"open_top": true},
	"american_dump_truck": {"floor": .95, "roof": 2.55},
	"american_tanker_truck": {"floor": .95, "roof": 2.55},
	"cargo_flatbed_truck": {"floor": .95, "roof": 2.55},
	"boxrunner": {"floor": .85, "roof": 1.98},
	"towmaster": {"floor": .78},
	"rescue_pumper": {"floor": .80},
	"snow_plow_truck": {"floor": .82},
	"beach_buggy": {"open_top": true, "body_scale": .88, "floor": .70, "sx": -.28, "sz": .18, "cush": .78, "belt": 1.13, "roof": 1.6, "wz0": -.62, "wz1": -.43, "rear": .7, "hw": .55},
	"dune_buggy": {"open_top": true, "body_scale": .88, "floor": .70, "sx": -.29, "sz": .18, "cush": .78, "belt": 1.02, "roof": 1.4, "wz0": -.58, "wz1": -.43, "rear": .7, "hw": .55},
	"port_forklift": {"open_top": true, "sx": 0.0, "sz": .50, "cush": .90, "belt": 1.1, "roof": 2.08, "wz0": -.2, "wz1": -.1, "rear": 1.1, "hw": .46},
}

static var _specs: Dictionary = {}
static var _meshes: Dictionary = {}
static var _glass: Dictionary = {}
static var _material: StandardMaterial3D

# --- API ----------------------------------------------------------------------------------

## Desligar devolve o comportamento antigo (motorista oculto, vidro opaco): a medição de
## desempenho antes/depois usa (tests/measure/measure_seated_driver.gd), e a variável de ambiente
## GETECO_SEM_MOTORISTA_SENTADO=1 liga o mesmo interruptor para comparar qualquer teste com o antes.
static var enabled := OS.get_environment("GETECO_SEM_MOTORISTA_SENTADO").is_empty()

## O veículo mostra o motorista sentado? Blindado tem escotilha e piloto próprios; moto usa a
## pose de guidão (`Driving._update_mounted_player`).
static func shows_driver(vehicle: Node) -> bool:
	if not enabled: return false
	var id := str(vehicle.get("archetype"))
	return not id.begins_with("bike_") and id != "army_tank"

## Banco de quem não tem porta (buggy e empilhadeira), em coordenadas do veículo: o ponto
## onde a animação de entrada deve terminar. Os demais usam a tabela de portas do veículo
## (`VehicleDoorSpecs`). Vector3.INF quando o veículo não é desses ou ainda não foi medido.
static func open_seat_local(vehicle: Node3D) -> Vector3:
	if str(vehicle.get("archetype")) not in ["beach_buggy", "dune_buggy", "port_forklift"]: return Vector3.INF
	var s := spec(vehicle)
	if s.is_empty(): return Vector3.INF
	return Vector3(s.sx, s.floor, s.sz)

## Quanto o corpo desce do porte de pé até o banco desta cabine (m). A apresentação de embarque
## pode usar para terminar a animação na altura em que o motorista vai ficar.
static func seated_drop(vehicle: Node3D) -> float:
	var s := spec(vehicle) if shows_driver(vehicle) else {}
	return .42 if s.is_empty() else clampf(STANDING_HIP - float(s.hip), .18, .50)

static func spec(vehicle: Node3D) -> Dictionary:
	var id := str(vehicle.get("archetype"))
	if _specs.has(id): return _specs[id]
	# Medir exige o modelo na árvore (transform global das peças).
	if not vehicle.is_inside_tree() or vehicle.get("visual") == null: return {}
	var s := _derive(vehicle)
	_specs[id] = s
	return s

# --- Especificação ------------------------------------------------------------------------

static func _is_glass(part: MeshInstance3D, surface: int, material: Material) -> bool:
	var key := ROLES.key(part, surface)
	if key in ["glass", "tinted_glass", "windshield", "window"]: return true
	if key in ["smoked_lens", "headlight", "tail", "lens", "brake_light", "paint"]: return false
	var standard := material as StandardMaterial3D
	if standard == null or standard.emission_enabled or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	# Modelos V1 antigos: caixas azul-petróleo sem nome (44616b, 213446, 203b49, 172835...).
	return standard.roughness <= .19 and absf(standard.metallic - .3) <= .06

static func _derive(vehicle: Node3D) -> Dictionary:
	var id := str(vehicle.get("archetype"))
	var kind: String = KIND_OF.get(id, "car")
	var k: Dictionary = KINDS[kind]
	var belt := INF
	var roof := -INF
	var wz0 := INF
	var wz1 := INF
	var rear := -INF
	var rear_top := 0.0
	var hw := 0.0
	var to_car := vehicle.global_transform.affine_inverse()
	var points: Array[Vector3] = []
	# Um trecho por superfície de vidro (intervalo em Z + vértices).
	var patches: Array = []
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name == "Interior" or part.name == "WarmUp": continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material == null or not _is_glass(part, surface, material): continue
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var xf: Transform3D = to_car * part.global_transform
			var patch := {"z0": INF, "z1": -INF, "points": []}
			for v in vertices:
				var p: Vector3 = xf * v
				patch.points.append(p)
				patch.z0 = minf(patch.z0, p.z)
				patch.z1 = maxf(patch.z1, p.z)
			patches.append(patch)
	# A cabine é a cadeia de vidro que começa na frente e não tem vão de mais de 0,8 m: van e
	# ambulância têm janelas soltas na carga, e o teto delas não é o teto do motorista.
	patches.sort_custom(func(a, b): return a.z0 < b.z0)
	var chain_end := -INF
	for patch in patches:
		if chain_end != -INF and float(patch.z0) - chain_end > .8: break
		chain_end = maxf(chain_end, float(patch.z1))
		points.append_array(patch.points)
	for p in points:
		belt = minf(belt, p.y)
		roof = maxf(roof, p.y)
		wz0 = minf(wz0, p.z)
		rear = maxf(rear, p.z)
	if points.is_empty():
		# Sem vidro identificável (buggy, empilhadeira, modelos sem material de vidro).
		belt = float(vehicle.body_height) * .62
		roof = float(vehicle.body_height) * .95
		wz0 = -float(vehicle.half_length) * .35
		rear = float(vehicle.half_length) * .35
		wz1 = wz0 + .3
		rear_top = rear - .3
		hw = float(vehicle.half_width) * .72
	else:
		wz1 = INF
		rear_top = -INF
		for p in points:
			if p.y > roof - .10:
				wz1 = minf(wz1, p.z)
				rear_top = maxf(rear_top, p.z)
			if p.y < belt + .18: hw = maxf(hw, absf(p.x))
	var s := {"kind": kind, "belt": belt, "roof": roof, "wz0": wz0, "wz1": wz1, "rear": rear, "rear_top": rear_top, "hw": hw, "open_top": false}
	for key in k: s[key] = k[key]
	for key in OVERRIDES.get(id, {}): s[key] = OVERRIDES[id][key]
	var theta := float(s.rec)
	var floor_y := float(s.floor)
	var scale := 1.0
	var hip := float(s.hip)
	if s.has("cush"):
		# Buggy e empilhadeira: o banco é do modelo, então a altura do quadril vem dele.
		hip = float(s.cush) + .12 - floor_y
	elif not bool(s.open_top):
		var fitted := _fit(theta, hip, float(s.hip_min), floor_y, float(s.roof) - .02)
		hip = fitted.x
		scale = fitted.y
	if s.has("body_scale"): scale = float(s.body_scale)
	s["hip"] = hip
	s["scale"] = scale
	s["cush"] = floor_y + hip - .12
	if not s.has("sx"): s["sx"] = -clampf(float(s.hw) * .45, .22, .55)
	# Ombro e coroa do Dante nesta pose (relativos à junta do quadril): o volante fica ao alcance
	# do braço e a cabeça atrás da borda do teto, em vez de valores soltos por classe.
	var shoulder := _rig_offset(RIG_SHOULDER, theta, scale)
	var crown := _rig_offset(RIG_CROWN, theta, scale)
	var dy := float(s.dy) * scale
	var arm := ARM_LENGTH * scale * .90
	var forward := sqrt(maxf(arm * arm - dy * dy - .012, .01))
	if not s.has("sz"):
		s["sz"] = maxf(float(s.wz0) + float(s.clear) + forward - shoulder.z, float(s.wz1) + .06 - crown.z)
	s["hub_z"] = float(s.sz) + shoulder.z - forward
	s["hub_y"] = floor_y + hip + shoulder.y + dy
	s["w"] = maxf(float(s.hw) - .07, .3)
	# Pé no pedal: o mais à frente que a perna alcança a esta altura de quadril.
	var leg := .70 * scale
	var rise := maxf(hip - .11, 0.0)
	s["foot_dist"] = minf(float(s.foot) * scale, sqrt(maxf(leg * leg - rise * rise, .04)))
	return s

# Medidas do esqueleto do Dante em pé (espaço do Actor, sem escala de visual): junta do quadril,
# centro dos ombros e topo da cabeça (coroa ~5 cm acima do osso head_end); comprimento do
# ombro ao centro da palma. Medidas com tests/capture/... (evidence/seated-driver/probe_rig).
const RIG_JOINT := Vector3(0, .764, .002)
const RIG_SHOULDER := Vector3(0, 1.211, .052)
const RIG_CROWN := Vector3(0, 1.66, -.023)
const ARM_LENGTH := .51

## Posição de um ponto do corpo relativa à junta do quadril quando o tronco reclina `theta` (rad)
## a partir da junta e o corpo é escalado por `scale`.
static func _rig_offset(point: Vector3, theta: float, scale: float) -> Vector3:
	var d := (point - RIG_JOINT) * scale
	return Vector3(d.x, d.y * cos(theta) - d.z * sin(theta), d.y * sin(theta) + d.z * cos(theta))

## Altura do quadril e escala do corpo para a cabeça caber sob `ceiling`: primeiro abaixa o
## banco até o mínimo, depois diminui o corpo. Devolve (quadril, escala).
static func _fit(theta: float, hip: float, hip_min: float, floor_y: float, ceiling: float) -> Vector2:
	for scale in [1.0, .95, .90, .86, .82]:
		var top: float = _rig_offset(RIG_CROWN, theta, scale).y
		var h := hip
		while h >= hip_min - .001:
			if floor_y + h + top <= ceiling: return Vector2(h, scale)
			h -= .02
	return Vector2(hip_min, .82)

# --- Vidro --------------------------------------------------------------------------------

## Versão translúcida (em cache) de um material de vidro. Continua sendo "glass" para o
## dano do veículo, que troca vidro por vidro estourado pela mesma detecção.
static func see_through(material: StandardMaterial3D) -> StandardMaterial3D:
	if _glass.has(material): return _glass[material]
	var copy := material.duplicate() as StandardMaterial3D
	copy.resource_name = "glass"
	copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color := copy.albedo_color
	color.a = GLASS_ALPHA
	copy.albedo_color = color
	_glass[material] = copy
	return copy

static func _open_glass(vehicle: Node3D) -> void:
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name == "Interior" or part.name == "RoofCut" or part.name == "WarmUp": continue
		if part.material_override != null:
			if part.material_override is StandardMaterial3D and _is_glass(part, 0, part.material_override):
				part.material_override = see_through(part.material_override)
			continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material is StandardMaterial3D and _is_glass(part, surface, material):
				part.set_surface_override_material(surface, see_through(material))

# --- Montagem no veículo ------------------------------------------------------------------

## Última montagem por etapa (ms), só para medição.
static var profile: Dictionary = {}
static var _warmed: Dictionary = {}

## Abre apenas os vidros para mostrar o motorista. O teto conserva a malha e a pintura
## opacas do modelo, inclusive após entrar, repintar ou mudar a câmera. Idempotente.
static func open_view(vehicle: Node3D) -> void:
	var s := spec(vehicle)
	if s.is_empty() or vehicle.get("visual") == null or vehicle.has_meta("interior_view"): return
	var began := Time.get_ticks_usec()
	vehicle.set_meta("interior_view", {"parts": [], "roofs": [], "alpha_materials": [], "slabs": []})
	_open_glass(vehicle)
	var after_glass := Time.get_ticks_usec()
	profile = {"vidro_ms": (after_glass - began) / 1000.0, "teto_ms": 0.0}
	# Carcaça: o dano troca materiais por papel e não conhece o teto recortado; `Driving` chama
	# `close_view` ao receber `destroyed` (antes do `wreck`), que devolve o casco inteiro.

## Interior (malha única) dentro do veículo. Chame DEPOIS de a porta existir: o recorte da
## porta pega qualquer triângulo voltado para o lado no vão, inclusive os cartões e bancos daqui.
## Idempotente; também abre a vista se ninguém abriu.
static func attach(vehicle: Node3D) -> void:
	var visual: Node3D = vehicle.get("visual")
	if visual == null: return
	var s := spec(vehicle)
	if s.is_empty(): return
	if not visual.has_node("Interior"):
		var node := MeshInstance3D.new()
		node.name = "Interior"
		node.mesh = mesh_for(str(vehicle.get("archetype")), s)
		# Dentro da carroceria: sombra projetada aqui só custaria passe de sombra.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# O visual pode vir escalado por variante; o interior é medido em coordenadas do veículo.
		node.scale = Vector3.ONE / visual.scale
		visual.add_child(node)
		if str(vehicle.get("archetype")) == "port_forklift": _hide_forklift_console(visual)
	open_view(vehicle)

## Prepara, quadro a quadro, o que custa caro na primeira vez de cada arquétipo (medida da
## cabine, malha do interior e variantes de material do vidro): chame quando o jogador chega
## perto do veículo, para o custo cair
## enquanto ele anda e não na abertura da porta. Só enche caches; não muda a cena.
static func prewarm(vehicle: Node3D) -> void:
	var id := str(vehicle.get("archetype"))
	if _warmed.has(id) or not shows_driver(vehicle) or not vehicle.is_inside_tree(): return
	_warmed[id] = true
	var tree := vehicle.get_tree()
	var s := spec(vehicle)
	if s.is_empty():
		_warmed.erase(id)
		return
	await tree.process_frame
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): return
	mesh_for(id, s)
	var warm: Array = []
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name in ["Interior", "RoofCut", "WarmUp"]: continue
		if part.material_override is StandardMaterial3D and _is_glass(part, 0, part.material_override):
			warm.append([mesh, see_through(part.material_override)])
			continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material is StandardMaterial3D and _is_glass(part, surface, material): warm.append([mesh, see_through(material)])
	await _warm_materials(vehicle, warm)

## O Godot só monta o sombreador e o pipeline de um material na primeira vez que uma instância
## o veste numa malha (medido: 21–26 ms no primeiro vidro/teto translúcido de cada tipo). Uma
## instância descartável por variante, com a malha real, longe da vista e por dois quadros, paga
## isso enquanto o jogador anda.
static func _warm_materials(vehicle: Node3D, entries: Array) -> void:
	var tree := vehicle.get_tree()
	var nodes: Array[MeshInstance3D] = []
	for entry in entries:
		var node := MeshInstance3D.new()
		node.name = "WarmUp"
		node.mesh = entry[0]
		node.material_override = entry[1]
		# Longe da vista (o custo é montar sombreador e pipeline, não desenhar).
		node.position = Vector3(0, -300, 0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vehicle.visual.add_child(node)
		nodes.append(node)
	await tree.process_frame
	await tree.process_frame
	for node in nodes:
		if is_instance_valid(node): node.queue_free()

## Devolve o teto ao casco (explosão do veículo). O vidro fica: o dano já o estoura.
static func close_view(vehicle: Node3D) -> void:
	set_low_camera_roof(vehicle, false)
	var view: Dictionary = vehicle.get_meta("interior_view", {})
	if view.is_empty(): return
	for entry in view.parts:
		if is_instance_valid(entry[0]): entry[0].mesh = entry[1]
	for roof in view.roofs:
		if is_instance_valid(roof): roof.queue_free()
	for entry in view.slabs:
		if is_instance_valid(entry[0]): entry[0].material_override = entry[1]
	for material in view.alpha_materials:
		if material is StandardMaterial3D:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.albedo_texture = null
	var paint = vehicle.get("_paint")
	if paint != null:
		for material in view.get("added_paint", []):
			paint.materials.erase(material)
			paint.roof_materials.erase(material)
	vehicle.remove_meta("interior_view")

## A câmera traseira precisa da carroceria fechada; não refazer cortes das portas.
static func set_low_camera_roof(vehicle: Node3D, solid: bool) -> void:
	var view: Dictionary = vehicle.get_meta("interior_view", {})
	if view.is_empty() or bool(view.get("low_camera_roof", false)) == solid: return
	view["low_camera_roof"] = solid
	# A cobertura do cupê também tem vidro; o alfa da vista superior abria buracos
	# e deixava interior/motorista sobrepostos na visão traseira.
	if solid:
		var glazing: Array = []
		for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == null or part.name in ["Interior", "RoofCut", "WarmUp"]: continue
			for surface in (1 if part.material_override != null else part.mesh.get_surface_count()):
				var original: Material = part.get_active_material(surface)
				if not original is StandardMaterial3D or not _is_glass(part, surface, original): continue
				var opaque := original.duplicate() as StandardMaterial3D
				opaque.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				var color := opaque.albedo_color
				color.a = 1.0
				opaque.albedo_color = color
				var slot: int = -1 if part.material_override != null else surface
				glazing.append([part, slot, part.material_override if slot == -1 else part.get_surface_override_material(slot)])
				if slot == -1: part.material_override = opaque
				else: part.set_surface_override_material(slot, opaque)
		view["low_camera_glazing"] = glazing
	else:
		for entry in view.get("low_camera_glazing", []):
			if not is_instance_valid(entry[0]): continue
			if entry[1] == -1: entry[0].material_override = entry[2]
			else: entry[0].set_surface_override_material(entry[1], entry[2])
		view.erase("low_camera_glazing")
	var materials: Array = view.alpha_materials.duplicate()
	for roof in view.roofs:
		if is_instance_valid(roof) and roof.material_override not in materials:
			materials.append(roof.material_override)
	for material in materials:
		if not material is StandardMaterial3D: continue
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = null if solid else _roof_alpha_texture()

static var _roof_texture: ImageTexture
static var _roof_cuts: Dictionary = {}

## Textura constante com o alfa do teto. O alfa vem daqui, e não de `albedo_color.a`, porque
## a repintura do veículo (VehiclePaint.apply) reescreve o albedo com alfa 1.
static func _roof_alpha_texture() -> ImageTexture:
	if _roof_texture == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(1, 1, 1, ROOF_ALPHA))
		_roof_texture = ImageTexture.create_from_image(image)
	return _roof_texture

## Variante translúcida do teto de um material (em cache no veículo, pelo material de origem, que é
## da tinta dele): a mesma instância serve ao prewarm e à abertura, então o custo de montar o
## sombreador cai no prewarm. Morre junto com o veículo.
static func _roof_variant(vehicle: Node3D, material: StandardMaterial3D) -> StandardMaterial3D:
	var cache: Dictionary = vehicle.get_meta("interior_variants", {})
	if cache.has(material): return cache[material]
	var variant := material.duplicate() as StandardMaterial3D
	variant.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	variant.albedo_texture = _roof_alpha_texture()
	cache[material] = variant
	vehicle.set_meta("interior_variants", cache)
	return variant

static func _cut_key(part: MeshInstance3D, surface: int, id: String) -> String:
	return "%d:%d:%s" % [part.mesh.get_instance_id(), surface, id]

## Peças do veículo que viram teto translúcido: `roof_paint` (peça de teto própria, muda no
## lugar), `slab` (placa larga de teto com material próprio: ônibus, jipe) e `cut` (o teto é
## parte da lataria: os triângulos de teto saem para uma peça à parte).
static func _roof_candidates(vehicle: Node3D, s: Dictionary) -> Array:
	var found: Array = []
	var to_car := vehicle.global_transform.affine_inverse()
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name == "Interior" or part.name == "RoofCut" or part.name == "WarmUp": continue
		for surface in mesh.get_surface_count():
			var material: Material = part.material_override if part.material_override != null else part.get_active_material(surface)
			if not material is StandardMaterial3D or material.albedo_texture != null: continue
			var key := ROLES.key(part, surface)
			var box: AABB = (to_car * part.global_transform) * mesh.get_aabb()
			if key == "roof_paint":
				found.append({"part": part, "surface": surface, "material": material, "kind": "roof_paint"})
			elif part.material_override != null and not (material as StandardMaterial3D).emission_enabled \
					and box.position.y >= float(s.roof) - .06 and box.position.y <= float(s.roof) + .12 and box.size.y < .35 and box.size.x >= float(s.hw) * 1.2 and box.size.z >= .7 and box.size.x * box.size.z >= .9 and box.get_center().z < float(s.rear_top) + .3:
				found.append({"part": part, "surface": surface, "material": material, "kind": "slab"})
			elif key in ["paint", "canvas"] and (part.material_override == null or surface == 0):
				found.append({"part": part, "surface": surface, "material": material, "kind": "cut"})
				break
	return found

## Teto translúcido no veículo conduzido: da câmera a 45° o teto opaco escondia o motorista e
## o interior inteiro. Peças de teto próprias (`roof_paint`) ficam translúcidas no lugar; nos
## cascos em que o teto é parte da lataria, os triângulos de teto viram uma peça à parte
## (malha em cache por arquétipo) com a mesma tinta.
static func _open_roof(vehicle: Node3D, s: Dictionary) -> void:
	var view: Dictionary = vehicle.get_meta("interior_view")
	var id := str(vehicle.get("archetype"))
	var to_car := vehicle.global_transform.affine_inverse()
	view["added_paint"] = []
	var paint = vehicle.get("_paint")
	for candidate in _roof_candidates(vehicle, s):
		var part: MeshInstance3D = candidate.part
		var surface: int = candidate.surface
		var material: StandardMaterial3D = candidate.material
		match str(candidate.kind):
			"roof_paint":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_texture = _roof_alpha_texture()
				view.alpha_materials.append(material)
			"slab":
				var slab := _roof_variant(vehicle, material)
				view.slabs.append([part, part.material_override])
				part.material_override = slab
				view.alpha_materials.append(slab)
				if paint != null and material in paint.materials:
					paint.materials.append(slab)
					view.added_paint.append(slab)
					if material in paint.roof_materials: paint.roof_materials.append(slab)
			"cut":
				var mesh: Mesh = part.mesh
				var cut := _cut_roof(part, surface, to_car * part.global_transform, s, _cut_key(part, surface, id))
				if cut.is_empty(): continue
				var roof := MeshInstance3D.new()
				roof.name = "RoofCut"
				roof.mesh = cut.roof
				roof.transform = part.transform
				var tinted := _roof_variant(vehicle, material)
				roof.material_override = tinted
				roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				part.get_parent().add_child(roof)
				view.parts.append([part, mesh])
				view.roofs.append(roof)
				part.mesh = cut.body
				# A repintura passa a valer também para o teto recortado.
				if paint != null:
					paint.materials.append(tinted)
					view.added_paint.append(tinted)

## Separa os triângulos de teto (voltados para cima, na altura do teto, sobre a cabine) da
## superfície de pintura. Devolve {body, roof} ou {} se não houver teto ali.
static func _cut_roof(part: MeshInstance3D, surface: int, xf: Transform3D, s: Dictionary, key: String) -> Dictionary:
	if _roof_cuts.has(key): return _roof_cuts[key]
	var mesh: Mesh = part.mesh
	# Só malhas de importação: as primitivas (caixa, cilindro) não têm superfícies editáveis.
	if not mesh is ArrayMesh:
		_roof_cuts[key] = {}
		return {}
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null: normals = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
	else:
		indices.resize(vertices.size())
		for i in indices.size(): indices[i] = i
	var y_min := float(s.roof) - .12
	var z0 := float(s.wz1) - .25
	var z1 := float(s.rear_top) + .25
	var half := float(s.hw) + .06
	var roof_indices := PackedInt32Array()
	var body_indices := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var a: Vector3 = xf * vertices[indices[i]]
		var b: Vector3 = xf * vertices[indices[i + 1]]
		var c: Vector3 = xf * vertices[indices[i + 2]]
		var center := (a + b + c) / 3.0
		var up := 0.0
		if normals.size() == vertices.size():
			up = (xf.basis * (normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]])).normalized().y
		else:
			up = absf((b - a).cross(c - a).normalized().y)
		var triangle := PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]])
		if center.y >= y_min and up > .55 and center.z >= z0 and center.z <= z1 and absf(center.x) <= half:
			roof_indices.append_array(triangle)
		else:
			body_indices.append_array(triangle)
	if roof_indices.size() < 6 or body_indices.size() < 6:
		_roof_cuts[key] = {}
		return {}
	var body := ArrayMesh.new()
	for j in mesh.get_surface_count():
		# A superfície cortada já foi lida acima: cada leitura de malha volta da GPU e trava o quadro.
		var other: Array = arrays.duplicate() if j == surface else mesh.surface_get_arrays(j)
		if j == surface: other[Mesh.ARRAY_INDEX] = body_indices
		body.add_surface_from_arrays(mesh.surface_get_primitive_type(j), other)
		body.surface_set_material(j, mesh.surface_get_material(j))
	var roof := ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = roof_indices
	roof.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result := {"body": body, "roof": roof}
	_roof_cuts[key] = result
	return result

## O console e o volante do modelo da empilhadeira ficam a 30 cm do banco, com o bloco do
## console na altura dos joelhos: o piloto não cabe. O interior traz uma coluna estreita e
## o volante mais à frente; estas peças (identificadas por material e caixa) saem de vista.
static func _hide_forklift_console(visual: Node3D) -> void:
	var targets := [
		AABB(Vector3(-.30, .68, -.08), Vector3(.60, .34, .26)),
		AABB(Vector3(.06, .98, .04), Vector3(.04, .28, .22)),
		AABB(Vector3(-.10, 1.13, .09), Vector3(.36, .24, .32)),
	]
	for part in visual.get_children():
		if not part is MeshInstance3D or part.mesh == null or part.has_meta("wheel_center"): continue
		var box: AABB = part.transform * part.mesh.get_aabb()
		for target in targets:
			if absf(box.position.x - target.position.x) < .03 and absf(box.position.y - target.position.y) < .03 and absf(box.position.z - target.position.z) < .03 \
					and absf(box.size.x - target.size.x) < .04 and absf(box.size.y - target.size.y) < .04 and absf(box.size.z - target.size.z) < .04:
				part.visible = false

static func _interior_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.resource_name = "interior"
		_material.vertex_color_use_as_albedo = true
		# Cores escritas em sRGB (hex), como no kit de props.
		_material.vertex_color_is_srgb = true
		_material.roughness = .86
	return _material

static var _alpha_tool: SurfaceTool
static var _alpha_material: StandardMaterial3D

static func mesh_for(id: String, s: Dictionary) -> ArrayMesh:
	if _meshes.has(id): return _meshes[id]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	# Segunda superficie: o forro do teto, translucido, para nao esconder o motorista de cima.
	_alpha_tool = SurfaceTool.new()
	_alpha_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_alpha_tool.set_smooth_group(-1)
	match str(s.kind):
		"forklift": _forklift(t, s)
		"buggy": _buggy(t, s)
		"bus": _bus(t, s)
		_: _cabin(t, s)
	t.generate_normals()
	var mesh := t.commit()
	mesh.surface_set_material(0, _interior_material())
	if _alpha_tool != null:
		_alpha_tool.generate_normals()
		_alpha_tool.commit(mesh)
		if mesh.get_surface_count() > 1:
			if _alpha_material == null:
				_alpha_material = _interior_material().duplicate() as StandardMaterial3D
				_alpha_material.resource_name = "interior_alpha"
				_alpha_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.surface_set_material(1, _alpha_material)
	_alpha_tool = null
	_meshes[id] = mesh
	return mesh

# --- Motorista ----------------------------------------------------------------------------

## Posiciona o Actor no banco e resolve pernas e braços uma vez. O NÓ do Actor fica sobre o
## veículo (mesma origem e base: `world.player.position` continua sendo a posição do carro,
## que dezenas de sistemas leem); só o `visual` desliza até o banco, então a pose vale
## enquanto ele dirigir.
## A mistura parte de onde o corpo está agora (pose, quadril e escala do último quadro da
## animação de entrada) para o banco, em vez de estalar. `blend_seconds` = 0 assenta direto.
static func seat_driver(actor: CharacterBody3D, vehicle: Node3D, blend_seconds := 0.0) -> void:
	var s := spec(vehicle)
	if s.is_empty(): return
	var from_pose: Array = actor._capture_pose() if blend_seconds > 0.0 and is_instance_valid(actor.skeleton) else []
	# Quadril e escala de partida: o corpo começa a mistura exatamente onde estava.
	var from_pelvis := pelvis_world(actor)
	var from_scale: Vector3 = actor.visual.scale
	var from_pelvis_local := Vector3.ZERO
	if not from_pose.is_empty():
		from_pelvis_local = actor.visual.global_basis.orthonormalized().inverse() * (from_pelvis - actor.visual.global_position)
	actor.global_transform = vehicle.global_transform
	actor.visual.rotation = Vector3.ZERO
	# Cabine baixa demais para o Dante de tamanho cheio: o corpo encolhe (ver `_fit`).
	actor.visual.scale = Vector3.ONE * float(s.scale)
	actor.visual.position = Vector3.ZERO
	var pelvis: Vector3 = actor.pose_seated_base(float(s.rec))
	var hip_target := Vector3(float(s.sx), float(s.floor) + float(s.hip), float(s.sz))
	# `pelvis` é o centro do quadril da pose no espaço do Actor: o visual anda o resto.
	var origin: Vector3 = hip_target - pelvis
	actor.visual.position = origin
	var targets := _limb_targets(s)
	actor.pose_seated_limbs(targets.feet, targets.hands)
	var state := {"origin": origin, "age": 0.0, "duration": blend_seconds}
	var start := origin
	if not from_pose.is_empty():
		# Vem da animação de entrada (pose de sentar genérica): mistura em vez de estalar.
		state["from_pose"] = from_pose
		state["to_pose"] = actor._capture_pose()
		start = vehicle.to_local(from_pelvis - vehicle.global_basis * from_pelvis_local)
		state["from_origin"] = start
		state["from_scale"] = from_scale
		state["to_scale"] = actor.visual.scale
		actor._apply_blend(from_pose, state.to_pose, 0.0)
		# O corpo mantém a escala da animação e vai para a do banco junto com a mistura.
		actor.visual.scale = from_scale
	actor.set_meta("seated_state", state)
	actor.visual.position = start
	actor.reset_physics_interpolation()

## Duração da mistura da pose da animação de entrada para a de motorista (e da de motorista para
## a de saída).
const SEAT_BLEND_SECONDS := 0.22

## Centro do quadril em coordenadas do mundo (média das juntas das coxas).
static func pelvis_world(actor: CharacterBody3D) -> Vector3:
	var skeleton: Skeleton3D = actor.skeleton
	if skeleton == null: return actor.global_position + Vector3.UP * STANDING_HIP
	var left := skeleton.to_global(skeleton.get_bone_global_pose(actor._combat_bones["LeftUpLeg"]).origin)
	var right := skeleton.to_global(skeleton.get_bone_global_pose(actor._combat_bones["RightUpLeg"]).origin)
	return (left + right) * 0.5

## Um tique de física: o corpo acompanha o veículo (incl. inclinação de rampa).
static func follow(actor: CharacterBody3D, vehicle: Node3D, delta: float) -> void:
	var state: Dictionary = actor.get_meta("seated_state", {})
	if state.is_empty(): return
	var origin: Vector3 = state.origin
	if state.has("from_pose"):
		state["age"] = float(state.age) + delta
		var k := clampf(float(state.age) / maxf(float(state.duration), 0.001), 0.0, 1.0)
		var eased := smoothstep(0.0, 1.0, k)
		actor._apply_blend(state.from_pose, state.to_pose, eased)
		origin = (state.from_origin as Vector3).lerp(origin, eased)
		actor.visual.scale = (state.from_scale as Vector3).lerp(state.to_scale, eased)
		if k >= 1.0:
			state.erase("from_pose")
			state.erase("to_pose")
	actor.global_transform = vehicle.global_transform
	actor.visual.position = origin

## Alvos de pé e mão no espaço do Actor, que coincide com o do veículo (mesma origem e base).
static func _limb_targets(s: Dictionary) -> Dictionary:
	var feet := {}
	var hands := {}
	var sx := float(s.sx)
	var ankle_y := float(s.floor) + .06 + .05 * float(s.scale)
	var scale := float(s.scale)
	var foot_z := float(s.sz) - float(s.foot_dist)
	var kind := str(s.kind)
	var spread := (.13 if kind != "forklift" else .21) * scale
	feet["Left"] = Vector3(sx - spread, ankle_y, foot_z)
	feet["Right"] = Vector3(sx + spread, ankle_y, foot_z - (.04 if kind != "forklift" else .0))
	# Volante: plano com a face voltada para o motorista e levemente para cima.
	var tilt := float(s.tilt)
	var u := Vector3.RIGHT
	var v := Vector3(0, cos(tilt), -sin(tilt))
	var n := Vector3(0, sin(tilt), cos(tilt))
	var hub := Vector3(sx, float(s.hub_y), float(s.hub_z))
	var r := float(s.r)
	var grip := deg_to_rad(float(s.grip))
	for side in ["Left", "Right"]:
		var angle := grip if side == "Left" else PI - grip
		var radial := u * cos(angle) + v * sin(angle)
		var tangent := -u * sin(angle) + v * cos(angle)
		# Y ao longo do aro, apontando para fora do corpo (mesma convenção do guidão); Z volta ao motorista.
		var axis_y := tangent if side == "Left" else -tangent
		var basis_z := n
		var basis_x := axis_y.cross(basis_z).normalized()
		basis_z = basis_x.cross(axis_y).normalized()
		hands[side] = Transform3D(Basis(basis_x, axis_y, basis_z), hub + radial * r)
	if kind == "forklift":
		# Mão esquerda na alavanca hidráulica do modelo, direita no volante (sem girar o aro).
		hands.erase("Left")
	return {"feet": feet, "hands": hands}

# --- Geometria ----------------------------------------------------------------------------

const C_DASH := Color("24272b")
const C_DASH_TOP := Color("30343a")
const C_SEAT := Color("8a7860")
const C_SEAT_DARK := Color("54493c")
const C_TRIM := Color("1a1c1f")
const C_CARPET := Color("2b2d30")
const C_ROOF := Color("bfb7a6")
const C_CHROME := Color("c3c9cd")
const C_RUBBER := Color("101214")
const C_BELT := Color("15171a")
const C_DIAL := Color("cfe3ee")
const C_AMBER := Color("e0a030")

static func _box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var h := size * .5
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	t.set_color(color)
	for face in faces:
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[1]]); t.add_vertex(corners[face[2]])
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[2]]); t.add_vertex(corners[face[3]])

static func _tube(t: SurfaceTool, from: Vector3, to: Vector3, radius: float, color: Color, sides := 6) -> void:
	var axis := to - from
	if axis.length() < .001: return
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < .95 else Vector3.RIGHT).normalized()
	var other := up.cross(side).normalized()
	t.set_color(color)
	for i in sides:
		var p0 := (side * cos(TAU * i / sides) + other * sin(TAU * i / sides)) * radius
		var p1 := (side * cos(TAU * (i + 1) / sides) + other * sin(TAU * (i + 1) / sides)) * radius
		t.add_vertex(from + p0); t.add_vertex(to + p0); t.add_vertex(to + p1)
		t.add_vertex(from + p0); t.add_vertex(to + p1); t.add_vertex(from + p1)
		t.add_vertex(to); t.add_vertex(to + p1); t.add_vertex(to + p0)
		t.add_vertex(from); t.add_vertex(from + p0); t.add_vertex(from + p1)

## Base do plano do volante: X para a direita, Y no plano para cima, Z para o motorista.
static func _wheel_basis(tilt: float) -> Basis:
	return Basis(Vector3.RIGHT, Vector3(0, cos(tilt), -sin(tilt)), Vector3(0, sin(tilt), cos(tilt)))

static func _steering_wheel(t: SurfaceTool, hub: Vector3, radius: float, tilt: float, rim: Color, column_to: Vector3) -> void:
	var b := _wheel_basis(tilt)
	var segments := 14
	var arc := TAU * radius / segments * 1.12
	var thickness := .036 if radius < .22 else .046
	for i in segments:
		var a := TAU * (i + .5) / segments
		var local_basis := b * Basis(Vector3.BACK, a)
		_box(t, hub + b * Vector3(cos(a), sin(a), 0) * radius, Vector3(thickness, arc, thickness), rim, local_basis)
	# Miolo e três raios (T): esquerdo, direito e inferior.
	_box(t, hub, Vector3(radius * .5, radius * .5, .05), C_TRIM, b)
	_box(t, hub + b * Vector3(0, 0, .032), Vector3(radius * .26, radius * .26, .02), C_CHROME, b)
	for a in [0.0, PI, PI * 1.5]:
		_box(t, hub + b * Vector3(cos(a), sin(a), 0) * radius * .5, Vector3(radius * .9, .04, .03), C_TRIM, b * Basis(Vector3.BACK, a))
	_tube(t, hub - b.z * .04, column_to, .034, C_TRIM, 6)

## Banco com encosto inclinado, apoio de cabeça e laterais.
static func _seat(t: SurfaceTool, x: float, z: float, cush: float, recline: float, width: float, color: Color, headrest := true, tall := 0.0) -> void:
	_box(t, Vector3(x, cush - .07, z), Vector3(width, .14, .50), color)
	# Base do banco / trilho.
	_box(t, Vector3(x, cush - .17, z), Vector3(width * .7, .06, .40), C_TRIM)
	var tilt := Basis(Vector3.RIGHT, recline + .05)
	var base := Vector3(x, cush, z + .23)
	var back_h := .58 + tall
	_box(t, base + tilt * Vector3(0, back_h * .5, 0), Vector3(width, back_h, .11), color, tilt)
	for side in [-1.0, 1.0]:
		_box(t, base + tilt * Vector3(side * (width * .5 - .03), back_h * .46, -.07), Vector3(.07, back_h * .8, .09), C_SEAT_DARK, tilt)
		_box(t, Vector3(x + side * (width * .5 - .03), cush + .02, z - .05), Vector3(.07, .07, .40), C_SEAT_DARK)
	if headrest:
		_box(t, base + tilt * Vector3(0, back_h + .1, -.005), Vector3(width * .42, .17, .10), color.darkened(.08), tilt)
		for side in [-1.0, 1.0]:
			_tube(t, base + tilt * Vector3(side * width * .12, back_h - .02, 0), base + tilt * Vector3(side * width * .12, back_h + .04, 0), .012, C_CHROME, 4)

## Cinto de três pontos do motorista: a tira sai do ombro externo e desce em diagonal pela
## frente do peito até a fivela do lado do console.
static func _belt(t: SurfaceTool, s: Dictionary) -> void:
	var rec := float(s.rec) + .05
	var hip := Vector3(float(s.sx), float(s.floor) + float(s.hip), float(s.sz))
	var scale := float(s.scale)
	var d := Vector3(0, cos(rec), sin(rec))
	var n := Vector3(0, sin(rec), -cos(rec))
	var top := hip + d * .50 * scale + n * .17 * scale + Vector3(-.15, 0, 0) * scale
	var low := hip + d * .06 * scale + n * .19 * scale + Vector3(.13, 0, 0) * scale
	var mid := (top + low) * .5
	var axis := (low - top)
	var length := axis.length()
	var y_dir := axis / length
	var x_dir := Vector3(y_dir.y, -y_dir.x, 0).normalized()
	var z_dir := x_dir.cross(y_dir).normalized()
	_box(t, mid, Vector3(.05, length, .012), C_BELT, Basis(x_dir, y_dir, z_dir))
	_box(t, low + Vector3(.01, -.01, 0), Vector3(.06, .05, .03), C_CHROME)

## Cabine comum: carro, esportivo, SUV, picape, van e caminhão.
static func _cabin(t: SurfaceTool, s: Dictionary) -> void:
	var w := float(s.w)
	var sx := float(s.sx)
	var sz := float(s.sz)
	var floor_y := float(s.floor)
	var cush := float(s.cush)
	var belt := float(s.belt)
	var roof := float(s.roof)
	var wz0 := float(s.wz0)
	var wz1 := float(s.wz1)
	var rear := float(s.rear)
	var rec := float(s.rec)
	var kind := str(s.kind)
	var open_top := bool(s.open_top)
	var big := kind in ["truck", "van"]
	var seat_w := .52 if not big else .58
	var seat_color := C_SEAT
	# Piso e túnel central.
	var floor_back := rear - .12
	_box(t, Vector3(0, floor_y - .01, (wz0 + floor_back) * .5), Vector3(w * 2 - .04, .03, floor_back - wz0), C_CARPET)
	# Painel: bloco do para-brisa até a coluna de direção, com topo na linha da cintura.
	var dash_top := belt - .03
	var dash_back := float(s.hub_z) - float(s.r) * .55 - .04
	var dash_front := wz0 - .04
	var dash_depth := maxf(dash_back - dash_front, .2)
	_box(t, Vector3(0, (dash_top + floor_y) * .5, dash_front + dash_depth * .5), Vector3(w * 2 - .02, dash_top - floor_y, dash_depth), C_DASH)
	_box(t, Vector3(0, dash_top + .005, dash_front + dash_depth * .5), Vector3(w * 2 - .04, .02, dash_depth - .04), C_DASH_TOP)
	# Saídas de ar e alto-falante no topo do painel.
	for x in [sx * 1.0, sx * .35, -sx * .35, -sx * 1.0]:
		_box(t, Vector3(x, dash_top + .022, dash_front + .1), Vector3(.13, .012, .05), C_TRIM)
	_box(t, Vector3(0, dash_top + .022, dash_front + .13), Vector3(.18, .012, .07), C_TRIM)
	# Capelo do painel de instrumentos, com mostradores voltados para o motorista.
	var hub_z := float(s.hub_z)
	var cluster_z := dash_back - .05
	_box(t, Vector3(sx, dash_top + .06, cluster_z), Vector3(.46, .11, .22), C_TRIM, Basis(Vector3.RIGHT, .18))
	for dx in [-.11, .11]:
		_box(t, Vector3(sx + dx, dash_top + .07, cluster_z + .114), Vector3(.13, .075, .012), C_DIAL, Basis(Vector3.RIGHT, .18))
	_box(t, Vector3(sx, dash_top + .07, cluster_z + .114), Vector3(.05, .05, .012), C_AMBER, Basis(Vector3.RIGHT, .18))
	# Console de rádio e climatização, e luvas do passageiro.
	_box(t, Vector3(0, dash_top - .14, dash_back - .02), Vector3(.30, .26, .12), Color("2e3136"))
	_box(t, Vector3(0, dash_top - .08, dash_back + .045), Vector3(.24, .09, .01), Color("8b959c"))
	for kx in [-.08, 0.0, .08]:
		_box(t, Vector3(kx, dash_top - .19, dash_back + .045), Vector3(.045, .045, .02), C_CHROME)
	_box(t, Vector3(-sx, dash_top - .13, dash_back + .015), Vector3(.40, .012, .012), Color("0f1012"))
	_box(t, Vector3(-sx, dash_top - .27, dash_back + .015), Vector3(.40, .012, .012), Color("0f1012"))
	# Volante e coluna.
	var column_to := Vector3(sx, float(s.hub_y) - .30, hub_z - .18)
	_steering_wheel(t, Vector3(sx, float(s.hub_y), hub_z), float(s.r), float(s.tilt), C_TRIM, column_to)
	# Pedais (freio, acelerador e apoio do pé esquerdo).
	var pedal_z := sz - float(s.foot_dist) - .05
	for entry in [[sx - .13, .07, .05], [sx + .02, .05, .045], [sx + .15, .08, .04]]:
		_box(t, Vector3(entry[0], floor_y + .12, pedal_z), Vector3(entry[1], .015 + entry[2], .12), C_RUBBER, Basis(Vector3.RIGHT, .7))
	# Bancos dianteiros e cinto.
	_seat(t, sx, sz, cush, rec, seat_w, seat_color, true, .05 if big else 0.0)
	_seat(t, -sx, sz, cush, rec, seat_w, seat_color, true, .05 if big else 0.0)
	_belt(t, s)
	# Console central: túnel, câmbio, freio de mão e porta-copos.
	_box(t, Vector3(0, floor_y + .11, sz - .05), Vector3(.22, .22, .78), Color("23262a"))
	_box(t, Vector3(0, floor_y + .225, sz - .05), Vector3(.2, .02, .74), Color("30343a"))
	var shift_top := Vector3(0, floor_y + (.52 if kind == "truck" else .36), sz - .28)
	_tube(t, Vector3(0, floor_y + .23, sz - .22), shift_top, .014, C_CHROME, 5)
	_box(t, shift_top + Vector3(0, .02, 0), Vector3(.05, .05, .05), C_TRIM)
	_box(t, Vector3(0, floor_y + .26, sz + .12), Vector3(.17, .05, .08), C_TRIM, Basis(Vector3.RIGHT, -.35))
	for cx in [-.05, .05]:
		_box(t, Vector3(cx, floor_y + .235, sz + .22), Vector3(.06, .012, .06), C_RUBBER)
	# Bancos traseiros: banco corrido com três apoios de cabeça.
	if bool(s.rows) and rear - sz > 1.3 and not big and not open_top:
		var rz := minf(rear - .44, sz + .98)
		_box(t, Vector3(0, cush - .09, rz), Vector3(w * 2 - .16, .14, .50), seat_color)
		var tilt := Basis(Vector3.RIGHT, .16)
		_box(t, Vector3(0, cush + .26, rz + .24), Vector3(w * 2 - .16, .58, .10), seat_color, tilt)
		for hx in [-w * .5, 0.0, w * .5]:
			_box(t, Vector3(hx, cush + .62, rz + .225), Vector3(.18, .15, .09), seat_color.darkened(.08), tilt)
	elif big and kind == "van":
		# Cabine de van: banco do passageiro em dois lugares e divisória atrás.
		_box(t, Vector3(0, cush + .28, rear + .05), Vector3(w * 2 - .04, .7, .05), Color("3a3d42"))
	# Porta-luvas, painéis de porta e apoio de braço.
	for side in [-1.0, 1.0]:
		var cardx: float = side * (w - .015)
		_box(t, Vector3(cardx, (floor_y + belt - .12) * .5 + .02, (wz0 + floor_back) * .5 + .05), Vector3(.03, belt - floor_y - .1, floor_back - wz0 - .3), C_TRIM)
		_box(t, Vector3(cardx - side * .03, belt - .13, sz + .05), Vector3(.07, .05, .36), Color("3a3d42"))
		_box(t, Vector3(cardx - side * .02, belt - .04, (wz0 + floor_back) * .5 + .05), Vector3(.05, .03, floor_back - wz0 - .34), Color("2b2e33"))
	if open_top: return
	# Forro do teto sob o teto, com luz de cortesia; quebra-sóis e retrovisor interno.
	var roof_z0 := wz1 - .02
	var roof_z1 := minf(rear - .1, floor_back)
	_box(_alpha_tool, Vector3(0, roof - .04, (roof_z0 + roof_z1) * .5), Vector3(w * 2 - .06, .03, roof_z1 - roof_z0), Color(C_ROOF, .30))
	_box(t, Vector3(0, roof - .058, sz + .1), Vector3(.14, .012, .09), Color("f0ecdc"))
	for vx in [sx, -sx]:
		_box(t, Vector3(vx, roof - .075, wz1 + .16), Vector3(.36, .018, .17), Color("a29b8b"))
	var mirror_top := Vector3(0, roof - .1, wz1 + .04)
	_tube(t, mirror_top, mirror_top + Vector3(0, -.06, .06), .012, C_TRIM, 4)
	_box(t, mirror_top + Vector3(0, -.09, .075), Vector3(.22, .06, .03), C_TRIM)
	_box(t, mirror_top + Vector3(0, -.09, .092), Vector3(.19, .045, .005), Color("8fa2ad"))
	# Colunas A e traseira (acabamento interno) — linhas escuras ao longo das janelas.
	for side in [-1.0, 1.0]:
		_box(t, Vector3(side * (w - .03), roof - .05, (roof_z0 + roof_z1) * .5), Vector3(.05, .04, roof_z1 - roof_z0), C_TRIM)

## Ônibus: cabine do motorista alta, volante quase deitado, corredor com bancos duplos,
## barras de apoio e luminárias. Uma malha só para o veículo inteiro.
static func _bus(t: SurfaceTool, s: Dictionary) -> void:
	_cabin(t, s)
	var w := float(s.w)
	var floor_y := float(s.floor)
	var roof := float(s.roof)
	var sz := float(s.sz)
	var rear := float(s.rear)
	var seat_color := Color("3d6a8a")
	var z := sz + 1.5
	while z < rear - .6:
		# Dois lugares por lado do corredor: um junto da janela e outro junto do corredor.
		for side in [-1.0, 1.0]:
			for lane in [w - .27, .52]:
				_seat(t, side * float(lane), z, floor_y + .42, .0, .44, seat_color, false, .05)
		z += 1.05
	# Barras de apoio verticais e corrimão longitudinal no teto.
	for side in [-1.0, 1.0]:
		var rail_x: float = side * .12
		_tube(t, Vector3(rail_x, roof - .16, sz + 1.2), Vector3(rail_x, roof - .16, rear - .4), .022, C_CHROME, 5)
		var pz := sz + 1.2
		while pz < rear - .5:
			_tube(t, Vector3(rail_x, floor_y, pz), Vector3(rail_x, roof - .16, pz), .02, Color("d9a322"), 5)
			pz += 2.1
	# Luminárias de teto.
	var lz := sz + 1.0
	while lz < rear - .3:
		_box(t, Vector3(0, roof - .07, lz), Vector3(.5, .015, .16), Color("f3efe0"))
		lz += 1.5
	# Cofre / catraca junto ao motorista.
	_box(t, Vector3(float(s.sx) + .62, floor_y + .5, sz - .4), Vector3(.3, 1.0, .3), Color("2f3338"))
	# Banco traseiro corrido.
	_seat(t, 0.0, rear - .5, floor_y + .42, .0, w * 1.6, seat_color, false, .05)

## Buggy: dois bancos concha, volante, alavanca de câmbio e cintos; sem painel nem teto.
static func _buggy(t: SurfaceTool, s: Dictionary) -> void:
	var sx := float(s.sx)
	var sz := float(s.sz)
	var cush := float(s.cush)
	var floor_y := float(s.floor)
	_seat_shell(t, sx, sz, cush, Color("2d2924"))
	_seat_shell(t, -sx, sz, cush, Color("2d2924"))
	# Painel baixo e coluna de direção.
	var hub_z := float(s.hub_z)
	_box(t, Vector3(0, floor_y + .35, hub_z - .12), Vector3(1.0, .22, .18), C_DASH)
	_box(t, Vector3(sx, floor_y + .49, hub_z - .1), Vector3(.30, .06, .12), C_TRIM, Basis(Vector3.RIGHT, .3))
	for dx in [-.06, .06]:
		_box(t, Vector3(sx + dx, floor_y + .5, hub_z - .03), Vector3(.07, .05, .01), C_DIAL, Basis(Vector3.RIGHT, .3))
	var column_to := Vector3(sx, float(s.hub_y) - .3, hub_z - .2)
	_steering_wheel(t, Vector3(sx, float(s.hub_y), hub_z), float(s.r), float(s.tilt), C_TRIM, column_to)
	# Câmbio e freio de mão no túnel entre os bancos.
	_box(t, Vector3(0, floor_y + .16, sz - .1), Vector3(.2, .22, .8), Color("23262a"))
	_tube(t, Vector3(0, floor_y + .27, sz - .2), Vector3(0, floor_y + .46, sz - .32), .016, C_CHROME, 5)
	_box(t, Vector3(0, floor_y + .48, sz - .33), Vector3(.06, .06, .06), C_TRIM)
	# Pedais.
	var pedal_z := sz - float(s.foot_dist) - .06
	for x in [sx - .12, sx + .03, sx + .15]:
		_box(t, Vector3(x, floor_y + .1, pedal_z), Vector3(.07, .05, .13), C_RUBBER, Basis(Vector3.RIGHT, .7))
	_belt(t, s)

static func _seat_shell(t: SurfaceTool, x: float, z: float, cush: float, color: Color) -> void:
	_box(t, Vector3(x, cush - .08, z), Vector3(.42, .16, .48), color)
	var tilt := Basis(Vector3.RIGHT, .32)
	_box(t, Vector3(x, cush + .30, z + .30), Vector3(.42, .62, .11), color, tilt)
	_box(t, Vector3(x, cush + .68, z + .37), Vector3(.24, .16, .09), color.lightened(.06), tilt)
	for side in [-1.0, 1.0]:
		_box(t, Vector3(x + side * .2, cush + .08, z + .02), Vector3(.06, .2, .5), color.darkened(.1))

## Empilhadeira: coluna de direção estreita entre os joelhos, volante pequeno com manopla,
## painel, alavancas, pedais, capa do banco e cinto abdominal. A proteção superior e o
## banco são do modelo.
static func _forklift(t: SurfaceTool, s: Dictionary) -> void:
	var sz := float(s.sz)
	var floor_y := float(s.floor)
	var hub_z := float(s.hub_z)
	var hub_y := float(s.hub_y)
	# Capa do banco e apoio lombar por cima do estofado do modelo.
	_box(t, Vector3(0, float(s.cush) + .02, sz), Vector3(.5, .045, .48), C_SEAT_DARK)
	var lean := Basis(Vector3.RIGHT, .1)
	_box(t, Vector3(0, float(s.cush) + .40, sz + .15), Vector3(.46, .5, .04), C_SEAT_DARK, lean)
	# Pedestal do painel e coluna.
	_box(t, Vector3(0, floor_y + .17, hub_z - .28), Vector3(.24, .34, .16), Color("2a2d31"))
	_box(t, Vector3(0, hub_y - .27, hub_z - .12), Vector3(.30, .10, .20), C_DASH, Basis(Vector3.RIGHT, -.25))
	for dx in [-.07, .07]:
		_box(t, Vector3(dx, hub_y - .21, hub_z - .03), Vector3(.08, .06, .01), C_DIAL, Basis(Vector3.RIGHT, -.25))
	var column_to := Vector3(0, hub_y - .25, hub_z - .12)
	_steering_wheel(t, Vector3(0, hub_y, hub_z), float(s.r), float(s.tilt), C_TRIM, column_to)
	# Manopla do volante (spinner).
	var b := _wheel_basis(float(s.tilt))
	_box(t, Vector3(0, hub_y, hub_z) + b * Vector3(-float(s.r) * .8, float(s.r) * .35, .035), Vector3(.05, .05, .06), C_AMBER, b)
	# Pedais e piso antiderrapante.
	_box(t, Vector3(0, floor_y + .008, hub_z - .05), Vector3(.62, .012, .5), Color("3a3d42"))
	for x in [-.2, .2]:
		_box(t, Vector3(x, floor_y + .06, hub_z - .18), Vector3(.09, .04, .12), C_RUBBER, Basis(Vector3.RIGHT, .7))
	# Alavancas do hidráulico à direita e apoio de braço.
	for i in 3:
		var lx := .28 + i * .0
		var lz := sz - .34 + i * .11
		_tube(t, Vector3(lx, float(s.cush) + .12, lz), Vector3(lx - .02, float(s.cush) + .36, lz - .03), .012, C_CHROME, 5)
		_box(t, Vector3(lx - .02, float(s.cush) + .38, lz - .03), Vector3(.035, .035, .035), [C_AMBER, Color("c0392b"), Color("2e86c1")][i])
	_box(t, Vector3(.29, float(s.cush) + .08, sz - .22), Vector3(.1, .09, .5), C_TRIM)
	# Cinto abdominal.
	_box(t, Vector3(0, float(s.cush) + .16, sz - .02), Vector3(.5, .03, .014), C_BELT)
	_box(t, Vector3(0, float(s.cush) + .16, sz - .03), Vector3(.06, .05, .02), C_CHROME)
	# Luz de trabalho / girofle no console da proteção: pequeno painel de comandos.
	_box(t, Vector3(0, 1.98, sz - .5), Vector3(.24, .05, .1), C_TRIM)
