extends SceneTree
## Tiro saindo da arma (gameplay/fx/MuzzleFx.gd, 29/10). Rodar COM janela (pipeline só existe com o
## driver de verdade; em headless as checagens de pipeline são puladas e o teste diz isso):
##   tools/run_godot_locked.sh --path . --script res://tests/test_muzzle_fx.gd
## Confere:
##   1. forma por família (fuzil mais longo, escopeta mais larga) e o caminho jogador/NPC/Cobra/silenciador;
##   2. N tiros de cada arma, do jogador e de NPC, não criam nó nem material (pools fixos);
##   3. depois do MuzzleFx.prewarm, nenhum pipeline novo (Performance.PIPELINE_COMPILATIONS_*);
##   4. luzes de cano ≤ 3, LightBudget ≤ 8, luz do jogador primeiro e nunca tomando vaga de luz contínua;
##   5. custo de CPU num tiroteio (6 NPCs + jogador), A/B com o MuzzleFx desligado no mesmo processo.
## NÃO mede GPU nem o export release: o custo do item 5 é do editor (debug), só indicação.
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
const MUZZLE := preload("res://gameplay/fx/MuzzleFx.gd")
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const HAND := Vector3(0.0, 1.25, 0.0)
const SHOTS_PER_WEAPON := 12
const PLAYER_WEAPONS := ["pistol", "magnum", "pistol_suppressed", "smg", "smg_compact", "smg_tactical",
	"ak47", "m4a1", "hunting_rifle", "shotgun", "sawed_off", "shotgun_auto", "rpg"]

## O mínimo do Gameplay que o disparo do jogador usa (`_flash_muzzle` + `weapon_shot`).
class Host extends Node3D:
	var weapon_id := "pistol"
	var player: Node3D
	var gun: Node3D
	var effects: Node3D
	var _muzzle_flash: MeshInstance3D
	var _muzzle_light: OmniLight3D
	var _muzzle_timer := 0.0
	var reload_timer := 0.0
	var _reload_total := 1.0
	var state := Ammo.new()
	func equipped() -> String: return weapon_id
	func attack_allowed() -> bool: return true
	func _ready() -> void:
		player = Node3D.new()
		add_child(player)
		gun = Node3D.new()
		add_child(gun)
	func equip(id: String) -> void:
		weapon_id = id
		for child in gun.get_children():
			gun.remove_child(child)
			child.free()
		gun.global_transform = Transform3D(Basis.looking_at(Vector3(1.0, 0.0, 0.35).normalized(), Vector3.UP), HAND)
		var tip := ARSENAL.build_cached(gun, id)
		_muzzle_flash = MeshInstance3D.new()
		_muzzle_flash.position = tip
		_muzzle_flash.visible = false
		gun.add_child(_muzzle_flash)
		_muzzle_light = OmniLight3D.new()
		_muzzle_light.position = tip
		_muzzle_light.visible = false
		gun.add_child(_muzzle_light)
	func shoot() -> void:
		var suppressed := bool(CATALOG.WEAPONS.get(weapon_id, {}).get("suppressed", false))
		_muzzle_flash.visible = true
		_muzzle_light.visible = not suppressed
		_muzzle_timer = 0.05
		var aim := -gun.global_basis.z
		effects.muzzle_smoke(_muzzle_flash.global_position, aim)
		effects.weapon_shot(weapon_id, gun.to_global(Vector3(0.025, 0.05, -0.025)), aim, 5)
	func _physics_process(delta: float) -> void:
		if is_instance_valid(effects): effects.update_weapon_feedback(self, delta)
		if _muzzle_timer > 0.0:
			_muzzle_timer -= delta
			if _muzzle_timer <= 0.0:
				_muzzle_flash.hide()
				_muzzle_light.hide()

class Ammo extends RefCounted:
	func get_ammo(_id: String) -> Dictionary: return {"magazine": 5, "reserve": 30}

