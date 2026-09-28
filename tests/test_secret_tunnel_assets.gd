extends SceneTree

class SessionMock extends Node:
	var world: Node3D

class WorldMock extends Node3D:
	var player: CharacterBody3D

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool,label: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error("SECRET_TUNNEL FAIL "+label)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var world := WorldMock.new()
	host.add_child(world)
	world.player = CharacterBody3D.new()
	world.add_child(world.player)
	var session := SessionMock.new()
	session.world = world
	host.add_child(session)
	var tunnel = preload("res://gameplay/urban_v1/SecretTunnel3D.gd").new()
	world.add_child(tunnel)
	tunnel.configure(session)
	check(tunnel.position.is_equal_approx(Vector3(-409.4,-8.86,99.65)),"authored outside Casa1 cellar's west wall")
	check(is_equal_approx(tunnel.rotation.y,PI),"stair points away from the rotated cellar wall")
	check(tunnel.entry_global().y < -4.0,"hidden shelf lands in basement depth")
	check(tunnel.entry_global().distance_to(Vector3(-409.4,-4.31,92.45)) < .02,"tunnel landing sits beyond the cellar bookshelf")
	check(tunnel.contains(tunnel.entry_global()),"tunnel owns its upper landing")
	check(not tunnel.contains(Vector3(-408.0,-4.3,87.0)),"cellar keeps its camera outside the tunnel landing")
	check(tunnel.headquarters_global().y < -8.0,"headquarters remains below the surface")
	check(tunnel.solids.size() >= 20,"solid inventory covers tunnel and headquarters")
	check(tunnel.lights.size() <= 9,"bounded real-light budget")
	check(tunnel.rats.size() == 3,"three lightweight rats authored")
	check(tunnel.tunnel_camera.cull_mask == (1 << 18),"underground camera excludes streamed surface")
	check(tunnel.lights.all(func(light): return (light.layers & tunnel.tunnel_camera.cull_mask) != 0),"underground camera can see every local light")
	check(tunnel.find_children("*","GeometryInstance3D",true,false).all(func(node): return node.layers == (1 << 18)),"tunnel visuals stay on underground layer")
	for body in tunnel.solids:
		check(body.has_meta("interior_solid_id"),"every solid has depth identity")
	check(not tunnel.visible,"tunnel starts suspended")
	tunnel.set_enabled(true)
	check(tunnel.visible,"tunnel can be activated")
	check(tunnel.solids.all(func(body): return body.collision_layer==1),"activation restores collisions")
	tunnel.set_enabled(false)
	check(tunnel.solids.all(func(body): return body.collision_layer==0),"suspension removes collisions")
	var audio = preload("res://gameplay/urban_v1/SecretTunnelAudio.gd").new()
	host.add_child(audio)
	audio.configure(world.player)
	var sfx := AudioServer.get_bus_index(&"SFX")
	var old_send := AudioServer.get_bus_send(sfx) if sfx>=0 else &"Master"
	audio.set_active(true)
	check(audio.active,"audio zone activates")
	audio.set_active(false)
	check(not audio.active,"audio zone deactivates")
	if sfx>=0: check(AudioServer.get_bus_send(sfx)==old_send,"SFX routing restored after tunnel")
	host.queue_free()
	await process_frame
	print("SECRET_TUNNEL PASS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
