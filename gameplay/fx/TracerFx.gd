extends MultiMeshInstance3D
## Traçado da bala do combate (pedido do jogador em 29/10: "parece tudo muito simples").
##
## Antes: 32 caixas de 1,8 cm × 42 cm, cada uma com o próprio StandardMaterial3D opaco e movida no
## passo de física; de dia eram tracinhos claros sem brilho e de noite pontinhos. Agora um MultiMesh
## (vagas fixas: `bolts` balas + TRAILS rastros) com `tracer_fx.gdshader`:
##   - núcleo quente e halo aditivos em HDR, que passam do limiar do glow do CityLook;
##   - cauda que estica com a velocidade mostrada e afina até a ponta; recolhe ao chegar;
##   - cintilação leve por bala; cor do catálogo/munição e perfil por arma (largura, brilho, calor);
##   - rastro de ar muito fraco atrás de fuzil e escopeta (um a cada três chumbos);
##   - "zunido": a bala da polícia/Cobras que passa rente à câmera abre o halo e estica.
##
## Custo: o movimento é calculado no shader a partir do relógio `clock`. A CPU só grava o buffer no
## disparo, no fim do voo da polícia e quando a vaga acaba (um `multimesh_set_buffer` no quadro em que
## algo mudou); por quadro, um parâmetro do material e uma comparação de tempo por vaga. Um desenho só
## para todos os traçados. Nada é criado por tiro: anel fixo, a vaga mais velha é reaproveitada.
## Transparente com posição sempre finita (29/10: NaN num transparente derrubava a ordenação alfa do
## release): o nó fica na origem e a AABB própria só soma pontos finitos; entrada não finita é recusada.
## Material criado uma vez e retido; pré-aquecido sob a cortina (CombatEffectsPrewarm -> prewarm()).
## GETECO_TRACER_FX=0 desliga o traçado inteiro (A/B de custo no mesmo export).
const SHADER := preload("res://gameplay/fx/tracer_fx.gdshader")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const NON_FINITE := preload("res://runtime/NonFiniteGuard.gd")
## Floats por instância: transformação 3D (12) + cor (4) + custom (4), na ordem de `multimesh_set_buffer`.
const STRIDE := 20
const TRAILS := 24
## Cauda = velocidade mostrada × este tempo (borrão de ~2 quadros a 60 Hz), entre MIN_TAIL e MAX_TAIL.
const TAIL_SECONDS := 0.034
const MIN_TAIL := 0.35
const MAX_TAIL := 3.2
## Voo visual do tiro do jogador, como o traçado antigo: o dano é hitscan, então o tiro longo não pode
## chegar muito depois do acerto (teto) nem o curto sumir num quadro (piso).
const MIN_FLIGHT := 0.045
const MAX_FLIGHT := 0.70
## Alcance provisório da bala da polícia até `move()` dizer onde ela parou (maior alcance do catálogo
## é 560/16 = 35 m).
const POLICE_REACH := 48.0
const DEFAULT_COLOR := Color(1.0, 0.89, 0.42)
## Perfis por família de arma. width = meia-largura do halo (m); energy = brilho; heat = núcleo puxado
## ao branco; core = núcleo como fração da meia-largura; tail = multiplicador da cauda; trail_* = rastro
## de ar (alpha aditivo, comprimento em m, vida em s depois que a bala chega, um a cada N chumbos).
const PROFILES := {
	"pistol": {"width": 0.020, "energy": 1.0, "heat": 0.72, "core": 0.30, "tail": 1.0, "trail_alpha": 0.0},
	"suppressed": {"width": 0.016, "energy": 0.55, "heat": 0.55, "core": 0.28, "tail": 0.8, "trail_alpha": 0.0},
	"magnum": {"width": 0.024, "energy": 1.2, "heat": 0.78, "core": 0.30, "tail": 1.1, "trail_alpha": 0.0},
	"smg": {"width": 0.017, "energy": 0.9, "heat": 0.70, "core": 0.30, "tail": 0.95, "trail_alpha": 0.0},
	"rifle": {"width": 0.024, "energy": 1.25, "heat": 0.80, "core": 0.28, "tail": 1.15,
		"trail_alpha": 0.055, "trail_length": 9.0, "trail_life": 0.5, "trail_every": 1},
	"marksman": {"width": 0.028, "energy": 1.45, "heat": 0.85, "core": 0.26, "tail": 1.25,
		"trail_alpha": 0.075, "trail_length": 14.0, "trail_life": 0.75, "trail_every": 1},
	"shotgun": {"width": 0.013, "energy": 0.62, "heat": 0.60, "core": 0.32, "tail": 0.75,
		"trail_alpha": 0.035, "trail_length": 3.5, "trail_life": 0.35, "trail_every": 3},
}
## Cor do ar mexido: quase branca, com um pouco da cor da bala perto dela.
const TRAIL_TINT := Color(0.86, 0.88, 0.92)

