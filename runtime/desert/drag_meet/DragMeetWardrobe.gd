extends RefCounted
## Vicente's own crew shares a jacket and a simple stitched mark, not Cobra uniforms.
const COAT := Color("673444")
const PANTS := Color("282b30")
const TRIM := Color("d3c5a2")
static var _patch_mesh: BoxMesh
static var _patch_material: StandardMaterial3D

static func dress(model: Node3D) -> void:
	model.coat_color = COAT
	model.pants_color = PANTS
	model.wardrobe_overrides.merge({"top":1,"bottom":0,"shoe":0,"bag":0,"backpack":false,
		"top_color":COAT,"bottom_color":PANTS,"inner":Color("d9d2c2"),"accent":TRIM},true)

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
