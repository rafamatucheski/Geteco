extends CharacterBody3D
## Authored contacts: distinct wardrobe/body/face, existing articulated human rig.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const CREW_OUTFIT := preload("res://runtime/desert/drag_meet/DragMeetWardrobe.gd")
const LOOKS := {
	"rauhz":{"name":"Rauhz","variant":9517,"coat":"14171b","pants":"292d33","skin":"d6aa91","hair":"584232","height":1.02,"build":1,"female":false,"hat":0,"beard":1,"glasses":false},
	"vicente":{"name":"Vicente","variant":9511,"coat":"6b5142","pants":"292d30","skin":"c38d6e","hair":"25201d","height":1.04,"build":1,"female":false,"hat":0,"beard":2,"glasses":false},
	"livia":{"name":"Lívia","variant":9512,"coat":"be6038","pants":"343539","skin":"8e5d42","hair":"1f1a17","height":.97,"build":0,"female":true,"hat":0,"beard":0,"glasses":true},
	"raul":{"name":"Raul","variant":9513,"coat":"65764c","pants":"625344","skin":"d2a37c","hair":"6d675e","height":1.07,"build":2,"female":false,"hat":1,"beard":3,"glasses":false},
	"nadir":{"name":"Nadir","variant":9514,"coat":"374f66","pants":"343434","skin":"a56f4b","hair":"171718","height":1.0,"build":1,"female":false,"hat":0,"beard":1,"glasses":true},
	"bia":{"name":"Bia","variant":9515,"coat":"446973","pants":"36464a","skin":"d5a57c","hair":"613b25","height":.96,"build":1,"female":true,"hat":1,"beard":0,"glasses":false},
	"irene":{"name":"Irene","variant":9516,"coat":"897961","pants":"3b3635","skin":"c5a484","hair":"9b9289","height":.98,"build":0,"female":true,"hat":0,"beard":0,"glasses":true},
	# Ato 2 (runtime/desert/act2): o piloto dos Cobras e o advogado de Vicente.
	"cascavel":{"name":"Cascavel","variant":9518,"coat":"2b2f24","pants":"1d1f1c","skin":"b98a66","hair":"151515","height":1.03,"build":2,"female":false,"hat":0,"beard":1,"glasses":true},
	"teodoro":{"name":"Teodoro","variant":9519,"coat":"3a3f4a","pants":"2c3038","skin":"d7b49a","hair":"6b6b6b","height":.98,"build":1,"female":false,"hat":0,"beard":0,"glasses":true},
	"jessica":{"name":"Jessica","variant":9301,"coat":"d8d0c6","pants":"27323b","skin":"efc5a5","hair":"d7b969","height":1.0,"build":0,"female":true,"hat":0,"beard":0,"glasses":false},
}
var identity_id := "vicente"
var visual: Node3D
var health := 100.0
var dead := false
func _ready() -> void:
	var look: Dictionary = LOOKS[identity_id]
	name = look.name
	set_meta("gameplay_role","desert_contact")
	set_meta("reaction_exempt",true)
	if identity_id=="vicente":
		add_to_group("desert_drag_crew")
	add_to_group("v2_damageable")
	add_to_group("police_witness")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.72 * float(look.height)
	shape.shape = capsule
	shape.position.y = capsule.height*.5
	add_child(shape)
	if identity_id=="jessica":
		visual = preload("res://gameplay/jessica/JessicaModel.gd").new()
		CREW_OUTFIT.style_rival(visual,identity_id)
		add_child(visual)
		add_to_group("jessica_character")
		return
	visual = CIVILIAN.new()
	visual.appearance_locked = true
	visual.appearance_variant = int(look.variant)
	visual.coat_color = Color(look.coat)
	visual.pants_color = Color(look.pants)
	visual.wardrobe_overrides = {"female":look.female,"height":look.height,"build":look.build,"skin":Color(look.skin),"hair_color":Color(look.hair),"hat":look.hat,"beard":look.beard,"glasses":look.glasses,"bag":0,"backpack":false,"top":1,"bottom":0,"shoe":0}
	CREW_OUTFIT.style_rival(visual,identity_id)
	if identity_id=="vicente": CREW_OUTFIT.dress(visual)
	add_child(visual)
	if identity_id=="vicente": CREW_OUTFIT.insignia(visual)
func _physics_process(delta: float) -> void:
	velocity = Vector3(0, maxf(-20.0,velocity.y-18.0*delta),0)
	move_and_slide()
func set_talking(value: bool) -> void:
	if dead: return
	if is_instance_valid(visual): visual.activity = "talk" if value else ""

func receive_damage(amount: float, source: Node = null) -> void:
	preload("res://runtime/desert/drag_meet/TrackParticipantDamage.gd").receive(self,visual,amount,source)