static var enabled := OS.get_environment("GETECO_TRACER_FX") != "0"
static var _ribbon: ArrayMesh

## Vagas de bala (as de rastro vêm depois delas no MultiMesh).
var bolts := 48
## Próxima vaga de bala do anel (o CombatEffects a expõe como `_next_tracer`).
var next_slot := 0
## Uma por vaga de bala, mutada no disparo (sem alocar por tiro): from, to, direction, speed, duration,
## manual. Só para quem inspeciona o tiro (testes); o voo não lê daqui.
var states: Array[Dictionary] = []
var _next_trail := 0
var _clock := 0.0
var _active := 0
var _dirty := false
var _buffer := PackedFloat32Array()
## Fim de cada vaga no relógio; 0 = livre.
var _end := PackedFloat32Array()
var _origin := PackedVector3Array()
var _velocity := PackedVector3Array()
var _start := PackedFloat32Array()
var _limit := PackedFloat32Array()
var _tail := PackedFloat32Array()
var _life := PackedFloat32Array()
var _serial := PackedInt32Array()
var _trail_of := PackedInt32Array()
var _colors := PackedColorArray()
var _shots := 0
var _volley_frame := -1
var _volley_origin := Vector3.ZERO
var _volley_index := 0
var _material: ShaderMaterial


func _init(capacity := 48) -> void:
	bolts = maxi(capacity, 1)
	name = "TracerFx"
	# Nó fixo na origem do mundo: os dados de posição vão no buffer, e a AABB própria cobre as balas.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	var total := bolts + TRAILS
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = ribbon_mesh()
	mesh.instance_count = total
	# AABB própria: sem ela o servidor recalcula a caixa a partir das instâncias (e os dados delas não
	# são posições). Atualizada só quando o conjunto de balas muda.
	mesh.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	multimesh = mesh
	_buffer.resize(total * STRIDE)
	_buffer.fill(0.0)
	_end.resize(total)
	_end.fill(0.0)
	_start.resize(total)
	_limit.resize(total)
	_tail.resize(total)
	_life.resize(total)
	_origin.resize(total)
	_velocity.resize(total)
	_serial.resize(total)
	_serial.fill(0)
	_trail_of.resize(bolts)
	_trail_of.fill(-1)
	_colors.resize(bolts)
	for index in bolts: states.append({"life": 0.0})
	RenderingServer.multimesh_set_buffer(mesh.get_rid(), _buffer)
	visible = false
	set_process(false)


## Fita compartilhada: 9 fileiras de 2 vértices. UV.y < 0 é a tampa redonda à frente da cabeça.
static func ribbon_mesh() -> ArrayMesh:
	if _ribbon != null: return _ribbon
	var rows := PackedFloat32Array([-1.0, -0.55, 0.0, 0.03, 0.09, 0.2, 0.38, 0.62, 1.0])
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows.size():
		for side in [-1.0, 1.0]:
			vertices.append(Vector3(side * 0.02, 0.0, rows[row]))
			uvs.append(Vector2(side, rows[row]))
		if row > 0:
			var a := (row - 1) * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_ribbon = ArrayMesh.new()
	_ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _ribbon


## Família de traçado pela arma em mão (catálogo); sem arma conhecida, pelo dano.
static func profile_name(weapon_id: String, damage: float) -> String:
	if not weapon_id.is_empty() and CATALOG.WEAPONS.has(weapon_id):
		var data: Dictionary = CATALOG.WEAPONS[weapon_id]
		if int(data.get("pellets", 1)) > 1: return "shotgun"
		if weapon_id == "hunting_rifle": return "marksman"
		if weapon_id in ["ak47", "m4a1"]: return "rifle"
		if weapon_id.begins_with("smg"): return "smg"
		if bool(data.get("suppressed", false)): return "suppressed"
		if weapon_id == "magnum": return "magnum"
		return "pistol"
	if is_finite(damage) and damage >= 90.0: return "marksman"
	if is_finite(damage) and damage >= 40.0: return "rifle"
	return "pistol"


