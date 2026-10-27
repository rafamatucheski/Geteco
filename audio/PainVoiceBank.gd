extends RefCounted
## Gemidos, gritos e gritos de morte gravados (ElevenLabs, 27/10/2026), separados pelo gênero do
## corpo. Antes toda pessoa dizia o mesmo "Ai!" sintetizado (uma tomada por gênero, com legenda
## flutuando), e o jogador percebia todo mundo igual. Agora cada corpo sorteia uma vez, a partir
## do próprio id, um grupo de voz e um tom fixo: a mesma pessoa soa sempre igual e duas pessoas
## quase nunca soam iguais. Sem os arquivos importados `pick` devolve vazio e quem chama segue
## com o som antigo.
const BINDING := preload("res://audio/VoiceActorBinding.gd")
const ROOT := "res://audio/pain_voices/"
## Nome no arquivo: <gênero>_<tipo>_<grupo>_<n>.wav. "light" usa o grupo da pessoa; os gritos
## fortes e de morte são do gênero inteiro, com o tom da pessoa por cima.
const GROUPS := {
	"female": {"light": ["young", "mature"], "heavy": ["any"], "death": ["any"]},
	"male": {"light": ["adult", "young", "older"], "heavy": ["any"], "death": ["any"]},
}
const MAX_TAKES := 8
## Tom fixo por pessoa (multiplica o pitch_scale) e variação pequena a cada grito.
const PITCH_RANGE := {"female": Vector2(0.95, 1.07), "male": Vector2(0.91, 1.05)}
const PITCH_JITTER := 0.025
static var _takes: Dictionary = {}
static var _last: Dictionary = {}

static func takes(gender: String, kind: String, group: String) -> Array:
	var key := "%s:%s:%s" % [gender, kind, group]
	if _takes.has(key): return _takes[key]
	var found: Array = []
	for index in MAX_TAKES:
		var path := "%s%s_%s_%s_%d.wav" % [ROOT, gender, kind, group, index]
		if not ResourceLoader.exists(path): break
		var stream := load(path) as AudioStream
		if stream != null: found.append(stream)
	_takes[key] = found
	return found

## Carrega tudo sob a cortina, um grupo por quadro: o primeiro tiro não paga leitura de disco.
static func prewarm(tree: SceneTree) -> void:
	for gender in GROUPS:
		for kind in GROUPS[gender]:
			for group in GROUPS[gender][kind]:
				takes(gender, kind, group)
				await tree.process_frame

## Grupo de voz e tom da pessoa, guardados nela. O id estável (pessoa persistente, identidade do
## pedestre ou nome do nó) sorteia uma vez; renascer com outro id é outra pessoa.
static func identity(actor: Node, gender: String) -> Dictionary:
	var kept: Variant = actor.get_meta("pain_voice", {})
	if kept is Dictionary and str(kept.get("gender", "")) == gender: return kept
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(BINDING.actor_id(actor) + gender)
	var groups: Array = GROUPS[gender].light
	var pitch_range: Vector2 = PITCH_RANGE[gender]
	var result := {"gender": gender, "group": str(groups[rng.randi() % groups.size()]), "pitch": rng.randf_range(pitch_range.x, pitch_range.y)}
	actor.set_meta("pain_voice", result)
	return result

## {stream, pitch} para `kind` ("light", "heavy", "death"), ou vazio sem gênero conhecido ou sem
## gravação. Nunca supõe homem quando o corpo não diz (mesma regra do VoiceActorBinding).
static func pick(actor: Node, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	if not is_instance_valid(actor): return {}
	var gender := BINDING.gender_of(actor)
	if not GROUPS.has(gender): return {}
	var who := identity(actor, gender)
	var group: String = str(who.group) if kind == "light" else "any"
	var pool := takes(gender, kind, group)
	# Sem grito forte gravado, o gemido da própria pessoa serve melhor que o silêncio.
	if pool.is_empty() and kind != "light": pool = takes(gender, "light", str(who.group))
	if pool.is_empty(): return {}
	var key := "%s:%s:%s" % [gender, kind, group]
	var index := rng.randi_range(0, pool.size() - 1)
	if pool.size() > 1 and int(_last.get(key, -1)) == index: index = (index + 1) % pool.size()
	_last[key] = index
	return {"stream": pool[index], "pitch": float(who.pitch) * rng.randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)}
