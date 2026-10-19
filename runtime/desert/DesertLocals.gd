extends Node
## Residents use the native civilian body, steering, damage and reaction director.
## One admission per half-second; they count towards the existing population cap.
const ACTOR := preload("res://scripts/Actor.gd")
const MODEL := preload("res://assets/CivilianModel.gd")
const ROUTINES := [
	{"id":"miragem_clerk","a":Vector3(269,.08,-772),"b":Vector3(278,.08,-772),"identity":9611,"coat":"a98356","skin":"a26d49","female":false},
	{"id":"pump_attendant","a":Vector3(289,.08,-752),"b":Vector3(300,.08,-752),"identity":9612,"coat":"536b70","skin":"cd9a74","female":false},
	{"id":"truck_driver","a":Vector3(248,.08,-763),"b":Vector3(258,.08,-763),"identity":9613,"coat":"865940","skin":"b48563","female":false},
	{"id":"solana_customer","a":Vector3(-258,.08,-865),"b":Vector3(-250,.08,-865),"identity":9614,"coat":"a47654","skin":"c89a79","female":true},
	{"id":"alvorada_customer","a":Vector3(-184,.08,-865),"b":Vector3(-176,.08,-865),"identity":9615,"coat":"6e7251","skin":"885e45","female":true},
]
var session
var locals: Dictionary = {}
var retired: Dictionary = {}
var _clock := 0.0
var _elapsed := 0.0

func configure(owner_session) -> void:
	session=owner_session
	name="DesertLocals"
	# Antes do deserto no quadro, para o enfeite ceder a vez no quadro em que um morador nasce.
	process_priority=-1

func _process(delta: float) -> void:
	_elapsed+=delta
	_clock+=delta
	if _clock<.5 or not is_instance_valid(session) or not session.ready_for_play: return
	_clock=0.0
	var active: bool=session.state.region_id=="desert" and session.state.place_id.is_empty()
	var admitted:=false
	for routine in ROUTINES:
		var distance: float=session.world.player.global_position.distance_to(routine.a)
		var stored_actor = locals.get(routine.id)
		var actor: CharacterBody3D=stored_actor if is_instance_valid(stored_actor) else null
		if is_instance_valid(actor):
			if not active or distance>110:
				session.world.people.erase(actor)
				actor.queue_free()
				locals.erase(routine.id)
				continue
			if actor.dead:
				retired[routine.id]=true
				continue
			# The reaction director owns civilians during flight/recovery.
			if actor.controlled_automatically: continue
			var pause := fposmod(_elapsed+float(routine.identity%11),22.0)>17.0
			actor.speed=0.0 if pause else 1.15
			var routine_model: Node3D=actor.visual.get_child(0)
			routine_model.activity="talk" if pause else ""
			continue
		if locals.has(routine.id):
			locals.erase(routine.id)
			retired[routine.id]=true
		if not active or distance>150: retired.erase(routine.id)
		if not active or distance>75 or retired.has(routine.id) or admitted: continue
		if session.world.people.size()>=session.controller._population_cap(): continue
		# Espera só o chão do deserto, não o enfeite fatiado (DesertRegion.surfaces_idle): com
		# is_streaming_idle(), a 60 fps (padrão) o morador podia esperar ~27 s perto da arrancada (e1fad702).
		var ground: Node3D=session.controller.region
		if not (ground.surfaces_idle() if ground.has_method("surfaces_idle") else ground.is_streaming_idle()): continue
		if ground.has_method("yield_dressing_this_frame"): ground.yield_dressing_this_frame()
		session.controller.region.prepare_collision_at(routine.a)
		session.controller.region.prepare_collision_at(routine.b)
		var clear:=true
		for sample in 9:
			if not session.position_clear(routine.a.lerp(routine.b,float(sample)/8.0)):
				clear=false
				break
		if not clear: continue
		actor=ACTOR.new()
		actor.identity=int(routine.identity)
		actor.position=routine.a
		actor.route=PackedVector3Array([routine.a,routine.b])
		actor.speed=1.15
		actor.set_meta("region_id","desert")
		actor.set_meta("desert_routine",routine.id)
		session.world.add_child(actor)
		# Construct the authored outfit before attaching its rig to the real actor.
		for previous in actor.visual.get_children():
			actor.visual.remove_child(previous)
			previous.queue_free()
		var model:=MODEL.new()
		model.appearance_locked=true
		model.appearance_variant=int(routine.identity)
		model.coat_color=Color(routine.coat)
		model.pants_color=Color("4b4940")
		model.wardrobe_overrides={"female":routine.female,"skin":Color(routine.skin),"hair_color":Color("44352a"),"hat":1 if routine.id=="truck_driver" else 0,"top":0,"bottom":0,"shoe":0,"bag":0,"backpack":false}
		preload("res://assets/civilians/CivilianBodyCatalog.gd").apply_keeping_sex(model, int(model.appearance_variant))
		model.rotation.y=PI
		actor.visual.add_child(model)
		session.world.people.append(actor)
		locals[routine.id]=actor
		admitted=true