## Tiro do jogador (hitscan): a bala visual vai de `origin` a `destination`. Devolve a vaga ou -1.
func shoot(origin: Vector3, destination: Vector3, speed: float, color: Color, damage: float, weapon_id := "") -> int:
	# Não finito é recusado (o CombatEffects já registra de onde veio, runtime/NonFiniteGuard.gd).
	if not enabled or not origin.is_finite() or not destination.is_finite(): return -1
	var distance := origin.distance_to(destination)
	if not is_finite(distance) or distance < 0.05: return -1
	var authored := speed if is_finite(speed) and speed > 0.0 else 57.5
	var flight := clampf(distance / authored, MIN_FLIGHT, MAX_FLIGHT)
	var direction := origin.direction_to(destination)
	var profile: Dictionary = PROFILES[profile_name(weapon_id, damage)]
	# Chumbos do mesmo disparo saem no mesmo passo de física e da mesma boca.
	var frame := Engine.get_physics_frames()
	if frame == _volley_frame and origin.is_equal_approx(_volley_origin): _volley_index += 1
	else:
		_volley_frame = frame
		_volley_origin = origin
		_volley_index = 0
	var with_trail := float(profile.trail_alpha) > 0.0 and _volley_index % int(profile.get("trail_every", 1)) == 0
	var slot := _spawn(origin, direction, distance / flight, distance, color, profile, false, with_trail)
	if slot >= 0:
		var state := states[slot]
		state.from = origin
		state.to = destination
		state.direction = direction
		state.speed = distance / flight
		state.duration = flight
		state.manual = false
		state.life = flight
	return slot


## Bala de NPC (polícia, Cobras, civis): o voo e o acerto são do Gameplay, que chama `move()` a cada
## passo. Devolve o token (vazio se recusada).
func incoming(origin: Vector3, direction: Vector3, speed: float, color: Color, damage: float) -> Dictionary:
	if not enabled or not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001: return {}
	var forward := direction.normalized()
	var shown := speed if is_finite(speed) and speed > 0.0 else 55.0
	var heavy := is_finite(damage) and damage >= 40.0
	var profile: Dictionary = PROFILES["rifle" if heavy else "pistol"]
	var slot := _spawn(origin, forward, shown, POLICE_REACH, color, profile, true, heavy)
	if slot < 0: return {}
	var state := states[slot]
	state.from = origin
	state.to = origin + forward * POLICE_REACH
	state.direction = forward
	state.speed = shown
	state.duration = POLICE_REACH / shown
	state.manual = true
	state.life = state.duration
	return {"index": slot, "serial": _serial[slot]}


## Posição da bala do NPC no passo de física. O shader já a anda na mesma velocidade; aqui só se
## corrige a linha (direção trocada no caminho) e, ao terminar, onde ela para (a cauda recolhe ali).
func move(token: Dictionary, point: Vector3, finished := false) -> void:
	if token.is_empty(): return
	var slot := int(token.get("index", -1))
	if slot < 0 or slot >= bolts or _serial[slot] != int(token.get("serial", -1)) or _end[slot] <= 0.0: return
	var start := _origin[slot]
	var speed := _velocity[slot].length()
	var forward := _velocity[slot] / speed
	if not point.is_finite():
		finished = true
		point = start + forward * minf(speed * (_clock - _start[slot]), _limit[slot])
	var along := (point - start).dot(forward)
	if (point - start - forward * along).length() > 0.35 and start.distance_to(point) > 0.05:
		forward = start.direction_to(point)
		_velocity[slot] = forward * speed
		along = start.distance_to(point)
		_write_slot(slot)
		var linked := _linked_trail(slot)
		if linked >= 0:
			_velocity[linked] = _velocity[slot]
			_write_slot(linked)
		_dirty = true
	if finished: _finish(slot, clampf(along, 0.0, POLICE_REACH))


## Liga o processamento e desenha uma bala lenta com rastro diante da câmera (sob a cortina): o mesmo
## MultiMesh e o mesmo material do jogo, para o primeiro tiro não compilar o pipeline.
func prewarm(point: Vector3, right: Vector3, _up := Vector3.UP) -> void:
	if not enabled or not point.is_finite() or not right.is_finite() or right.length_squared() < 0.0001: return
	var slot := _spawn(point - right.normalized() * 0.9, right.normalized(), 2.0, 1.8, Color("ffe36b"), PROFILES.rifle, false, true)
	# Começa já no meio do caminho, com cauda e rastro visíveis no primeiro quadro.
	if slot >= 0:
		for index in [slot, _linked_trail(slot)]:
			if index < 0: continue
			_start[index] -= 0.6
			_end[index] += 1.0
			_write_slot(index)


func clear() -> void:
	_end.fill(0.0)
	_buffer.fill(0.0)
	_trail_of.fill(-1)
	for state in states:
		state.clear()
		state.life = 0.0
	_active = 0
	_clock = 0.0
	_dirty = false
	if multimesh != null: RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
	visible = false
	set_process(false)


