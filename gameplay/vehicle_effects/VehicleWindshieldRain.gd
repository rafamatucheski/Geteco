extends RefCounted
## Gotas e limpador de para-brisa do veículo que o jogador conduz.
##
## A câmera do jogo é externa (ortogonal, de cima), então o que se vê é o vidro por fora: gotas
## sobre todas as peças de vidro e um limpador varrendo o para-brisa. Nada disso altera os
## materiais do modelo (mexer em flags de StandardMaterial3D cria variante de shader e custou
## 47-68 ms no primeiro desenho; ver VehicleMaterialVariantPrewarm). Em vez disso:
##   - uma malha de vidro copiada, em cache por arquétipo, 1,2 cm para fora do vidro original,
##     com `VehicleWindshieldRain.gdshader` (mistura alfa, sem escrita de profundidade);
##   - duas tiras (braço e palheta) com `VehicleWiper.gdshader`, no plano do para-brisa.
## Gotas e varrido são animados por TIME no shader: sem script por quadro. Seco, ou em veículo
## que ninguém conduz, `tick` só decrementa um relógio e retorna; a malha só existe enquanto
## chove (ou enquanto as gotas ainda secam) e é liberada depois.
##
## Variantes de pipeline novas (para o pré-aquecimento): os dois ShaderMaterial de
## `warm_materials()`; nenhum StandardMaterial3D ganha flag nova.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const GLASS_SHADER := preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gdshader")
const WIPER_SHADER := preload("res://gameplay/vehicle_effects/VehicleWiper.gdshader")
const NODE_NAME := "WindshieldRain"
## Folga do vidro copiado sobre o original (m): evita z-fighting sem descolar a gota.
const OFFSET := .012
const CHECK_SECONDS := .25
## Chuva (0..1 de Weather.rain_strength_at) a partir da qual há gotas / o limpador liga e desliga.
const DROP_MIN := .03
const WIPER_ON := .28
const WIPER_OFF := .15
const RISE_PER_SECOND := .5
const DRY_PER_SECOND := .12
const SHELTER_DRY_PER_SECOND := .4

static var _meshes: Dictionary = {}    # arquétipo -> {glass, wiper, params}

var vehicle: Node3D
## Teste/ferramentas: objeto com `rain_strength_at(Vector3)` e `_covered`; sem ele lê o do mundo.
var weather_override: Object

var _clock := 0.0
var _target := 0.0
var _sheltered := false
var _level := 0.0
var _amp := 0.0
var _wiper_on := false
var _strength := 0.0
var _node: Node3D
var _glass_material: ShaderMaterial
var _wiper_material: ShaderMaterial
var _pushed_level := -1.0
var _pushed_amp := -1.0

func _init(car: Node3D = null) -> void:
	vehicle = car

## Ativo = existe malha de gotas na cena.
func is_active() -> bool:
	return is_instance_valid(_node)

func level() -> float: return _level
func wiper_amplitude() -> float: return _amp

