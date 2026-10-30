extends SceneTree
## Teste de contrato; não aprova visual/performance. Receptores de dano instrumentados
## observam as entradas reais do Vehicle antes de mudanças em geometria/material.
const PROXY := preload("res://gameplay/vehicle_effects/VehicleShadowProxy.gd")
const HULL := preload("res://gameplay/vehicle_effects/VehicleShadowHull.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BLOOD := preload("res://gameplay/vehicle_effects/VehicleBlood.gd")
const TUNING := preload("res://gameplay/desert_cars/TuningAppearance.gd")
var failures: Array[String] = []
var checks := 0

class DamageObserver extends Node:
	var car: Node3D
	var saw_proxy := false
	var calls := 0
	func observe() -> void:
		calls += 1
		saw_proxy = saw_proxy or car._shadow_proxy.active() or car.visual.get_node("Body").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	func note_source(_source: Node) -> void: observe()
	func refresh() -> void: observe()
	func wreck() -> void: observe()
	func restore() -> void: observe()
	func refresh_paint_finish() -> void: observe()

class DentObserver extends Node:
	var car: Node3D
	var dents: Array = []
	var saw_proxy := false
	var calls := 0
	func observe() -> void:
		calls += 1
		saw_proxy = saw_proxy or car._shadow_proxy.active() or car.visual.get_node("Body").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	func impact(_amount: float, _point: Vector3, _normal: Vector3) -> void: observe()
	func restore_records(_records: Array) -> void: observe()
	func clear() -> void: observe()

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("VEHICLE_SHADOW_PROXY tempo limite"); quit(3))
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures.append(label)
	push_error(label)

func car_for(id: String) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = "shadow-contract-" + id
	root.add_child(car)
	car.set_physics_process(false)
	return car

func body_of(car: Node3D) -> MeshInstance3D:
	return car.visual.get_node_or_null("Body") as MeshInstance3D

func caster_of(car: Node3D) -> MeshInstance3D:
	return body_of(car).get_node_or_null("VehicleShadowProxy") as MeshInstance3D

func has_vertex(vertices: PackedVector3Array, expected: Vector3) -> bool:
	for point in vertices:
		if point.is_equal_approx(expected): return true
	return false

func observe_damage(car: Node3D) -> DamageObserver:
	car.damage_look.free()
	var observer := DamageObserver.new()
	observer.car = car
	car.add_child(observer)
	car.damage_look = observer
	return observer

func observe_dents(car: Node3D) -> DentObserver:
	car.body_dents.free()
	var observer := DentObserver.new()
	observer.car = car
	car.add_child(observer)
	car.body_dents = observer
	return observer

