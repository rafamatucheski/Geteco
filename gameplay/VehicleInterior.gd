extends RefCounted
## Interior visível e motorista sentado ao volante.
##
## Até aqui quem dirigia sumia (`world.player.hide()`) e os vidros dos modelos eram opacos:
## o carro andava "vazio" e a empilhadeira nem tinha piloto. Este módulo dá ao veículo que o
## jogador conduz (a) um interior de uma malha só (volante, painel, bancos, console, pedais,
## retrovisor, forro, cintos) e a pose de
## motorista sentado com as mãos no volante.
##
## Custo: uma `MeshInstance3D` por veículo conduzido, malha em cache por arquétipo, sem
## colisão, sem nó por peça e sem script por quadro. O corpo do motorista acompanha o
## veículo com uma atribuição de transform por tique de física (`follow`).
##
## Só o veículo que o jogador entra recebe interior; os vidros conservam os materiais originais.
## O trânsito segue
## com os modelos achatados, de vidro opaco, como antes.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Malha da cabine e teto recortado em auxiliares estáticos (01/11, Onda 2 do plano de divisão);
## cada função antiga que alguém chama continua aqui como delegação de uma linha.
const CABIN_MESH := preload("res://gameplay/VehicleCabinMesh.gd")
const ROOF_CUT := preload("res://gameplay/VehicleRoofCut.gd")

## Altura do quadril (junta da coxa) do Dante de pé sobre a sola. Medido no esqueleto.
const STANDING_HIP := 0.77
## Opacidade do teto do veículo conduzido (textura constante, ver `_roof_alpha_texture`).
const ROOF_ALPHA := 0.30

# --- Classes de cabine -------------------------------------------------------------------
## KINDS, KIND_OF e OVERRIDES (com a legenda das colunas) moram em dados; ficam reexportados aqui
## com o mesmo nome.
const TABLES := preload("res://data/catalogs/VehicleInteriorKinds.gd")
const KINDS := TABLES.KINDS
const KIND_OF := TABLES.KIND_OF
const OVERRIDES := TABLES.OVERRIDES

static var _specs: Dictionary = {}
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D
## Vértices dos vidros por malha ("id:superfície" -> {ref, vertices}), lidos sob a cortina por
## `cache_glass`. `surface_get_arrays` lê o buffer de volta da GPU e espera os quadros em voo: na
## serra (17/10) a primeira medição da cabine do summit_suv estacionado, ao passar a 1,8 m da porta
## (Driving._process -> prewarm -> spec), custou um quadro de 47 ms. GETECO_INTERIOR_SPEC_CACHE=0
## volta à leitura direta, para A/B.
static var spec_cache := OS.get_environment("GETECO_INTERIOR_SPEC_CACHE") != "0"
static var _glass_vertices: Dictionary = {}
## Arrays de contato na CPU compartilhados pelos modelos; preenchidos junto com os vidros sob a cortina de carregamento.
static var _contact_arrays: Dictionary = {}
const GLASS_CACHE_PRUNE := 512

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
	var began := STALL_WORK.begin()
	var s := _derive(vehicle)
	STALL_WORK.finish_slow("vehicle.interior.spec", began, 2000, vehicle)
	_specs[id] = s
	return s

## Sob a cortina: lê uma vez para a CPU os vidros do modelo da frota (malhas compartilhadas por
## todas as instâncias do arquétipo), para `_derive` em jogo não voltar à GPU.
static func cache_glass(model: Node3D) -> void:
	if not spec_cache or not enabled or not is_instance_valid(model): return
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center"): continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			contact_arrays(mesh, surface)
			if material != null and _is_glass(part, surface, material): _glass_points(mesh, surface)

## O recorte da porta troca a malha da peça por uma nova montada na CPU: se a original já estava
## no cache, a nova herda os vértices que o recorte acabou de usar, sem leitura de GPU.
static func inherit_glass(original: Mesh, replacement: Mesh, surface: int, arrays: Array) -> void:
	if original == null or replacement == null: return
	remember_contact(replacement, surface, arrays)
	if not spec_cache: return
	if not _glass_vertices.has("%d:%d" % [original.get_instance_id(), surface]): return
	if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return
	_remember_glass(replacement, surface, arrays[Mesh.ARRAY_VERTEX])

