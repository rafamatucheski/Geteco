extends CharacterBody3D
## Helena fora do caixa (cais, ponto de ônibus, rua do banco): mesmo rig dos contatos autorais do
## deserto (CivilianModel com aparência travada), roupa de banco. Não leva dano nem reage a crime:
## é personagem de cena, montado só perto e devolvido ao se afastar.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const LOOK := {"variant": 9601, "coat": "33415a", "pants": "26282d", "skin": "c79676", "hair": "231a16",
	"height": .97, "build": 0, "female": true, "hat": 0, "beard": 0, "glasses": false}
var visual: Node3D
## Mala de rodinha da despedida (M07).
var with_suitcase := false

func _ready() -> void:
	name = "Helena"
	set_meta("gameplay_role", "story_contact")
	set_meta("reaction_exempt", true)
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.72 * float(LOOK.height)
	shape.shape = capsule
	shape.position.y = capsule.height * .5
	add_child(shape)
	visual = CIVILIAN.new()
	visual.appearance_locked = true
	visual.appearance_variant = int(LOOK.variant)
	visual.coat_color = Color(LOOK.coat)
	visual.pants_color = Color(LOOK.pants)
	visual.wardrobe_overrides = {"female": LOOK.female, "height": LOOK.height, "build": LOOK.build, "skin": Color(LOOK.skin),
		"hair_color": Color(LOOK.hair), "hat": LOOK.hat, "beard": LOOK.beard, "glasses": LOOK.glasses, "bag": 1, "backpack": false,
		"top": 1, "bottom": 0, "shoe": 0}
	add_child(visual)
	if with_suitcase:
		# Mala com uma roda quebrada: o carrinho tomba para um lado.
		var part = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
		var bag := Node3D.new()
		bag.position = Vector3(.45, 0, .1)
		bag.rotation.z = .06
		add_child(bag)
		part.piece(bag, Vector3(.40, .58, .24), Vector3(0, .36, 0), Color("6a2f2b"))
		part.piece(bag, Vector3(.03, .38, .03), Vector3(-.12, .84, 0), Color("2b2b2b"))
		part.piece(bag, Vector3(.03, .38, .03), Vector3(.12, .84, 0), Color("2b2b2b"))
		part.piece(bag, Vector3(.27, .03, .03), Vector3(0, 1.03, 0), Color("2b2b2b"))
		part.piece(bag, Vector3(.06, .06, .06), Vector3(-.15, .03, 0), Color("161616"))

func _physics_process(delta: float) -> void:
	velocity = Vector3(0, maxf(-20.0, velocity.y - 18.0 * delta), 0)
	move_and_slide()

func face(point: Vector3) -> void:
	var direction := point - global_position
	direction.y = 0
	if direction.length() > .05: visual.rotation.y = atan2(direction.x, direction.z)

func set_talking(value: bool) -> void:
	if is_instance_valid(visual) and "activity" in visual: visual.activity = "talk" if value else ""