## Descarga: só esconde e para (o servidor pode já estar desmontando a cena).
func shutdown() -> void:
	visible = false
	set_process(false)


## Balas e rastros vivos.
func active_count() -> int:
	return _active


func bolt_count() -> int:
	var count := 0
	for slot in bolts: if _end[slot] > 0.0: count += 1
	return count


func trail_count() -> int:
	return _active - bolt_count()


## Cor (sRGB, como veio do catálogo) da bala na vaga.
func slot_color(slot: int) -> Color:
	return _colors[slot] if slot >= 0 and slot < bolts else Color.BLACK


## Cauda máxima (m) da vaga: estica com a velocidade mostrada.
func slot_tail(slot: int) -> float:
	return _tail[slot] if slot >= 0 and slot < _tail.size() else 0.0


## Cópia do buffer enviado ao servidor (testes conferem que é tudo finito).
func buffer_snapshot() -> PackedFloat32Array:
	return _buffer.duplicate()


func _process(delta: float) -> void:
	_clock += delta
	for slot in _end.size():
		var end := _end[slot]
		if end > 0.0 and _clock >= end: _release(slot)
	if _dirty: _commit()
	if _active == 0:
		# Ocioso: zera o relógio para os floats do shader não perderem precisão numa sessão longa.
		_clock = 0.0
		visible = false
		set_process(false)
		return
	_material.set_shader_parameter(&"clock", _clock)


func _spawn(origin: Vector3, direction: Vector3, speed: float, limit: float, color: Color, profile: Dictionary, from_outside: bool, with_trail: bool) -> int:
	var slot := next_slot
	next_slot = (next_slot + 1) % bolts
	# Anel cheio: a bala mais velha cede a vaga (o rastro dela segue sozinho até apagar).
	if _end[slot] > 0.0: _release(slot)
	_trail_of[slot] = -1
	_serial[slot] += 1
	_shots += 1
	var shown := clampf(speed, 1.0, 400.0)
	var tail := clampf(shown * TAIL_SECONDS * float(profile.tail), MIN_TAIL, MAX_TAIL)
	_origin[slot] = origin
	_velocity[slot] = direction * shown
	_start[slot] = _clock
	_limit[slot] = clampf(limit, 0.0, 1000.0)
	_tail[slot] = tail
	_life[slot] = 0.0
	_end[slot] = _clock + (_limit[slot] + tail) / shown + 0.02
	_colors[slot] = color
	var seed_value := fmod(float(_shots) * 0.618034, 1.0)
	var linear := _linear(color)
	_set_instance(slot, Vector3(_clock, _limit[slot], tail), Vector3(float(profile.width), float(profile.heat), seed_value),
		Color(linear.r, linear.g, linear.b, float(profile.energy)), Vector4(0.0, 1.0 if from_outside else 0.0, float(profile.core), 0.0))
	if _end[slot] <= 0.0: return -1
	_active += 1
	if with_trail: _spawn_trail(slot, linear, profile, seed_value)
	_dirty = true
	set_process(true)
	return slot


func _spawn_trail(bolt: int, linear: Color, profile: Dictionary, seed_value: float) -> void:
	var slot := bolts + _next_trail
	_next_trail = (_next_trail + 1) % TRAILS
	if _end[slot] > 0.0: _release(slot)
	_serial[slot] += 1
	_origin[slot] = _origin[bolt]
	_velocity[slot] = _velocity[bolt]
	_start[slot] = _start[bolt]
	_limit[slot] = _limit[bolt]
	_tail[slot] = _tail[bolt]
	_life[slot] = float(profile.trail_life)
	var speed := _velocity[slot].length()
	_end[slot] = _start[slot] + _limit[slot] / speed + _life[slot] + 0.02
	var tint := TRAIL_TINT.srgb_to_linear().lerp(linear, 0.2)
	_set_instance(slot, Vector3(_start[slot], _limit[slot], _tail[slot]), Vector3(float(profile.width) * 1.6, 0.0, seed_value),
		Color(tint.r, tint.g, tint.b, float(profile.trail_alpha)), Vector4(1.0, 0.0, _life[slot], float(profile.trail_length)))
	if _end[slot] <= 0.0: return
	_trail_of[bolt] = slot
	_active += 1


## Rastro ainda ligado a esta bala (a vaga do rastro pode ter sido reaproveitada por outra).
func _linked_trail(bolt: int) -> int:
	var slot := _trail_of[bolt]
	if slot < 0 or _end[slot] <= 0.0: return -1
	if not is_equal_approx(_start[slot], _start[bolt]) or not _origin[slot].is_equal_approx(_origin[bolt]): return -1
	return slot