static func _glass_points(mesh: Mesh, surface: int) -> PackedVector3Array:
	if not spec_cache: return mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var entry: Variant = _glass_vertices.get("%d:%d" % [mesh.get_instance_id(), surface])
	if entry != null and entry.ref.get_ref() == mesh: return entry.vertices
	var vertices: PackedVector3Array = contact_arrays(mesh, surface)[Mesh.ARRAY_VERTEX]
	_remember_glass(mesh, surface, vertices)
	return vertices

static func contact_arrays(mesh: Mesh, surface: int) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(),surface]
	var entry: Variant = _contact_arrays.get(key)
	if entry != null and entry.ref.get_ref() == mesh: return entry.arrays
	var arrays := MESH_ARRAYS.arrays_of(mesh, surface)
	remember_contact(mesh,surface,arrays)
	return arrays

static func remember_contact(mesh: Mesh, surface: int, arrays: Array) -> void:
	if _contact_arrays.size() >= GLASS_CACHE_PRUNE:
		for key in _contact_arrays.keys():
			if _contact_arrays[key].ref.get_ref() == null: _contact_arrays.erase(key)
	_contact_arrays["%d:%d" % [mesh.get_instance_id(),surface]] = {"ref":weakref(mesh),"arrays":arrays}

static func _remember_glass(mesh: Mesh, surface: int, vertices: PackedVector3Array) -> void:
	if _glass_vertices.size() >= GLASS_CACHE_PRUNE:
		# Recortes de porta de carros que já sumiram: só as entradas mortas saem.
		for key in _glass_vertices.keys():
			if _glass_vertices[key].ref.get_ref() == null: _glass_vertices.erase(key)
	_glass_vertices["%d:%d" % [mesh.get_instance_id(), surface]] = {"ref": weakref(mesh), "vertices": vertices}

# --- Especificação ------------------------------------------------------------------------

static func _is_glass(part: MeshInstance3D, surface: int, material: Material) -> bool:
	var key := ROLES.key(part, surface).get_slice("#",0)
	if key in ["glass", "tinted_glass", "windshield", "window"]: return true
	if key in ["smoked_lens", "headlight", "tail", "lens", "brake_light", "paint"]: return false
	var standard := material as StandardMaterial3D
	if standard == null or standard.emission_enabled or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	# Modelos V1 antigos: caixas azul-petróleo sem nome (44616b, 213446, 203b49, 172835...).
	return standard.roughness <= .19 and absf(standard.metallic - .3) <= .06

static func _derive(vehicle: Node3D) -> Dictionary:
	var id := str(vehicle.get("archetype"))
	# Modelos feitos à mão podem descrever o compartimento de passageiros independentemente
	# da geometria dos vidros (recortes de porta e retrovisores externos não são dimensões da cabine).
	var authored: Dictionary = vehicle.visual.get_meta("vehicle_interior_spec", {})
	var kind: String = str(authored.get("kind", KIND_OF.get(id, "car")))
	if not KINDS.has(kind): kind = "car"
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
			var vertices := _glass_points(mesh, surface)
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
	for key in authored: s[key] = authored[key]
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

# --- Montagem no veículo ------------------------------------------------------------------

## Última montagem por etapa (ms), só para medição.
static var profile: Dictionary = {}
static var _warmed: Dictionary = {}
static var _warming: Dictionary = {} # Family -> owner instance_id; no persistent Node references.

## Registra a apresentação da cabine sem alterar vidro, teto ou pintura do modelo.
## A aparência original permanece ao entrar e mudar a câmera. Idempotente.
static func open_view(vehicle: Node3D) -> void:
	var s := spec(vehicle)
	if s.is_empty() or vehicle.get("visual") == null or vehicle.has_meta("interior_view"): return
	var began := Time.get_ticks_usec()
	vehicle.set_meta("interior_view", {"parts": [], "roofs": [], "alpha_materials": [], "slabs": []})
	profile = {"vista_ms": (Time.get_ticks_usec() - began) / 1000.0}
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
		var id := str(vehicle.get("archetype"))
		if CABIN_MESH._wheel_meshes.has(id):
			var wheel := MeshInstance3D.new()
			wheel.name = "SteeringWheel"
			wheel.mesh = CABIN_MESH._wheel_meshes[id]
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wheel.transform = CABIN_MESH._wheel_frames[id]
			wheel.set_meta("frame", CABIN_MESH._wheel_frames[id])
			node.add_child(wheel)
		if str(vehicle.get("archetype")) == "port_forklift": _hide_forklift_console(visual)
	open_view(vehicle)

