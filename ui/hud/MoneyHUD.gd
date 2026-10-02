extends VBoxContainer
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPH := preload("res://ui/hud/HUDGlyph.gd")
var amount: Label
var change: Label
var _balance := -1
var _tween: Tween
func _ready() -> void:
	name="MoneyHUD"; mouse_filter=MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new(); panel.size_flags_horizontal=SIZE_SHRINK_END; panel.add_theme_stylebox_override("panel",STYLE.compact(true,10)); add_child(panel)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",8); panel.add_child(row)
	row.add_child(GLYPH.new("money",STYLE.MONEY))
	amount=STYLE.label("",20,STYLE.MONEY); row.add_child(amount)
	change=STYLE.label("",15,STYLE.MONEY); change.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; add_child(change); change.hide()
func update_balance(balance: int, infinite: bool = false) -> void:
	if infinite:
		amount.text="$ ∞"
		if _tween: _tween.kill()
		change.hide()
		_balance = -1
		return
	amount.text="$ "+STYLE.amount(balance)
	if _balance>=0 and _balance!=balance:
		change.text=("+ $ " if balance>_balance else "− $ ")+STYLE.amount(absi(balance-_balance))
		if _tween: _tween.kill()
		change.show(); change.modulate.a=0
		_tween=create_tween(); _tween.tween_property(change,"modulate:a",1.0,STYLE.FADE); _tween.tween_interval(1.5)
		_tween.tween_property(change,"modulate:a",0.0,STYLE.FADE); _tween.tween_callback(change.hide)
	_balance=balance