## Luzes contínuas (como faróis/giroflex de NPC) registradas no orçamento, com refresh por quadro como
## o VehicleEquipment faz.
class SteadyOwner extends Node:
	var lights: Array[Light3D] = []
	var reference := Vector3.ZERO
	func _budget_request() -> Dictionary:
		var wanted: Array[Dictionary] = []
		for light in lights: wanted.append({"light": light, "headlight": false})
		return {"lights": lights, "wanted": wanted, "player": false, "camera": reference}
	func _process(_delta: float) -> void:
		BUDGET.refresh()

var failures: Array[String] = []
var checks := 0
var _windowed := true
var _host: Host
var _fx: Node3D
var _muzzle: Node3D
var _world: Node3D
var _camera: Camera3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("MUZZLE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(240.0).timeout.connect(func(): print("MUZZLE timeout"); quit(3))
	_windowed = DisplayServer.get_name() != "headless"
	if OS.get_environment("GETECO_MUZZLE_FX") == "0": push_error("GETECO_MUZZLE_FX=0: nada a testar"); quit(2); return
	_build_scene()
	for i in 10: await process_frame
	_muzzle = _fx.muzzle_fx
	check(_muzzle != null, "CombatEffects monta o MuzzleFx")
	if _muzzle == null:
		_finish()
		return
	_check_shapes()
	await _prewarm()
	var retained := _retained_materials()
	var nodes_before := _count(_fx)
	var pools_before := _pools()
	var pipelines_before := _pipelines()
	await _check_paths()
	await _fire_every_weapon()
	await _check_budget_priority()
	for i in 30: await process_frame
	check(_count(_fx) == nodes_before, "nenhum nó novo sob o CombatEffects (%d → %d)" % [nodes_before, _count(_fx)])
	check(_pools() == pools_before, "pools do cano do mesmo tamanho %s" % str(_pools()))
	var foreign := _foreign_materials(retained)
	check(foreign.is_empty(), "só materiais retidos no cano (%d estranhos %s)" % [foreign.size(), str(foreign.slice(0, 3))])
	var after := _pipelines()
	var delta := {}
	for key in after: delta[key] = int(after[key]) - int(pipelines_before[key])
	if _windowed:
		var total := 0
		for key in delta: total += int(delta[key])
		check(total == 0, "nenhum pipeline compilado depois do pré-aquecimento %s" % str(delta))
	else:
		print("MUZZLE SKIP pipelines: headless usa o driver dummy ", delta)
	await _measure_cost()
	_finish()

func _finish() -> void:
	if is_instance_valid(_fx): _fx.clear()
	print("MUZZLE_FX checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _build_scene() -> void:
	root.size = Vector2i(1280, 720)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var holder := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.03, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.38, 0.5)
	environment.ambient_light_energy = 0.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.0
	holder.environment = environment
	_world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 0.1
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(60, 0.1, 60)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0, -0.05, 0)
	_world.add_child(floor_node)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = floor_mesh.size
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = floor_node.position
	_world.add_child(floor_body)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_world.add_child(_camera)
	_camera.look_at_from_position(Vector3(1.0, 5.0, 9.0), Vector3(1.0, 1.0, 0.0))
	_camera.current = true
	_host = Host.new()
	_world.add_child(_host)
	_fx = EFFECTS.new()
	_host.add_child(_fx)
	_host.effects = _fx

func _check_shapes() -> void:
	var meshes: Dictionary = _muzzle._meshes
	var pistol: AABB = (meshes.pistol[0] as ArrayMesh).get_aabb()
	var rifle: AABB = (meshes.rifle[0] as ArrayMesh).get_aabb()
	var shotgun: AABB = (meshes.shotgun[0] as ArrayMesh).get_aabb()
	check(rifle.size.z > pistol.size.z * 1.6, "fuzil mais longo que a pistola (%.2f × %.2f m)" % [rifle.size.z, pistol.size.z])
	check(shotgun.size.x > pistol.size.x * 1.5, "escopeta mais larga que a pistola (%.2f × %.2f m)" % [shotgun.size.x, pistol.size.x])
	var distinct := {}
	for mesh in meshes.pistol: distinct[(mesh as ArrayMesh).get_aabb()] = true
	check(distinct.size() == MUZZLE.VARIANTS, "pistola com %d variações de clarão" % distinct.size())