func run() -> void:
	var old_enabled: bool = PROXY.enabled
	var old_warmed: bool = PROXY.prewarmed
	# Exercita o comportamento desligado no mesmo processo, sem exigir outro export.
	PROXY.enabled = false
	PROXY.prewarmed = false
	var off := car_for("union_sedan")
	check(off._shadow_proxy == null and caster_of(off) == null, "desligado não acrescenta helper ou malha")
	check(body_of(off).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "desligado conserva a sombra do Body")
	off.free()
	for id in ["bike_urban","beach_buggy","american_dump_truck","biarticulated_510","police_cruiser","metro_hatch","monaliza","muscle_classic"]:
		check(not PROXY.supports(id), "modelo sem suporte/aberto/articulado/destacável conserva o original: " + id)
	check(not HULL.accepts_bounds("union_sedan", AABB(Vector3.ZERO, Vector3.ZERO)), "limites degenerados recusados")
	check(not HULL.accepts_bounds("union_sedan", AABB(Vector3(NAN,0,0), Vector3.ONE)), "limites não finitos recusados")
	check(not HULL.accepts_bounds("union_sedan", AABB(Vector3.ZERO, Vector3.ONE * 20.0)), "modelo remodelado recusado")
	check(not HULL.accepts_bounds("sedan_classic", HULL.PROFILES.union_sedan.bounds), "Classic recusa os limites antigos do Union")
	check(not HULL.accepts_bounds("union_sedan", HULL.PROFILES.sedan_classic.bounds), "Union recusa os limites encurtados do Classic")
	PROXY.enabled = true
	var waiting := car_for("union_sedan")
	check(not waiting._shadow_proxy.active() and caster_of(waiting) == null, "sem pré-aquecimento renderizado concluído mantém sombra original")
	check(int(PROXY.snapshot().waiting_for_prewarm_by_profile.get("union_sedan",0)) == 1, "fila de pré-aquecimento aparece no diagnóstico")
	waiting.receive_damage(1.0)
	# Simula pré-aquecimento concluído só para contratos lógicos. Não certifica
	# pipelines de shader; a validação renderizada/temporal é executada à parte.
	PROXY.prewarmed = true
	waiting._shadow_proxy.request()
	check(not waiting._shadow_proxy.active(), "dano cancela instalação pendente")
	waiting.free()
	for id in HULL.PROFILE_IDS:
		var car := car_for(id)
		var body := body_of(car)
		var caster := caster_of(car)
		if caster == null:
			print("Diagnóstico de recusa do proxy: ", JSON.stringify({"perfil":id,
				"motivos":PROXY.snapshot().refusals_by_profile.get(id,{}),
				"body":str(body.get_aabb()) if body != null else "ausente",
				"sombra":body.cast_shadow if body != null else -1,
				"versao_modelo":car.visual.get_meta("fleet_redesign_version",0)}))
		check(car._shadow_proxy.active() and caster != null, id + " instala sobre o Body real da frota")
		if caster == null:
			car.free()
			continue
		var original_mesh := body.mesh
		var original_material := body.get_active_material(0)
		var original_shape: Shape3D = car.shape.shape
		check(int(PROXY.snapshot().active_proxies) == 1 and int(PROXY.snapshot().active_original_surfaces) == body.mesh.get_surface_count(), id + " diagnóstico conta superfícies ativas sem varrer a frota")
		check(caster.mesh.get_surface_count() == 1, id + " uma superfície de sombra")
		check(caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, id + " sem passe de cor")
		check(caster.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and caster.layers == body.layers, id + " GI desligada e camadas da fonte")
		check(caster.mesh == HULL.mesh_for(id) and caster.material_override == HULL.material(), id + " recursos compartilhados")
		check(caster.has_meta("door_cut_exempt") and not BLOOD.eligible(caster,car.visual), id + " excluído de portas/sangue")
		car._shadow_proxy.request()
		check(body.get_node("VehicleShadowProxy") == caster, id + " pedido repetido é idempotente")
		var pose := caster.global_transform
		car.visual.position += Vector3.UP * .3
		check(caster.global_position.distance_to(pose.origin + Vector3.UP * .3) < .0001, id + " acompanha o visual sem atualização por quadro")
		car.visual.position -= Vector3.UP * .3
		body.visible = false
		check(not caster.is_visible_in_tree(), id + " acompanha visibilidade da fonte")
		body.visible = true
		car.invalidate_shadow_proxy()
		check(caster_of(car) == null and body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, id + " restaura imediatamente")
		check(body.mesh == original_mesh and body.get_active_material(0) == original_material and car.shape.shape == original_shape, id + " identidade da fonte e da colisão preservada")
		car._shadow_proxy.request()
		check(not car._shadow_proxy.active(), id + " invalidação permanece até o reparo")
		car.repair()
		check(car._shadow_proxy.active(), id + " reparo completo e intacto reinstala")
		car.free()
		check(int(PROXY.snapshot().active_proxies) == 0, id + " saída da árvore atualiza registro ativo")
	check(HULL.mesh_for("union_sedan") != HULL.mesh_for("sedan_classic"), "Classic e Union mantêm cascos próprios após a remodelagem de 19/10")
	# Capô e porta-malas baixos preservam a diferença de altura em relação ao teto.
	var roof_points := {"union_sedan":Vector3(.68,1.38,1.04),
		"sedan_classic":Vector3(.68,1.464,.92), "aurora_executive":Vector3(.72,1.3489,1.2487903226)}
	for id in HULL.PROFILE_IDS:
		var hull := HULL.mesh_for(id)
		var arrays: Array = hull.surface_get_arrays(0) # Leitura restrita ao teste.
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var hood_y := 0.0
		var roof_y := 0.0
		for point in vertices:
			if point.z < -1.0: hood_y = maxf(hood_y,point.y)
			roof_y = maxf(roof_y,point.y)
		check(hood_y < 1.0 and roof_y > 1.3 and vertices.size() < 300, id + " casco inclinado e limitado, sem preencher toda a AABB")
		check(has_vertex(vertices,roof_points[id]), id + " teto acompanha a remodelagem autorada de 19/10")
		if id == "sedan_classic":
			check(has_vertex(vertices,Vector3(.85,.29,-2.1376)), "Classic acompanha o balanço dianteiro encurtado")
	# Passes de sombra existentes recebem o mesmo recurso/formato, sem luz adicional.
	var cell := Node3D.new()
	root.add_child(cell)
	for index in HULL.PROFILE_IDS.size():
		check(PROXY.add_prewarm_caster(cell,index), "pré-aquecimento acrescenta caster do perfil " + HULL.PROFILE_IDS[index])
		check(cell.get_child_count() == index + 1 and cell.get_child(index) is MeshInstance3D, "pré-aquecimento não acrescenta luz ou nó de processamento")
		check(cell.get_child(index).mesh == HULL.mesh_for(HULL.PROFILE_IDS[index]), "pré-aquecimento desenha casco de produção " + HULL.PROFILE_IDS[index])
	cell.free()
	var special := car_for("union_sedan")
	special.invalidate_shadow_proxy()
	body_of(special).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	special.repair()
	check(not special._shadow_proxy.active() and body_of(special).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "modo intencional de sombra da fonte é conservado")
	check(PROXY.snapshot().refusals_by_profile.get("union_sedan",{}).has("source_shadow_mode"), "motivo da recusa aparece no diagnóstico")
	special.free()
	var impacted := car_for("union_sedan")
	var look := observe_damage(impacted)
	var dents := observe_dents(impacted)
	var destroyed_saw_proxy: Array[bool] = [false]
	impacted.destroyed.connect(func() -> void: destroyed_saw_proxy[0] = impacted._shadow_proxy.active() or caster_of(impacted) != null)
	impacted.receive_impact(1.0,Vector3(0,.7,-2.0),null,10.0,Vector3.BACK)
	check(dents.calls > 0 and not dents.saw_proxy and not look.saw_proxy, "impacto restaura antes de amassados e rotinas de dano")
	impacted.repair()
	check(impacted._shadow_proxy.active(), "reparo reinstala somente após as rotinas instrumentadas")
	impacted.restore_body_dents([])
	check(not impacted._shadow_proxy.active() and not dents.saw_proxy, "restauração de topologia salva invalida antes das rotinas")
	impacted.repair()
	impacted.restore_health(impacted.max_health * .5)
	check(not impacted._shadow_proxy.active() and not look.saw_proxy, "dano salvo restaura caster antes da atualização de material")
	impacted.repair()
	impacted.receive_damage(100000.0)
	check(not destroyed_saw_proxy[0] and not look.saw_proxy, "ouvintes de destroyed e carcaça não encontram proxy")
	impacted.free()
	var faded := car_for("union_sedan")
	faded.fade_traffic_retirement(.25)
	check(caster_of(faded) == null and not faded._shadow_proxy.active(), "retirada do tráfego remove antes de alfa/afundamento")
	faded.free()
	var door := car_for("union_sedan")
	door.warm_doors(1)
	check(caster_of(door) == null and not door._shadow_proxy.active(), "preparação fatiada da porta invalida imediatamente")
	door.repair()
	check(not door._shadow_proxy.active(), "portas preparadas continuam inelegíveis após reparo")
	door.free()
	var tuned := car_for("union_sedan")
	TUNING.apply_vehicle(tuned,{"finish":"finish_matte"})
	check(caster_of(tuned) == null and not tuned._shadow_proxy.active(), "entrada direta de tuning invalida antes das mudanças")
	tuned.repair()
	check(not tuned._shadow_proxy.active(), "tuning continua inelegível após reparo")
	tuned.free()
	PROXY._pending.clear()
	PROXY.enabled = old_enabled
	PROXY.prewarmed = old_warmed
	print("VEHICLE_SHADOW_PROXY verificações=",checks," falhas=",failures)
	quit(0 if failures.is_empty() else 1)
