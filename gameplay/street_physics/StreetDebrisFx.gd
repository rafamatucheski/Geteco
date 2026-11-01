extends RefCounted
## Detritos da rua: estouro de vidro, lixo/vidro espalhado no chão (uma malha por estouro, apoiada no
## piso) e gêiser de hidrante que apaga fogo perto. Separado de StreetPhysics.gd em 01/11 só para o
## dono caber na leitura. O estado (_litter, _geysers), GEYSER_DOUSE_RADIUS e os materiais estáticos
## (glass_shard_material/mesh, debris_material, puddle_material, warm_materials, com as static var
## que os retêm) continuam no StreetPhysics, porque VehicleMaterialVariantPrewarm,
## StreetEffectsPrewarm, ImpactFx, CombatEffects e testes os chamam lá; o dono mantém cada função
## antiga como delegação de uma linha com a mesma assinatura e os mesmos padrões. `g` fica como
## Node3D, e não como o script do dono, para não criar preload cíclico. Até as chamadas entre funções
## deste arquivo passam por `g.` (subclasses de teste sobrescrevem spawn_glass), e os spans
## STALL_WORK continuam tendo o StreetPhysics como dono.

const CONTACT_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const DEBRIS_GROUND := preload("res://gameplay/street_physics/DebrisGroundProjection.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func spawn_glass(point: Vector3, direction: Vector3) -> void:
	var began := STALL_WORK.begin()
	g._stall_spawn_glass(point,direction)
	STALL_WORK.finish_slow("street.glass",began,5000,g)

func _stall_spawn_glass(point: Vector3, direction: Vector3) -> void:
	var stage := STALL_WORK.begin()
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.amount = 26
	burst.lifetime = 0.9
	burst.explosiveness = 0.95
	burst.mesh = g.glass_shard_mesh()
	burst.material_override = g.glass_shard_material()
	burst.direction = (direction + Vector3.UP * 0.6).normalized()
	burst.spread = 55.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 5.0
	burst.gravity = Vector3(0, -12, 0)
	burst.angular_velocity_min = -720
	burst.angular_velocity_max = 720
	STALL_WORK.finish_slow("street.glass.resources",stage,5000,g)
	stage = STALL_WORK.begin()
	g.add_child(burst)
	# Callers already supply the broken pane/contact height.
	var baseline := "--debris-baseline" in OS.get_cmdline_user_args()
	burst.global_position = point+Vector3.UP*.8 if baseline else point
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
	STALL_WORK.finish_slow("street.glass.attach",stage,5000,g)
	g._scatter(point, direction, 22, Vector2(0.04, 0.09), Color(0.8, 0.92, 0.98, 0.9), 0.05, 60.0, 0.0 if baseline else .6)

func spawn_litter(point: Vector3, direction: Vector3) -> void:
	g._scatter(point, direction, 14, Vector2(0.12, 0.3), Color(0.86, 0.84, 0.76), 0.9, 90.0)


## Pedacinhos no chão (vidro, papel): uma malha só, some depois de `lifetime`.
func _scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float, settle_delay := 0.0) -> void:
	var began := STALL_WORK.begin()
	g._stall_scatter(point,direction,count,size,color,roughness,lifetime,settle_delay)
	STALL_WORK.finish_slow("street.scatter",began,5000,g)