## Como no jogo: cada arma desenhada uma vez (CombatEffectsPrewarm desenha o catálogo), as cápsulas de
## latão e de escopeta do anel, e o MuzzleFx.prewarm; depois o clear e tempo para as especializações.
func _prewarm() -> void:
	for id in PLAYER_WEAPONS:
		_host.equip(id)
		await process_frame
		await process_frame
	var basis := _camera.global_basis
	var origin := _camera.global_position - basis.z * 7.0
	for pair in [[0, _fx._shell_mesh], [1, _fx._shotgun_shell_mesh]]:
		var node: MeshInstance3D = _fx._shells[pair[0]]
		node.mesh = pair[1]
		node.global_transform = Transform3D(basis.scaled(Vector3.ONE * 3.0), origin + basis.x * (float(pair[0]) - 0.5))
		node.visible = true
	_muzzle.prewarm(origin, basis.x, basis.y)
	await _draws(6)
	_fx.clear()
	for i in 60: await process_frame

func _draws(count: int) -> void:
	var drawn := [0]
	var counter := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(counter)
	for i in 120:
		await process_frame
		if drawn[0] >= count: break
	RenderingServer.frame_post_draw.disconnect(counter)

func _check_paths() -> void:
	# Jogador: a âncora do Gameplay apaga e o clarão/luz próprios acendem no mesmo quadro.
	_host.equip("pistol")
	await physics_frame
	var lights_before: int = _muzzle.lights_started
	_host.shoot()
	# frame_post_draw: o refresh do LightBudget roda no _process do MuzzleFx, depois do sinal process_frame.
	await RenderingServer.frame_post_draw
	check(not _host._muzzle_flash.visible and not _host._muzzle_light.visible, "tiro do jogador esconde clarão e luz antigos do Gameplay")
	check(_muzzle._flash_nodes[0].visible and _muzzle._flash_age[0] >= 0.0, "clarão do jogador aceso")
	check(_muzzle.lights_started == lights_before + 1 and _muzzle._light_nodes[0].visible, "luz do jogador acesa pelo orçamento")
	for i in 10: await physics_frame
	await process_frame
	check(not _muzzle._flash_nodes[0].visible and not _muzzle._light_nodes[0].visible, "clarão e luz somem sozinhos")
	# Silenciador: brasa, sem luz.
	_host.equip("pistol_suppressed")
	await physics_frame
	lights_before = _muzzle.lights_started
	_host.shoot()
	await process_frame
	check(_muzzle.lights_started == lights_before and _muzzle._flash_mesh_kind[0] == "suppressed", "silenciador sem luz e com brasa pequena")
	# Lança-foguetes: o clarão do Gameplay continua.
	_host.equip("rpg")
	await physics_frame
	_host.shoot()
	await process_frame
	check(_host._muzzle_flash.visible, "lança-foguetes mantém o clarão próprio do Gameplay")
	# Cobra: muzzle_smoke + weapon_shot("ak47") → clarão de fuzil e cápsula de fuzil quente.
	await physics_frame
	var npc_slot: int = 1 + _muzzle._next_flash
	var shell_slot: int = _fx._next_shell
	_fx.muzzle_smoke(Vector3(3, 1.3, -1), Vector3.LEFT)
	_fx.weapon_shot("ak47", Vector3(3, 1.2, -1), Vector3.LEFT, 1)
	await process_frame
	check(_muzzle._flash_mesh_kind[npc_slot] == "rifle", "Cobra com AK-47 tem clarão de fuzil")
	check(_fx._shells[shell_slot].mesh == _muzzle._rifle_shell_mesh and _fx._shells[shell_slot].material_override == _muzzle._hot_brass, "cápsula de fuzil sai quente")
	await create_timer(MUZZLE.SHELL_HOT_TIME + 0.15).timeout
	check(_fx._shells[shell_slot].material_override == null, "cápsula esfria depois de %.2f s" % MUZZLE.SHELL_HOT_TIME)
	# Polícia: só muzzle_smoke → clarão de pistola (família "npc").
	await physics_frame
	npc_slot = 1 + _muzzle._next_flash
	_fx.muzzle_smoke(Vector3(-3, 1.3, -1), Vector3.RIGHT)
	await process_frame
	check(_muzzle._flash_mesh_kind[npc_slot] == "pistol", "policial sem dica usa o clarão de pistola")
	# Rajada: uma baforada por ~0,15 s no mesmo cano.
	_host.equip("smg")
	var started: int = _muzzle.smoke_started
	for shot in 8:
		await physics_frame
		_host.shoot()
		for tick in 4: await physics_frame
	var puffs: int = _muzzle.smoke_started - started
	check(puffs >= 3 and puffs <= 5, "rajada de 8 tiros em ~0,6 s solta %d baforadas (3–5)" % puffs)
	_fx.clear()
	await process_frame
	var lit := 0
	for light in _muzzle._light_nodes: lit += 1 if light.visible else 0
	var emitting := 0
	for emitter in _muzzle._smoke + _muzzle._sparks: emitting += 1 if emitter.visible else 0
	check(lit == 0 and emitting == 0 and not _muzzle._flash_nodes[0].visible, "clear apaga luz, clarão e partículas sem disparar nada")

