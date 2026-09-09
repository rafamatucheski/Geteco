class_name MonalizaAudioKit
extends RefCounted
## Síntese procedural original e isolada para o primeiro carro pessoal do
## Dante: a Monaliza, um cupê turbo de quatro cilindros preparado, azul e
## laranja. Nenhum sample de terceiros -- tudo aqui é osciladores + ruído
## filtrado, gerado a partir do zero.
##
## Não integra com VehicleEngineSound.gd, ProceduralAudio.gd, PlayerCar ou
## qualquer script de carro -- é a Astra quem decide como (e se) conectar
## isto. Ver audio/monaliza_review/README.md para sample rate, volumes
## sugeridos, durações e limites.
##
## Todas as funções `generate_*_stream()` retornam um AudioStreamWAV pronto
## (mono, 16-bit, SAMPLE_RATE). O cache de instância é responsabilidade de
## quem integrar -- este arquivo não cacheia nada.

const SAMPLE_RATE := 22050

const ENGINE_DURATION := 1.0
const TURBO_SPOOL_DURATION := 1.0
const TURBO_RELEASE_DURATION := 0.55
const IGNITION_CRANK_DURATION := 0.55
const IGNITION_CATCH_DURATION := 0.75
const IGNITION_DURATION := IGNITION_CRANK_DURATION + IGNITION_CATCH_DURATION
const DEMO_DURATION := 4.6

# ==========================================
# PEÇAS DE SÍNTESE REUTILIZADAS (mesma "linguagem sonora" em todos os arquivos,
# inclusive na demonstração composta)
# ==========================================

## Pilha harmônica do motor: 4 cilindros turbo, não um V8. Ordens pares
## (2ª/4ª) reforçadas -- é o que dá aquele "zumbido" característico de
## inline-4 -- e sem rumble grave abaixo de ~40Hz, que é onde um V8 "pesa".
static func _engine_tone(phase: float) -> float:
	var combustion := 0.0
	for h in range(1, 9):
		var amp := 1.0 / pow(float(h), 1.35)
		if h == 2 or h == 4:
			amp *= 1.4
		combustion += sin(phase * float(h) + float(h % 3) * 0.15) * amp
	return combustion

## Estalo mecânico curto (injeção/válvulas) uma vez por ciclo de combustão --
## não é um chiado contínuo, só uma textura de "corpo" no motor.
static func _mechanical_clatter(cycle_phase: float) -> float:
	var frac := fposmod(cycle_phase, 1.0)
	if frac >= 0.05:
		return 0.0
	var env := 1.0 - (frac / 0.05)
	return randf_range(-1.0, 1.0) * env * env

## Motor de arranque girando: pulsos mecânicos rítmicos + ruído de atrito
## filtrado. `lp_state` é um Dictionary {"v": float} mutável entre chamadas
## (mantém o estado do filtro passa-baixa de uma amostra para a outra).
static func _cranking_sample(t: float, lp_state: Dictionary) -> float:
	var pulse_rate := 9.0
	var pulse_phase := fposmod(t * pulse_rate, 1.0)
	var pulse_env := 1.0 if pulse_phase < 0.55 else 0.0
	var whir := sin(TAU * 145.0 * t) * 0.4 * pulse_env
	var noise := randf_range(-1.0, 1.0)
	var lp: float = lp_state.get("v", 0.0)
	lp += (noise - lp) * 0.28
	lp_state["v"] = lp
	var grind := lp * 0.35 * pulse_env
	return whir + grind

## Alívio de turbo (blow-off): ataque rápido, ruído filtrado com flutter
## (o clássico "pssh-tt-tt-tt" da wastegate) e um assobio curto descendente
## simulando a turbina desacelerando. `lp_state` como acima.
static func _release_sample(t: float, lp_state: Dictionary) -> float:
	var attack := 0.006
	var env := (t / attack) if t < attack else exp(-(t - attack) * 7.5)
	var flutter := 0.55 + 0.45 * sin(TAU * 17.0 * t) * exp(-t * 3.0)
	var noise := randf_range(-1.0, 1.0)
	var lp: float = lp_state.get("v", 0.0)
	lp += (noise - lp) * 0.22
	lp_state["v"] = lp
	var chirp_freq := lerpf(2200.0, 900.0, clampf(t / 0.30, 0.0, 1.0))
	var chirp := sin(TAU * chirp_freq * t) * exp(-t * 6.0) * 0.35
	return (lp * 0.85 * flutter + chirp) * env

