extends SceneTree
const ACTOR:=preload("res://scripts/Actor.gd")
const SKATE:=preload("res://activities/skate/Skate.gd")
const BOARD:=preload("res://activities/skate/SkateBody.gd")
const DIRECTOR:=preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")
class Population extends Node3D:
	var people: Array=[]
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("SKATE_CIVILIAN_ESCAPE ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func run() -> void:
	var scene:=Population.new()
	root.add_child(scene)
	var floor_body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(40,1,40)
	collider.shape=shape
	collider.position.y=-.5
	floor_body.add_child(collider)
	scene.add_child(floor_body)
	var actor:=ACTOR.new()
	actor.identity=82200
	scene.add_child(actor)
	actor.position=Vector3(5,.08,5)
	actor.route=PackedVector3Array([actor.position,actor.position+Vector3.RIGHT*5])
	scene.people.append(actor)
	var skate:=SKATE.new()
	skate.set_physics_process(false)
	scene.add_child(skate)
	var board:=BOARD.new()
	scene.add_child(board)
	board.set_physics_process(false)
	board.position=actor.position
	skate._attach_ambient(actor,board,false)
	check(not actor.is_physics_processing() and board.rider==actor,"skate possui o movimento antes do perigo")
	var director:=DIRECTOR.new()
	scene.add_child(director)
	director.configure(scene,null)
	var start:=actor.position
	director.report_gunfire(start+Vector3.RIGHT*6,start+Vector3.LEFT*20)
	check(actor.is_physics_processing() and actor.controlled_automatically,"tiro transfere a física para a fuga")
	check(skate.ambient.is_empty() and board.rider==null and not board.riding,"skate não continua escrevendo a posição")
	check(not actor.has_meta("civilian_movement_owner") and actor.health==100,"transferência limpa não causa dano")
	for frame in 90: await physics_frame
	check(actor.position.distance_to(start)>3,"corrida física desloca o antigo skatista")
	director.reset_population()
	check(not actor.controlled_automatically and is_equal_approx(actor.speed,1.6),"retomada devolve velocidade e controle")
	scene.free()
	print("SKATE_CIVILIAN_ESCAPE failures=",failures)
	quit(0 if failures==0 else 1)
