extends RefCounted
## Passada cresce com a velocidade, sem deixar os passos acelerarem demais.
const MIN_STRIDE := 0.78
const MAX_STRIDE := 2.5
const SPEED_PER_STEP := 2.6

static func stride(speed: float) -> float:
	return clampf(speed / SPEED_PER_STEP, MIN_STRIDE, MAX_STRIDE)
