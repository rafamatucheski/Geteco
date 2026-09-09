extends SceneTree
const ENCOUNTER := preload("res://world/harbor/cobras/CobraEncounter.gd")
const BOSS := preload("res://world/harbor/cobras/CobraBoss.gd")
const BULLET := preload("res://Bullet.tscn")
var failures := 0
var completions := 0
class Subject extends CharacterBody2D:
	var is_dead := false
	var is_in_dialogue := false
	var is_control_disabled := false
	func take_damage(_amount: int, _player: bool = false) -> void: pass
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := Subject.new()
	player.add_to_group("player")
	player.position = Vector2(-150,0)
	world.add_child(player)
	for attempt in 2:
		var encounter := ENCOUNTER.new()
		encounter.configure("boss",PackedVector2Array([Vector2.ZERO,Vector2(0,100),Vector2(0,200)]))
		world.add_child(encounter)
		encounter.completed.connect(func(): completions += 1)
		encounter.set_physics_process(false)
		for actor in encounter.actors: actor.set_physics_process(false)
		var boss = encounter.actors[0]
		check(boss is BOSS and not encounter.actors[1] is BOSS,"Only leader receives new identity")
		check(boss.max_health==110 and boss.health==110 and boss.weapon_id=="smg","No health or weapon buff")
		check(boss.torso_node.has_node("CopperZip") and boss.left_upper_arm.has_node("ShoulderCap"),"Details attach to articulated bones")
		check(not boss.has_vest and boss.left_upper_arm.get_node("ShoulderCap").mesh is SphereMesh and boss.left_lower_leg.get_node("BootCuff").mesh is CylinderMesh,"Jacket uses rounded shoulders and tapered cuffs, not box armor")
		check(encounter.actors.size()==3 and get_nodes_in_group("cobra_boss").size()==1,"Retry has one boss and finite cast")
		await physics_frame
		await physics_frame
		if attempt==0 and "--capture" in OS.get_cmdline_user_args(): await _capture(encounter)
		var bullet := BULLET.instantiate()
		bullet.owner_body = player
		bullet.damage = 55
		bullet.position = Vector2(-90,0)
		bullet.direction = Vector2.RIGHT
		world.add_child(bullet)
		for frame in 20: await physics_frame
		check(boss.health==55,"Real player-owned projectile damages boss through physics")
		encounter._physics_process(.1)
		check(encounter.phase=="reposition","55 percent phase preserved")
		encounter._physics_process(5.1)
		check(encounter.phase=="last_stand","Retreat deadline progresses to final stand")
		for actor in encounter.actors: actor.take_damage(1000,true)
		encounter._physics_process(.1)
		encounter._physics_process(10)
		check(completions==attempt+1,"Completion emitted once per finite encounter")
		encounter.queue_free()
		await process_frame
		await process_frame
	print("COBRA_BOSS_RESULT failures=%d retries=2 real_bullet_hits=2" % failures)
	quit(0 if failures==0 else 1)
func _capture(encounter: Node) -> void:
	root.size = Vector2i(1100,700)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color("22262d")
	backdrop.size = Vector2(1100,700)
	layer.add_child(backdrop)
	for i in 3:
		var actor = encounter.actors[i]
		actor.viewport.size = Vector2i(400,500)
		actor.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for child in actor.viewport.get_children():
			if child is Camera3D:
				child.position = Vector3(2.2,1.9,-3.8)
				child.look_at(Vector3(0,.8,0))
		var portrait := TextureRect.new()
		portrait.texture = actor.viewport.get_texture()
		portrait.position = Vector2(10+i*360,60)
		portrait.size = Vector2(360,540)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.add_child(portrait)
		var caption := Label.new()
		caption.text = ["CHEFE COBRA · SMG","COBRA · ESCOPETA","COBRA · PISTOLA"][i]
		caption.position = Vector2(35+i*360,610)
		caption.add_theme_font_size_override("font_size",22)
		layer.add_child(caption)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("D:/geteco/cobra-boss-reference.png")==OK,"Rendered comparison saved")
	layer.queue_free()