func tick(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = CHECK_SECONDS
		_target = _read_target()
	if not is_instance_valid(_node):
		if _target <= DROP_MIN or not _create(): return
	var rate := RISE_PER_SECOND
	if _target < _level: rate = SHELTER_DRY_PER_SECOND if _sheltered else DRY_PER_SECOND
	_level = move_toward(_level, _target, delta * rate)
	if _wiper_on and (_strength < WIPER_OFF or _sheltered): _wiper_on = false
	elif not _wiper_on and _strength > WIPER_ON and not _sheltered: _wiper_on = true
	_amp = move_toward(_amp, 1.0 if _wiper_on else 0.0, delta * .8)
	if _level <= .001 and _amp <= .001 and _target <= DROP_MIN:
		dispose()
		return
	if not is_equal_approx(_pushed_level, _level) or not is_equal_approx(_pushed_amp, _amp):
		_pushed_level = _level
		_pushed_amp = _amp
		_glass_material.set_shader_parameter("rain", _level)
		_glass_material.set_shader_parameter("wiper_amp", _amp)
		_wiper_material.set_shader_parameter("wiper_amp", _amp)

## Libera a malha e os materiais (o cache de malhas por arquétipo continua).
func dispose() -> void:
	if is_instance_valid(_node):
		if _node.is_inside_tree(): _node.queue_free()
		else: _node.free()
	_node = null
	_glass_material = null
	_wiper_material = null
	_level = 0.0
	_amp = 0.0
	_wiper_on = false
	_pushed_level = -1.0
	_pushed_amp = -1.0

## Materiais de shader que o jogo usa, para o pré-aquecimento desenhá-los uma vez às escondidas.
static func warm_materials() -> Array[ShaderMaterial]:
	var glass := ShaderMaterial.new()
	glass.shader = GLASS_SHADER
	glass.set_shader_parameter("rain", .5)
	var wiper := ShaderMaterial.new()
	wiper.shader = WIPER_SHADER
	return [glass, wiper]

## Malhas (vidro e limpador) de um arquétipo já na árvore; vazio sem vidro. Exposto para testes.
static func geometry_for(car: Node3D) -> Dictionary:
	if car.has_method("snapshot_glass") and not car.snapshot_glass().is_empty(): return _build(car)
	var id := str(car.get("archetype"))
	if _meshes.has(id): return _meshes[id]
	var built := _build(car)
	if not built.is_empty(): _meshes[id] = built
	return built

func _read_target() -> float:
	_strength = 0.0
	_sheltered = false
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): return 0.0
	if not bool(vehicle.get("controlled")) or bool(vehicle.get("traffic")) or float(vehicle.get("health")) <= 0.0 or not vehicle.is_visible_in_tree(): return 0.0
	var weather := weather_override if weather_override != null else _world_weather()
	if weather == null or not weather.has_method("rain_strength_at"): return 0.0
	_strength = clampf(float(weather.rain_strength_at(vehicle.global_position)), 0.0, 1.0)
	# `_covered` é a mesma decisão de abrigo que apaga a chuva do ar (Weather._update).
	_sheltered = bool(weather.get("_covered"))
	if _sheltered: return 0.0
	return clampf(_strength * 1.6, 0.0, 1.0) if _strength > DROP_MIN else 0.0

func _world_weather() -> Object:
	var world := vehicle.get_parent()
	var session = world.get("session") if world != null else null
	return session.get("weather") if session != null else null

func _create() -> bool:
	var visual = vehicle.get("visual")
	if visual == null or not vehicle.is_inside_tree(): return false
	var g := geometry_for(vehicle)
	if g.is_empty(): return false
	_node = Node3D.new()
	_node.name = NODE_NAME
	# O vidro foi medido em coordenadas do veículo; o visual pode vir escalado (como o Interior).
	_node.scale = Vector3.ONE / (visual as Node3D).scale
	_glass_material = ShaderMaterial.new()
	_glass_material.shader = GLASS_SHADER
	_wiper_material = ShaderMaterial.new()
	_wiper_material.shader = WIPER_SHADER
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = g.glass
	glass.material_override = _glass_material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.add_child(glass)
	if g.wiper != null:
		var params: Dictionary = g.params
		# O período só é escolhido aqui: mudar `wiper_period` com o TIME correndo pularia a fase.
		var period := lerpf(2.0, .85, clampf(_strength, 0.0, 1.0))
		_glass_material.set_shader_parameter("pivots", params.pivots)
		_glass_material.set_shader_parameter("wiper_length", params.length)
		for material in [_glass_material, _wiper_material]: material.set_shader_parameter("wiper_period", period)
		_wiper_material.set_shader_parameter("plane", params.plane)
		_wiper_material.set_shader_parameter("plane_normal", params.plane_normal)
		var arm := MeshInstance3D.new()
		arm.name = "Wiper"
		arm.mesh = g.wiper
		arm.material_override = _wiper_material
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_node.add_child(arm)
	(visual as Node3D).add_child(_node)
	_pushed_level = -1.0
	_pushed_amp = -1.0
	return true

# --- Geometria ------------------------------------------------------------------------------

