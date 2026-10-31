extends SceneTree
## Regressão rápida de layout usando os controles de produção, sem Main nem mundo de jogo.
## Também aceita --touch-controls para exercitar o layout de toque de produção.
const HUD := preload("res://ui/hud/ContextualHUDManager.gd")
const CAPTION := preload("res://ui/dialogue/DialogueCaption.gd")
const SAVE_INDICATOR := preload("res://ui/SaveIndicator.gd")
const STYLE := preload("res://ui/GameStyle.gd")
const LONG_PROMPT := "Entrar no veículo de transporte e confirmar a viagem até a oficina do Maciota, levando os equipamentos guardados na mochila."
const LONG_HINT := "Botão lateral direito do controle"
const OBJECTIVE := "Encontre Maciota na oficina do porto."
const STATION := "PORTO GROOVE · Wednesday Night"
const DISPATCH := "Rádio · Suspeito segue pela avenida do porto. Mantenham distância."
const FEEDBACK := "Equipamento guardado. A mochila continua disponível durante a viagem."
const SPOKEN_LINE := "Já peguei a pista no porto. Vou conferir o endereço antes de seguir para a montanha."
const SAVE_REASON := "Salvamento indisponível durante a transição de região. Aguarde a chegada ao destino."

class Controls extends Node:
	var binding := "E"
	func prompt(_action: String) -> String: return binding

class Session extends Node:
	var speech_caption: Control
	var panel: Control

var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var hud
var controls: Controls
var session: Session
var station: Label
var caption
var save_layer: CanvasLayer
var indicator: Control

func _initialize() -> void: run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle() -> void:
	# Native containers and wrapped text settle over successive deferred passes.
	for frame in 12: await process_frame

