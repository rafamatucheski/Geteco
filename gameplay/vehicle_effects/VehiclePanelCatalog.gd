extends RefCounted
## Offline-prepared variants. Shared pristine geometry; only damaged instances
## duplicate vertices. The remaining fleet keeps its existing presentation.
const IDS := ["sport_coupe", "monaliza", "metro_hatch", "police_cruiser"]
static var _scenes: Dictionary = {}

static func supports(archetype: String) -> bool:
	return archetype in IDS

static func create(archetype: String) -> Node3D:
	if not supports(archetype): return null
	if not _scenes.has(archetype):
		var path := "res://assets/fleet/breakaway/" + archetype + ".scn"
		if archetype == "monaliza": path = "res://assets/fleet/interactive/monaliza_breakaway.scn"
		if not ResourceLoader.exists(path): return null
		_scenes[archetype] = load(path) as PackedScene
	var scene: PackedScene = _scenes[archetype]
	return scene.instantiate() as Node3D if scene != null else null
