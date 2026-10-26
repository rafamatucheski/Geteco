extends RefCounted
## Descanso que pula o relógio até uma hora fixa e salva: Horizonte (até as 20h), quarto do Motel
## Oásis e catre do Refúgio da Serra (até as 7h, curado). Antes cada lugar tinha a própria cópia
## destas linhas; a virada do dia (moon_day) precisa ser igual em todos.

## Com estrela de polícia ou save bloqueado (atividade, combate) não se descansa.
static func blocked(session) -> bool:
	return session.world.gameplay.stars > 0 or not session.save_block_reason().is_empty()

static func until(session, hour: float, heal := false) -> void:
	var weather = session.weather
	var target := hour / 24.0
	var day_fraction := fposmod(target - weather.time_of_day, 1.0)
	session.activities.advance_time(day_fraction * 600.0)
	if weather.time_of_day + day_fraction >= 1.0: session.state.world_state.moon_day = weather.moon_day() + 1
	weather.time_of_day = target
	session.state.world_state.time = weather.time_of_day
	weather._update()
	if heal: session.world.gameplay.heal(100.0)
	session.save_game()