## Faz o fim de um buffer de loop convergir suavemente para o valor exato da
## primeira amostra (samples[0]) -- é isso que faz a emenda (última amostra
## -> primeira amostra, quando o loop volta ao início) ficar sem degrau.
## Rede de segurança sobretudo para as camadas com ruído; os osciladores de
## frequência inteira já fecham quase exatos sozinhos.
##
## (Importante: o alvo do blend tem que ser sempre samples[0] -- uma versão
## anterior desta função misturava com samples[i], que converge para um
## valor no MEIO do começo do buffer, não para samples[0], e por isso não
## eliminava o degrau da emenda de verdade.)
static func _declick_loop(samples: PackedFloat32Array, crossfade_n: int) -> void:
	var n := samples.size()
	crossfade_n = mini(crossfade_n, int(n / 4))
	var head: float = samples[0]
	for i in range(crossfade_n):
		var w := float(i + 1) / float(crossfade_n) # sobe suave até 1.0 exatamente na última amostra
		var tail_idx := n - crossfade_n + i
		samples[tail_idx] = samples[tail_idx] * (1.0 - w) + head * w

## Interpolação linear por trechos entre pontos-chave [[tempo, valor], ...]
## ordenados por tempo crescente. Usado para as curvas de frequência/
## amplitude da demonstração composta.
static func _lerp_curve(t: float, points: Array) -> float:
	if points.is_empty():
		return 0.0
	if t <= points[0][0]:
		return points[0][1]
	for k in range(points.size() - 1):
		var a: Array = points[k]
		var b: Array = points[k + 1]
		if t <= b[0]:
			var ratio := clampf((t - a[0]) / maxf(0.0001, b[0] - a[0]), 0.0, 1.0)
			return lerpf(a[1], b[1], ratio)
	return points[points.size() - 1][1]

## Converte um buffer de floats (aprox. -1..1, com alguma margem) num
## AudioStreamWAV mono 16-bit, com soft-clip (tanh) -- garante que nada
## satura em cheio mesmo se a soma das camadas passar de 1.0 antes do
## `drive`/`peak`.
static func _to_wav(samples: PackedFloat32Array, loop: bool, drive: float, peak: float) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var s := tanh(samples[i] * drive) * peak
		data.encode_s16(i * 2, clampi(int(s * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream

# ==========================================
# OS 4 ARQUIVOS ENTREGÁVEIS
# ==========================================

## engine.wav -- loop de motor encorpado, 4 cilindros turbo (não um V8).
static func generate_engine_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * ENGINE_DURATION)
	var fundamental := 64.0 # Hz inteiro -> ciclos exatos em 1.0s (loop sem costura)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var phase := TAU * fundamental * t
		var combustion := _engine_tone(phase)
		var sub := sin(phase * 0.5) * 0.10 # fundação grave discreta, sem virar rumble de V8
		var flutter := 0.95 + 0.05 * sin(TAU * 5.0 * t) # 5Hz inteiro -> continua periódico em 1.0s
		var clatter := _mechanical_clatter(fundamental * t) * 0.05
		samples[i] = (combustion * 0.5 + sub) * flutter + clatter
	_declick_loop(samples, 220) # ~10ms, rede de segurança para o clatter aleatório
	return _to_wav(samples, true, 1.15, 0.55)

## turbo_spool.wav -- loop de assobio discreto (nível bem abaixo do motor).
static func generate_turbo_spool_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * TURBO_SPOOL_DURATION)
	var freq_a := 1200.0 # Hz inteiro
	var freq_b := 1215.0 # Hz inteiro -> beat de 15Hz, também inteiro em 1.0s
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		samples[i] = sin(TAU * freq_a * t) * 0.5 + sin(TAU * freq_b * t) * 0.5
	var lp := 0.0
	for i in range(n):
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.10
		samples[i] += lp * 0.06 # sopro de ar bem discreto, não um chiado alto
	_declick_loop(samples, 220)
	return _to_wav(samples, true, 1.0, 0.30)

## turbo_release.wav -- one-shot curto de alívio ao soltar o acelerador.
static func generate_turbo_release_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * TURBO_RELEASE_DURATION)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp_state := {"v": 0.0}
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		samples[i] = _release_sample(t, lp_state)
	return _to_wav(samples, false, 1.1, 0.70)

