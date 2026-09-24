extends Node
## Apresentação da reação civil: grito (áudio do V1) e balão de fala (textos do V1). Não decide nem move.
## Limites: no máximo MAX_VOICES gritos simultâneos e um balão por civil, com vida curta; tudo é liberado com o civil.
const MAX_VOICES := 3
const SCREAM_COOLDOWN := 4.0
const BUBBLE_LIFE := 2.5
const STREAMS := [
	"res://assets/gameplay/audio/panic_0.wav",
	"res://assets/gameplay/audio/panic_1.wav",
	"res://assets/gameplay/audio/panic_2.wav",
]
const PHRASES_PANIC := ["SOCORRO!", "PARA COM ISSO!", "CORRE!", "CUIDADO!"]
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")

var voices: Array[AudioStreamPlayer3D] = []
var streams: Array[AudioStream] = []
var last_scream := {}   ## instance_id -> tempo (s) do último grito
var bubbles := {}       ## instance_id -> {label, life}
var props := {}         ## instance_id -> phone or pistol mesh
var clock := 0.0

func _ready() -> void:
	for path in STREAMS:
		var stream := load(path) as AudioStream
		if stream: streams.append(stream)
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 45.0
		voice.unit_size = 6.0
		voice.volume_db = -4.0
		add_child(voice)
		voices.append(voice)

func scream(actor: Node3D) -> bool:
	if streams.is_empty() or not is_instance_valid(actor): return false
	var id := actor.get_instance_id()
	if clock - float(last_scream.get(id, -99.0)) < SCREAM_COOLDOWN: return false
	for voice in voices:
		if voice.playing: continue
		last_scream[id] = clock
		voice.stream = streams[randi() % streams.size()]
		voice.global_position = actor.global_position + Vector3.UP * 1.5
		voice.play()
		return true
	return false

func bubble(actor: Node3D, text: String) -> void:
	if not is_instance_valid(actor): return
	var id := actor.get_instance_id()
	var entry: Dictionary = bubbles.get(id, {})
	if entry.is_empty():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 40
		label.pixel_size = 0.006
		label.outline_size = 10
		label.modulate = Color(0.95, 0.65, 0.2)
		label.position = Vector3(0.0, 2.3, 0.0)
		actor.add_child(label)
		entry = {"label": label, "life": 0.0}
		bubbles[id] = entry
	entry.label.text = text
	entry.life = BUBBLE_LIFE

func random_phrase() -> String: return PHRASES_PANIC[randi() % PHRASES_PANIC.size()]

func _show_prop(actor: Node3D, kind: String) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.get("visual")): return
	var id := actor.get_instance_id()
	if props.has(id): return
	var holder := Node3D.new()
	holder.name = "ReactionProp"
	actor.visual.add_child(holder)
	if kind == "pistol":
		ARSENAL.build(holder, "pistol")
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.18, 0.025)
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("252a32")
		material.metallic = 0.1
		mesh.material_override = material
		holder.add_child(mesh)
	holder.position = Vector3(0.28, 1.5, -0.04) if kind == "phone" else Vector3(0.25, 1.13, -0.47)
	props[id] = holder
	var model: Node3D = actor.visual.get_child(0)
	if model.get("hand_targets") is Array:
		model.hand_targets[0] = holder.global_position

func show_phone(actor: Node3D) -> void: _show_prop(actor, "phone")

func show_pistol(actor: Node3D) -> void: _show_prop(actor, "pistol")

func hide_prop(actor: Node3D) -> void:
	if not is_instance_valid(actor): return
	var id := actor.get_instance_id()
	if not props.has(id): return
	var holder: Node3D = props[id]
	props.erase(id)
	if is_instance_valid(holder): holder.queue_free()
	var model: Node3D = actor.visual.get_child(0) if is_instance_valid(actor.get("visual")) else null
	if is_instance_valid(model) and model.get("hand_targets") is Array:
		model.hand_targets[0] = null

func clear_actor(actor_id: int) -> void:
	var entry: Dictionary = bubbles.get(actor_id, {})
	if not entry.is_empty() and is_instance_valid(entry.label): entry.label.queue_free()
	bubbles.erase(actor_id)
	last_scream.erase(actor_id)
	var prop: Variant = props.get(actor_id)
	if is_instance_valid(prop):
		var actor: Node3D = prop.get_parent().get_parent() as Node3D
		hide_prop(actor)
	else: props.erase(actor_id)

func clear_all() -> void:
	for id in bubbles.keys(): clear_actor(id)
	for id in props.keys(): clear_actor(id)
	last_scream.clear()

func _process(delta: float) -> void:
	clock += delta
	for id in bubbles.keys():
		var entry: Dictionary = bubbles[id]
		entry.life -= delta
		if entry.life <= 0.0 or not is_instance_valid(entry.label):
			if is_instance_valid(entry.label): entry.label.queue_free()
			bubbles.erase(id)
	for id in props.keys():
		var holder: Variant = props[id]
		if not is_instance_valid(holder):
			props.erase(id)
			continue
		var visual: Node3D = holder.get_parent()
		if visual.get_child_count() == 0: continue
		var model: Node3D = visual.get_child(0)
		if model.get("hand_targets") is Array: model.hand_targets[0] = holder.global_position
	if last_scream.size() > 64:
		for id in last_scream.keys():
			if clock - float(last_scream[id]) > SCREAM_COOLDOWN: last_scream.erase(id)
