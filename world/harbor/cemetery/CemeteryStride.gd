extends RefCounted
## Existing joints, distance-driven support and a level boot, as on Dante.
static func ankle(knee: Node3D, length: float) -> void:
	var foot := Node3D.new()
	foot.name = "StrideFoot"
	foot.position.y = -length
	knee.add_child(foot)
	for child in knee.get_children():
		if child is MeshInstance3D and child.position.y < -.20:
			child.reparent(foot, false)
			child.position.y += length

static func pose(hip: Node3D, knee: Node3D, phase: float, upper: float, lower: float, sole: float, forward: float) -> void:
	var cycle := fposmod(phase, TAU) / PI
	var z := lerpf(-.20, .20, minf(cycle, 1.0))
	var lift := 0.0
	if cycle > 1:
		var t := cycle - 1.0
		z = .20 * (1 + 2*t - 12*t*t + 8*t*t*t)
		lift = pow(sin(t*PI), 2) * .09
	z *= -forward
	var down := hip.position.y - sole - lift
	var reach := minf(Vector2(down, z).length(), upper + lower - .001)
	var bend := forward * acos(clampf((reach*reach-upper*upper-lower*lower)/(2*upper*lower), -1, 1))
	hip.rotation.x = atan2(-z, down) - atan2(lower*sin(bend), upper+lower*cos(bend))
	knee.rotation.x = bend
	knee.get_node("StrideFoot").rotation.x = -hip.rotation.x-bend
