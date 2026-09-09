extends RefCounted
## Read-only audio zones matched to authored garden surfaces, not collision layers.
## Paved paths and actual access bounds override grass. Unmapped ground is concrete.
## Coordinates below are LOCAL to each provider; update when these gardens are reauthored.
const GARDENS := {
	"District": [Rect2(545, 770, 220, 70), Rect2(1440, 1740, 620, 330)],
	"EastDistrict": [Rect2(4810, 1655, 600, 150), Rect2(5695, 1740, 625, 340)],
	"NorthDistrict": [Rect2(4780, -235, 650, 120), Rect2(5690, -235, 650, 120)]
}
const PAVED := {
	"District": [Rect2(650, 755, 15, 85), Rect2(1440, 1910, 620, 65), Rect2(1535, 1660, 70, 475), Rect2(1785, 1765, 205, 120)],
	"EastDistrict": [Rect2(4810, 1711, 600, 32)],
	"NorthDistrict": [Rect2(4780, -155, 650, 35), Rect2(5070, -350, 45, 235), Rect2(5690, -155, 650, 35), Rect2(5980, -350, 45, 235)]
}

static func resolve(actor: Node2D, raining: bool) -> String:
	var world := actor.get_tree().current_scene
	# Interior identity and real room bounds win over global weather lag at a doorway.
	for room in actor.get_tree().get_nodes_in_group("harbor_interior"):
		if world and not world.is_ancestor_of(room): continue
		if room.has_method("get_camera_rect") and room.get_camera_rect().has_point(actor.global_position):
			return String(room.get_meta("footstep_surface", "tile" if String(room.interior_id) in ["clinic", "police", "morgue", "ammunation"] else "concrete"))
	var surface := "concrete"
	for water in actor.get_tree().get_nodes_in_group("water_surface"):
		if water.is_deck_at(actor): return "metal"
		if water.is_water_at(actor): return "water"
	if world:
		var waterfront := world.get_node_or_null("Waterfront") as Node2D
		if waterfront and waterfront.has_method("get_ship_access_data"):
			var ship: Dictionary = waterfront.get_ship_access_data()
			var local := waterfront.to_local(actor.global_position)
			if ship.gangway_bounds.has_point(local) or Geometry2D.is_point_in_polygon(local, ship.deck_polygon):
				surface = "metal"
		if surface == "concrete":
			for provider_name in GARDENS:
				var provider := world.get_node_or_null(NodePath(provider_name)) as Node2D
				if provider == null: continue
				var local := provider.to_local(actor.global_position)
				var paved := false
				for path in PAVED[provider_name]:
					if path.has_point(local): paved = true
				for access in provider.get("accesses"):
					if access.bounds.has_point(local): paved = true
				if paved: continue
				for garden in GARDENS[provider_name]:
					if garden.has_point(local): surface = "grass"
	if raining:
		return "wet" if surface == "concrete" else surface + "_wet"
	return surface
