extends Node
## Ações de jogo independentes dos atalhos de navegação dos menus.
signal bindings_changed
signal device_changed
var using_gamepad := false
var aim_direction := Vector2.RIGHT
var remapping := false
var touch_move := Vector2.ZERO
var touch_aim := Vector2.ZERO
const KEYS := {
	"move_up": [KEY_W,KEY_UP], "move_down": [KEY_S,KEY_DOWN],
	"move_left": [KEY_A,KEY_LEFT], "move_right": [KEY_D,KEY_RIGHT],
	"sprint": [KEY_SHIFT], "interact": [KEY_E], "exit_vehicle": [KEY_F,KEY_ENTER],
	"handbrake": [KEY_SPACE], "horn": [KEY_H], "headlights": [KEY_L],
	"radio_next": [KEY_R], "reload": [KEY_R], "journal": [KEY_J], "trunk": [KEY_T],
	"weapon_next": [KEY_Q], "weapon_previous": [], "unarmed": [KEY_X],
	"fire": [], "aim": [], "pause_game": [KEY_ESCAPE], "world_map": [KEY_M],
	"weapon_slot_1": [KEY_1],
	"weapon_slot_2": [KEY_2],
	"weapon_slot_3": [KEY_3],
	"weapon_slot_4": [KEY_4],
	"weapon_slot_5": [KEY_5],
	"weapon_slot_6": [KEY_6],
	"weapon_slot_7": [KEY_7],
	"weapon_slot_8": [KEY_8],
	"weapon_slot_9": [KEY_9],
	"weapon_slot_10": [KEY_0],

}
const LABELS := {
	"move_up": ["Avançar / Acelerar","Move forward / Accelerate"],
	"move_down": ["Recuar / Ré","Move backward / Reverse"],
	"move_left": ["Esquerda","Left"], "move_right": ["Direita","Right"],
	"sprint": ["Correr","Sprint"], "interact": ["Interagir / Entrar","Interact / Enter"],
	"exit_vehicle": ["Sair do veículo","Exit vehicle"], "handbrake": ["Freio de mão","Handbrake"],
	"horn": ["Buzina","Horn"], "headlights": ["Faróis","Headlights"],
	"reload": ["Recarregar","Reload"], "radio_next": ["Próxima rádio","Next radio"], "journal": ["Diário","Journal"],
	"trunk": ["Porta-malas","Trunk"], "weapon_next": ["Próxima arma","Next weapon"],
	"weapon_previous": ["Arma anterior","Previous weapon"], "unarmed": ["Mãos livres","Unarmed"],
	"fire": ["Atacar / Disparar","Attack / Fire"], "aim": ["Mirar","Aim"],
	"pause_game": ["Pausa","Pause"], "world_map": ["Mapa / GPS","Map / GPS"],
}
const PAD := {"interact":JOY_BUTTON_A,"exit_vehicle":JOY_BUTTON_B,"handbrake":JOY_BUTTON_X,"trunk":JOY_BUTTON_Y,"weapon_next":JOY_BUTTON_RIGHT_SHOULDER,"weapon_previous":JOY_BUTTON_LEFT_SHOULDER,"journal":JOY_BUTTON_BACK,"pause_game":JOY_BUTTON_START,"sprint":JOY_BUTTON_LEFT_STICK,"horn":JOY_BUTTON_RIGHT_STICK,"headlights":JOY_BUTTON_DPAD_UP,"radio_next":JOY_BUTTON_DPAD_RIGHT,"unarmed":JOY_BUTTON_DPAD_DOWN,"reload":JOY_BUTTON_DPAD_LEFT}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_bindings()
	var config := ConfigFile.new()
	if config.load(get_node("/root/SettingsManager")._settings_path) == OK:
		import_bindings(config.get_value("controls","bindings",{}))

func reset_bindings() -> void:
	for action in KEYS:
		if not InputMap.has_action(action): InputMap.add_action(action,0.22)
		InputMap.action_erase_events(action)
		for code in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = code
			InputMap.action_add_event(action,e)
	for pair in [["fire",MOUSE_BUTTON_LEFT],["aim",MOUSE_BUTTON_RIGHT],["weapon_next",MOUSE_BUTTON_WHEEL_UP],["weapon_previous",MOUSE_BUTTON_WHEEL_DOWN]]:
		var e := InputEventMouseButton.new()
		e.button_index = pair[1]
		InputMap.action_add_event(pair[0],e)
	for action in PAD:
		var e := InputEventJoypadButton.new()
		e.button_index = PAD[action]
		InputMap.action_add_event(action,e)
	for entry in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0],["fire",JOY_AXIS_TRIGGER_RIGHT,1.0],["aim",JOY_AXIS_TRIGGER_LEFT,1.0]]:
		var e := InputEventJoypadMotion.new()
		e.axis = entry[1]
		e.axis_value = entry[2]
		InputMap.action_add_event(entry[0],e)
	bindings_changed.emit()

