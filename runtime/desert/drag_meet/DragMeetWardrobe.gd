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
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").apply(model)

## Compartilhado pela pessoa no encontro, pelo motorista sentado e pelo retrato bakeado.
## As jaquetas usam a casca de tecido contínua em vez de volumes isolados no peito.
static func style_rival(model: Node3D, identity: String) -> void:
	var looks := {
		"rauhz":{"hair":2,"top":0,"top_color":Color("14171b"),"inner":Color("14171b"),"accent":Color("bd4b40")},
		"livia":{"hair":4,"top_color":Color("754534"),"inner":Color("b4aaa0"),"accent":Color("b26943")},
		"raul":{"hair":0,"top_color":Color("47513e"),"inner":Color("969082"),"accent":Color("736b4c")},
		"nadir":{"hair":2,"top_color":Color("293c4c"),"inner":Color("959ca0"),"accent":Color("4d6674")},
		"jessica":{"hair":3,"top_color":Color("bbb4a9"),"inner":Color("41464a"),"accent":Color("858b91")},
	}
	if identity == "vicente":
		vicente(model)
		return
	if identity.begins_with("open_"):
		model.wardrobe_overrides["female"] = identity in ["open_celia","open_mara","open_luna"]
		preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").apply(model)
		return
	if not looks.has(identity): return
	model.wardrobe_overrides.merge({"top":2,"body_profile":{"bust":false},"head_scale":Vector3.ONE*.94},true)
	model.wardrobe_overrides.merge(looks[identity],true)
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").apply(model)

## Vicente tem corpo próprio do Meshy (20/10/2026): jaqueta curta da turma com a marca já pintada na
## textura. Personagem de história visto de perto não sorteia corpo do catálogo de pedestres; sem o
## catálogo ligado (`GETECO_NO_MESHY_BODIES`) cai na roupa articulada da turma, como antes.
const VICENTE_BODY := "res://assets/civilians/meshy/vicente/vicente.glb"

static func vicente(model: Node3D) -> void:
	dress(model)
	if model.body_source == "": return
	model.body_source = VICENTE_BODY
	model.body_tint = {}
	model.body_accessories = []

static func insignia(model: Node3D) -> void:
	# O corpo do Meshy já traz a marca bordada; os pontos soltos boiariam fora da jaqueta.
	if model.get("body_source") != null and model.body_source == VICENTE_BODY: return
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
