extends "res://assets/CivilianModel.gd"
## O Vance usa a mesma escala humana, corpo importado e mãos articuladas dos
## moradores modernos. A loja é dona deste modelo e do tempo de vida dele.

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 841
	coat_color = Color("69714f")
	pants_color = Color("303a31")
	wardrobe_overrides = {"female": false, "build": 0, "top": 5, "bottom": 0,
		"shoe": 2, "height": 1.0, "hat": 1, "hair": 1, "beard": 1,
		"glasses": false, "backpack": false, "bag": 0,
		"accent": Color("444c35"), "shoe_color": Color("292b25")}
	# Fixa a fonte do uniforme de trabalho: um pedestre escolhido ao acaso pode ter
	# uma jaqueta clara embutida que um multiplicador oliva não consegue neutralizar.
	var uniform := "res://assets/civilians/meshy/police/tactical_gray.glb"
	if preload("res://assets/civilians/RoleBodyCatalog.gd").enabled and ResourceLoader.exists(uniform):
		body_source = uniform
		body_tint = {"tone": Color(.62, .72, .45), "brightness": .96}
		body_accessories = [{"kind": "cap", "color": Color("444c35"), "band": Color("262d24")}]
	super._ready()
	# Mantém o sólido do funcionário independente do balcão. O modelo de atendimento não precisa
	# de ator extra, API de dano/morte nem viewport individual.
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
