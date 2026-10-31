extends RefCounted
## SÓ EXPERIMENTO. Sem chamador em tempo de execução, mutação de save ou edição de material produtivo.
## Instale depois do teleporte/streaming e então espere capture_static(world, probe).
## Recaptura explicitamente depois que a transição de clima/luz assentar.
## https://docs.godotengine.org/en/stable/classes/class_reflectionprobe.html
## Um único cubemap com projeção em caixa aproxima a geometria a partir de uma origem. Não
## é um espelho planar: paralaxe, silhuetas e oclusão fora da origem diferem.

const POSITION := Vector3(58.0,2.0,135.0)
const BOX_CENTER := Vector3(58.0,17.0,135.0)
const VOLUME := Vector3(80.0,35.0,80.0)
const CAPTURE_FRAMES := 24
const OVERRIDE_META := &"coastal_probe_trial_road_overrides"
const EXCLUDED_CAPTURE_NODES := [&"CityLightPools",&"CitySidewalkLampPools",&"RainPuddles",&"RainPuddle",&"Water",&"AlpineWater"]

static func install(world: Node) -> ReflectionProbe:
	var existing := world.get_node_or_null("CoastalReflectionProbeTrial") as ReflectionProbe
	if existing != null: return existing
	var probe := ReflectionProbe.new()
	probe.name = "CoastalReflectionProbeTrial"
	probe.visible = false
	probe.size = VOLUME
	probe.box_projection = true
	probe.origin_offset = POSITION-BOX_CENTER
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.interior = false
	probe.enable_shadows = true
	probe.intensity = 1.0
	probe.max_distance = 60.0
	# Um fundo de caixa abaixo do chão distorcia o reflexo projetado. Mantém-no
	# só .5m abaixo do calçamento, com uma transição curta para o calçamento ficar inteiro
	# dentro da influência (uma transição de 8m o apagaria quase todo no nível do piso).
	probe.blend_distance = .35
	probe.mesh_lod_threshold = 2.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = 0
	probe.reflection_mask = 1
	world.add_child(probe)
	# Área editada da polícia: centro (66,120),18x10m,altura13.375m.
	# Esta origem fica na rua a sudoeste dela, fora do prédio.
	probe.global_position = BOX_CENTER
	return probe

static func capture_static(world: Node, probe: ReflectionProbe) -> Dictionary:
	if not is_instance_valid(probe) or not world.is_inside_tree(): return {"ok":false,"reason":"Missing scene/probe"}
	if probe.get_meta("trial_capture_running",false): return {"ok":false,"reason":"Capture already running"}
	probe.set_meta("trial_capture_running",true)
	# Reserva um bit de render hoje sem uso nesta cena temporária. Manter
	# os bits originais de cada malha preserva a visibilidade normal para câmera/luz.
	var used := 0
	var visuals: Array[Node] = [world]
	while not visuals.is_empty():
		var node: Node = visuals.pop_back()
		if node is VisualInstance3D and node != probe: used |= node.layers
		visuals.append_array(node.get_children())
	var capture_bit := 0
	for index in range(19,0,-1):
		if (used & (1 << index)) == 0:
			capture_bit = 1 << index
			break
	if capture_bit == 0:
		probe.set_meta("trial_capture_running",false)
		return {"ok":false,"reason":"No unused layer for static-only capture"}
	var changed: Array[Dictionary] = []
	var pending: Array[Node] = [world]
	var capture_bounds := AABB(POSITION-Vector3.ONE*60.0,Vector3.ONE*120.0)
	var excluded_dynamic_roots := 0
	var excluded_effect_roots: Array[String] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		# As poças de luz no chão são quads emissivos autorais, não geometria de fachada.
		# Capturá-las gerava sprites claros flutuando no reflexo.
		# Poças/água animadas também não podem assar um reflexo congelado nele.
		if node.name in EXCLUDED_CAPTURE_NODES:
			excluded_effect_roots.append(str(node.get_path()))
			continue
		# Tanto veículos quanto atores produtivos derivam de CharacterBody3D.
		# Poda as árvores inteiras deles, mais destroços físicos e efeitos de partícula.
		if node is CharacterBody3D or node is RigidBody3D or node is GPUParticles3D or node is CPUParticles3D or node.is_in_group("drivable"):
			excluded_dynamic_roots += 1
			continue
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			var mesh := node as GeometryInstance3D
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			if mesh.is_visible_in_tree() and capture_bounds.intersects(bounds):
				changed.append({"node":weakref(mesh),"layers":mesh.layers})
				mesh.layers |= capture_bit
		pending.append_array(node.get_children())
	probe.cull_mask = capture_bit
	probe.visible = true
	var sequence := int(probe.get_meta("trial_capture_sequence",0))+1
	probe.set_meta("trial_capture_sequence",sequence)
	# UPDATE_ONCE é sujado por mudanças de transformação, não por mudança de clima.
	# Alterna 2mm em vez de trocar para o caro UPDATE_ALWAYS.
	probe.global_position = BOX_CENTER+Vector3(.002 if sequence%2 else 0.0,0,0)
	var began := Time.get_ticks_usec()
	for index in CAPTURE_FRAMES:
		await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
	# O cubemap capturado fica residente. Restaura as camadas de render temporárias da cena;
	# não move esta sonda de novo até a próxima chamada explícita de capture_static.
	for entry in changed:
		var mesh = entry.node.get_ref()
		if is_instance_valid(mesh): mesh.layers = entry.layers
	probe.set_meta("trial_capture_running",false)
	return {"ok":true,"static_meshes":changed.size(),"excluded_dynamic_roots":excluded_dynamic_roots,"excluded_effect_roots":excluded_effect_roots,"capture_layer_bit":capture_bit,"settle_frames":CAPTURE_FRAMES,"settle_wall_ms":(Time.get_ticks_usec()-began)/1000.0,"position":str(probe.global_position),"capture_origin":str(probe.global_position+probe.origin_offset),"size":str(probe.size),"note":"Settle wall time is not GPU probe cost; compare frame samples separately. Static CharacterBody/RigidBody actors excluded; animated meshes outside those trees may remain."}

static func set_experimental_wet_road(world: Node, enabled: bool) -> int:
	# Só experimento opcional de visibilidade, explicitamente separado da rua real
	# com rugosidade .56. Chame com false para a comparação com material padrão.
	if not enabled:
		var saved: Array = world.get_meta(OVERRIDE_META,[])
		for entry in saved:
			var material: StandardMaterial3D = entry.material
			material.roughness = entry.roughness
			material.metallic_specular = entry.specular
		world.remove_meta(OVERRIDE_META)
		return saved.size()
	if world.has_meta(OVERRIDE_META): return (world.get_meta(OVERRIDE_META) as Array).size()
	var session = world.get("session")
	if session == null or session.weather == null: return 0
	var weather = session.weather
	if int(weather.weather_state) not in [1,2] or float(weather.coastal_wetness)<.5: return 0
	var saved: Array[Dictionary] = []
	var seen := {}
	var pending: Array[Node] = [world]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and str(node.name).begins_with("HarborRoad_202932"):
			var material := node.get_active_material(0) as StandardMaterial3D
			if material != null and not seen.has(material.get_instance_id()):
				seen[material.get_instance_id()] = true
				saved.append({"material":material,"roughness":material.roughness,"specular":material.metallic_specular})
				material.roughness = .28
				material.metallic_specular = .5
		pending.append_array(node.get_children())
	world.set_meta(OVERRIDE_META,saved)
	return saved.size()
