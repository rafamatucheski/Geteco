extends RefCounted
## Consultas de geometria sobre um veículo baked (filhos MeshInstance3D achatados).
## Usado pelas correções da frota para achar a superfície real da carroceria em vez
## de chutar coordenadas: raio contra os triângulos de cada peça, no espaço do modelo.

var model: Node3D
var _faces := {}

func _init(target: Node3D) -> void:
	model = target

func parts() -> Array:
	var found := []
	for child in model.get_children():
		if child is MeshInstance3D and child.mesh != null: found.append(child)
	return found

func faces(part: MeshInstance3D) -> PackedVector3Array:
	if not _faces.has(part):
		var local := part.mesh.get_faces()
		var world := PackedVector3Array()
		world.resize(local.size())
		for i in local.size(): world[i] = part.transform * local[i]
		_faces[part] = world
	return _faces[part]

func forget(part: MeshInstance3D) -> void:
	_faces.erase(part)

func bounds(part: MeshInstance3D) -> AABB:
	return part.transform * part.get_aabb()

## Primeiro acerto do raio; ignora as peças em `skip` e as que o filtro recusar.
func ray(origin: Vector3, direction: Vector3, skip: Array = [], accept: Callable = Callable()) -> Dictionary:
	var best := {}
	var best_distance := INF
	for part in parts():
		if part in skip or not part.visible: continue
		if accept.is_valid() and not accept.call(part): continue
		var box := bounds(part).grow(.01)
		if not box.intersects_segment(origin, origin + direction * 50.0): continue
		var tris := faces(part)
		for i in range(0, tris.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(origin, direction, tris[i], tris[i + 1], tris[i + 2])
			if hit == null: continue
			var distance: float = origin.distance_to(hit)
			if distance < best_distance:
				best_distance = distance
				best = {"point": hit, "distance": distance, "part": part}
	return best

static func material_of(part: MeshInstance3D) -> Material:
	if part.material_override: return part.material_override
	if part.get_surface_override_material_count() > 0 and part.get_surface_override_material(0): return part.get_surface_override_material(0)
	if part.mesh.get_surface_count() > 0: return part.mesh.surface_get_material(0)
	return null

static func color_of(part: MeshInstance3D) -> Color:
	var material := material_of(part)
	return material.albedo_color if material is StandardMaterial3D else Color.BLACK

static func emissive(part: MeshInstance3D) -> bool:
	var material := material_of(part)
	return material is StandardMaterial3D and material.emission_enabled

static func is_lamp(part: MeshInstance3D) -> bool:
	for key in part.get_meta_list():
		var value := str(part.get_meta(key))
		if value in ["taillight", "tail", "brake", "headlight", "indicator", "taillight_vert", "brake_light"] or key.ends_with("_lamp"): return true
	return emissive(part)

## Lanterna traseira: meta explícita ou lente vermelha emissiva na metade de trás.
static func is_tail_lamp(part: MeshInstance3D) -> bool:
	for key in part.get_meta_list():
		if str(part.get_meta(key)) in ["taillight", "tail", "brake", "taillight_vert", "brake_light"]: return true
	var color := color_of(part)
	return emissive(part) and color.r > .55 and color.g < .35 and color.b < .35
