extends Node
## Ações de jogo independentes dos atalhos de navegação dos menus.
signal bindings_changed
signal device_changed
signal controller_connection_changed(device: int, connected: bool, controller_name: String)
var using_gamepad := false
var active_joypad := -1
var sprint_toggled := false
var aim_direction := Vector2.RIGHT
var _last_aim_physics_frame := -1
var remapping := false
var touch_move := Vector2.ZERO
var touch_aim := Vector2.ZERO
const AIM_STICK_DEADZONE := 0.20
const AIM_TURN_SPEED_MIN := 1.20
const AIM_TURN_SPEED_MAX := 5.50
const AIM_RESPONSE_CURVE := 1.65
const KEYS := {
	"camera_left": [KEY_Z], "camera_right": [KEY_C], "inventory": [KEY_TAB], "weapon_flashlight": [KEY_G],
	"move_up": [KEY_W,KEY_UP], "move_down": [KEY_S,KEY_DOWN],
	"move_left": [KEY_A,KEY_LEFT], "move_right": [KEY_D,KEY_RIGHT],
	"sprint": [KEY_SHIFT], "interact": [KEY_E], "vehicle_interact": [KEY_F], "exit_vehicle": [KEY_F,KEY_ENTER],
	"handbrake": [KEY_SPACE], "horn": [KEY_H], "headlights": [KEY_L],
	"radio_next": [KEY_R], "radio_previous": [], "reload": [KEY_R], "journal": [KEY_J], "trunk": [KEY_T],
	"weapon_next": [KEY_Q], "weapon_previous": [], "unarmed": [KEY_X],
	"fire": [], "aim": [], "accelerate": [], "brake": [], "pause_game": [KEY_ESCAPE], "world_map": [KEY_M],
	"siren_toggle": [],
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
	"weapon_flashlight": ["Lanterna da arma", "Weapon flashlight"],
	"move_up": ["Avançar / Acelerar","Move forward / Accelerate"],
	"move_down": ["Recuar / Ré","Move backward / Reverse"],
	"move_left": ["Esquerda","Left"], "move_right": ["Direita","Right"],
	"sprint": ["Correr","Sprint"], "interact": ["Ação","Action"],
	"vehicle_interact": ["Entrar / Roubar veículo","Enter / Steal vehicle"],
	"exit_vehicle": ["Sair do veículo","Exit vehicle"], "handbrake": ["Freio de mão","Handbrake"],
	"horn": ["Buzina","Horn"], "headlights": ["Faróis","Headlights"],
	"reload": ["Recarregar","Reload"], "radio_next": ["Próxima rádio","Next radio"],
	"radio_previous": ["Rádio anterior","Previous radio"], "journal": ["Diário","Journal"],
	"trunk": ["Porta-malas","Trunk"], "weapon_next": ["Próxima arma","Next weapon"],
	"weapon_previous": ["Arma anterior","Previous weapon"], "unarmed": ["Mãos livres","Unarmed"],
	"fire": ["Atacar / Disparar","Attack / Fire"], "aim": ["Mirar","Aim"],
	"accelerate": ["Acelerar", "Accelerate"], "brake": ["Frear / Ré", "Brake / Reverse"],
	"pause_game": ["Pausa","Pause"], "world_map": ["Mapa / GPS","Map / GPS"],
	"siren_toggle": ["Sirene", "Siren"],
}
const PAD := {
	"interact": JOY_BUTTON_X, "vehicle_interact": JOY_BUTTON_Y,
	"exit_vehicle": JOY_BUTTON_Y, "handbrake": JOY_BUTTON_A,
	"trunk": JOY_BUTTON_DPAD_DOWN,
	"weapon_next": JOY_BUTTON_RIGHT_SHOULDER, "weapon_previous": JOY_BUTTON_LEFT_SHOULDER,
	"journal": JOY_BUTTON_BACK, "pause_game": JOY_BUTTON_START,
	"sprint": JOY_BUTTON_LEFT_STICK, "horn": JOY_BUTTON_RIGHT_STICK,
	"siren_toggle": JOY_BUTTON_RIGHT_STICK,
	"headlights": JOY_BUTTON_DPAD_UP,
	"radio_next": JOY_BUTTON_RIGHT_SHOULDER, "radio_previous": JOY_BUTTON_LEFT_SHOULDER,
	"unarmed": JOY_BUTTON_DPAD_DOWN, "reload": JOY_BUTTON_X,
	"weapon_flashlight": JOY_BUTTON_MISC1, "world_map": JOY_BUTTON_TOUCHPAD,
}
const UI_PAD := {
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B,
	"ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN,
	"ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT,
}
## Only pairs whose consumers are mutually exclusive may intentionally share a binding.
## Keep this list narrow: `interact` and `vehicle_interact` can both be live on foot.
const CONTEXTUAL_BINDING_PAIRS := [
	["vehicle_interact", "exit_vehicle"],
	["reload", "radio_next"],
	["weapon_next", "radio_next"],
	["weapon_previous", "radio_previous"],
	["fire", "accelerate"],
	["aim", "brake"],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty(): active_joypad = connected[0]
	reset_bindings()
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
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
	for entry in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0],["fire",JOY_AXIS_TRIGGER_RIGHT,1.0],["aim",JOY_AXIS_TRIGGER_LEFT,1.0],["accelerate",JOY_AXIS_TRIGGER_RIGHT,1.0],["brake",JOY_AXIS_TRIGGER_LEFT,1.0]]:
		var e := InputEventJoypadMotion.new()
		e.axis = entry[1]
		e.axis_value = entry[2]
		InputMap.action_add_event(entry[0],e)
	_ensure_menu_bindings()
	bindings_changed.emit()

