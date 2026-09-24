extends RefCounted
## Parâmetros e funções puras da ultrapassagem de viaturas por carros ambiente
## que cederam passagem (`traffic_yield_state` = held | pulling). Metros e
## segundos; todos os valores são escolhas novas e não têm calibração em jogo.

const EVAL_INTERVAL := 0.25
## Quanto à frente, na própria faixa, procurar veículos.
const DETECT_AHEAD := 32.0
## Começa a planejar quando o primeiro bloqueador está a menos de max(TRIGGER_MIN, v·TRIGGER_SECONDS + 8).
const TRIGGER_MIN := 12.0
const TRIGGER_SECONDS := 1.6
## Folga lateral entre o casco da viatura e o do carro ultrapassado.
const CLEAR_SIDE := 0.6
## O casco varrido é maior que o do Vehicle por estas folgas (por lado / por ponta).
const PAD_SIDE := 0.25
const PAD_END := 0.4
const MAX_SHIFT := 4.5
const MIN_SHIFT := 0.05
## Comprimento de rampa por metro de deslocamento lateral (rápido / devagar).
const RAMP_PER_M_FAST := 6.0
const RAMP_PER_M_SLOW := 3.5
const SLOW_SPEED := 3.0
const MIN_RAMP := 8.0
## Depois da traseira/dianteira do último bloqueador.
const FRONT_CLEAR := 2.5
const TAIL := 8.0
const SAMPLE_STEP := 1.5
## Variação máxima de rumo entre amostras (≈ raio 12 m): sem ultrapassar em curva fechada.
const MAX_TURN := 0.12
## O casco não pode cruzar o eixo da rua a menos que a contramão seja permitida.
const CENTER_MARGIN := 0.05
const ONCOMING_LOOKAHEAD := 40.0
const PASS_SPEED := 6.0
const ONCOMING_SPEED := 5.0
const RETURN_SPEED := 3.0
## Bloqueador que anda mais rápido que isto ainda está se acomodando: espera.
const BLOCKER_MAX_SPEED := 4.5
const WAIT_MAX := 20.0
const PASSING_MAX := 30.0
## Parada com algo à frente durante a ultrapassagem antes de abortar.
const STUCK_ABORT := 1.0
## Folga mínima prevista entre a viatura e quem vem na faixa contrária quando ela termina de passar.
const SAFE_GAP := 4.0
## Distância extra para sair da faixa contrária depois da dianteira do último bloqueador.
const RETURN_ALLOWANCE := 6.0
## Velocidade usada para estimar quanto falta para sair, mesmo parada.
const MIN_EXIT_SPEED := 3.0
## Parada em espera pela faixa contrária sem solução: declara "sem solução" (segue esperando).
const OPPOSING_PATIENCE := 10.0
## Volta à faixa impedida por tanto tempo: declara "sem solução" (segue esperando).
const RECOVER_PATIENCE := 12.0
## Episódio de recuperação (do primeiro aborto/espera fora do eixo até voltar) além disto:
## declara "sem solução". Relógio do episódio, não reiniciado por abortos repetidos.
const EPISODE_PATIENCE := 45.0
## Voltas que travaram (returning -> recovering) no mesmo episódio antes de declarar "sem solução".
const RETURN_MAX_FAILURES := 3
## Rampas de retorno tentadas, como múltiplos da rampa normal. Só mais suaves: uma rampa
## mais curta exigiria esterço que ninguém verificou.
const RETURN_RAMP_SCALES: Array[float] = [1.0, 1.6, 2.4]
## Cosseno mínimo entre o rumo da viatura e o do eixo para tentar o retorno (sem meia-volta).
const RETURN_MIN_ALIGNMENT := 0.35
## Eixo acabando perto: o retorno pode encurtar a cauda até este mínimo depois da rampa.
const RETURN_MIN_TAIL := 1.0
## Corpo à frente que anda menos que isto conta como parado (classifica a espera pela faixa contrária).
const STATIONARY_SPEED := 0.3
## Sem tick por tantos quadros de física = a unidade foi suspensa: descarta o plano.
const RESUME_GAP_FRAMES := 20
const YIELD_STATES: Array[String] = ["held", "pulling"]

## Condição necessária para uma espera sair sozinha (texto para log/integrador, sem HUD).
## Nenhuma delas é forçada pelo código: a viatura só se move quando a condição se cumpre
## e a varredura de casco aprova a curva. "" = motivo sem condição catalogada.
static func exit_condition(reason: String) -> String:
	if reason == "return_blocked:route_ends":
		return "nenhuma: o eixo não comporta a rampa (só remoção, suspensão longa ou dismiss_all)"
	if reason.begins_with("return_blocked:") or reason == "return_blocked_by_oncoming":
		return "faixa própria livre à frente do retorno (fila, sólido ou bloqueador ao lado saírem) e sem cruzamento/curva na rampa"
	match reason:
		"oncoming_stopped_ahead": return "o carro contrário parado voltar a andar (sem ré implementada)"
		"oncoming_deadlock", "oncoming_traffic": return "folga prevista ≥ SAFE_GAP na faixa contrária"
		"bypass_obstructed": return "o desvio preservado ficar livre na varredura de casco"
		"engine_disabled_while_displaced", "engine_disabled_waiting": return "o motor ser liberado (engine_disabled = false)"
		"recovery_no_progress", "return_failed_repeatedly": return "uma curva de retorno aprovada que a viatura consiga completar"
		"heading_mismatch": return "o rumo da viatura voltar a ficar compatível com o do eixo (não há meia-volta)"
	return ""

static func smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func ramp_length(shift_change: float, speed: float) -> float:
	var per_meter := RAMP_PER_M_SLOW if speed < SLOW_SPEED else RAMP_PER_M_FAST
	return maxf(MIN_RAMP, absf(shift_change) * per_meter)

## Deslocamento lateral à esquerda da rota, `s` metros à frente do ponto atual.
## Sobe de `start` a `target` em `ramp_in`, fica até `hold_until`, volta a zero em `ramp_out`.
static func profile(s: float, start: float, target: float, ramp_in: float, hold_until: float, ramp_out: float) -> float:
	if s < ramp_in: return lerpf(start, target, smooth(s / maxf(ramp_in, 0.001)))
	if s <= hold_until: return target
	return lerpf(target, 0.0, smooth((s - hold_until) / maxf(ramp_out, 0.001)))

## Quanto a viatura precisa se deslocar à esquerda para passar de um carro cujo
## centro está `right_of_route` à direita do eixo da rota. Zero = já cabe.
static func needed_shift(right_of_route: float, blocker_half_width: float, own_half_width: float) -> float:
	return maxf(0.0, blocker_half_width + CLEAR_SIDE + own_half_width - right_of_route)