## A bala do NPC parou a `distance` m da boca: a cabeça segura ali e a cauda recolhe.
func _finish(slot: int, distance: float) -> void:
	var speed := _velocity[slot].length()
	_limit[slot] = distance
	_end[slot] = maxf(_start[slot] + (distance + _tail[slot]) / speed + 0.02, _clock + 0.001)
	states[slot].to = _origin[slot] + _velocity[slot] / speed * distance
	_write_slot(slot)
	var linked := _linked_trail(slot)
	if linked >= 0:
		_limit[linked] = distance
		_end[linked] = maxf(_start[linked] + distance / speed + _life[linked] + 0.02, _clock + 0.001)
		_write_slot(linked)
	_dirty = true


func _release(slot: int) -> void:
	if _end[slot] <= 0.0: return
	_end[slot] = 0.0
	# Brilho zero: o shader recolhe a fita para fora da tela.
	_buffer[slot * STRIDE + 15] = 0.0
	if slot < bolts:
		states[slot].life = 0.0
	_active = maxi(_active - 1, 0)
	_dirty = true


## Regrava só os campos de voo (origem, velocidade, tempo) mantendo cor, largura e modo.
func _write_slot(slot: int) -> void:
	var base := slot * STRIDE
	var timing := Vector3(_start[slot], _limit[slot], _tail[slot])
	var origin := _origin[slot]
	var velocity := _velocity[slot]
	if not (timing.is_finite() and origin.is_finite() and velocity.is_finite()):
		_release(slot)
		return
	_buffer[base] = timing.x
	_buffer[base + 2] = velocity.x
	_buffer[base + 3] = origin.x
	_buffer[base + 4] = timing.y
	_buffer[base + 6] = velocity.y
	_buffer[base + 7] = origin.y
	_buffer[base + 8] = timing.z
	_buffer[base + 10] = velocity.z
	_buffer[base + 11] = origin.z


func _set_instance(slot: int, timing: Vector3, look: Vector3, color: Color, extra: Vector4) -> void:
	var origin := _origin[slot]
	var velocity := _velocity[slot]
	var values := [origin, velocity, timing, look]
	for value: Vector3 in values:
		if not value.is_finite():
			_end[slot] = 0.0
			return
	if not (is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a) and extra.is_finite()):
		_end[slot] = 0.0
		return
	var base := slot * STRIDE
	# Linhas da matriz 3×4: (x.x, y.x, z.x, origem.x), (x.y, y.y, z.y, origem.y), (x.z, y.z, z.z, origem.z).
	_buffer[base] = timing.x
	_buffer[base + 1] = look.x
	_buffer[base + 2] = velocity.x
	_buffer[base + 3] = origin.x
	_buffer[base + 4] = timing.y
	_buffer[base + 5] = look.y
	_buffer[base + 6] = velocity.y
	_buffer[base + 7] = origin.y
	_buffer[base + 8] = timing.z
	_buffer[base + 9] = look.z
	_buffer[base + 10] = velocity.z
	_buffer[base + 11] = origin.z
	_buffer[base + 12] = color.r
	_buffer[base + 13] = color.g
	_buffer[base + 14] = color.b
	_buffer[base + 15] = color.a
	_buffer[base + 16] = extra.x
	_buffer[base + 17] = extra.y
	_buffer[base + 18] = extra.z
	_buffer[base + 19] = extra.w


## Envia o buffer e ajusta a AABB às balas vivas (só pontos finitos).
func _commit() -> void:
	_dirty = false
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
	var box := AABB()
	var has := false
	for slot in _end.size():
		if _end[slot] <= 0.0: continue
		var start := _origin[slot]
		var speed := _velocity[slot].length()
		if speed <= 0.0: continue
		var finish := start + _velocity[slot] / speed * _limit[slot]
		if not (start.is_finite() and finish.is_finite()): continue
		if has: box = box.expand(start)
		else:
			box = AABB(start, Vector3.ZERO)
			has = true
		box = box.expand(finish)
	if has:
		# Folga para o halo, o zunido e o rastro que se abre.
		box = box.grow(0.75)
		if box.position.is_finite() and box.size.is_finite(): multimesh.custom_aabb = box
	visible = _active > 0


static func _linear(color: Color) -> Color:
	var safe := color
	if not (is_finite(safe.r) and is_finite(safe.g) and is_finite(safe.b)): safe = DEFAULT_COLOR
	return Color(clampf(safe.r, 0.0, 1.0), clampf(safe.g, 0.0, 1.0), clampf(safe.b, 0.0, 1.0)).srgb_to_linear()
