extends Node3D
## Poças e gotas de sangue no chão (porte nativo 3D de guns/combat/GroundBlood.gd da V1).
##
## Regras mantidas da V1:
## - poça de morte cresce devagar (~2,2 s), gota de ferido aparece quase na hora;
## - a cor escurece de vermelho vivo para marrom em ~12 s;
## - vida de 18 s com 6 s de desvanecimento para manchas comuns;
## - no máximo 64 manchas; a mais antiga sai primeiro;
## - no máximo 5 cadáveres com poça no mundo; o mais antigo desvanece junto com a
##   poça dele (evita cemitério de corpos em tiroteio longo).
## Melhorias: a poça de morte fica até o corpo sair (rabecão/orçamento), a forma é
## gerada por semente (perfis compacto, alongado, respingado e irregular, como na
## V1) e cada mancha registra raio para o rastro de pneu/sapato (BloodTracks3D).

const LIFETIME := 18.0
const FADE_DURATION := 6.0
const CORPSE_LIFETIME := 240.0
const MAX_STAINS := 64
const MAX_CORPSES := 5
const CORPSE_FADE_SECONDS := 0.45
const FRESH := Color("9a1a20")
const DRIED := Color("3f1417")
const Y := 0.05

var stains: Array[Dictionary] = []
var corpses: Array[Dictionary] = []
var _meshes: Array[ArrayMesh] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "GroundBlood3D"
	_rng.randomize()
	# Oito formas pré-geradas bastam: rotação, escala e esticamento por mancha
	# variam o resto. Gerar malha por mancha custaria alocação em tiroteio.
	for variant in 8: _meshes.append(_build_shape(variant))


## Poça. `lethal` = morte (grande, dura enquanto houver corpo); senão ferimento.
func spawn_pool(point: Vector3, lethal: bool, body: Node3D = null, stretch_dir := Vector3.ZERO) -> Dictionary:
	# Morte: ~1,1–1,6 m (V1 17 px = 1,06 m era lido de cima a 2D; em 3D o corpo
	# deitado cobre o centro, então a poça precisa passar da silhueta).
	var radius := _rng.randf_range(1.1, 1.6) if lethal else _rng.randf_range(0.3, 0.46)
	var stain := _allocate(point, radius, 2.2 if lethal else 0.5, stretch_dir)
	stain.lethal = lethal
	stain.lifetime = CORPSE_LIFETIME if lethal else LIFETIME
	if lethal and is_instance_valid(body) and not body.get_meta("is_player_body", false):
		_register_corpse(body, stain)
	return stain


## Gota de quem está sangrando e andando.
func spawn_drip(point: Vector3, strength: float) -> Dictionary:
	var stain := _allocate(point, lerpf(0.08, 0.16, strength) * _rng.randf_range(0.88, 1.12), 0.2)
	stain.lifetime = LIFETIME
	return stain


## Respingo alongado (atropelamento): várias manchas ao longo do rumo do impacto.
func spawn_splatter(point: Vector3, direction: Vector3, strength: float) -> void:
	var flat := Vector3(direction.x, 0, direction.z)
	if flat.length_squared() < 0.0001: flat = Vector3.FORWARD
	flat = flat.normalized()
	var count := 2 + int(strength * 4.0)
	for index in count:
		var along := _rng.randf_range(0.3, 1.0 + strength * 2.4)
		var side := _rng.randf_range(-0.35, 0.35) * (0.5 + along * 0.3)
		var spot := point + flat * along + flat.cross(Vector3.UP) * side
		var stain := _allocate(spot, _rng.randf_range(0.14, 0.34) * (1.0 + strength * 0.5), 0.15, flat)
		stain.lifetime = LIFETIME * 1.5


## Manchas próximas, para rastro de pneu e sapato.
func stains_near(point: Vector3, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stain in stains:
		if not is_instance_valid(stain.node): continue
		var d := Vector2(point.x - stain.point.x, point.z - stain.point.z).length()
		if d < radius + float(stain.radius) * float(stain.node.scale.x): result.append(stain)
	return result


func _allocate(point: Vector3, radius: float, grow_time: float, stretch_dir := Vector3.ZERO) -> Dictionary:
	while stains.size() >= MAX_STAINS:
		var oldest: Dictionary = stains.pop_front()
		if is_instance_valid(oldest.node): oldest.node.queue_free()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _meshes[_rng.randi() % _meshes.size()]
	var material := _material()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var yaw := _rng.randf_range(-PI, PI)
	var squash := 1.0
	if stretch_dir.length_squared() > 0.0001:
		yaw = atan2(stretch_dir.x, stretch_dir.z)
		squash = 0.55
	mesh.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * squash, 1, radius)), Vector3(point.x, _ground_y(point) + Y + _rng.randf_range(0, 0.004), point.z))
	mesh.scale = Vector3(0.3, 1, 0.3) * mesh.scale
	var stain := {"node": mesh, "material": material, "point": mesh.global_position, "radius": radius, "age": 0.0, "grow": grow_time, "lifetime": LIFETIME, "lethal": false, "target_scale": Vector3(radius * squash, 1, radius)}
	stains.append(stain)
	return stain


