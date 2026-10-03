extends RefCounted
## Observes actual motion and rider input; UI clicks alone cannot pass a lesson.
enum Stage {ACCELERATE, BRAKE, CORNER, LAP, COMPLETE}
var stage := Stage.ACCELERATE
var _held := 0.0
var _turn := 0.0
var _last_yaw := 0.0
var _lap_at_start := 0

func begin(yaw: float, laps: int = 0) -> void:
	stage = Stage.ACCELERATE
	_held = 0.0
	_turn = 0.0
	_last_yaw = yaw
	_lap_at_start = laps

func observe(delta: float, speed: float, yaw: float, throttle: float, steering: float, brake: bool, riding: bool, grounded: bool, laps: int) -> bool:
	var turn := absf(wrapf(yaw - _last_yaw, -PI, PI))
	_last_yaw = yaw
	if not riding or not grounded:
		_held = 0.0
		return false
	var previous := stage
	match stage:
		Stage.ACCELERATE:
			_held = _held + delta if throttle > .3 and speed >= 5.0 else 0.0
			if _held >= 1.0: stage = Stage.BRAKE
		Stage.BRAKE:
			if brake and absf(speed) < 1.0:
				stage = Stage.CORNER
				_turn = 0.0
		Stage.CORNER:
			if absf(steering) > .15 and speed >= 2.0 and speed <= 10.0 and turn < .12:
				_turn += turn
			if _turn >= .65:
				stage = Stage.LAP
				_lap_at_start = laps
		Stage.LAP:
			if laps > _lap_at_start: stage = Stage.COMPLETE
	return previous != stage

func instruction() -> String:
	match stage:
		Stage.ACCELERATE: return "Digo: acelere com W ou ↑; mantenha 18 km/h por um segundo."
		Stage.BRAKE: return "Digo: solte o acelerador e freie com Espaço até parar."
		Stage.CORNER: return "Digo: faça uma curva com A/D ou ←/→, entre 7 e 36 km/h."
		Stage.LAP: return "Digo: complete uma volta pelos pontos da pista. No salto, W/S ajustam a moto."
	return "Digo: mandou bem! Pare para devolver a moto; as corridas ficam comigo."
