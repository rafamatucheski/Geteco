extends Node2D
## One brief mark at the actual contact and the last travelled segment.
## No additional blood, decals, particles, lights, or HUD elements.
var age := 0.0
var trail := Vector2.ZERO
var normal := Vector2.LEFT
var surface := &"concrete"
var accepted := false
var strength := 1.0
const LIFE := .24

static func contact(projectile: Node2D, at: Vector2, hit_normal: Vector2, material: StringName, damaged: bool) -> void:
	if projectile.get_tree().get_nodes_in_group("shot_contacts").size() >= 48: return
	var effect = load("res://world/shared/combat/ShotFeedback.gd").new()
	effect.trail = (projectile.global_position - at).limit_length(70)
	effect.normal = hit_normal if not hit_normal.is_zero_approx() else -projectile.direction.normalized()
	effect.surface = material
	effect.accepted = damaged
	effect.strength = clampf(.75 + float(projectile.damage) / 70.0, .75, 1.4)
	projectile.get_parent().add_child(effect)
	effect.global_position = at
	effect.z_as_relative = false
	effect.z_index = 20
	effect.add_to_group("shot_contacts")

func _process(delta: float) -> void:
	age += delta
	if age >= LIFE: queue_free()
	else: queue_redraw()

func _draw() -> void:
	var fade := 1.0 - age / LIFE
	if age < .085 and trail.length_squared() > 1:
		draw_line(trail, Vector2.ZERO, Color(1, .89, .58, (1.0-age/.085)*.8), 1.25, true)
	var tint := Color(.78,.76,.69,fade*.7)
	if surface == &"metal": tint = Color(1,.88,.46,fade)
	elif surface == &"glass": tint = Color(.66,.87,.96,fade*.85)
	elif surface == &"wood": tint = Color(.58,.40,.23,fade*.8)
	elif surface == &"flesh": tint = Color(.85,.81,.73,fade*(.7 if accepted else .35))
	# Cloth contact is compact; rejected damage has no strong hit accent.
	var radius := (2.0 if surface == &"flesh" else 4.0) * strength
	for i in 4:
		var ray := normal.rotated((float(i)-1.5)*.48)
		var pos := ray * radius * (1.0+age*20.0)
		draw_line(pos-ray*radius*.7, pos, tint, 1.25, true)
	if age < .07 and (surface != &"flesh" or accepted):
		draw_circle(Vector2.ZERO, 2.3*strength, Color(1,.95,.79,1.0-age/.07))
