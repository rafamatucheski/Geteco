extends RefCounted
## Vento único do clima. Direção e força de base vêm do perfil da região
## (AtmosphereProfile.wind, lido como km/h no plano x/z); por cima correm rajadas
## que chegam, seguram e passam. Chuva, neve, granizo, capim e o som do vento leem
## este mesmo estado: a rajada que entorta a chuva é a que se ouve e a que deita o mato.
## Antes cada efeito tinha a própria senoide (a chuva do porto oscilava 0,035 e quase
## ninguém via) e o vento dos perfis não era usado por nada.
## GETECO_WIND_GUSTS=0 volta à chuva quase reta, à neve fixa e ao som antigo (A/B).
static var enabled := OS.get_environment("GETECO_WIND_GUSTS") != "0"
const KMH := 1.0/3.6
## Perfil com vento quase nulo (transição porto→costa cruza o zero): mantém a direção anterior.
const MIN_DIRECTION_KMH := 1.5
## Rajada sobe rápido e morre devagar; constantes de tempo em segundos.
const RISE_SECONDS := .55
const FALL_SECONDS := 1.7

## Velocidade horizontal (m/s) já com a rajada.
var velocity := Vector3.ZERO
## Envelope da rajada, 0 calmo .. 1 rajada cheia de tempestade.
var gust := 0.0
## Direção horizontal unitária (x, z), com a deriva lenta.
var direction := Vector2(1, 0)
var _base := Vector2.ZERO
var _primed := false
var _clock := 0.0
var _gusting := false
var _phase_left := 3.0
var _peak := 0.0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

## Testes fixam a sequência de rajadas.
func seed_with(value: int) -> void:
	_rng.seed = value

## `storm` 0..1: chuva/frente presentes. Garoa dá rajadas fracas e raras; tempestade, fortes e seguidas.
func advance(delta: float, profile_wind: Vector2, storm: float) -> void:
	delta = maxf(delta, 0.0)
	storm = clampf(storm, 0.0, 1.0)
	_clock += delta
	# O perfil já chega misturado entre regiões a cada 0,2 s; suaviza o degrau que sobra.
	_base = profile_wind if not _primed else _base.lerp(profile_wind, 1.0-exp(-delta/4.0))
	_primed = true
	if _base.length() > MIN_DIRECTION_KMH:
		# Deriva de ±13° em dezenas de segundos: a chuva não cai sempre no mesmo ângulo.
		var wander := .16*sin(_clock*.043)+.06*sin(_clock*.17)
		direction = _base.normalized().rotated(wander)
	_phase_left -= delta
	if _phase_left <= 0.0:
		_gusting = not _gusting
		if _gusting:
			_peak = _rng.randf_range(.45, 1.0)*lerpf(.35, 1.0, storm)
			_phase_left = _rng.randf_range(.8, 2.5)*lerpf(1.0, 1.6, storm)
		else:
			_phase_left = _rng.randf_range(lerpf(8.0, 3.0, storm), lerpf(16.0, 7.0, storm))
	var target := _peak if _gusting else 0.0
	var seconds := RISE_SECONDS if target > gust else FALL_SECONDS
	gust = lerpf(gust, target, 1.0-exp(-delta/seconds))
	# Turbulência dentro da rajada, nunca no calmo.
	var flutter := 1.0+.08*sin(_clock*2.3)*gust
	var speed := _base.length()*KMH*lerpf(.75, 1.5, storm)*(1.0+1.1*gust)*flutter
	velocity = Vector3(direction.x, 0.0, direction.y)*speed
