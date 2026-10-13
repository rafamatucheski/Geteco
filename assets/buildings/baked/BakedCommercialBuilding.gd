extends "res://world/urban_detail/UrbanCommercialBuilding.gd"
const BAKED_CATALOG := preload("res://assets/buildings/baked/BuildingBakeCatalog.gd")
## Runtime exportável: conserva o contrato nativo sem reconstruir as malhas serializadas.
func _ready() -> void:
	visuals_root = get_node("Visuals")
	collision_root = get_node("Collision")
	# O acabamento noturno identifica os materiais compartilhados por identidade.
	for mesh: MeshInstance3D in visuals_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("baked_window_key"):
			mesh.material_override = window_glass_material(str(mesh.get_meta("baked_window_key")), 0.22)
		elif mesh.name == &"LobbyGlass":
			mesh.material_override = UrbanMaterials.glass_display()
	super._ready()
	# O arquivo conserva a base sem P5. Seu interruptor continua independente
	# no mesmo build, inclusive quando a tarefa F mede apenas a P6.
	for mesh: MeshInstance3D in visuals_root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.get_meta("baked_detail", false): continue
		var limit := mesh.visibility_range_end
		var margin := mesh.visibility_range_end_margin
		BAKED_CATALOG.apply_detail_range(mesh)
		if limit > 0.0 and mesh.visibility_range_end > limit:
			mesh.visibility_range_end = limit
			mesh.visibility_range_end_margin = margin

func build() -> void:
	pass