func run() -> void:
	viewport = SubViewport.new()
	viewport.name = "HUDLayoutFixture"
	viewport.disable_3d = true
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	controls = Controls.new()
	viewport.add_child(controls)
	session = Session.new()
	viewport.add_child(session)
	hud = HUD.new()
	viewport.add_child(hud)
	hud.set_process(false)
	# Nenhum mundo é necessário para o layout. Desliga a atualização de dados do minimapa, que
	# se esconde com razão quando nenhuma sessão de jogo foi fornecida.
	hud.minimap.set_process(false)
	hud.minimap.show()
	caption = CAPTION.new()
	hud.add_child(caption)
	session.speech_caption = caption
	hud._session = session
	hud._bound = true
	hud._speech_caption = caption
	hud._watch_layout(caption)
	station = STYLE.label(STATION, 13)
	station.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	station.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	station.add_theme_stylebox_override("normal", STYLE.compact(false, 8))
	hud.attach_station_notice(station)
	save_layer = CanvasLayer.new()
	save_layer.layer = 125
	viewport.add_child(save_layer)
	indicator = SAVE_INDICATOR.new()
	save_layer.add_child(indicator)
	indicator.set_blocked(SAVE_REASON)
	populate()
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(800, 600)]:
		viewport.size = extent
		caption.hide()
		controls.binding = "E"
		hud.interaction_row.update_prompt(LONG_PROMPT, "vehicle_interact", controls)
		hud._queue_layout()
		await settle()
		var context := "gameplay %s" % extent
		check_channels(context)
		check_feed(context)
		check_text(context)
		check_prompt(context)
		if extent.x == 800:
			check(hud.interaction_label.get_line_count() > 1, "small viewport wraps the long action instead of squeezing it")
		var long_size: Vector2 = hud.interaction_row.size
		hud.interaction_row.update_prompt("Entrar", "vehicle_interact", controls)
		await settle()
		check(hud.interaction_row.size.x < long_size.x and hud.interaction_row.size.y <= long_size.y,
			"short action releases the long prompt's space at %s" % extent)
		check_prompt("short action %s" % extent)
		# A ação continua a mesma: só o atalho atual cresce.
		controls.binding = LONG_HINT
		hud.interaction_row.update_prompt("Entrar", "vehicle_interact", controls)
		await settle()
		check(hud.interaction_key.text == LONG_HINT and hud.interaction_label.text == "Entrar",
			"rebinding preserves the complete key and action at %s" % extent)
		check_prompt("long binding %s" % extent)
		check_channels("long binding %s" % extent)
		controls.binding = "E"
		hud.interaction_row.update_prompt(LONG_PROMPT, "vehicle_interact", controls)
		caption.set_line("Dante", SPOKEN_LINE)
		await settle()
		check(caption.message.text == SPOKEN_LINE and caption.message.visible_characters == -1,
			"spoken caption preserves the full line at %s" % extent)
		check_channels("speech %s" % extent)
		check_feed("speech %s" % extent)
		check_prompt("speech %s" % extent)
		check_save("speech %s" % extent)
		# O retorno de save pertence à própria camada e precisa sobreviver ao canal de jogo
		# escondido, incluindo uma pausa sem HUD processando.
		caption.hide()
		hud.root_control.hide()
		paused = true
		await settle()
		check(indicator.is_visible_in_tree() and indicator.get_parent() == save_layer,
			"save warning remains on its independent layer during pause at %s" % extent)
		check(indicator.get_node("BlockedReason").text == SAVE_REASON,
			"pause preserves the complete save warning at %s" % extent)
		check_bounds(save_rect(), "paused save warning %s" % extent)
		paused = false
		hud.root_control.show()
		await settle()
		check_save("resumed gameplay %s" % extent)
	viewport.free()
	print("HUD_LAYOUT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func populate() -> void:
	hud.player_status.update_status(82.0, 65.0, {"visible": true, "temperature": 42.0, "text": "Frio", "key": "exposed"}, 0.0)
	hud.player_status.update_rage({"unlocked": true, "charge": 70.0, "ready": false}, "G")
	hud.money.update_balance(123456, false)
	hud.stars_label.text = "[right]★★★  Busca[/right]"
	hud.stars_label.show()
	hud.search_progress.value = 0.35
	hud.search_progress.show()
	hud.radio_label.text = DISPATCH
	hud.radio_label.show()
	hud.objective_card.present(OBJECTIVE, "Novo objetivo", 60.0)
	hud.feedback_card.present(FEEDBACK, "", 60.0)
	hud.current_objective_label.text = OBJECTIVE
	hud.current_objective.show()
	hud.minimap.caption.text = "Oficina do Maciota · 450 m"
	hud.minimap.caption.show()
	hud.minimap.weekday_label.text = "Terça-feira\n18h30\nTempo limpo"
	hud.minimap.weather_icon.position = hud.minimap.weekday_label.position + Vector2(0, 74)
	hud.weapon_icon.set_weapon("pistol")
	hud.ammo_label.text = "18  |  96"
	hud.backpack_hint.text = "Tab"
	hud.speed_label.text = "72 km/h"
	hud.speed_label.show()

func check_bounds(rect: Rect2, context: String) -> void:
	check(viewport.get_visible_rect().grow(0.01).encloses(rect), "%s stays inside viewport: %s" % [context, rect])

func check_channels(context: String) -> void:
	# Compare peer regions only. Children intentionally occupy their own panels.
	var channels: Array[Dictionary] = []
	for entry in [
		["status", hud.player_status], ["money and search", hud.top_right_panel],
		["center feed", hud._center_feed], ["minimap", hud.minimap],
		["destination", hud.minimap.caption], ["conditions", hud.minimap.weekday_label],
		["weather", hud.minimap.weather_icon], ["objective", hud.current_objective],
		["equipment", hud._lower_right], ["speed", hud.speed_label],
		["interaction", hud.interaction_row], ["speech", caption],
	]:
		var control: Control = entry[1]
		if control.is_visible_in_tree(): channels.append({"name": entry[0], "rect": control.get_global_rect()})
	if indicator.is_visible_in_tree(): channels.append({"name": "save warning", "rect": save_rect()})
	for index in channels.size():
		var current: Dictionary = channels[index]
		check_bounds(current.rect, "%s %s" % [context, current.name])
		for other_index in range(index+1, channels.size()):
			var other: Dictionary = channels[other_index]
			check(not current.rect.intersects(other.rect), "%s: %s %s intersects %s %s" % [context, current.name, current.rect, other.name, other.rect])

func check_feed(context: String) -> void:
	var notices: Array[Control] = [station, hud.radio_label, hud.objective_card, hud.feedback_card]
	for index in notices.size():
		var notice := notices[index]
		check(notice.is_visible_in_tree(), "%s notice %d remains visible" % [context, index])
		check(hud._center_feed.get_global_rect().grow(0.01).encloses(notice.get_global_rect()),
			"%s notice %d fits the shared feed" % [context, index])
		for other_index in range(index+1, notices.size()):
			check(not notice.get_global_rect().intersects(notices[other_index].get_global_rect()),
				"%s feed messages %d and %d stay separate" % [context, index, other_index])
	for radio: Control in [station, hud.radio_label]:
		check(absf(radio.get_global_rect().get_center().x-viewport.get_visible_rect().get_center().x) <= 1.0,
			"%s radio stays horizontally centered" % context)

func check_text(context: String) -> void:
	check(station.text == STATION and hud.radio_label.text == DISPATCH, "%s preserves both radio messages" % context)
	check(hud.objective_label.text == OBJECTIVE and hud.current_objective_label.text == OBJECTIVE,
		"%s preserves objective text in both presentations" % context)
	check(hud.notice_label.text == FEEDBACK and hud.interaction_label.text == LONG_PROMPT,
		"%s preserves feedback and the complete interaction" % context)
	check(hud.player_status.cold_row.is_visible_in_tree() and hud.search_progress.is_visible_in_tree(),
		"%s includes expanded cold and search status" % context)
	check(hud.minimap.caption.size.x <= hud.minimap.size.x,
		"%s destination stays within the navigation channel" % context)

func check_prompt(context: String) -> void:
	var surface: Rect2 = hud.interaction_row.get_global_rect()
	check_bounds(surface, context+" interaction")
	for label: Label in [hud.interaction_key, hud.interaction_label]:
		if not label.is_visible_in_tree(): continue
		check(surface.grow(0.01).encloses(label.get_global_rect()), "%s complete key/action stays inside prompt" % context)
		check(label.visible_characters == -1 and label.max_lines_visible == -1, "%s key/action does not truncate text" % context)
	check(not hud.interaction_key.get_global_rect().intersects(hud.interaction_label.get_global_rect()),
		"%s key and action stay separate" % context)

func save_rect() -> Rect2:
	var rect := indicator.get_global_rect()
	var reason: Label = indicator.get_node("BlockedReason")
	if reason.is_visible_in_tree(): rect = rect.merge(reason.get_global_rect())
	return rect

func check_save(context: String) -> void:
	check(indicator.is_visible_in_tree(), "%s keeps the save warning visible" % context)
	var rect := save_rect()
	check_bounds(rect, context+" save warning")
	# Os instrumentos do desktop ficam embaixo; os de toque ficam em cima.
	# O aviso pode usar qualquer das fileiras adjacentes, mas não pode cobrir nenhum instrumento.
	check(not rect.intersects(hud.speed_label.get_global_rect()) and not rect.intersects(hud._lower_right.get_global_rect()),
		"%s keeps the whole save warning separate from speed and equipment" % context)
