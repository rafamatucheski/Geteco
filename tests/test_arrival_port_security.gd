extends SceneTree
## A chegada pública e o acesso à pesca nunca podem contar como invasão da área de carga.
class State extends RefCounted:
	var region_id := "harbor"
	var place_id := ""
class Driving extends RefCounted:
	var occupied := false
	var car: CharacterBody3D
class Combat extends Node:
	var reports := 0
	func register_crime(_points: int, _point: Vector3) -> void: reports += 1
class World extends Node3D:
	var player := CharacterBody3D.new()
	var driving := Driving.new()
	var gameplay := Combat.new()
	func _ready() -> void:
		add_child(player)
		add_child(gameplay)
class Session extends RefCounted:
	var ready_for_play := true
	var state := State.new()
	var world: World
	var admitting := false
	func has_position_transition() -> bool: return admitting
	func save_game() -> void: pass
	func show_message(_message: String) -> void: pass
	func show_speech(_speaker: String, _message: String, _duration := 5.0, _play_voice := true, _persona := "", _canonical := "", _character_id := "", _section := "") -> void: pass
class Checkpoint extends "res://gameplay/urban_v1/HarborPortSecurity.gd":
	# Exercita o scanner de produção sem montar os rigs de funcionários não relacionados.
	func _ready() -> void:
		active = true
		_was_active = true
		_staff_respawn.clear()
		set_process(false)
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var security = preload("res://gameplay/urban_v1/HarborPortSecurity.gd").new()
	for point in [Vector3(233,.56,188.2), Vector3(233,.2,194), Vector3(237,.2,202), Vector3(233,.2,202.6), Vector3(239,.2,195.1), Vector3(241,.56,189.2), Vector3(223,5.73,174.7), Vector3(223,.2,153)]:
		check(not security._inside_security_zone(point), "public passenger/fishing access stays peaceful at %s" % point)
	for point in [Vector3(245,0,203), Vector3(218.75,0,218.75), Vector3(266,0,192), Vector3(387.5,0,231.25)]:
		check(security._inside_security_zone(point), "freight yard, cargo ship and loading pier retain security at %s" % point)
	security.free()
	var session := Session.new()
	session.world = World.new()
	root.add_child(session.world)
	var checkpoint := Checkpoint.new()
	checkpoint.configure(session)
	root.add_child(checkpoint)
	session.world.player.position = Vector3(233,.2,194)
	checkpoint._process(.2)
	session.admitting = true
	session.world.player.position = Vector3(250,0,220)
	checkpoint._process(.2)
	check(not checkpoint.alerted and session.world.gameplay.reports == 0, "scripted relocation cannot report an invasion")
	session.admitting = false
	checkpoint._process(.2)
	check(not checkpoint.alerted and session.world.gameplay.reports == 0, "admitted location establishes the first security sample")
	session.world.player.position = Vector3(233,.2,202.6)
	checkpoint._process(.2)
	check(not checkpoint.alerted, "quay edge remains public after admission")
	session.world.player.position = Vector3(245,0,203)
	checkpoint._process(.2)
	check(checkpoint.alerted and session.world.gameplay.reports == 1, "voluntary unpaid freight entry still calls security")
	checkpoint._process(.2)
	check(session.world.gameplay.reports == 1, "remaining inside does not duplicate the report")
	checkpoint.restore_snapshot({"version":1,"authorized_entry":false,"authorized_visit":false,"exiting_port":false})
	checkpoint._process(.2)
	check(not checkpoint.alerted and session.world.gameplay.reports == 1, "save admission inside the port does not invent a new crime")
	checkpoint.free()
	session.world.free()
	print("ARRIVAL_PORT_SECURITY checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
