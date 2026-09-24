extends SceneTree
## Separate visual-depth check for the new Cobra vegetation. Collision is
## exercised by test_harbor_fidelity_contract.gd; this capture checks occlusion.

const REGION := preload("res://world/regions/NativeRegion.gd")
const OUTPUT_ROOT := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/harbor-fidelity"
const SCALE := 1.0/16.0

var camera: Camera3D
var actor: MeshInstance3D

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size = Vector2i(900,600)
	root.content_scale_size = root.size
	var stage := Node3D.new()
	root.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("82939a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5d1bd")
	environment.ambient_light_energy = .9
	environment_node.environment = environment
	stage.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62,-32,0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	stage.add_child(sun)
	var tree_point := Vector3(7580*SCALE,0,1610*SCALE)
	stage.add_child(REGION.build_region("harbor",tree_point))
	actor = MeshInstance3D.new()
	actor.name = "OcclusionProbe"
	var capsule := CapsuleMesh.new()
	capsule.radius = .34
	capsule.height = 1.8
	actor.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ff2bb7")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	actor.material_override = material
	actor.position = tree_point+Vector3(0,.9,1.3)
	stage.add_child(actor)
	camera = Camera3D.new()
	camera.position = tree_point+Vector3(0,8,11)
	camera.fov = 42
	stage.add_child(camera)
	camera.look_at(tree_point+Vector3(0,1.4,0))
	camera.make_current()
	for frame in 30: await process_frame
	await _save("occlusion-cobra-ahead")
	actor.position = tree_point+Vector3(0,.9,-1.3)
	for frame in 4: await process_frame
	await _save("occlusion-cobra-behind")
	quit(0)

func _save(id: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("%s/final-%s.png"%[OUTPUT_ROOT,id])
	assert(result==OK)
