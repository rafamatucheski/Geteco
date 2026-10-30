extends "res://world/places/NativePlace.gd"
## Academia Ferro Velho (Harbor). Usa o contrato das estações dos bares: `nearest_action` oferece o
## aparelho mais perto e `start_game` começa a série (o FullSession já despacha "bar_game" para o
## lugar e não deixa salvar com `game_active`). Uma série trava o Dante no aparelho, toca o clipe do
## Mixamo pelo Gameplay (`exercise_clip`) e, completa, sobe força ou fôlego em `GymState`.
const ID := "harbor_gym"
const GYM := preload("res://activities/gym/GymState.gd")
## Lote do lado do Lastro, conferido na captura (em x 22 o canto oeste encostava no ponto de ônibus).
const EXTERIOR := Vector3(26, 0, 54)
## Onde o Dante fica em cada aparelho (local), virado para −Z. Batem com GymModel.
const STATIONS := {
	"punching_bag": Vector3(-4.0, 0, -2.25),
	"speedbag": Vector3(-2.0, 0, -2.9),
	"bicep_curl": Vector3(.3, 0, -2.75),
	"push_up": Vector3(2.3, 0, -2.3),
	"treadmill": Vector3(4.3, 0, -2.3),
	"jump_rope": Vector3(-3.6, 0, 1.3),
	"air_squat": Vector3(-1.6, 0, 1.3),
	"situps": Vector3(3.6, 0, 1.3),
}
## Uma série: o tempo do clipe em laço até completar. Sair antes não conta.
const SET_SECONDS := 8.0
const REACH := 1.1
var session
var game_active := false
var _station := ""
var _age := 0.0
var _was_locked := false
var _opened_health := 0.0

static func definition_data() -> Dictionary:
	var reward := {"id":"ferro_velho_first_aid","kind":"item","item":"first_aid","amount":1,"local_position":Vector3(-4.9,0,-.9)}
	return {"id":ID,"original_name":"Ferro Velho","region":"harbor","source_id":"ferro_velho",
		"model":"res://world/places/gym/GymModel.gd",
		"exterior_position":EXTERIOR,"entry_position":EXTERIOR+Vector3(0,0,5.4),"return_position":EXTERIOR+Vector3(0,0,6.4),
		"spawn":Vector3(0,0,2.6),"exit":Vector3(0,0,3.3),"size":Vector2(11,8),"camera_target":Vector3(0,.7,0),"camera_size":12.5,
		"variant":0,"service":"gym","reward":reward,"rewards":[reward],"npc_model":"","npc_point":Vector3.ZERO,
		"npcs":[],"integration_status":"native"}

func _ready() -> void:
	super._ready()
	for station in STATIONS: interaction_points[station] = to_global(STATIONS[station])
	set_process(false)

func on_session_entered(owner_session) -> void:
	session = owner_session

func nearest_action(owner_session) -> Dictionary:
	if game_active or owner_session.modal or not active or owner_session.world.gameplay.health <= 0: return {}
	var result := {}
	var distance := REACH
	for key in STATIONS:
		var separation: float = owner_session.world.player.global_position.distance_to(interaction_points[key])
		if separation < distance:
			distance = separation
			var saved: Dictionary = GYM.data(owner_session.state.world_state)
			var attribute: String = GYM.STATIONS[key]
			var level := int(saved.get(attribute, 0))
			result = {"id":"bar_game","target":key,"label":"%s · %s %d/%d" % [GYM.LABELS[key], "Força" if attribute == "strength" else "Fôlego", level, GYM.MAX_LEVEL]}
	return result

func start_game(kind: String, owner_session) -> bool:
	if not STATIONS.has(kind) or nearest_action(owner_session).get("target","") != kind: return false
	var gameplay = owner_session.world.gameplay
	if not gameplay.has_method("play_exercise") or not gameplay.play_exercise("mixgym/" + kind, 0.0): return false
	session = owner_session
	_station = kind
	_age = 0.0
	_opened_health = float(gameplay.health)
	var player = owner_session.world.player
	_was_locked = bool(player.input_locked)
	player.input_locked = true
	player.global_position = to_global(STATIONS[kind])
	player.velocity = Vector3.ZERO
	player.visual.rotation.y = global_rotation.y
	game_active = true
	if kind == "bicep_curl": _hold_dumbbell(player)
	set_process(true)
	return true

## Halter na mão direita durante a rosca (o clipe fecha a mão no vazio sem ele).
var _dumbbell: Node3D
func _hold_dumbbell(player) -> void:
	var skeleton: Skeleton3D = player.get("skeleton")
	if skeleton == null or skeleton.find_bone("RightHand") < 0: return
	var mount := BoneAttachment3D.new()
	mount.bone_name = "RightHand"
	skeleton.add_child(mount)
	_dumbbell = mount
	var bar := MeshInstance3D.new()
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = .016
	bar_mesh.bottom_radius = .016
	bar_mesh.height = .3
	bar.mesh = bar_mesh
	bar.position = Vector3(0, .09, .03)
	bar.rotation.z = PI * .5
	mount.add_child(bar)
	for side in [-1, 1]:
		var plate := MeshInstance3D.new()
		var plate_mesh := CylinderMesh.new()
		plate_mesh.top_radius = .055
		plate_mesh.bottom_radius = .055
		plate_mesh.height = .05
		plate.mesh = plate_mesh
		plate.position = Vector3(side * .12, 0, 0)
		bar.add_child(plate)
	# Mesmo material do metal escuro dos aparelhos (variante já aquecida pela sala).
	var metal: Material = model.material("202325", "metal") if model.has_method("material") else null
	for mesh in mount.find_children("*", "MeshInstance3D", true, false): mesh.material_override = metal

func _drop_dumbbell() -> void:
	if is_instance_valid(_dumbbell): _dumbbell.queue_free()
	_dumbbell = null

## Qualquer tecla de movimento ou de voltar interrompe a série (sem ganho).
func handle_game_input(event: InputEvent) -> bool:
	if not game_active: return false
	for action in ["ui_cancel", "pause_game", "move_up", "move_down", "move_left", "move_right", "interact"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_finish(false)
			return true
	return false

func _process(delta: float) -> void:
	if not game_active: return
	if not is_instance_valid(session) or session.room != self or not active or session.world.gameplay.health < _opened_health:
		_finish(false)
		return
	_age += delta
	if is_instance_valid(model) and model.has_method("animate"): model.animate(_station, _age)
	var clip_length: float = session.world.gameplay.exercise_length()
	if clip_length > 0.0: session.world.gameplay.exercise_time = fposmod(_age, clip_length)
	if _age >= SET_SECONDS: _finish(true)

func _finish(complete: bool) -> void:
	if not game_active: return
	game_active = false
	set_process(false)
	if is_instance_valid(model) and model.has_method("rest"): model.rest()
	_drop_dumbbell()
	if is_instance_valid(session):
		session.world.gameplay.stop_exercise()
		session.world.player.input_locked = _was_locked
		if complete:
			var result: Dictionary = GYM.complete_set(session.state.world_state, _station)
			if result.get("ok", false):
				var name: String = "Força" if result.attribute == "strength" else "Fôlego"
				session.show_message(("%s subiu para %d/%d." if result.raised else "%s no máximo (%d/%d).") % [name, result.level, GYM.MAX_LEVEL])
				session.save_game()
	_station = ""

func set_active(value: bool) -> void:
	if not value: _finish(false)
	super.set_active(value)

func _exit_tree() -> void:
	_finish(false)