func _ensure_menu_bindings() -> void:
	for action in UI_PAD:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.22)
		_add_unique_pad_button(action, UI_PAD[action])
	for entry in [["ui_left",JOY_AXIS_LEFT_X,-1.0],["ui_right",JOY_AXIS_LEFT_X,1.0],["ui_up",JOY_AXIS_LEFT_Y,-1.0],["ui_down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = entry[1]
		event.axis_value = entry[2]
		_add_unique_event(entry[0], event)

func _add_unique_pad_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	_add_unique_event(action, event)

func _add_unique_event(action: StringName, event: InputEvent) -> void:
	for existing in InputMap.action_get_events(action):
		if existing.is_match(event): return
	InputMap.action_add_event(action, event)

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
		if other == action or _binding_context_is_exclusive(action,other): continue
		for existing in InputMap.action_get_events(other):
			if existing.is_match(event): return _text("Já usado: ","Already used: ")+label(other)
	_clear_keyboard(action)
	InputMap.action_add_event(action,event)
	bindings_changed.emit()
	return ""

func _binding_context_is_exclusive(first: String,second: String) -> bool:
	for pair in CONTEXTUAL_BINDING_PAIRS:
		if (pair[0] == first and pair[1] == second) or (pair[0] == second and pair[1] == first):
			return true
	return false

func label(action: String) -> String:
	if action.begins_with("weapon_slot_"): return _text("Arma rápida ","Quick weapon ")+action.get_slice("_",2)
	var pair: Array = LABELS.get(action,[action,action])
	return _text(pair[0],pair[1])

func hint(action: String,keyboard_only := false) -> String:
	if using_gamepad and not keyboard_only:
		var playstation := is_playstation_controller()
		if action in ["fire","accelerate"]: return "R2" if playstation else "RT"
		if action in ["aim","brake"]: return "L2" if playstation else "LT"
		if action.begins_with("move_"): return _text("Analógico E","Left stick")
		var button: int = int(PAD.get(action, UI_PAD.get(action, -1)))
		if button >= 0: return _pad_button_hint(button, playstation)
	var labels: Array[String] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey: labels.append(OS.get_keycode_string(e.physical_keycode if e.physical_keycode else e.keycode))
		elif e is InputEventMouseButton:
			labels.append({1:_text("Mouse E","Mouse L"),2:_text("Mouse D","Mouse R"),4:"↑ Mouse",5:"↓ Mouse"}.get(e.button_index,"Mouse"))
	return " / ".join(labels) if not labels.is_empty() else "—"

func movement() -> Vector2:
	return touch_move if not touch_move.is_zero_approx() else Input.get_vector("move_left","move_right","move_up","move_down")

func vehicle_input() -> Vector2:
	var move := movement()
	if not using_gamepad: return Vector2(move.x,-move.y)
	return Vector2(Input.get_axis("move_left","move_right"),Input.get_action_strength("accelerate")-Input.get_action_strength("brake"))

func sprinting() -> bool:
	return sprint_toggled if using_gamepad else Input.is_action_pressed("sprint")

func reset_sprint_toggle() -> void:
	sprint_toggled = false

func aim_target(actor: Node2D) -> Vector2:
	if not touch_aim.is_zero_approx(): return actor.global_position+touch_aim.normalized()*400
	if using_gamepad:
		var device := _resolve_joypad()
		var physics_frame := Engine.get_physics_frames()
		if device >= 0 and physics_frame != _last_aim_physics_frame:
			_last_aim_physics_frame = physics_frame
			var stick := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
			if not _update_gamepad_aim(stick,get_physics_process_delta_time()):
				var move := movement()
				if move.length()>AIM_STICK_DEADZONE and not Input.is_action_pressed("aim"): aim_direction = move.normalized()
		return actor.global_position+aim_direction*400
	return actor.get_global_mouse_position()

func aim_target_3d(actor: Node3D, camera: Camera3D, delta: float) -> Vector3:
	var direction := touch_aim
	if direction.is_zero_approx():
		var device := _resolve_joypad()
		if device >= 0:
			var stick := Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
			if not _update_gamepad_aim(stick,delta) and not Input.is_action_pressed("aim"):
				var move := movement()
				if move.length() > AIM_STICK_DEADZONE: aim_direction = move.normalized()
		direction = aim_direction
	var right := camera.global_basis.x
	var down := camera.global_basis.z
	right.y = 0
	down.y = 0
	return actor.global_position+(right.normalized()*direction.x+down.normalized()*direction.y).normalized()*25

func _update_gamepad_aim(stick: Vector2,delta: float) -> bool:
	var strength := minf(stick.length(),1.0)
	if strength <= AIM_STICK_DEADZONE: return false
	var normalized_strength := (strength-AIM_STICK_DEADZONE)/(1.0-AIM_STICK_DEADZONE)
	var response := pow(normalized_strength,AIM_RESPONSE_CURVE)
	var turn_speed := lerpf(AIM_TURN_SPEED_MIN,AIM_TURN_SPEED_MAX,response)
	var target := stick.normalized()
	var angle := aim_direction.angle_to(target)
	var turn := minf(absf(angle),turn_speed*maxf(delta,0.0))
	if turn > 0.0: aim_direction = aim_direction.rotated(signf(angle)*turn).normalized()
	return true

func _input(event: InputEvent) -> void:
	var old := using_gamepad
	var old_joypad := active_joypad
	if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value)>0.3):
		using_gamepad = true
		active_joypad = event.device
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventMouseMotion and event.relative.length()>2):
		using_gamepad = false
	if old != using_gamepad or old_joypad != active_joypad: device_changed.emit()
	if remapping: return
	if event is InputEventJoypadButton and event.pressed and event.button_index == PAD.sprint and not get_tree().paused:
		var player := get_tree().get_first_node_in_group("player")
		if player == null or player.visible: sprint_toggled = not sprint_toggled

