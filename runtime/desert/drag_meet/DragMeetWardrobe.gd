extends RefCounted
## Vicente's own crew shares a jacket and a simple stitched mark, not Cobra uniforms.
const COAT := Color("41363d")
const PANTS := Color("282b30")
const TRIM := Color("d3c5a2")
static var _patch_mesh: BoxMesh
static var _patch_material: StandardMaterial3D

static func dress(model: Node3D) -> void:
	model.coat_color = COAT
	model.pants_color = PANTS
	model.wardrobe_overrides.merge({"top":2,"bottom":0,"shoe":1,"bag":0,"backpack":false,
		"top_color":COAT,"bottom_color":PANTS,"inner":Color("9b9b92"),"accent":TRIM,
		"body_profile":{"bust":false},"head_scale":Vector3.ONE*.94},true)

## Shared by the person at the meet, the seated driver and the baked portrait.
## Jackets use their continuous cloth shell rather than isolated chest bulges.
static func style_rival(model: Node3D, identity: String) -> void:
	var looks := {
		"rauhz":{"hair":2,"top":0,"top_color":Color("14171b"),"inner":Color("14171b"),"accent":Color("bd4b40")},
		"livia":{"hair":4,"top_color":Color("754534"),"inner":Color("b4aaa0"),"accent":Color("b26943")},
		"raul":{"hair":0,"top_color":Color("47513e"),"inner":Color("969082"),"accent":Color("736b4c")},
		"nadir":{"hair":2,"top_color":Color("293c4c"),"inner":Color("959ca0"),"accent":Color("4d6674")},
		"jessica":{"hair":3,"top_color":Color("bbb4a9"),"inner":Color("41464a"),"accent":Color("858b91")},
	}
	if not looks.has(identity): return
	model.wardrobe_overrides.merge({"top":2,"body_profile":{"bust":false},"head_scale":Vector3.ONE*.94},true)
	model.wardrobe_overrides.merge(looks[identity],true)

static func insignia(model: Node3D) -> void:
	if not is_instance_valid(model.spine): return
	if _patch_mesh == null:
		_patch_mesh = BoxMesh.new()
		_patch_mesh.size = Vector3(.042,.16,.012)
		_patch_material = StandardMaterial3D.new()
		_patch_material.albedo_color = TRIM
		_patch_material.roughness = .95
	for side in [-1.0,1.0]:
		var stitch := MeshInstance3D.new()
		stitch.name = "CrewStitch"
		stitch.mesh = _patch_mesh
		stitch.material_override = _patch_material
		stitch.position = Vector3(side*.043,.17,-.165)
		stitch.rotation.z = side*-.48
		stitch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.spine.add_child(stitch)