## Prepara quadro a quadro a medida, malha e materiais originais de vidro de cada arquétipo.
## Instâncias temporárias fora da vista preparam recursos de superfície; não garantem
## o pipeline de desenho da primeira exibição. Família só fica concluída após terminar.
static func prewarm(vehicle: Node3D) -> void:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree() or not shows_driver(vehicle): return
	var id := str(vehicle.get("archetype"))
	if _warmed.has(id): return
	var pending_id := int(_warming.get(id, 0))
	if pending_id != 0 and is_instance_id_valid(pending_id):
		var pending := instance_from_id(pending_id) as Node3D
		if pending != null and pending.is_inside_tree(): return
	# Sem fila de waiters: duplicatas retornam cedo; se o dono sumiu, um pedido
	# novo retoma os caches parciais. O token impede a tarefa antiga de apagá-lo.
	var request_id := vehicle.get_instance_id()
	_warming[id] = request_id
	var tree := vehicle.get_tree()
	var s := spec(vehicle)
	if s.is_empty():
		_finish_warming(id, request_id, false)
		return
	await tree.process_frame
	if int(_warming.get(id, 0)) != request_id: return
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		_finish_warming(id, request_id, false)
		return
	mesh_for(id, s)
	var warm: Array = []
	for part in vehicle.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name in ["Interior", "RoofCut", "WarmUp"]: continue
		if part.material_override is StandardMaterial3D and _is_glass(part, 0, part.material_override):
			warm.append([mesh, part.material_override])
			continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material is StandardMaterial3D and _is_glass(part, surface, material): warm.append([mesh, material])
	var completed := await _warm_materials(vehicle, warm)
	_finish_warming(id, request_id, completed)

static func _finish_warming(id: String, request_id: int, completed: bool) -> void:
	if int(_warming.get(id, 0)) != request_id: return
	if completed: _warmed[id] = true
	_warming.erase(id)

