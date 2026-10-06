extends CharacterBody3D
## Authored contacts: distinct wardrobe/body/face, existing articulated human rig.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const LOOKS := {
	"vicente":{"name":"Vicente","variant":9511,"coat":"6b5142","pants":"292d30","skin":"c38d6e","hair":"25201d","height":1.04,"build":1,"female":false,"hat":0,"beard":2,"glasses":false},
	"livia":{"name":"Lívia","variant":9512,"coat":"be6038","pants":"343539","skin":"8e5d42","hair":"1f1a17","height":.97,"build":0,"female":true,"hat":0,"beard":0,"glasses":true},
	"raul":{"name":"Raul","variant":9513,"coat":"65764c","pants":"625344","skin":"d2a37c","hair":"6d675e","height":1.07,"build":2,"female":false,"hat":1,"beard":3,"glasses":false},
	"nadir":{"name":"Nadir","variant":9514,"coat":"374f66","pants":"343434","skin":"a56f4b","hair":"171718","height":1.0,"build":1,"female":false,"hat":0,"beard":1,"glasses":true},
	"bia":{"name":"Bia","variant":9515,"coat":"446973","pants":"36464a","skin":"d5a57c","hair":"613b25","height":.96,"build":1,"female":true,"hat":1,"beard":0,"glasses":false},
	"irene":{"name":"Irene","variant":9516,"coat":"897961","pants":"3b3635","skin":"c5a484","hair":"9b9289","height":.98,"build":0,"female":true,"hat":0,"beard":0,"glasses":true},
}
var identity_id := "vicente"
var visual: Node3D
func _ready() -> void:
	var look: Dictionary = LOOKS[identity_id]
	name = look.name
	set_meta("gameplay_role","desert_contact")
	set_meta("reaction_exempt",true)
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
	visual = CIVILIAN.new()
	visual.appearance_locked = true
	visual.appearance_variant = int(look.variant)
	visual.coat_color = Color(look.coat)
	visual.pants_color = Color(look.pants)
	visual.wardrobe_overrides = {"female":look.female,"height":look.height,"build":look.build,"skin":Color(look.skin),"hair_color":Color(look.hair),"hat":look.hat,"beard":look.beard,"glasses":look.glasses,"bag":0,"backpack":false,"top":1,"bottom":0,"shoe":0}
	add_child(visual)
func _physics_process(delta: float) -> void:
	velocity = Vector3(0, maxf(-20.0,velocity.y-18.0*delta),0)
	move_and_slide()
func set_talking(value: bool) -> void:
	visual.activity = "talk" if value else ""
