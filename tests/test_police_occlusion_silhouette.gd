extends SceneTree
const AID := preload("res://gameplay/PoliceOcclusionSilhouette.gd")
var failures := 0
var checks := 0

class Controller extends Node3D:
	var state := {"place_id": ""}

class Officer extends Node3D:
	var controller: Node3D
	var dead := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("POLICE_SILHOUETTE ", "PASS " if ok else "FAIL ", label)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 5, 10)
	camera.make_current()
	var gameplay := Controller.new()
	scene.add_child(gameplay)
	var officer := Officer.new()
	officer.controller = gameplay
	scene.add_child(officer)
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position.y = 1.0
	officer.add_child(body)
	var accessory := MeshInstance3D.new()
	accessory.mesh = BoxMesh.new()
	var unrelated := StandardMaterial3D.new()
	accessory.material_overlay = unrelated
	officer.add_child(accessory)
	var aid := AID.new()
	officer.add_child(aid)
	aid.set_process(false)
	aid._process(0.0)
	check(body.material_overlay is ShaderMaterial, "exterior police receive overlay")
	check(body.material_overlay.get_shader_parameter("tint") == AID.TINT, "distinct police blue")
	check(accessory.material_overlay == unrelated, "existing overlay preserved")
	officer.position.x = 4
	aid._process(0.01)
	check(body.material_overlay.get_shader_parameter("target_inverse") == Projection(officer.global_transform.affine_inverse()), "moving officer updates own reference every frame")
	gameplay.state.place_id = "harbor_bank"
	aid._process(0.01)
	check(body.material_overlay == null, "interior removes effect immediately")
	gameplay.state.place_id = ""
	aid._process(0.01)
	check(body.material_overlay != null, "return outdoors restores effect")
	officer.hide()
	aid._process(0.01)
	check(body.material_overlay == null, "hidden officer loses effect")
	officer.show()
	officer.position.x = 100
	aid._process(0.01)
	check(body.material_overlay == null, "distant officer stays inactive")
	officer.position.x = 0
	aid._process(0.01)
	check(body.material_overlay != null, "approaching officer reactivates")
	body.queue_free()
	await process_frame
	var replacement := MeshInstance3D.new()
	replacement.mesh = CapsuleMesh.new()
	officer.add_child(replacement)
	aid._process(0.3)
	check(replacement.material_overlay != null, "rebuilt model receives effect")
	officer.dead = true
	aid._process(0.01)
	check(replacement.material_overlay == null and not aid.is_processing(), "death removes effect and stops updates")
	check(accessory.material_overlay == unrelated, "cleanup preserves unrelated overlay")
	var real_officer := preload("res://gameplay/dispatch/DispatchOfficer.gd").new()
	scene.add_child(real_officer)
	var integrated := false
	for child in real_officer.get_children():
		if child.get_script() == AID: integrated = true
	check(integrated, "dispatch officers inherit silhouette component")
	scene.queue_free()
	await process_frame
	print("POLICE_SILHOUETTE ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
