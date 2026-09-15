extends Control
## A small distant flock, drawn in the illustration's coordinates.
## The presentation shares one pausable clock with the water/cloud shader.
var elapsed := 0.0

func _init() -> void:
	name = "SunsetBirds"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func advance(delta: float, reduced_motion: bool) -> void:
	if reduced_motion:
		return
	elapsed += minf(delta, 0.1)
	queue_redraw()

func _draw() -> void:
	# Two loose groups cross an open sky corridor, fading before the cranes
	# and Dante. No random spawning, allocations of nodes or screen-wide flock.
	for group in 2:
		var progress := fposmod(elapsed / (39.0 + group * 13.0) + group * 0.53 + 0.18, 1.0)
		var opacity := smoothstep(0.0, 0.13, progress) * (1.0 - smoothstep(0.80, 1.0, progress))
		for bird in (3 if group == 0 else 2):
			var phase := elapsed * (3.4 + bird * 0.26) + bird * 1.8 + group
			var uv := Vector2(lerpf(0.461, 0.613, progress) - bird * 0.008,
				0.167 + group * 0.040 + bird * 0.005 + sin(progress * TAU) * 0.006)
			var center := uv * size
			var span := size.x * (0.0025 - group * 0.00045)
			# Rounded wings alternate flapping and gliding; just a few pixels wide.
			var flap := sin(phase) * 0.72 - 0.18
			var wing := PackedVector2Array([
				center + Vector2(-span, -span * flap),
				center + Vector2(-span * 0.48, -span * (flap * 0.55 + 0.23)),
				center,
				center + Vector2(span * 0.48, -span * (flap * 0.55 + 0.23)),
				center + Vector2(span, -span * flap)])
			draw_polyline(wing, Color(0.19, 0.16, 0.17, opacity * 0.68), maxf(0.7, size.x * 0.00065), true)

	# Fagulhas douradas sutis flutuando com a brisa no horizonte aberto do porto
	for m in 4:
		var mote_p := fposmod(elapsed / (28.0 + m * 7.0) + m * 0.25, 1.0)
		var mote_alpha := smoothstep(0.0, 0.2, mote_p) * (1.0 - smoothstep(0.75, 1.0, mote_p)) * 0.45
		var mote_uv := Vector2(
			lerpf(0.47, 0.60, mote_p),
			0.14 + m * 0.035 + sin(elapsed * 1.5 + m * 2.1) * 0.012
		)
		var mote_center := mote_uv * size
		draw_circle(mote_center, maxf(1.0, size.x * 0.0007), Color(1.0, 0.78, 0.35, mote_alpha))