## ignition.wav (opcional) -- arranque girando, motor pega, breve acomodação.
static func generate_ignition_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * IGNITION_DURATION)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp_state := {"v": 0.0}
	var engine_phase := 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var value := 0.0
		# Cruzamento suave arranque -> motor pegando, centrado no fim do
		# cranking (evita o clique de uma troca abrupta entre as duas texturas).
		var crank_w := clampf((t - (IGNITION_CRANK_DURATION - 0.04)) / 0.08, 0.0, 1.0)
		if t < IGNITION_CRANK_DURATION:
			value += _cranking_sample(t, lp_state) * clampf(t / 0.03, 0.0, 1.0) * (1.0 - crank_w)
		var lt := t - IGNITION_CRANK_DURATION
		var freq := lerpf(95.0, 62.0, clampf(lt / 0.55, 0.0, 1.0))
		var tail_env := 1.0
		if lt > IGNITION_CATCH_DURATION - 0.12:
			tail_env = clampf((IGNITION_CATCH_DURATION - lt) / 0.12, 0.0, 1.0)
		value += _engine_tone(engine_phase) * 0.45 * crank_w * tail_env
		engine_phase += TAU * freq / float(SAMPLE_RATE)
		samples[i] = value
	return _to_wav(samples, false, 1.1, 0.60)

# ==========================================
# DEMONSTRAÇÃO COMPOSTA (partida + aceleração + alívio, para audição)
# ==========================================

## Não é uma simples concatenação dos 4 arquivos (colar buffers com pitch
## diferente entre si causaria estalos de emenda) -- é uma síntese contínua
## dedicada que reaproveita exatamente as mesmas peças (_engine_tone,
## _cranking_sample, _release_sample) ao longo de uma linha do tempo com
## frequência/amplitude variando suavemente. Como é um único cálculo
## contínuo (não um loop, não há costura para fechar), não há risco de
## clique de emenda em lugar nenhum do arquivo.
static func generate_demo_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * DEMO_DURATION)
	var samples := PackedFloat32Array()
	samples.resize(n)

	# [tempo(s), valor] -- motor: idle -> acelera -> solta o acelerador -> assenta
	var engine_freq_points := [[0.42, 58.0], [0.90, 58.0], [3.05, 145.0], [3.35, 68.0], [4.20, 80.0], [4.60, 80.0]]
	# Turbo: silencioso -> constrói pressão -> cai rápido no alívio
	var turbo_amp_points := [[0.0, 0.0], [1.40, 0.0], [2.10, 0.22], [2.90, 0.30], [3.05, 0.30], [3.35, 0.0], [4.60, 0.0]]
	var turbo_freq_points := [[0.0, 700.0], [1.40, 700.0], [2.90, 1650.0], [3.05, 1650.0], [3.35, 750.0], [4.60, 750.0]]

	var release_start := 3.05

	var engine_phase := 0.0
	var turbo_phase := 0.0
	var crank_lp := {"v": 0.0}
	var release_lp := {"v": 0.0}

	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var value := 0.0

		# Arranque -> motor pegando (mesmo cruzamento suave do ignition.wav).
		var crank_w := clampf((t - 0.46) / 0.08, 0.0, 1.0)
		if t < 0.55:
			value += _cranking_sample(t, crank_lp) * clampf(t / 0.03, 0.0, 1.0) * (1.0 - crank_w)

		var eng_freq := _lerp_curve(t, engine_freq_points)
		var eng_env := crank_w * clampf((DEMO_DURATION - t) / 0.4, 0.0, 1.0) # fade-out final de 0.4s
		value += _engine_tone(engine_phase) * 0.5 * eng_env
		engine_phase += TAU * eng_freq / float(SAMPLE_RATE)

		var turbo_amp := _lerp_curve(t, turbo_amp_points)
		if turbo_amp > 0.0001:
			var turbo_freq := _lerp_curve(t, turbo_freq_points)
			value += sin(turbo_phase) * turbo_amp
			turbo_phase += TAU * turbo_freq / float(SAMPLE_RATE)

		var rel_t := t - release_start
		if rel_t >= 0.0 and rel_t < TURBO_RELEASE_DURATION:
			value += _release_sample(rel_t, release_lp) * 0.8

		samples[i] = value

	return _to_wav(samples, false, 1.0, 0.65)