## Cada arma do jogador SHOTS_PER_WEAPON vezes na cadência do catálogo, com 6 NPCs atirando junto.
func _fire_every_weapon() -> void:
	var max_lights := 0
	var max_budget := 0
	for id in PLAYER_WEAPONS:
		_host.equip(id)
		# Cadência do catálogo, no máximo 0,3 s entre tiros (o lança-foguetes de 1,65 s só alongaria o teste).
		var interval := clampf(float(CATALOG.WEAPONS[id].get("fire_interval", 0.2)), 1.0 / 60.0, 0.3)
		var clock := interval
		var shots := 0
		var tick := 0
		while shots < SHOTS_PER_WEAPON:
			await physics_frame
			tick += 1
			clock += 1.0 / Engine.physics_ticks_per_second
			if clock >= interval:
				clock = 0.0
				_host.shoot()
				shots += 1
			if tick % 6 == 0: _npc_volley(tick)
			await process_frame
			var lit := 0
			for light in _muzzle._light_nodes: lit += 1 if light.visible else 0
			max_lights = maxi(max_lights, lit)
			max_budget = maxi(max_budget, int(BUDGET.counts().active_lights))
	check(max_lights <= 1 + MUZZLE.NPC_LIGHTS, "no máximo %d luzes de cano ao mesmo tempo (máx. %d)" % [1 + MUZZLE.NPC_LIGHTS, max_lights])
	check(max_budget <= BUDGET.MAX_LIGHTS, "LightBudget dentro do teto de %d (máx. %d)" % [BUDGET.MAX_LIGHTS, max_budget])
	print("MUZZLE stats shots=", _muzzle.shots, " lights=", _muzzle.lights_started, " lights_skipped=", _muzzle.lights_skipped,
		" smoke=", _muzzle.smoke_started, " merged=", _muzzle.smoke_merged, " dropped=", _muzzle.smoke_dropped, " queue_dropped=", _muzzle.dropped_events)

const NPC_IDS := ["", "smg", "ak47", "", "m4a1", "shotgun"]

## Seis atiradores em leque: polícia (só muzzle_smoke) e Cobras (muzzle_smoke + weapon_shot).
func _npc_volley(tick: int, effects: Node3D = null) -> void:
	var target := effects if effects != null else _fx
	for index in 6:
		if (tick / 6 + index) % 3 != 0: continue
		var angle := lerpf(-0.9, 0.9, float(index) / 5.0)
		var origin := Vector3(sin(angle) * 6.5 + 1.5, 1.3, -cos(angle) * 4.0 + 4.0)
		var direction := origin.direction_to(HAND)
		target.muzzle_smoke(origin, direction)
		if NPC_IDS[index] != "": target.weapon_shot(NPC_IDS[index], origin, direction, 1)