func export_bindings() -> Dictionary:
	var saved := {}
	for action in KEYS:
		saved[action] = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey: saved[action].append({"key":int(e.physical_keycode if e.physical_keycode else e.keycode)})
			elif e is InputEventMouseButton: saved[action].append({"mouse":int(e.button_index)})
	return saved

func import_bindings(saved: Dictionary) -> void:
	for action in saved:
		if not KEYS.has(action) or action == "pause_game": continue
		_clear_keyboard(action)
		for data in saved[action]:
			var e: InputEvent
			if data.has("key"):
				e = InputEventKey.new()
				e.physical_keycode = int(data.key)
			elif data.has("mouse"):
				e = InputEventMouseButton.new()
				e.button_index = int(data.mouse)
			if e != null: InputMap.action_add_event(action,e)
	bindings_changed.emit()

func _clear_keyboard(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton: InputMap.action_erase_event(action,e)

func rebind(action: String,event: InputEvent) -> String:
	if event is InputEventKey and event.keycode in [KEY_ESCAPE,KEY_TAB,KEY_ENTER]:
		return _text("Tecla reservada para os menus.","Key reserved for menus.")
	for other in KEYS:
		if other == action or (other in ["reload","radio_next"] and action in ["reload","radio_next"]): continue
		for existing in InputMap.action_get_events(other):
			if existing.is_match(event): return _text("Já usado: ","Already used: ")+label(other)
	_clear_keyboard(action)
	InputMap.action_add_event(action,event)
	bindings_changed.emit()
	return ""

func label(action: String) -> String:
	if action.begins_with("weapon_slot_"): return _text("Arma rápida ","Quick weapon ")+action.get_slice("_",2)
	var pair: Array = LABELS.get(action,[action,action])
	return _text(pair[0],pair[1])

func hint(action: String,keyboard_only := false) -> String:
	if using_gamepad and not keyboard_only:
		if action == "fire": return "RT"
		if action == "aim": return "LT"
		if action.begins_with("move_"): return _text("Analógico E","Left stick")
		if PAD.has(action): return {0:"A",1:"B",2:"X",3:"Y",4:"View",6:"Menu",7:"L3",8:"R3",9:"LB",10:"RB",11:"↑",12:"↓",13:"←",14:"→"}.get(PAD[action],"Pad")
	var labels: Array[String] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey: labels.append(OS.get_keycode_string(e.physical_keycode if e.physical_keycode else e.keycode))
		elif e is InputEventMouseButton:
			labels.append({1:_text("Mouse E","Mouse L"),2:_text("Mouse D","Mouse R"),4:"↑ Mouse",5:"↓ Mouse"}.get(e.button_index,"Mouse"))
	return " / ".join(labels) if not labels.is_empty() else "—"

func movement() -> Vector2:
	return touch_move if not touch_move.is_zero_approx() else Input.get_vector("move_left","move_right","move_up","move_down")

func aim_target(actor: Node2D) -> Vector2:
	if not touch_aim.is_zero_approx(): return actor.global_position+touch_aim.normalized()*400
	if using_gamepad:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var stick := Vector2(Input.get_joy_axis(pads[0],JOY_AXIS_RIGHT_X),Input.get_joy_axis(pads[0],JOY_AXIS_RIGHT_Y))
			if stick.length()>0.22: aim_direction = stick.normalized()
			elif movement().length()>0.22 and not Input.is_action_pressed("aim"): aim_direction = movement().normalized()
		return actor.global_position+aim_direction*400
	return actor.get_global_mouse_position()

func _input(event: InputEvent) -> void:
	var old := using_gamepad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value)>0.3): using_gamepad = true
	elif event is InputEventKey or (event is InputEventMouseMotion and event.relative.length()>2): using_gamepad = false
	if old != using_gamepad: device_changed.emit()
	if remapping: return

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
