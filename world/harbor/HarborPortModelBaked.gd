extends Node2D
## Versão pré-renderizada de HarborPortModelView: mesmo contrato público
## (position, z_index, model.height/hoist_start/hoist_end, project_floor,
## colisão de prédio), mas sem SubViewport/Camera3D/malha 3D em tempo real --
## a textura e a geometria vêm de tools/bake_south_port_models.gd
## (world/harbor/HarborPortModelBakeData.gd).
##
## A câmera original é ortográfica e FIXA (nunca se move depois de nascer);
## unproject_position() é uma transformação afim determinística. A fórmula
## abaixo foi verificada contra a câmera real (erro máximo 0,0003px, ver
## histórico do commit) antes de substituir os métodos que a usavam. Não
## reimplementa MountainStaticModelView.gd (script compartilhado com a
## Mountain Pass) -- fica isolado aqui, dentro do Harbor.

const BAKE := preload("res://world/harbor/HarborPortModelBakeData.gd")

class BakedModelData extends RefCounted:
	var height := 0.0
	var hoist_start := Vector3.ZERO
	var hoist_end := Vector3.ZERO

var sprite_3d: Sprite2D
var model: BakedModelData
var footprint := Rect2()
var kind := ""
var _camera_position := Vector3.ZERO
var _camera_target := Vector3.ZERO
var _basis_x := Vector3.RIGHT
var _basis_y := Vector3.UP
var _pixels_per_unit := 1.0
var _viewport_size := Vector2i.ZERO

static func has_data(label: String) -> bool:
	return BAKE.ENTRIES.has(label)

func setup(model_kind: String, rect: Rect2, label: String) -> void:
	kind = model_kind
	footprint = rect
	position = rect.get_center()
	z_index = 4
	var data: Dictionary = BAKE.ENTRIES[label]
	_camera_position = data.camera_position
	_camera_target = data.camera_target
	_viewport_size = data.viewport_size
	var basis_z := -(_camera_target - _camera_position).normalized()
	_basis_x = Vector3.UP.cross(basis_z).normalized()
	_basis_y = basis_z.cross(_basis_x).normalized()
	_pixels_per_unit = float(_viewport_size.x) / float(data.camera_size)

	model = BakedModelData.new()
	model.height = data.height
	model.hoist_start = data.hoist_start
	model.hoist_end = data.hoist_end

	sprite_3d = Sprite2D.new()
	sprite_3d.texture = load(data.texture)
	sprite_3d.scale = data.sprite_scale
	sprite_3d.position = data.sprite_position
	add_child(sprite_3d)

	if kind in ["warehouse", "office"]:
		var bounds: Dictionary = data.solid_floor_bounds
		for id in bounds:
			var body := add_solid(bounds[id], String(id))
			body.add_to_group("building_geodata")
			body.add_to_group("building_blocker")
			var polygon: PackedVector2Array = body.get_child(0).polygon
			var solid_bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon: solid_bounds = solid_bounds.expand(point)
			body.set_meta("solid_rects_local", [solid_bounds])
		preload("res://systems/interiors/ExteriorOcclusion.gd").attach(sprite_3d, rect.size.y * .5)

	queue_redraw()

func project_point(point: Vector3) -> Vector2:
	var relative := point - _camera_position
	var local_x := relative.dot(_basis_x)
	var local_y := relative.dot(_basis_y)
	return sprite_3d.position + Vector2(local_x, -local_y) * _pixels_per_unit * sprite_3d.scale

func project_floor(point: Vector2) -> Vector2:
	return project_point(Vector3(point.x, 0, point.y))

func add_solid(rect: Rect2, label: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
	body.add_child(shape)
	add_child(body)
	return body

func _draw() -> void:
	if kind == "crane": return
	var r := Rect2(-footprint.size * .5, footprint.size)
	draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0.035, .07, .085, .28))