## Prioridade: com 8 luzes contínuas, nenhuma luz de cano acende e nenhuma contínua apaga; com 6, o
## jogador pega uma das 2 vagas e o NPC fica com a outra, sem apagar contínua.
func _check_budget_priority() -> void:
	if not BUDGET.enabled:
		print("MUZZLE SKIP prioridade: GETECO_LIGHT_BUDGET=0")
		return
	for steady_count in [8, 6]:
		var owner := SteadyOwner.new()
		owner.reference = HAND
		for index in steady_count:
			var light := OmniLight3D.new()
			light.omni_range = 3.0
			light.light_energy = 0.5
			light.set_meta("budget_energy", 0.5)
			light.position = Vector3(-6.0 + index * 1.5, 2.5, -4.0)
			owner.add_child(light)
			owner.lights.append(light)
		_world.add_child(owner)
		BUDGET.register(owner)
		for i in 3: await process_frame
		_host.equip("shotgun")
		var steady_dropped := 0
		var player_lit := 0
		var npc_lit := 0
		for round_index in 6:
			await physics_frame
			_host.shoot()
			_fx.muzzle_smoke(Vector3(4, 1.3, -1), Vector3.LEFT)
			_fx.muzzle_smoke(Vector3(-4, 1.3, -1), Vector3.RIGHT)
			for frame in 4:
				await process_frame
				for light in owner.lights: steady_dropped += 0 if light.visible else 1
				player_lit = maxi(player_lit, 1 if _muzzle._light_nodes[0].visible else 0)
				var npc := 0
				for slot in range(1, _muzzle._light_nodes.size()): npc += 1 if _muzzle._light_nodes[slot].visible else 0
				npc_lit = maxi(npc_lit, npc)
				check_budget_total(steady_count)
			for frame in 20: await physics_frame
		check(steady_dropped == 0, "%d luzes contínuas nunca apagam por causa do tiro (%d quadros apagados)" % [steady_count, steady_dropped])
		if steady_count == 8: check(player_lit == 0 and npc_lit == 0, "sem vaga sobrando, nenhuma luz de cano acende")
		else: check(player_lit == 1 and npc_lit <= 1, "com 2 vagas: luz do jogador acende e no máximo 1 de NPC (npc=%d)" % npc_lit)
		BUDGET.unregister(owner)
		owner.queue_free()
		_fx.clear()
		await process_frame

var _budget_over := false
func check_budget_total(_steady: int) -> void:
	if _budget_over: return
	if int(BUDGET.counts().active_lights) > BUDGET.MAX_LIGHTS:
		_budget_over = true
		check(false, "LightBudget passou de %d luzes" % BUDGET.MAX_LIGHTS)

