extends SceneTree
## Vídeo curto da polícia com corpo do Meshy: cada policial mira, dá três tiros (recuo e clarão) e recarrega,
## com a câmera de perto em três quartos. Usa o Movie Maker do Godot (renderizado, nunca headless).
## Uso: "$GODOT" --path . --write-movie evidence/npc-meshy/video/policia.avi --fixed-fps 30 --resolution 1280x720 --script res://tools/record_police_video.gd
const MODEL := preload("res://gameplay/PoliceModel.gd")
## [escalão, índice de aparência, arma]
const CAST := [[0, 1, "pistol"], [1, 0, "smg"], [2, 3, "smg"], [4, 2, "m4a1"]]
const SEGMENT := 4.0
var officers: Array = []
var camera: Camera3D
var frame := 0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	_build.call_deferred()

func _build() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.8
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	stage.add_child(ground)
	for k in CAST.size():
		var police := MODEL.new()
		police.tier = CAST[k][0]
		police.appearance_index = CAST[k][1]
		police.position = Vector3(k * 3.0, 0, 0)
		stage.add_child(police)
		officers.append(police)
	camera = Camera3D.new()
	camera.fov = 30.0
	stage.add_child(camera)
	camera.current = true
	await process_frame
	for k in officers.size(): officers[k].equip(CAST[k][2])
	ready_to_roll = true

var ready_to_roll := false

func _process(delta: float) -> bool:
	if not ready_to_roll: return false
	var t := float(frame) / 30.0
	var index := mini(int(t / SEGMENT), CAST.size() - 1)
	var local := t - float(index) * SEGMENT
	for k in officers.size():
		var police: Node3D = officers[k]
		var active := k == index
		var reloading := active and local > 2.4 and local < 3.7
		var progress := clampf((local - 2.4) / 1.3, 0.0, 1.0)
		# Três tiros em 1,0 s / 1,4 s / 1,8 s.
		if active and (is_equal_approx(snappedf(local, 1.0 / 30.0), 1.0) or is_equal_approx(snappedf(local, 1.0 / 30.0), 1.4) or is_equal_approx(snappedf(local, 1.0 / 30.0), 1.8)):
			police.attack()
		police.update_pose(delta, active and local > 0.3, reloading, progress, 0.0)
		police.rotation.y = deg_to_rad(-35.0) if active else 0.0
	var focus := Vector3(index * 3.0, 1.25, 0)
	var swing := deg_to_rad(20.0 + 12.0 * sin(local * 0.9))
	camera.position = focus + Vector3(sin(swing) * 3.1, 0.15, cos(swing) * 3.1)
	camera.look_at(focus, Vector3.UP)
	frame += 1
	if t >= SEGMENT * CAST.size():
		quit(0)
	return false