## Associa variantes às malhas reais por dois quadros para preparar recursos.
## As instâncias ficam fora da vista; a primeira exibição ainda pode compilar Draw.
## Cancelamento remove os temporários e permite que outro veículo tente novamente.
static func _warm_materials(vehicle: Node3D, entries: Array) -> bool:
	var tree := vehicle.get_tree()
	var nodes: Array[MeshInstance3D] = []
	for entry in entries:
		var node := MeshInstance3D.new()
		node.name = "WarmUp"
		node.mesh = entry[0]
		node.material_override = entry[1]
		node.position = Vector3(0, -300, 0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vehicle.visual.add_child(node, true)
		nodes.append(node)
	var completed := true
	for frame in 2:
		await tree.process_frame
		if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
			completed = false
			break
	for node in nodes:
		if is_instance_valid(node): node.queue_free()
	return completed

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
	# A câmera não substitui os materiais de vidro do modelo.
	var materials: Array = view.alpha_materials.duplicate()
	for roof in view.roofs:
		if is_instance_valid(roof) and roof.material_override not in materials:
			materials.append(roof.material_override)
	for material in materials:
		if not material is StandardMaterial3D: continue
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = null if solid else _roof_alpha_texture()

static func _roof_alpha_texture() -> ImageTexture: return ROOF_CUT._roof_alpha_texture()
static func _open_roof(vehicle: Node3D, s: Dictionary) -> void: ROOF_CUT._open_roof(vehicle, s)

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

## Giro do volante com a direção no batente (±0,48 rad nas rodas): ~110°, como em jogo de carro; mais que
## isso as mãos cruzariam sem o gesto de trocar a pegada.
const WHEEL_TURN := 1.9
static var _alpha_material: StandardMaterial3D

static func _interior_alpha_material() -> StandardMaterial3D:
	if _alpha_material == null:
		_alpha_material = _interior_material().duplicate() as StandardMaterial3D
		_alpha_material.resource_name = "interior_alpha"
		_alpha_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _alpha_material

## Submete os mesmos shaders compartilhados usados por mesh_for antes do jogo começar.
## Não marca nenhuma família de veículo como aquecida nem cria a geometria dela.
static func prepare_shared_materials() -> void:
	if not enabled: return
	_interior_material().get_rid()
	_interior_alpha_material().get_rid()

static func mesh_for(id: String, s: Dictionary) -> ArrayMesh: return CABIN_MESH.mesh_for(id, s)

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
	var frame: Transform3D = vehicle.global_transform
	# Lowrider: o motorista sobe, inclina e pula com a carroceria (LowriderHydraulics).
	var lift: Node = vehicle.get("hydraulics")
	if lift != null: frame = frame * lift.body_transform()
	actor.global_transform = frame
	actor.visual.position = origin
	if steering_enabled and not state.has("from_pose"): _steer_pose(actor, vehicle, state, delta)

## Volante girando, mãos no aro, tronco jogado para fora da curva e cabeça olhando para dentro dela.
## GETECO_DRIVER_STEER=0 volta ao motorista parado (pose resolvida uma vez em `seat_driver`).
static var steering_enabled := OS.get_environment("GETECO_DRIVER_STEER") != "0"

## Um tique: gira o volante e, se a direção ou a inclinação mudaram o bastante, refaz a pose (base
## reclinada → inclinação do tronco → pernas e braços por IK → cabeça), ~0,1 ms só para o jogador.
static func _steer_pose(actor: CharacterBody3D, vehicle: Node3D, state: Dictionary, delta: float) -> void:
	var s := spec(vehicle)
	if s.is_empty() or delta <= 0.0: return
	var steer := clampf(float(vehicle.get("steering")) / .48, -1.0, 1.0)
	var wheel: Node3D = state.get("wheel")
	if not is_instance_valid(wheel):
		var visual: Node3D = vehicle.get("visual")
		wheel = visual.get_node_or_null("Interior/SteeringWheel") if visual != null else null
		state["wheel"] = wheel
	# Sem volante próprio (ônibus) as mãos ficam onde a malha única desenhou o aro.
	var angle := steer * WHEEL_TURN if is_instance_valid(wheel) else 0.0
	if is_instance_valid(wheel): wheel.transform = (wheel.get_meta("frame") as Transform3D) * Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
	# Aceleração lateral = velocidade × giro da carroceria: o tronco vai para fora da curva (inércia).
	var yaw := vehicle.global_rotation.y
	var rate := angle_difference(float(state.get("yaw", yaw)), yaw) / delta
	state["yaw"] = yaw
	var lateral := float(vehicle.get("speed")) * rate
	var lean := lerpf(float(state.get("lean", 0.0)), clampf(lateral * .012, -.14, .14), 1.0 - exp(-5.0 * delta))
	state["lean"] = lean
	# Olha para dentro da curva antes de girar o volante todo, e um pouco pela velocidade de giro.
	var look := lerpf(float(state.get("look", 0.0)), clampf(steer * .38 + rate * .12, -.5, .5), 1.0 - exp(-4.0 * delta))
	state["look"] = look
	if absf(angle - float(state.get("posed_angle", 99.0))) < .015 and absf(lean - float(state.get("posed_lean", 99.0))) < .005 \
		and absf(look - float(state.get("posed_look", 99.0))) < .01: return
	state["posed_angle"] = angle
	state["posed_lean"] = lean
	state["posed_look"] = look
	actor.pose_seated_base(float(s.rec))
	actor.pose_driver_lean(lean)
	var targets := _limb_targets(s, angle)
	actor.pose_seated_limbs(targets.feet, targets.hands)
	actor.pose_driver_look(look)

## Alvos de pé e mão no espaço do Actor, que coincide com o do veículo (mesma origem e base).
## `wheel_angle`: giro do volante (rad, anti-horário visto pelo motorista); as mãos andam com o aro.
static func _limb_targets(s: Dictionary, wheel_angle := 0.0) -> Dictionary:
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
		var angle := (grip if side == "Left" else PI - grip) + wheel_angle
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

## Cores da malha da cabine: a montagem mora em VehicleCabinMesh, que as lê por `g.`; ficam aqui
## porque test_coupe_cabin compara as cores dos vértices com C_TRIM e C_DIAL do dono.
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
