extends Node2D
## The port's existing props, with each collider derived from its visible meshes.
const VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const PROJECTION := preload("res://world/shared/interiors/InteriorSolidProjection.gd")
const OCCLUSION := preload("res://world/shared/interiors/ExteriorOcclusion.gd")
const PALLETS := preload("res://prototypes/harbor_art_pack/props/PortPalletStack3D.gd")
const DRUMS := preload("res://prototypes/harbor_art_pack/props/PortDrumClusterPallet3D.gd")

func _ready() -> void:
	z_index = 4
	for item in [
		["PalletsWest", PALLETS, Vector2(-35, -40)],
		["PalletsEast", PALLETS, Vector2(35, -40)],
		["DrumsWest", DRUMS, Vector2(-35, 40)],
		["DrumsEast", DRUMS, Vector2(35, 40)],
	]:
		var view := VIEW.new()
		view.name = item[0]
		view.position = item[2]
		add_child(view)
		view.build_view(item[1], 3.4, 26.0, Vector3(0, .45, 0), Vector3(0,24,20), Vector2i(192,160))
		for mesh in view.model.find_children("*", "MeshInstance3D", true, false):
			mesh.set_meta("interior_solid_id", StringName(item[0]))
		var body := StaticBody2D.new()
		body.name = "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("garage_supply_solid")
		view.add_child(body)
		PROJECTION.build(view.model, body, view.project_floor)
		var edge := -INF
		for shape in body.get_children():
			for point in shape.polygon: edge = maxf(edge, point.y)
		OCCLUSION.attach(view.sprite_3d, edge)
		preload("res://prototypes/harbor_art_pack/PortMeshOptimizer.gd").optimize_hierarchy(view.model)