static func _build(car: Node3D) -> Dictionary:
	var visual = car.get("visual")
	if visual == null or not car.is_inside_tree(): return {}
	var to_car := car.global_transform.affine_inverse()
	var tris: Array = []   # [a, b, c, normal]
	var sum := Vector3.ZERO
	for part in (visual as Node3D).find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = part.mesh
		if mesh == null or part.has_meta("wheel_center") or part.name in ["Interior", "WarmUp", "RoofCut", NODE_NAME] or "/WindshieldRain/" in str(part.get_path()): continue
		for surface in mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			if material == null or not INTERIOR._is_glass(part, surface, material): continue
			if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < .01: continue
			var arrays := INTERIOR.contact_arrays(mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var xf: Transform3D = to_car * part.global_transform
			var count := index.size() if not index.is_empty() else vertices.size()
			for i in range(0, count - 2, 3):
				var a: Vector3 = xf * vertices[index[i] if not index.is_empty() else i]
				var b: Vector3 = xf * vertices[index[i + 1] if not index.is_empty() else i + 1]
				var c: Vector3 = xf * vertices[index[i + 2] if not index.is_empty() else i + 2]
				var normal := (b - a).cross(c - a)
				if normal.length_squared() < 1e-8: continue
				tris.append([a, b, c, normal.normalized()])
				sum += (a + b + c) / 3.0
	if tris.is_empty(): return {}
	var centre := sum / tris.size()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var front_points: Array[Vector3] = []
	for t in tris:
		var normal: Vector3 = t[3]
		var middle: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		# Para fora do vidro = longe do centro da cabine.
		if normal.dot(middle - centre) < 0.0: normal = -normal
		var front: bool = normal.z < -.35
		for k in 3:
			positions.append(t[k] + normal * OFFSET)
			normals.append(normal)
			colors.append(Color(1.0 if front else 0.0, 0, 0, 1))
			if front: front_points.append(t[k])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var glass := ArrayMesh.new()
	glass.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result := {"glass": glass, "wiper": null, "params": {}}
	if front_points.size() >= 3: _add_wiper(result, front_points)
	return result

static func _add_wiper(result: Dictionary, points: Array[Vector3]) -> void:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var mean_y := 0.0
	var mean_z := 0.0
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		mean_y += p.y
		mean_z += p.z
	mean_y /= points.size()
	mean_z /= points.size()
	# Plano z = a + b*y por mínimos quadrados em y (a curvatura lateral é ignorada).
	var cov := 0.0
	var var_y := 0.0
	for p in points:
		cov += (p.y - mean_y) * (p.z - mean_z)
		var_y += (p.y - mean_y) * (p.y - mean_y)
	var slope := cov / var_y if var_y > 1e-6 else 0.0
	var width := max_x - min_x
	var height := max_y - min_y
	if width < .3 or height < .15: return
	var base_y := min_y + height * .06
	var length := minf(height * .86, width * .46)
	var pivot_a := Vector2(min_x + width * .22, base_y)
	var pivot_b := Vector2(min_x + width * .62, base_y)
	# Normal do plano, voltada para a frente do veículo (-Z) e para cima.
	var normal := Vector3(0, slope, -1.0).normalized()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for pivot in [pivot_a, pivot_b]:
		# Braço fino perto do pivô e palheta mais larga até a ponta.
		for strip in [[0.0, length * .38, .007], [length * .14, length, .014]]:
			var first := vertices.size()
			for corner in [[strip[0], -strip[2]], [strip[1], -strip[2]], [strip[1], strip[2]], [strip[0], strip[2]]]:
				vertices.append(Vector3(corner[0], corner[1], 0))
				colors.append(Color(pivot.x, pivot.y, 0, 1))
			indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# O vértice nasce plano (z=0) e o shader o move; a caixa precisa cobrir o vidro todo.
	mesh.custom_aabb = AABB(Vector3(min_x - .3, min_y - .3, mean_z - 1.0), Vector3(width + .6, height + .6, 2.0))
	result.wiper = mesh
	result.params = {
		"pivots": Vector4(pivot_a.x, pivot_a.y, pivot_b.x, pivot_b.y),
		"length": length,
		"plane": Vector4(mean_z - slope * mean_y, slope, 0.0, OFFSET + .008),
		"plane_normal": normal,
	}