func is_playstation_controller(device := -1) -> bool:
	device = _resolve_joypad(device)
	if device < 0: return false
	var name := Input.get_joy_name(device).to_lower()
	return "dualsense" in name or "dualshock" in name or "playstation" in name or "wireless controller" in name

func controller_name(device := -1) -> String:
	device = _resolve_joypad(device)
	return Input.get_joy_name(device) if device >= 0 else ""

func rumble(weak := 0.35,strong := 0.65,duration := 0.18,device := -1) -> bool:
	device = _resolve_joypad(device)
	if device < 0 or not Input.has_joy_vibration(device): return false
	Input.start_joy_vibration(device,clampf(weak,0.0,1.0),clampf(strong,0.0,1.0),maxf(duration,0.01))
	return true

func stop_rumble(device := -1) -> void:
	device = _resolve_joypad(device)
	if device >= 0: Input.stop_joy_vibration(device)

func _resolve_joypad(device := -1) -> int:
	if device >= 0 and device in Input.get_connected_joypads(): return device
	if active_joypad in Input.get_connected_joypads(): return active_joypad
	var connected := Input.get_connected_joypads()
	return connected[0] if not connected.is_empty() else -1

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var old_joypad := active_joypad
	if connected and active_joypad < 0: active_joypad = device
	elif not connected and active_joypad == device: active_joypad = _resolve_joypad()
	controller_connection_changed.emit(device,connected,Input.get_joy_name(device) if connected else "")
	if old_joypad != active_joypad: device_changed.emit()

func _pad_button_hint(button: int, playstation: bool) -> String:
	if playstation:
		return {0:"✕",1:"○",2:"□",3:"△",4:"Create",5:"PS",6:"Options",7:"L3",8:"R3",9:"L1",10:"R1",11:"↑",12:"↓",13:"←",14:"→",15:"Mic",20:"Touchpad"}.get(button,"Controle")
	return {0:"A",1:"B",2:"X",3:"Y",4:"View",5:"Guide",6:"Menu",7:"L3",8:"R3",9:"LB",10:"RB",11:"↑",12:"↓",13:"←",14:"→",15:"Share",20:"Touchpad"}.get(button,"Pad")

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