## Sangue fica sobre calçada/asfalto (y~0.03); em escada/laje usa o chão real.
func _ground_y(point: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.2, point + Vector3.DOWN * 2.0, 1)
	var hit := space.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else point.y


func _material() -> StandardMaterial3D:
	# Material por mancha só para cor/alfa próprios; 64 no máximo.
	var material := StandardMaterial3D.new()
	material.albedo_color = FRESH
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.roughness = 0.18
	material.metallic_specular = 0.9
	material.render_priority = -1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _process(delta: float) -> void:
	_prune_corpses()
	for index in range(stains.size() - 1, -1, -1):
		var stain: Dictionary = stains[index]
		var node: MeshInstance3D = stain.node
		if not is_instance_valid(node):
			stains.remove_at(index)
			continue
		stain.age = float(stain.age) + delta
		var age: float = stain.age
		var grow := smoothstep(0.0, float(stain.grow), age)
		node.scale = (stain.target_scale as Vector3) * lerpf(0.3, 1.0, grow)
		var color := FRESH.lerp(DRIED, minf(age / 12.0, 1.0))
		var remaining := float(stain.lifetime) - age
		color.a = clampf(remaining / FADE_DURATION, 0.0, 1.0)
		(stain.material as StandardMaterial3D).albedo_color = color
		# Poça fresca brilha (molhada); seca fica fosca.
		(stain.material as StandardMaterial3D).roughness = lerpf(0.15, 0.7, minf(age / 20.0, 1.0))
		if remaining <= 0.0:
			node.queue_free()
			stains.remove_at(index)


func _register_corpse(body: Node3D, stain: Dictionary) -> void:
	for entry in corpses:
		if entry.body.get_ref() == body:
			entry.stains.append(stain)
			return
	corpses.append({"body": weakref(body), "stains": [stain]})
	while corpses.size() > MAX_CORPSES:
		_fade_corpse(corpses.pop_front())


func _prune_corpses() -> void:
	for index in range(corpses.size() - 1, -1, -1):
		var body = corpses[index].body.get_ref()
		if not is_instance_valid(body):
			# Rabecão levou o corpo: a poça passa a secar e sumir normalmente.
			for stain in corpses[index].stains:
				stain.lifetime = minf(float(stain.lifetime), float(stain.age) + LIFETIME)
			corpses.remove_at(index)


func _fade_corpse(entry: Dictionary) -> void:
	var body = entry.body.get_ref()
	if is_instance_valid(body) and body is Node3D:
		body.set_meta("corpse_budget_evicted", true)
		var visual: Node3D = body.get("visual")
		var tween: Tween = body.create_tween()
		if is_instance_valid(visual):
			tween.tween_property(visual, "scale", visual.scale * 0.01, CORPSE_FADE_SECONDS)
		tween.tween_callback(body.queue_free)
	for stain in entry.stains:
		stain.lifetime = float(stain.age) + CORPSE_FADE_SECONDS


## Forma de poça: contorno irregular com lóbulos + gotas satélite (perfis da V1).
func _build_shape(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301 + variant * 97
	var profile := variant % 4
	var squash := rng.randf_range(0.55, 0.85)
	var stretch := rng.randf_range(0.9, 1.1)
	if profile == 1:
		squash = rng.randf_range(0.34, 0.48)
		stretch = rng.randf_range(1.12, 1.3)
	var phase := rng.randf_range(0, TAU)
	var lobes := rng.randi_range(3, 7)
	var roughness := 0.18 if profile == 3 else 0.10
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var outline: Array[Vector3] = []
	for i in 28:
		var angle := TAU * i / 28.0
		var edge := 0.82 + roughness * sin(angle * lobes + phase) + 0.08 * cos(angle * 3.0 - phase) + rng.randf_range(-0.04, 0.04)
		outline.append(Vector3(cos(angle) * stretch, 0, sin(angle) * squash) * edge)
	for i in outline.size():
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(outline[(i + 1) % outline.size()])
		tool.add_vertex(outline[i])
	var drops := rng.randi_range(7, 11) if profile == 2 else rng.randi_range(2, 6)
	for d in drops:
		var angle := rng.randf_range(0, TAU)
		var center := Vector3(cos(angle) * stretch, 0, sin(angle) * squash) * rng.randf_range(1.05, 1.65)
		var r := rng.randf_range(0.04, 0.12)
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			tool.add_vertex(center)
			tool.add_vertex(center + Vector3(cos(a1), 0, sin(a1)) * r)
			tool.add_vertex(center + Vector3(cos(a0), 0, sin(a0)) * r)
	return tool.commit()
