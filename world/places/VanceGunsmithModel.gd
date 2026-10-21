extends "res://assets/CivilianModel.gd"
## Vance uses the same human scale, imported body and articulated hands as the
## modern townspeople. The shop owns this model and its lifetime.

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 841
	coat_color = Color("69714f")
	pants_color = Color("303a31")
	wardrobe_overrides = {"female": false, "build": 0, "top": 5, "bottom": 0,
		"shoe": 2, "height": 1.0, "hat": 1, "hair": 1, "beard": 1,
		"glasses": false, "backpack": false, "bag": 0,
		"accent": Color("444c35"), "shoe_color": Color("292b25")}
	# Fix the work uniform's source: a randomly selected pedestrian can contain
	# a bright baked jacket that an olive multiplier cannot neutralize.
	var uniform := "res://assets/civilians/meshy/police/tactical_gray.glb"
	if preload("res://assets/civilians/RoleBodyCatalog.gd").enabled and ResourceLoader.exists(uniform):
		body_source = uniform
		body_tint = {"tone": Color(.62, .72, .45), "brightness": .96}
		body_accessories = [{"kind": "cap", "color": Color("444c35"), "band": Color("262d24")}]
	super._ready()
	# Keep the staff solid independently from the counter. No extra actor,
	# damage/death API or individual viewport is needed for the service model.
	var solid := StaticBody3D.new()
	solid.name = "VanceBody"
	solid.collision_layer = 2
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "BodyCapsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.76
	shape.shape = capsule
	shape.position.y = .88
	solid.add_child(shape)
	add_child(solid)