## Tiroteio de 3 s (jogador de submetralhadora + 6 NPCs a ~4 tiros/s cada), A/B no mesmo processo:
## A = MuzzleFx, B = CombatEffects com GETECO_MUZZLE_FX=0 (fumaça antiga). Tempo de _process+física
## por quadro (ms) e os spans do MuzzleFx. Debug/editor: indicação, não certificado de release.
func _measure_cost() -> void:
	OS.set_environment("GETECO_MUZZLE_FX", "0")
	var host_b := Host.new()
	_world.add_child(host_b)
	var fx_b: Node3D = EFFECTS.new()
	host_b.add_child(fx_b)
	host_b.effects = fx_b
	OS.set_environment("GETECO_MUZZLE_FX", "")
	check(fx_b.muzzle_fx == null, "GETECO_MUZZLE_FX=0 volta ao caminho antigo")
	host_b.equip("smg")
	_host.equip("smg")
	for i in 30: await process_frame
	var results := {"A": [], "B": []}
	var spans := {}
	# Seis rodadas alternadas; o primeiro par é aquecimento (na 1ª rodada A apareceram quadros de ~24 ms
	# fora dos spans do MuzzleFx, sem repetir depois) e fica fora da média.
	for round_index in 6:
		var label := "A" if round_index % 2 == 0 else "B"
		var host := _host if label == "A" else host_b
		var effects: Node3D = _fx if label == "A" else fx_b
		effects.clear()
		for i in 20: await process_frame
		var compiled := _pipelines()
		STALL_WORK.start_aggregate()
		var samples: Array = await _firefight(host, effects, 3.0)
		var totals := STALL_WORK.stop_aggregate()
		var round_summary := _summary(samples)
		var slow := samples.filter(func(value): return float(value) > 5.0).size()
		var after := _pipelines()
		var new_pipelines := 0
		for key in after: new_pipelines += int(after[key]) - int(compiled[key])
		print("MUZZLE ROUND ", round_index, " ", label, " ", round_summary, " slow>5ms=", slow, " max=%.2f" % float(samples.max()), " pipelines=", new_pipelines)
		if round_index < 2: continue
		(results[label] as Array).append_array(samples)
		if label == "A":
			for name in totals.labels:
				var row: Dictionary = totals.labels[name]
				if str(name).begins_with("combat.muzzle_fx"):
					if not spans.has(name): spans[name] = {"calls": 0, "total_usec": 0, "max_usec": 0}
					spans[name].calls += int(row.calls)
					spans[name].total_usec += int(row.total_usec)
					spans[name].max_usec = maxi(int(spans[name].max_usec), int(row.max_usec))
	var a := _summary(results.A)
	var b := _summary(results.B)
	print("MUZZLE COST A(MuzzleFx) ", a, " B(antigo) ", b, " delta_p50_ms=%.3f delta_mean_ms=%.3f" % [a.p50 - b.p50, a.mean - b.mean])
	var frames := maxi(1, (results.A as Array).size())
	for name in spans:
		print("MUZZLE SPAN ", name, " calls=", spans[name].calls, " mean_per_frame_ms=%.3f max_ms=%.3f" % [float(spans[name].total_usec) / 1000.0 / float(frames), float(spans[name].max_usec) / 1000.0])
	check(a.mean - b.mean <= 0.5, "tiroteio custa ≤ 0,5 ms/quadro a mais de CPU no editor (%.3f ms)" % (a.mean - b.mean))
	host_b.queue_free()

func _firefight(host: Host, effects: Node3D, seconds: float) -> Array:
	var samples: Array = []
	var clock := 0.0
	var elapsed := 0.0
	var tick := 0
	while elapsed < seconds:
		await physics_frame
		tick += 1
		elapsed += 1.0 / Engine.physics_ticks_per_second
		clock += 1.0 / Engine.physics_ticks_per_second
		if clock >= 0.075:
			clock = 0.0
			host.shoot()
		if tick % 4 == 0: _npc_volley(tick, effects)
		await process_frame
		samples.append(1000.0 * (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
	return samples

static func _summary(samples: Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += float(value)
	var count := maxi(1, sorted.size())
	return {"frames": sorted.size(), "mean": total / float(count), "p50": float(sorted[count / 2]) if not sorted.is_empty() else 0.0,
		"p95": float(sorted[mini(count - 1, int(count * 0.95))]) if not sorted.is_empty() else 0.0}

func _pipelines() -> Dictionary:
	return {"canvas": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)),
		"mesh": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)),
		"surface": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)),
		"draw": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)),
		"specialization": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))}

func _pools() -> Array:
	return [_muzzle._flash_nodes.size(), _muzzle._light_nodes.size(), _muzzle._smoke.size(), _muzzle._sparks.size(), _fx._shells.size()]

static func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children(): total += _count(child)
	return total

func _retained_materials() -> Dictionary:
	var retained := {}
	for material in _muzzle._flash_materials: retained[material] = true
	for material in [_muzzle._spark_material, _muzzle._smoke_material, _muzzle._hot_brass]: retained[material] = true
	return retained

## Material em uso nos nós do cano e nas cápsulas que não veio do setup.
func _foreign_materials(retained: Dictionary) -> Array:
	var foreign: Array = []
	for node in _muzzle._flash_nodes:
		if node.material_override != null and not retained.has(node.material_override): foreign.append("flash:%s" % node.material_override)
	for shell in _fx._shells:
		# Sem override = latão frio da própria malha do CombatEffects.
		if shell.material_override != null and not retained.has(shell.material_override): foreign.append("shell:%s" % shell.material_override)
	for emitter in _muzzle._smoke + _muzzle._sparks:
		var mesh_material: Material = (emitter.mesh as PrimitiveMesh).material
		if not retained.has(mesh_material): foreign.append("emitter:%s" % mesh_material)
	return foreign
