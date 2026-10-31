extends Node3D
## Raio visual reaproveitável. Quem chama escolhe um impacto global desobstruído no chão/telhado
## e guia o envelope do clarão; este nó não tem timers nem laço de quadro.
## 16 segmentos de tronco + no máximo 3 * 4 de galho = 28 segmentos de trajeto / 224 triângulos
## entre núcleo e halo. Fitas cruzadas mantêm volume em vistas de 45/58 graus.

const TRUNK_SEGMENTS := 16
const MAX_BRANCHES := 3
const BRANCH_SEGMENTS := 4
const CORE_WIDTH := 0.065
const HALO_WIDTH := 0.24
const CORE_COLOR := Color(0.86, 0.93, 1.0)
const HALO_COLOR := Color(0.40, 0.60, 1.0)

var _core_mesh := ImmediateMesh.new()
var _halo_mesh := ImmediateMesh.new()
var _core_material := StandardMaterial3D.new()
var _halo_material := StandardMaterial3D.new()
var _trunk_points := PackedVector3Array()
var _has_strike := false
var _strength := 0.0


func _init() -> void:
	# World anchoring prevents a moving/scaled weather parent dragging the bolt.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_trunk_points.resize(TRUNK_SEGMENTS + 1)
	_configure_material(_core_material, CORE_COLOR)
	_configure_material(_halo_material, HALO_COLOR)
	_add_mesh_instance("Core", _core_mesh)
	_add_mesh_instance("Halo", _halo_mesh)
	visible = false
	set_process(false)
	set_physics_process(false)


## Substitui a trajetória anterior e mostra o novo raio com força total.
## Todos os vértices são offsets locais a partir de point. Só o RNG fornecido é consumido.
func strike(point: Vector3, rng: RandomNumberGenerator) -> void:
	if rng == null or not point.is_finite():
		clear()
		return
	if is_inside_tree():
		global_transform = Transform3D(Basis.IDENTITY, point)
	else:
		transform = Transform3D(Basis.IDENTITY, point)
	_core_mesh.clear_surfaces()
	_halo_mesh.clear_surfaces()
	_core_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _core_material)
	_halo_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _halo_material)
	var height := rng.randf_range(26.0, 32.0)
	var drift := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
	for index in range(TRUNK_SEGMENTS + 1):
		var progress := float(index) / float(TRUNK_SEGMENTS)
		var remaining := 1.0 - progress
		var jitter := (
			Vector3(rng.randf_range(-0.75, 0.75), 0.0, rng.randf_range(-0.75, 0.75))
			* sin(progress * PI)
		)
		_trunk_points[index] = Vector3.UP * height * remaining + drift * remaining + jitter
	# Exact contact, without a buried continuation or a surface splash plane.
	_trunk_points[TRUNK_SEGMENTS] = Vector3.ZERO
	for index in range(TRUNK_SEGMENTS):
		var width_scale := lerpf(0.8, 1.0, float(index) / float(TRUNK_SEGMENTS))
		_add_segment(_trunk_points[index], _trunk_points[index + 1], width_scale, width_scale)
	var branch_count := rng.randi_range(2, MAX_BRANCHES)
	for branch_index in range(branch_count):
		_add_branch(branch_index, rng)
	_core_mesh.surface_end()
	_halo_mesh.surface_end()
	_has_strike = true
	set_strength(1.0)


## Limitado a [0, 1]. Zero esconde sem descartar a trajetória atual, para que
## um pulso posterior reaproveite exatamente o mesmo raio sem reconstruir geometria.
func set_strength(value: float) -> void:
	var next_strength := clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	var should_show := _has_strike and next_strength > 0.0
	if is_equal_approx(_strength, next_strength) and visible == should_show:
		return
	_strength = next_strength
	_core_material.albedo_color = Color(CORE_COLOR, _strength)
	_core_material.emission_energy_multiplier = 1.7 * _strength
	_halo_material.albedo_color = Color(HALO_COLOR, 0.12 * _strength)
	_halo_material.emission_energy_multiplier = 0.65 * _strength
	visible = should_show


## Cancela o raio; set_strength sozinho não ressuscita um raio limpo.
## Malhas/materiais/nós continuam alocados para o próximo raio.
func clear() -> void:
	_has_strike = false
	set_strength(0.0)


func _configure_material(material: StandardMaterial3D, color: Color) -> void:
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, 0.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	# Mantém a oclusão por profundidade comum do mundo, incluindo prédios e impactos em telhados.
	# Fitas transparentes não escrevem profundidade nem furam o halo umas das outras.
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	material.disable_fog = false


func _add_mesh_instance(instance_name: String, mesh: ImmediateMesh) -> void:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(instance)


func _add_branch(branch_index: int, rng: RandomNumberGenerator) -> void:
	# Separate trunk bands avoid several branches growing from one noisy knot.
	var attachment := 4 + branch_index * 3 + rng.randi_range(0, 1)
	var origin := _trunk_points[attachment]
	var angle := rng.randf_range(0.0, TAU)
	var outward := Vector3(cos(angle), 0.0, sin(angle))
	var length := rng.randf_range(2.0, 4.5)
	var drop := minf(rng.randf_range(2.5, 5.0), origin.y * 0.55)
	var previous := origin
	for index in range(1, BRANCH_SEGMENTS + 1):
		var progress := float(index) / float(BRANCH_SEGMENTS)
		var jitter := (
			Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
			* sin(progress * PI)
		)
		var next := origin + outward * length * progress + Vector3.DOWN * drop * progress + jitter
		var start_scale := lerpf(0.55, 0.10, float(index - 1) / float(BRANCH_SEGMENTS))
		var end_scale := lerpf(0.55, 0.10, progress)
		_add_segment(previous, next, start_scale, end_scale)
		previous = next


func _add_segment(start: Vector3, end: Vector3, start_scale: float, end_scale: float) -> void:
	var direction := (end - start).normalized()
	var reference := Vector3.RIGHT if absf(direction.x) < 0.9 else Vector3.FORWARD
	var side := direction.cross(reference).normalized()
	var crossed_side := direction.cross(side).normalized()
	# Os dois planos contêm o eixo do segmento; não são sprites XY planos.
	_add_ribbon(_core_mesh, start, end, side, CORE_WIDTH, start_scale, end_scale)
	_add_ribbon(_core_mesh, start, end, crossed_side, CORE_WIDTH, start_scale, end_scale)
	_add_ribbon(_halo_mesh, start, end, side, HALO_WIDTH, start_scale, end_scale)
	_add_ribbon(_halo_mesh, start, end, crossed_side, HALO_WIDTH, start_scale, end_scale)


func _add_ribbon(
	mesh: ImmediateMesh,
	start: Vector3,
	end: Vector3,
	side: Vector3,
	width: float,
	start_scale: float,
	end_scale: float
) -> void:
	var start_offset := side * width * 0.5 * start_scale
	var end_offset := side * width * 0.5 * end_scale
	mesh.surface_add_vertex(start - start_offset)
	mesh.surface_add_vertex(start + start_offset)
	mesh.surface_add_vertex(end + end_offset)
	mesh.surface_add_vertex(start - start_offset)
	mesh.surface_add_vertex(end + end_offset)
	mesh.surface_add_vertex(end - end_offset)
