extends RefCounted
## Reuse authored, recorded dialogue on its actual owner. One ambient utterance
## at a time, once per person per visit; no synthetic voices or story spoilers.
const VOICE := preload("res://audio/ActorDialogueVoice.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const LINES := {
	"livia":{"persona":"lívia","text":"Tem largada de manhã, de tarde e de noite. Chegue com o carro inteiro e respeite a pista."},
	"raul":{"persona":"raul","text":"Meu carro tem mais idade que metade dos pilotos. Não precisa de peça cara para largar direito."},
	"nadir":{"persona":"nadir","text":"Na minha prova, uma troca ruim custa a corrida inteira. Prepare o carro com o Digo."},
	"jessica":{"persona":"jessica","text":"Olha quem saiu de Harbor. Meu carro está pronto, Dante."},
	"rauhz":{"persona":"rauhz","text":"MK1, 2002. Na última largada, cada troca conta."},
}
var heard: Dictionary = {}
var next_at := 8.0
var speaking: WeakRef

func update(session, listener: Vector3, suppressed: bool, elapsed: float) -> void:
	if suppressed:
		stop()
		return
	if is_speaking() or elapsed<next_at or not is_instance_valid(session.desert.story): return
	var nearest: Node3D
	var identity := ""
	var distance := 14.0
	for id in LINES:
		if heard.has(id): continue
		var actor: Node3D = session.desert.story.actors.get(id)
		if not is_instance_valid(actor) or actor.dead or not actor.is_visible_in_tree(): continue
		var separation := listener.distance_to(actor.global_position)
		if separation<distance:
			distance=separation
			nearest=actor
			identity=id
	if nearest==null: return
	var line: Dictionary = LINES[identity]
	var row := BANK.canonical(str(line.text),str(line.persona))
	var profile := BANK.profile(row)
	heard[identity]=true
	next_at=elapsed+24.0
	if profile.is_empty(): return
	var binding := {"persona":line.persona,"gender":profile.gender,"character_id":profile.character_id,"section":row.get("source_section","")}
	var result := VOICE.speak(nearest,str(line.text),binding)
	if result.stream!=null: speaking=weakref(nearest)

func is_speaking() -> bool:
	var actor := speaking.get_ref() as Node3D if speaking!=null else null
	if not is_instance_valid(actor): return false
	var player := actor.get_node_or_null(VOICE.PLAYER_NAME)
	return is_instance_valid(player) and player.surface==null and player.playing

func stop() -> void:
	var actor := speaking.get_ref() as Node3D if speaking!=null else null
	if is_instance_valid(actor):
		var player := actor.get_node_or_null(VOICE.PLAYER_NAME)
		# A modal dialogue may already have taken over this same voice player.
		if is_instance_valid(player) and player.surface==null: player.silence()
	speaking=null
