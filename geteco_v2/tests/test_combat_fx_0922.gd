extends SceneTree
## Regressões de 2026-09-22 nos efeitos de combate:
##   - cadáver com os braços apontando para o céu (queda de costas + pose de braço "para a frente");
##   - corpo tombando na direção do atirador;
##   - rugido do lança-chamas pulsando (rajada curta sem laço);
##   - chumbos da escopeta reiniciando o mesmo emissor de sangue;
##   - explosão sem bola de fogo nem marca no chão.
## Mede geometria e estado; NÃO mede a aparência final na tela.

const FALL = preload("res://gameplay/CharacterFallPresentation3D.gd")
const EFFECTS = preload("res://gameplay/CombatEffects.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")

var _failures := 0

func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: _failures += 1

## Boneco mínimo com a mesma convenção do `CivilianModel`: modelo girado 180° dentro
## do visual, braços pendurados em -Y a partir do ombro, mão a 0,55 m.
func _dummy(root: Node3D) -> Dictionary:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := Node3D.new()
	actor.add_child(visual)
	var model := Node3D.new()
	model.rotation.y = PI
	visual.add_child(model)
	var hands: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = ("left_" if side < 0 else "right_") + "upper_arm"
		arm.position = Vector3(side * 0.2, 1.4, 0.0)
		model.add_child(arm)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.55, 0)
		arm.add_child(hand)
		hands.append(hand)
	return {"actor": actor, "visual": visual, "hands": hands}

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	await process_frame

	# Queda: atirador em -Z do alvo, golpe viajando para +Z.
	var cases: Array[Dictionary] = []
	for variant_seed in 12:
		seed(variant_seed)
		var d := _dummy(root)
		FALL.apply_fall(d.actor, d.visual, Vector3(0, 0, 1))
		cases.append(d)
	await create_timer(1.4).timeout
	var worst_hand := -INF
	var worst_torso_z := INF
	for d in cases:
		var base_y: float = (d.actor as Node3D).global_position.y
		for hand in d.hands: worst_hand = maxf(worst_hand, (hand as Node3D).global_position.y - base_y)
		# O visual inclina de costas: o tronco (acima da origem em repouso) deve ir para +Z, longe do atirador.
		var torso: Vector3 = (d.visual as Node3D).global_transform * Vector3(0, 1.2, 0)
		worst_torso_z = minf(worst_torso_z, torso.z)
	_check(worst_hand < 0.45, "mãos do cadáver perto do chão (mais alta: %.2f m)" % worst_hand)
	_check(worst_torso_z > 0.2, "corpo cai para longe do atirador (tronco z mínimo: %.2f)" % worst_torso_z)

	# Efeitos
	var fx: Node3D = EFFECTS.new()
	root.add_child(fx)
	await process_frame
	var used := {}
	for pellet in 8:
		fx.blood(Vector3(pellet, 1, 0), Vector3.FORWARD, 8.0)
	for emitter in fx._blood: if emitter.emitting: used[emitter] = true
	_check(used.size() == EFFECTS.BURST_POOL, "rajada de 8 chumbos usa os %d emissores de sangue (usou %d)" % [EFFECTS.BURST_POOL, used.size()])
	fx.impact(Vector3.ZERO, Vector3.UP, "metal", 10.0)
	fx.impact(Vector3.ZERO, Vector3.UP, "vidro_inexistente", 10.0)
	fx.flame(Vector3.ZERO, Vector3.FORWARD, 4.0)
	_check(fx._flame_light.visible, "jato de chamas acende a luz tremulante")
	fx.explosion(Vector3.ZERO, 7.5)
	_check(fx._blast_fire.emitting, "explosão dispara a bola de fogo")
	fx.clear()
	_check(not fx._flame_light.visible and not fx._blast_fire.emitting, "clear() apaga luz e bola de fogo")

	# Áudio
	var flame := AUDIO.flamethrower() as AudioStreamWAV
	_check(flame.loop_mode == AudioStreamWAV.LOOP_FORWARD and flame.loop_end > 0, "rugido do lança-chamas em laço")
	var bytes := flame.data
	var last := bytes.decode_s16(bytes.size() - 2)
	var first := bytes.decode_s16(0)
	_check(absi(last - first) < 6000, "emenda do laço sem salto (|Δ| = %d)" % absi(last - first))
	_check(AUDIO.grenade_bounce() != null, "quique da granada gerado")

	print("RESULT: %s (%d falhas)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	quit(0 if _failures == 0 else 1)
