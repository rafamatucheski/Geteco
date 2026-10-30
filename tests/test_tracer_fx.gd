extends SceneTree
## Traçado da bala (gameplay/fx/TracerFx.gd, 29/10). Contrato, não aparência nem quadro em release:
## pool fixo (nada criado por tiro, N traçados além da capacidade), dados enviados ao servidor e AABB
## sempre finitos (inclusive com entrada NaN/INF), material e malha retidos depois de clear(), perfil
## por arma (rastro só em fuzil/escopeta), cauda que estica com a velocidade, bala da polícia que para
## onde o Gameplay manda, vagas que acabam sozinhas e o custo de CPU da atualização (build de debug,
## sem GPU). Com janela, também desenha alguns quadros para o shader compilar (erro sai no log).
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
const TRACER := preload("res://gameplay/fx/TracerFx.gd")
const STEP := 1.0 / 60.0

## Dono do CombatEffects no jogo é o Gameplay; aqui só a arma em mão importa.
class Host extends Node3D:
	var weapon_id := "pistol"
	func equipped() -> String: return weapon_id

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print("TRACER ", "PASS " if ok else "FAIL ", label, "" if detail.is_empty() else " (" + detail + ")")
	if not ok: failures.append(label)

func finite_data(fx: Node) -> bool:
	for value in fx.buffer_snapshot():
		if not is_finite(value): return false
	var box: AABB = fx.multimesh.custom_aabb
	var place: Transform3D = fx.global_transform
	return box.position.is_finite() and box.size.is_finite() and place.origin.is_finite() and place.basis.x.is_finite() \
		and place.basis.y.is_finite() and place.basis.z.is_finite()

