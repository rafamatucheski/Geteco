extends SceneTree
const DIRECTOR := preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")

class Witness extends CharacterBody3D:
	var health := 100.0
	var dead := false
	var is_player := false
	var speed := 1.5
	var controlled_automatically := false
	var automatic_direction := Vector3.ZERO

class IdentifiedWitness extends Witness:
	var identity: Variant = 0

class Context extends Node:
	var player: Node3D
	var health := 100.0
	func attack_allowed() -> bool: return true

class Presentation extends Node:
	var screams := 0
	func scream(_person: Node3D) -> bool:
		screams += 1
		return true
	func clear_actor(_id: int) -> void: pass
	func clear_all() -> void: pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var player := Node3D.new()
	scene.add_child(player)
	var context := Context.new()
	context.player = player
	scene.add_child(context)
	var director := DIRECTOR.new()
	director.gameplay = context
	scene.add_child(director)
	director.set_physics_process(false)
	var presentation := Presentation.new()
	director.add_child(presentation)
	director.presenter = presentation
	var witness := Witness.new()
	witness.set_meta("gameplay_role","civilian")
	scene.add_child(witness)
	witness.position = Vector3(2,0,0)
	check(director.report_assault(witness,player),"Unidentified witness accepts real player assault report")
	check(director.reactors.has(witness.get_instance_id()),"Unidentified witness receives reaction state")
	if director.reactors.has(witness.get_instance_id()):
		check(director.reactors[witness.get_instance_id()].phase == "panic","Unidentified witness flees instead of inventing aggressive temperament")
	check(presentation.screams == 1,"Unidentified witness receives panic presentation")
	var identified := IdentifiedWitness.new()
	scene.add_child(identified)
	identified.position = Vector3(2,0,0)
	for value in [null,"unknown",{},18.5]:
		identified.identity = value
		check(director._response(identified,player) == "panic","Invalid identity safely falls back to panic: " + str(value))
	for entry in [{"id":0,"phase":"panic"},{"id":11,"phase":"call"},{"id":15,"phase":"melee"},{"id":18,"phase":"armed"}]:
		identified.identity = entry.id
		check(director._response(identified,player) == entry.phase,"Valid identity preserves temperament: " + str(entry.id))
	director.reset_population()
	check(not witness.controlled_automatically and is_equal_approx(witness.speed,1.5),"Cleanup restores witness movement")
	var resident := RESIDENT.new()
	resident.configure({"id":"identity_regression_resident","position":Vector3(2,0,0)})
	scene.add_child(resident)
	resident.set_physics_process(false)
	check(not director.report_assault(resident,player),"Production village resident keeps its own movement and combat controller")
	check(not director.reactors.has(resident.get_instance_id()),"Village resident cannot enter generic reaction state")
	check(resident.health == 90.0 and not resident.hostile,"Director leaves village resident state untouched")
	scene.queue_free()
	await process_frame
	print("CIVILIAN_MISSING_IDENTITY checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
