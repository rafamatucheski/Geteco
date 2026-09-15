extends RefCounted
## Small surface scratches, bounded inside the physical body footprint.
## Coordinates remain in vehicle space; never add protruding sheet polygons.
static func add_scrape(container: Node2D, hit: Vector2, inward: Vector2, footprint: Vector2, strength: float) -> void:
	while container.get_child_count() >= 6:
		var oldest := container.get_child(0)
		container.remove_child(oldest)
		oldest.queue_free()
	var bounds := footprint * 0.30
	var center := hit.clamp(-bounds,bounds)
	var tangent := inward.orthogonal().normalized()
	if tangent.is_zero_approx(): tangent = Vector2.RIGHT
	var half_length := lerpf(1.8,3.2,clampf(strength,0,1))
	var scratch := Line2D.new()
	scratch.name = "BodySurfaceScrape"
	scratch.points = PackedVector2Array([center-tangent*half_length,center+tangent*half_length])
	scratch.width = 0.85
	scratch.antialiased = true
	scratch.default_color = Color(0.40,0.43,0.45,0.65)
	container.add_child(scratch)
