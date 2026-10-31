extends RefCounted
class_name HarborV1BuildingProjection

## Lápide de compatibilidade de uma migração intermediária abandonada. O Harbor de
## produção precisa usar geometria nativa composta; quem chama não pode reavivar
## em silêncio uma projeção plana de atlas.
static func attach(building: Node3D, data: Dictionary) -> MeshInstance3D:
	push_error("HarborV1BuildingProjection was removed: %s must remain native 3D" % String(data.get("id",building.name if building!=null else "unknown")))
	return null
