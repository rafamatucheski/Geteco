class_name AmmuNationInterior
extends CanvasLayer

signal exit_requested

var shopper: Node
var active := false
var time := 0.0
var room: Control
var wallet: Label
var notice: Label
var loadout_button: Button

func _ready() -> void:
	layer = 60
	_build()
	hide()

func open_store(player: Node) -> void:
	shopper = player
	active = true
	show()
	if shopper:
		shopper.hide()
		shopper.set_physics_process(false)
	_refresh("BEM-VINDO. ESCOLHA UMA ARMA NA MESA.")

func close_store() -> void:
	active = false
	hide()
	if shopper and is_instance_valid(shopper):
		shopper.show()
		shopper.set_physics_process(true)
	exit_requested.emit()

func _process(delta: float) -> void:
	if not active: return
	time += delta
	room.queue_redraw()
	if Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_ESCAPE):
		close_store()

func _buy(id: String) -> void:
	if shopper and shopper.has_method("buy_weapon"):
		_refresh(shopper.buy_weapon(id))

func _ammo(id: String, rounds: int, price: int) -> void:
	if shopper and shopper.has_method("buy_ammo_amount"):
		_refresh(shopper.buy_ammo_amount(id, rounds, price))

func _refresh(text: String) -> void:
	if wallet and shopper:
		wallet.text = "$ %08d" % int(shopper.get("money"))
	if notice: notice.text = text
	if loadout_button and shopper:
		var quote: Dictionary = shopper.car_loadout_ammo_quote()
		loadout_button.text = "RECARREGAR LOADOUT\nDO CARRO — $%d" % int(quote.price)
		loadout_button.disabled = quote.rounds.is_empty() or shopper.money < int(quote.price)

func _build() -> void:
	room = InteriorArt.new()
	room.owner_interior = self
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(room)
	wallet = Label.new(); wallet.position = Vector2(930, 32); wallet.size = Vector2(300, 44)
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; wallet.add_theme_font_size_override("font_size", 28); wallet.add_theme_color_override("font_color", Color("65f080")); room.add_child(wallet)
	var title := Label.new(); title.text = "AMMU-NATION"; title.position = Vector2(470, 28); title.size = Vector2(340, 44); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color("f4d35e")); room.add_child(title)
	notice = Label.new(); notice.position = Vector2(300, 635); notice.size = Vector2(680, 28); notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; notice.add_theme_font_size_override("font_size", 16); notice.add_theme_color_override("font_color", Color.WHITE); room.add_child(notice)
	_add_button("PISTOLA 9MM\nMUNIÇÃO +24  $40", Vector2(130, 500), func(): _ammo("pistol", 24, 40))
	_add_button("SMG\nCOMPRAR  $1200", Vector2(430, 500), func(): _buy("smg"))
	_add_button("ESCOPETA\nCOMPRAR  $1800", Vector2(730, 500), func(): _buy("shotgun"))
	_add_button("[E] SAIR DA LOJA", Vector2(1010, 570), close_store)
	loadout_button = Button.new()
	loadout_button.position = Vector2(1010, 480)
	loadout_button.size = Vector2(230, 76)
	loadout_button.pressed.connect(func():
		if active and is_instance_valid(shopper): _refresh(shopper.buy_car_loadout_ammo()))
	room.add_child(loadout_button)

func _add_button(text: String, pos: Vector2, action: Callable) -> void:
	var button := Button.new(); button.text = text; button.position = pos; button.size = Vector2(190, 76); button.add_theme_font_size_override("font_size", 15); button.pressed.connect(action); room.add_child(button)

class InteriorArt:
	extends Control
	var owner_interior: AmmuNationInterior
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("182026"))
		draw_rect(Rect2(80, 90, size.x - 160, size.y - 170), Color("354049"))
		for x in range(100, int(size.x - 80), 64): draw_line(Vector2(x,90), Vector2(x,size.y-80), Color(0.18,0.22,0.25), 1)
		for y in range(90, int(size.y - 80), 64): draw_line(Vector2(80,y), Vector2(size.x-80,y), Color(0.18,0.22,0.25), 1)
		draw_rect(Rect2(80,90,size.x-160,70), Color("68201d"))
		draw_string(ThemeDB.fallback_font, Vector2(105,135), "MUNIÇÕES • PROTEÇÃO • SOBREVIVÊNCIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffe36b"))
		for i in range(3):
			var p := Vector2(225 + i * 300, 330)
			draw_circle(p, 98, Color("251b14")); draw_arc(p,98,0,TAU,32,Color("d8ad55"),4)
			var a := owner_interior.time * (1.2 + i * 0.18)
			var gun := PackedVector2Array([p+Vector2(-45, -10).rotated(a),p+Vector2(52,-10).rotated(a),p+Vector2(60,0).rotated(a),p+Vector2(0,5).rotated(a),p+Vector2(-8,35).rotated(a),p+Vector2(-20,5).rotated(a),p+Vector2(-45,5).rotated(a)])
			draw_colored_polygon(gun, [Color("aab6c2"),Color("78dcff"),Color("ff9b63")][i])
		# vendedor atrás do balcão
		draw_rect(Rect2(1010,235,160,170),Color("512c21")); draw_circle(Vector2(1090,245),22,Color("b87b5b")); draw_rect(Rect2(1065,267,50,92),Color("273b58")); draw_string(ThemeDB.fallback_font,Vector2(1035,390),"VENDEDOR",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
