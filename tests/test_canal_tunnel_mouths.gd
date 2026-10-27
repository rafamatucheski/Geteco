extends SceneTree
## Regression: tunnel mouths open through street trim; activity stays off the ramp.
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var mouths := TUNNEL.traffic_roads(region.roads)
	check(mouths.size() == 1, "Both street connections exist")
	for row in region.roads:
		if row.id not in [TUNNEL.WEST_ROAD, TUNNEL.EAST_ROAD]: continue
		var mouth := TUNNEL._mouth_on(region.roads, row.id, TUNNEL.W_STUB if row.id == TUNNEL.WEST_ROAD else TUNNEL.E_STUB)
		for z in [TUNNEL.inner_north(), TUNNEL.inner_south()]:
			var a: Vector3 = row.points[0]
			var b: Vector3 = row.points[-1]
			var center := a.lerp(b, (z - a.z) / (b.z - a.z))
			var edge := center.x + float(row.width) * .5 * (1 if row.id == TUNNEL.WEST_ROAD else -1)
			check(TUNNEL.W_STUB <= edge if row.id == TUNNEL.WEST_ROAD else TUNNEL.E_STUB >= edge, "Asphalt meets saved street across full mouth width")
		check(absf(mouth.y) < .01, "Mouth stays at street height")
	# Real carving code, with a sidewalk sheet spanning each level approach.
	for x in [142.0, 341.0]:
		var chunk := Node3D.new()
		root.add_child(chunk)
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2, 16)
		mesh.mesh = plane
		mesh.position = Vector3(x, .01, TUNNEL.CENTER_Z)
		chunk.add_child(mesh)
		TUNNEL.carve_chunk(chunk, Rect2(x - 2, 48, 4, 32))
		var faces := mesh.mesh.get_faces()
		var inside := 0
		for i in range(0, faces.size(), 3):
			var center := mesh.to_global((faces[i] + faces[i+1] + faces[i+2]) / 3)
			if absf(center.z - TUNNEL.CENTER_Z) < TUNNEL.HALF - .01: inside += 1
		check(inside == 0, "No sidewalk triangles across level mouth at x=%s" % x)
		check(not faces.is_empty(), "Sidewalk beside the opening survives")
		chunk.free()
	var drift: Dictionary = DEFINITIONS.drifts("harbor").harbor_cold_storage
	var point := DEFINITIONS.at(drift.pos)
	check(not TUNNEL.reserves(Vector2(point.x, point.z), drift.radius / 16.0), "Entire drift activity is outside tunnel reservation")
	for entry in DEFINITIONS.collectibles():
		if entry.region == "harbor" and entry.place == "":
			check(not TUNNEL.reserves(Vector2(entry.point.x, entry.point.z), 1), "Collectible stays off tunnel: " + entry.id)
	var roads := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	var material: Material = roads._coastal_asphalt_material()
	check(TUNNEL.material("asphalt").shader == material.shader, "Tunnel uses current street shader")
	check(TUNNEL.material("asphalt").get_shader_parameter("base_texture") == material.get_shader_parameter("base_texture"), "Tunnel uses current street aggregate")
	region.free()
	print("CANAL_MOUTHS ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
