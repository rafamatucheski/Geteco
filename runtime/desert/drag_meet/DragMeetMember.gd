extends "res://runtime/desert/drag_meet/TrackParticipant.gd"
## Damageable entourage on authored, floor-checked anchors. No per-frame physics;
## the articulated rig owns idle/gesture LOD and the visit owns recovery.
const MODEL := preload("res://assets/CivilianModel.gd")
const OUTFIT := preload("res://runtime/desert/drag_meet/DragMeetWardrobe.gd")
var slot := 0

func _ready() -> void:
	super._ready()
	name = "VicenteCrew%d" % slot
	set_meta("gameplay_role","vicente_crew")
	set_meta("reaction_exempt",true)
	add_to_group("desert_drag_crew")
	collision_layer = 2
	collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.74
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = .87
	add_child(shape)
	visual = MODEL.new()
	visual.appearance_locked = true
	visual.appearance_variant = 9780+slot
	visual.wardrobe_overrides = {"female":slot==3,"height":1.0,"build":2 if slot<2 else slot%2,
		"skin":[Color("b97d5d"),Color("815339"),Color("d5ab87")][slot%3],
		"hair":4 if slot==3 else slot%3,"hair_color":Color("26201f"),"hat":1 if slot==4 else 0,"beard":0 if slot==3 else slot%3,"glasses":slot<2}
	OUTFIT.dress(visual)
	add_child(visual)
	OUTFIT.insignia(visual)

func converse(target: Vector3, speaking: bool, animate: bool) -> void:
	if dead: return
	var direction := target-global_position
	if direction.length_squared()>.01: visual.rotation.y = atan2(direction.x,direction.z)
	visual.activity = "talk" if speaking else ""
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(visual,animate)
