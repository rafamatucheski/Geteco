extends Control
const STYLE := preload("res://ui/GameStyle.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")
const ENTRY := preload("res://systems/inventory/ui/GridEntry.gd")
signal selected(container: String,index: int)
var adapter
var container_id := "storage"
var columns := 4
var rows := 3
var cell := 64.0
var entries: Array = []
var selection:=-1
var hover_cell:=Vector2i(-1,-1)
var hover_size:=Vector2i.ONE
var hover_valid:=false

func configure(owner_adapter, container: String, data: Dictionary, cell_size := 64.0) -> void:
	adapter=owner_adapter; container_id=container; cell=cell_size
	var bounds := GRID.dimensions(data,container)
	columns=bounds.x; rows=bounds.y
	entries=data[container]
	mouse_exited.connect(func(): hover_cell=Vector2i(-1,-1); queue_redraw())
	custom_minimum_size=Vector2(columns*cell,rows*cell)
	size=custom_minimum_size
	for child in get_children(): remove_child(child); child.queue_free()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var definition := GRID.spec(str(entry.id))
		var button := ENTRY.new()
		button.board=self; button.index=i
		button.position=Vector2(float(entry.x),float(entry.y))*cell+Vector2.ONE*3
		button.size=Vector2(GRID.extent(entry))*cell-Vector2.ONE*6
		button.item_texture=ICONS.get_icon(str(definition.get("icon","quest")))
		button.tooltip_text=str(definition.label)
		button.add_theme_stylebox_override("normal",_item_style(false))
		button.add_theme_stylebox_override("hover",_item_style(true))
		button.pressed.connect(func(): selected.emit(container_id,i))
		button.focus_entered.connect(func(): selected.emit(container_id,i))
		button.add_theme_stylebox_override("focus",_item_style(true))
		add_child(button)
		var art:=TextureRect.new(); art.texture=button.item_texture
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position=Vector2(7,7); art.size=button.size-Vector2(14,19); art.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(art)
		var amount := Label.new()
		amount.text=str(entry.amount) if int(entry.amount)>1 else ""
		amount.position=Vector2(button.size.x-28,1); amount.add_theme_font_size_override("font_size",12)
		amount.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(amount)
		if definition.get("quest",false):
			var tag := Label.new(); tag.text="◇"; tag.modulate=STYLE.WAYPOINT; tag.position=Vector2(5,button.size.y-18)
			tag.add_theme_font_size_override("font_size",10); tag.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(tag)
	queue_redraw()

func _draw() -> void:
	for y in rows:
		for x in columns:
			var rect := Rect2(Vector2(x,y)*cell+Vector2.ONE*2,Vector2.ONE*(cell-4))
			draw_style_box(_item_style(false),rect)
	if hover_cell.x>=0:
		var rect:=Rect2(Vector2(hover_cell)*cell+Vector2.ONE*2,Vector2(hover_size)*cell-Vector2.ONE*4)
		draw_rect(rect,Color(.35,.68,.48,.4) if hover_valid else Color(.85,.35,.25,.4))

func _item_style(active: bool) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=STYLE.SURFACE.lightened(.04) if active else STYLE.SURFACE
	style.border_color=STYLE.ACCENT if active else STYLE.LINE
	style.set_border_width_all(1); style.set_corner_radius_all(8)
	return style

func mark_selected(index: int) -> void:
	selection=index
	for child in get_children():
		if child is Button: child.add_theme_stylebox_override("normal",_item_style(child.index==index))

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("owner")!=adapter: return false
	if not adapter.can_edit(container_id) or not adapter.can_edit(str(data.container)): return false
	var snapshot: Dictionary = adapter.economy().grid_snapshot()
	var source: String = data.container
	var index := int(data.index)
	if index<0 or index>=snapshot[source].size(): return false
	var entry: Dictionary=snapshot[source][index]
	hover_cell=Vector2i(at/cell); hover_size=GRID.extent(entry)
	hover_valid=GRID.accepts(container_id,str(entry.id)) and GRID.fits(entries,Vector2i(columns,rows),entry,hover_cell,index if source==container_id else -1)
	if container_id=="trunk" and str(entry.id).begins_with("ammo:") and GRID.ammo_slots(entries,index if source==container_id else -1)>=GRID.TRUNK_AMMO_SLOTS: hover_valid=false
	queue_redraw(); return hover_valid

func _drop_data(at: Vector2, data: Variant) -> void:
	hover_cell=Vector2i(-1,-1); queue_redraw()
	adapter.move(str(data.container),int(data.index),container_id,Vector2i(at/cell))
