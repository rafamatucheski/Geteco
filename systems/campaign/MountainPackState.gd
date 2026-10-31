extends RefCounted
## Estado opcional: saves antigos não precisam de migração nem de conclusão de missão inventada.
const STORY := preload("res://systems/campaign/MountainStoryProgress.gd")
const DOWNHILL := preload("res://systems/campaign/MountainDownhillProgress.gd")
const JEEP := preload("res://systems/campaign/MountainJeepProgress.gd")

static func validate_world(world_state: Dictionary, economy: Dictionary) -> bool:
	if world_state.has("mountain_story") and not STORY.validate_snapshot(world_state.mountain_story): return false
	var downhill: Variant = world_state.get("mountain_downhill", DOWNHILL.defaults())
	var jeep: Variant = world_state.get("mountain_jeep", JEEP.DEFAULT)
	# Valida também blocos ausentes: um recibo de recompensa órfão não é um save antigo.
	if not downhill is Dictionary or not jeep is Dictionary: return false
	if not DOWNHILL.validate_wallet(downhill, economy): return false
	if not JEEP.validate_wallet(jeep, economy): return false
	return true