## Avança o relógio do traçado sem deixar o motor rodar quadros no meio (teste determinístico).
func advance(fx: Node, seconds: float) -> bool:
	var finite := true
	var elapsed := 0.0
	while elapsed < seconds:
		fx._process(STEP)
		elapsed += STEP
		finite = finite and finite_data(fx)
	return finite

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var host := Host.new()
	scene.add_child(host)
	var effects: Node3D = EFFECTS.new()
	host.add_child(effects)
	await process_frame
	var fx = effects.tracer_fx
	check(fx != null and fx.get_parent() == effects and fx is MultiMeshInstance3D, "CombatEffects monta o TracerFx (MultiMesh) no _ready")
	if fx == null:
		finish()
		return
	var multimesh: MultiMesh = fx.multimesh
	var total: int = multimesh.instance_count
	var material: Material = fx.material_override
	var ribbon: Mesh = multimesh.mesh
	check(total == EFFECTS.MAX_TRACERS + TRACER.TRAILS, "vagas fixas = balas + rastros", str(total))
	check(material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path == "res://gameplay/fx/tracer_fx.gdshader", "material é o shader do traçado")
	check(effects._tracers.is_empty() and FileAccess.get_file_as_string("res://gameplay/CombatEffectsPrewarm.gd").contains("tracer_fx.prewarm"),
		"pré-aquecimento sob a cortina desenha o TracerFx (e não há mais nós de traçado soltos)")
	var children := effects.get_child_count()
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)

	# 1) Muito mais tiros que vagas, de todas as famílias, mais balas da polícia.
	var weapons := ["pistol", "smg", "ak47", "shotgun", "hunting_rifle", "magnum", "pistol_suppressed", "m4a1", "sawed_off"]
	for shot in 3 * EFFECTS.MAX_TRACERS:
		host.weapon_id = weapons[shot % weapons.size()]
		var origin := Vector3(0.05 * shot, 1.4, 0.0)
		effects.tracer(origin, origin + Vector3(0.4, -0.1, -45.0), 40.0, Color("ffe36b"), 30.0)
	var tokens: Array[Dictionary] = []
	for index in 20:
		tokens.append(effects.police_tracer(Vector3(index, 1.5, -30.0), Vector3.BACK, 45.0, Color("ffe36b"), 42.0 if index % 2 == 0 else 6.0))
	fx._process(STEP)
	check(multimesh.instance_count == total and is_same(fx.multimesh, multimesh), "pool não cresce com %d tiros" % (3 * EFFECTS.MAX_TRACERS + 20))
	check(fx.bolt_count() <= EFFECTS.MAX_TRACERS and fx.bolt_count() > 0 and fx.trail_count() <= TRACER.TRAILS and fx.trail_count() > 0,
		"vivos dentro das vagas", "balas=%d rastros=%d" % [fx.bolt_count(), fx.trail_count()])
	check(effects.get_child_count() == children and Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes,
		"nenhum nó criado por tiro", "objetos %d -> %d" % [objects, Performance.get_monitor(Performance.OBJECT_COUNT)])
	check(is_same(fx.material_override, material) and is_same(multimesh.mesh, ribbon), "material e malha são os mesmos depois da rajada")
	check(finite_data(fx), "buffer e AABB finitos com o pool cheio")
	var moved := true
	for step in 30:
		for index in tokens.size():
			effects.move_police_tracer(tokens[index], Vector3(index, 1.5, -30.0 + 45.0 * STEP * (step + 1)), step == 29 and index % 3 == 0)
		moved = moved and advance(fx, STEP)
	check(moved, "voo da polícia guiado pelo Gameplay mantém tudo finito")

	# 2) Entrada não finita é recusada ou saneada; nada não finito chega ao servidor.
	effects.clear()
	host.weapon_id = "pistol"
	effects.tracer(Vector3(NAN, 1.0, 0.0), Vector3(0, 1, -10), 40.0, Color.YELLOW, 30.0)
	effects.tracer(Vector3(0, 1, 0), Vector3(INF, 1.0, -10.0), 40.0, Color.YELLOW, 30.0)
	check(fx.active_count() == 0, "origem/destino NaN ou INF não abrem vaga")
	effects.tracer(Vector3(0, 1, 0), Vector3(0, 1, -10), NAN, Color(NAN, NAN, NAN), NAN)
	check(fx.bolt_count() == 1, "velocidade, cor e dano NaN viram padrão (o tiro ainda aparece)")
	var bad_origin: Dictionary = effects.police_tracer(Vector3(NAN, 0, 0), Vector3.FORWARD)
	var bad_direction: Dictionary = effects.police_tracer(Vector3(0, 1.5, -5), Vector3(INF, 0, 0))
	var no_direction: Dictionary = effects.police_tracer(Vector3(0, 1.5, -5), Vector3.ZERO)
	check(bad_origin.is_empty() and bad_direction.is_empty() and no_direction.is_empty(), "bala da polícia com origem/direção inválida devolve token vazio")
	var token: Dictionary = effects.police_tracer(Vector3(0, 1.5, -20), Vector3.BACK, NAN, Color(INF, 0, 0), NAN)
	check(not token.is_empty(), "bala da polícia com velocidade/cor/dano NaN usa padrão")
	advance(fx, 0.1)
	effects.move_police_tracer(token, Vector3(NAN, NAN, NAN), false)
	effects.move_police_tracer({}, Vector3.ZERO, true)
	effects.move_police_tracer(bad_origin, Vector3(INF, 0, 0), true)
	check(finite_data(fx), "buffer e AABB finitos depois das entradas NaN/INF")
	check(advance(fx, 0.3) and fx.bolt_count() == 0, "ponto NaN encerra a bala onde ela estava; a vaga acaba")

	# 3) Vagas acabam sozinhas e o nó se esconde e para.
	effects.clear()
	host.weapon_id = "hunting_rifle"
	effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -60), 62.5, Color("f1c40f"), 120.0)
	check(fx.visible or fx._dirty, "tiro deixa o traçado pronto para desenhar")
	advance(fx, 2.5)
	check(fx.active_count() == 0 and not fx.visible and not fx.is_processing(), "bala e rastro acabam, nó escondido e parado")

	# 4) Perfis: rastro só nos pesados; escopeta um a cada três chumbos.
	host.weapon_id = "pistol"
	effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -20), 38.75, Color("ffe36b"), 34.0)
	check(fx.trail_count() == 0, "pistola sem rastro de ar")
	host.weapon_id = "ak47"
	effects.tracer(Vector3(0, 1.4, 0.5), Vector3(0, 1.4, -20), 47.5, Color("ff6348"), 42.0)
	check(fx.trail_count() == 1, "fuzil deixa rastro de ar")
	effects.clear()
	host.weapon_id = "shotgun"
	for pellet in 8:
		effects.tracer(Vector3(0, 1.4, 0), Vector3(pellet - 4.0, 1.4, -15), 30.0, Color("ff9b63"), 18.0)
	check(fx.bolt_count() == 8 and fx.trail_count() == 3, "escopeta: 8 chumbos, rastro em 3", "rastros=%d" % fx.trail_count())
	check(TRACER.profile_name("", 120.0) == "marksman" and TRACER.profile_name("", 42.0) == "rifle" and TRACER.profile_name("", 6.0) == "pistol"
		and TRACER.profile_name("pistol_suppressed", 28.0) == "suppressed", "família por arma e, sem arma, pelo dano")

	# 5) A cauda estica com a velocidade mostrada; cor do catálogo/munição preservada na vaga.
	effects.clear()
	host.weapon_id = "pistol"
	var slow_slot: int = effects._next_tracer
	effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -10), 30.0, Color("ffd36b"), 34.0)
	var fast_slot: int = effects._next_tracer
	effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -10), 60.0, Color("8fe8ff"), 34.0)
	check(fx.slot_tail(fast_slot) > fx.slot_tail(slow_slot) * 1.5, "cauda estica com a velocidade", "%.2f m -> %.2f m" % [fx.slot_tail(slow_slot), fx.slot_tail(fast_slot)])
	check(fx.slot_color(fast_slot).is_equal_approx(Color("8fe8ff")), "cor da munição chega à vaga")
	check((effects._tracer_state[fast_slot].from as Vector3).is_equal_approx(Vector3(0, 1.4, 0)), "estado de compatibilidade guarda a boca do cano")

	# 6) Bala da polícia: o Gameplay diz onde parou; a cauda recolhe e a vaga acaba logo depois.
	effects.clear()
	var police: Dictionary = effects.police_tracer(Vector3(0, 1.5, 0), Vector3.FORWARD, 40.0)
	var point := Vector3(0, 1.5, 0)
	for step in 10:
		point += Vector3.FORWARD * 40.0 * STEP
		effects.move_police_tracer(police, point, step == 9)
		advance(fx, STEP)
	check(fx.bolt_count() == 1, "bala que parou ainda recolhe a cauda no ponto do acerto")
	advance(fx, 0.12)
	check(fx.bolt_count() == 0, "vaga da polícia acaba depois do recolhimento")
	var stale: Dictionary = effects.police_tracer(Vector3(0, 1.5, 0), Vector3.FORWARD, 40.0)
	for shot in EFFECTS.MAX_TRACERS: effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -30), 40.0, Color.WHITE, 30.0)
	var reused_from: Vector3 = effects._tracer_state[stale.index].from
	effects.move_police_tracer(stale, Vector3(50, 1.5, 0), true)
	check((effects._tracer_state[stale.index].from as Vector3).is_equal_approx(reused_from) and finite_data(fx), "token velho não mexe na vaga reaproveitada")

	# 7) Pré-aquecimento usa o mesmo material; clear() limpa e retém.
	effects.clear()
	fx.prewarm(Vector3(0, 1.5, -5), Vector3.RIGHT)
	check(fx.bolt_count() == 1 and fx.trail_count() == 1, "pré-aquecimento desenha bala e rastro")
	effects.clear()
	check(fx.active_count() == 0 and not fx.visible and is_same(fx.material_override, material) and is_same(fx.multimesh, multimesh),
		"clear() apaga e mantém material/MultiMesh")

	# 8) Interruptor de A/B.
	TRACER.enabled = false
	effects.tracer(Vector3(0, 1.4, 0), Vector3(0, 1.4, -30), 40.0, Color.WHITE, 30.0)
	check(fx.active_count() == 0 and effects.police_tracer(Vector3(0, 1.4, 0), Vector3.FORWARD).is_empty(), "GETECO_TRACER_FX=0 desliga o traçado")
	TRACER.enabled = true

	# 9) CPU: pool cheio de fuzil (balas + rastros), quadro sem mudança e quadro com disparo.
	effects.clear()
	host.weapon_id = "ak47"
	var began := Time.get_ticks_usec()
	for shot in EFFECTS.MAX_TRACERS:
		effects.tracer(Vector3(0.02 * shot, 1.4, 0), Vector3(0.02 * shot, 1.4, -200), 47.5, Color("ff6348"), 42.0)
	var spawn_us := float(Time.get_ticks_usec() - began) / EFFECTS.MAX_TRACERS
	fx._process(0.0001)
	began = Time.get_ticks_usec()
	for frame in 200: fx._process(0.0001)
	var idle_us := float(Time.get_ticks_usec() - began) / 200.0
	began = Time.get_ticks_usec()
	for frame in 200:
		fx._dirty = true
		fx._process(0.0001)
	var commit_us := float(Time.get_ticks_usec() - began) / 200.0
	print("TRACER_CPU disparo=%.1f us  quadro_sem_mudanca=%.1f us  quadro_com_envio=%.1f us  vivos=%d (debug, sem GPU)" % [spawn_us, idle_us, commit_us, fx.active_count()])
	check(commit_us + spawn_us * 4.0 < 300.0, "CPU por quadro com 4 disparos e envio < 0,3 ms (debug)", "%.0f us" % (commit_us + spawn_us * 4.0))

	# 10) Com janela: alguns quadros desenhados para o shader compilar (erro de shader sai no log).
	if DisplayServer.get_name() != "headless":
		effects.clear()
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.look_at_from_position(Vector3(0, 1.7, 3), Vector3(0, 1.4, -10))
		camera.current = true
		for weapon in ["pistol", "ak47", "shotgun"]:
			host.weapon_id = weapon
			effects.tracer(Vector3(0.3, 1.4, 0), Vector3(1.0, 1.3, -40), 45.0, Color("ffe36b"), 30.0)
		effects.police_tracer(Vector3(-2, 1.5, -25), Vector3(-2, 1.5, -25).direction_to(Vector3(0.4, 1.6, 3.2)), 45.0)
		for frame in 12: await RenderingServer.frame_post_draw
		check(finite_data(fx), "quadros desenhados com dados finitos")
	finish()

func finish() -> void:
	print("TRACER_FX checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
