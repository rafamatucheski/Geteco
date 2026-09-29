extends SceneTree
## Feedback de recompensa da V1 em todas as coletas: apresentação (absorção/retorno)
## e banco de sons (achado, dinheiro, arma, item, conquista).
const PICKUP := preload("res://systems/inventory/PickupPresentation.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("REWARD_FEEDBACK ","PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func run() -> void:
	for kind in ["pickup","cash","weapon","collectible","achievement"]:
		for take in (3 if kind in ["pickup","cash"] else 1):
			var stream := REWARD_AUDIO.stream(kind,take)
			check(stream != null and stream.get_length() > 0.2,"som %s take %d importado"%[kind,take])
	check(REWARD_AUDIO.kind_for_reward("cash") == "cash" and REWARD_AUDIO.kind_for_reward("weapon") == "weapon" and REWARD_AUDIO.kind_for_reward("item") == "pickup","categoria por tipo de recompensa")
	REWARD_AUDIO.play(root,"collectible")
	var pool := root.get_node_or_null("RewardAudioVoices")
	check(pool != null and pool.get_child_count() == REWARD_AUDIO.VOICES,"pool de vozes criado na cena")
	var playing := 0
	for voice in pool.get_children(): if voice.playing: playing += 1
	check(playing == 1,"uma voz tocando")
	REWARD_AUDIO.play(root,"collectible")
	playing = 0
	for voice in pool.get_children(): if voice.playing: playing += 1
	check(playing == 1,"repetição no mesmo quadro é coalescida")
	var holder := PICKUP.new()
	root.add_child(holder)
	var art := Node3D.new()
	art.add_child(MeshInstance3D.new())
	holder.configure(art,"cash")
	holder.set_available(false,true)
	check(holder.consumed and holder.visible,"coleta animada começa absorvendo")
	holder.set_available(false)
	check(holder.visible,"reconciliação não corta a absorção")
	await create_timer(.35).timeout
	check(not holder.visible,"some no fim da absorção")
	holder.set_available(false)
	check(not holder.visible,"segue escondido")
	holder.set_available(true)
	check(holder.visible and not holder.consumed and art.scale == Vector3.ONE,"volta restaurado")
	print("REWARD_FEEDBACK_RESULT failures=",failures)
	quit(1 if failures else 0)