func _stall_scatter(point: Vector3, direction: Vector3, count: int, size: Vector2, color: Color, roughness: float, lifetime: float, settle_delay := 0.0) -> void:
	var stage := STALL_WORK.begin()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var space: PhysicsDirectSpaceState3D = g.get_world_3d().direct_space_state
	var baseline := "--debris-baseline" in OS.get_cmdline_user_args()
	var vertex_count := 0
	var flat := Vector3(direction.x, 0, direction.z).normalized() if Vector2(direction.x, direction.z).length() > 0.01 else Vector3.FORWARD
	for index in count:
		var center := flat * randf_range(-0.4, 2.2) + flat.cross(Vector3.UP) * randf_range(-1.1, 1.1)
		var s := randf_range(size.x, size.y)
		var a := randf_range(0, TAU)
		var corners: Array[Vector3] = [Vector3(cos(a), 0, sin(a))*s, Vector3(cos(a + 2.2), 0, sin(a + 2.2))*s, Vector3(cos(a + 4.1), 0, sin(a + 4.1))*s]
		var projected := DEBRIS_GROUND.triangle(space,point+center,corners,baseline)
		if projected.is_empty(): continue
		var normal := (projected[1]-projected[0]).cross(projected[2]-projected[0]).normalized()
		if normal.y<0: normal = -normal
		tool.set_normal(normal)
		for vertex: Vector3 in projected:
			tool.add_vertex(vertex-point)
			vertex_count += 1
	if vertex_count==0: return # No supporting floor: never invent a floating plane.
	var mesh := MeshInstance3D.new()
	mesh.name = "GroundDebris"
	mesh.set_meta("surface_debris",true)
	STALL_WORK.finish_slow("street.scatter.geometry",stage,5000,g)
	stage = STALL_WORK.begin()
	mesh.mesh = tool.commit()
	STALL_WORK.finish_slow("street.scatter.commit",stage,5000,g)
	stage = STALL_WORK.begin()
	var material: StandardMaterial3D = g.debris_material(color, roughness)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	STALL_WORK.finish_slow("street.scatter.material",stage,5000,g)
	stage = STALL_WORK.begin()
	g.add_child(mesh)
	mesh.global_position = point
	mesh.visible = settle_delay<=0.0
	g._litter.append(mesh)
	while g._litter.size() > 24:
		var oldest = g._litter.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	STALL_WORK.finish_slow("street.scatter.attach",stage,5000,g)
	var tween := mesh.create_tween()
	if settle_delay>0.0:
		tween.tween_interval(settle_delay)
		tween.tween_callback(mesh.show)
	tween.tween_interval(lifetime)
	tween.tween_property(material, "albedo_color:a", 0.0, 4.0)
	tween.tween_callback(mesh.queue_free)

## Hidrante quebrado: coluna d'água de verdade (WaterJet3D) caindo em volta, em
## vez de esferas soltas. Apaga fogo que estiver no alcance (GEYSER_DOUSE_RADIUS).
func spawn_geyser(point: Vector3) -> void:
	var jet = preload("res://gameplay/fx/WaterJet3D.gd").new()
	jet.flight_time = 1.5
	g.add_child(jet)
	jet.aim(point + Vector3.UP * 0.35, point + Vector3(0.9, 0.0, 0.4))
	jet.set_active(true)
	var puddle := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.005
	disc.radial_segments = 18
	puddle.mesh = disc
	var wet: StandardMaterial3D = g.puddle_material()
	puddle.material_override = wet
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(puddle)
	puddle.global_position = Vector3(point.x, point.y + 0.04, point.z)
	puddle.scale = Vector3(0.2, 1, 0.2)
	g._geysers.append({"jet": jet, "puddle": puddle, "material": wet, "age": 0.0})
	CONTACT_AUDIO.play_contact(g, null, point, 8.0, "metal", "prop|" + str(Vector3i((point * 2.0).round())))


## Jorra ~14 s, perde força nos últimos 4 s; a poça cresce e depois seca.
func _update_geysers(delta: float) -> void:
	for index in range(g._geysers.size() - 1, -1, -1):
		var geyser: Dictionary = g._geysers[index]
		geyser.age = float(geyser.age) + delta
		var age: float = geyser.age
		# Sem tipo na leitura: o jato é liberado aos 16 s e o dicionário continua
		# com a referência; atribuir instância liberada a variável tipada é erro.
		var jet = geyser.jet
		var puddle = geyser.puddle
		if is_instance_valid(jet):
			var force := 1.0 - smoothstep(10.0, 14.0, age)
			jet.pressure = force
			jet.flight_time = lerpf(0.6, 1.5, force)
			jet.aim(jet.drops.global_position, jet.end_point)
			if age > 14.0: jet.set_active(false)
			if age > 16.0: jet.queue_free()
			elif force > 0.2: g._douse_near(jet.drops.global_position, delta * force)
		if is_instance_valid(puddle):
			var radius := lerpf(0.2, 3.2, smoothstep(0.0, 12.0, age))
			puddle.scale = Vector3(radius, 1, radius)
			(geyser.material as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - smoothstep(40.0, 60.0, age))
		if age > 60.0:
			if is_instance_valid(puddle): puddle.queue_free()
			g._geysers.remove_at(index)

func _douse_near(point: Vector3, amount: float) -> void:
	var gameplay = g.controller.world.get("gameplay") if g.controller != null and g.controller.world != null else null
	var emergency = gameplay.get("emergency") if gameplay != null else null
	if emergency == null: return
	for fire in emergency.fires:
		if is_instance_valid(fire) and fire.global_position.distance_to(point) < g.GEYSER_DOUSE_RADIUS:
			emergency.extinguish(fire, amount * 0.5)
