extends Control
## Functional race instruments; no world-decoration captions.
var rpm := 900.0
var redline := 7000.0
var shift_rpm := 6000.0
var speed := 0.0
var gear := 1
var nitro := 0.0
var remaining := 0.0
var seconds := 0.0
var gap := 0.0
var headline := ""
var rival := ""
var feedback := ""
var clock := 0.0
var rival_offscreen := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_state(drive, distance_left: float, elapsed: float, lead: float, text: String, rival_name: String) -> void:
	rpm = drive.rpm
	redline = drive.redline
	shift_rpm = drive.ideal_shift_rpm
	speed = drive.speed_mps*3.6
	gear = drive.gear
	nitro = drive.nitro
	remaining = distance_left
	seconds = elapsed
	gap = lead
	headline = text
	rival = rival_name
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var center := Vector2(size.x*.5, size.y-115)
	draw_style_box(_panel(), Rect2(Vector2(center.x-245,size.y-225),Vector2(490,210)))
	var dial := center+Vector2(-110,18)
	draw_arc(dial, 77, -PI*1.18, PI*.18, 54, Color("657079"), 8, true)
	var start := -PI*1.18
	var sweep := PI*1.36
	var staging := not headline.is_empty() and headline.is_valid_int()
	var good_start := start+sweep*(.43 if staging else clampf((shift_rpm-350)/redline,0,1))
	var good_end := start+sweep*(.64 if staging else clampf((shift_rpm+180)/redline,0,1))
	draw_arc(dial,77,good_start,good_end,12,Color("85e6b4"),10,true)
	draw_arc(dial,77,start+sweep*.96,start+sweep,8,Color("ed745b"),10,true)
	for mark in range(0, int(ceil(redline/1000))+1):
		var angle := start+sweep*float(mark)*1000/redline
		if angle > start+sweep: break
		var unit := Vector2(cos(angle),sin(angle))
		draw_line(dial+unit*60,dial+unit*68,Color("d4d9da"),2,true)
		draw_string(font,dial+unit*49+Vector2(-4,4),str(mark),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d4d9da"))
	var needle_angle := start+sweep*clampf(rpm/redline,0,1.03)
	draw_line(dial,dial+Vector2(cos(needle_angle),sin(needle_angle))*64,Color("ffb560"),3,true)
	draw_circle(dial,5,Color("ffb560"))
	draw_string(font,dial+Vector2(-32,38),"RPM × 1000",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("aeb7bb"))
	draw_string(font,center+Vector2(0,4),"%03d"%roundi(speed),HORIZONTAL_ALIGNMENT_LEFT,-1,48,Color.WHITE)
	draw_string(font,center+Vector2(5,27),"km/h",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("aeb7bb"))
	draw_string(font,center+Vector2(134,4),str(gear),HORIZONTAL_ALIGNMENT_LEFT,-1,48,Color("ffb560"))
	draw_string(font,center+Vector2(126,27),"MARCHA",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("aeb7bb"))
	draw_rect(Rect2(center+Vector2(-202,68),Vector2(402,5)),Color("384149"))
	draw_rect(Rect2(center+Vector2(-202,68),Vector2(402*nitro,5)),Color("65d5f4"))
	var info := "%04.1f s    %d m    %+.1f m"%[seconds,ceili(maxf(0,remaining)),gap]
	draw_string(font,Vector2(center.x-190,size.y-194),info,HORIZONTAL_ALIGNMENT_CENTER,380,18,Color.WHITE)
	draw_string(font,Vector2(size.x*.5-300,38),"DANTE  ×  "+rival.to_upper(),HORIZONTAL_ALIGNMENT_CENTER,600,21,Color.WHITE)
	if rival_offscreen!=0:
		var at := Vector2(20 if rival_offscreen<0 else size.x-260,size.y*.44)
		draw_style_box(_panel(),Rect2(at,Vector2(240,42)))
		var label := "%s  %s · %d m"%["←" if rival_offscreen<0 else "→",rival,roundi(absf(gap))]
		draw_string(font,at+Vector2(12,28),label,HORIZONTAL_ALIGNMENT_LEFT,216,20,Color("ffcf87"))
	draw_string(font,Vector2(size.x*.5-300,90),headline,HORIZONTAL_ALIGNMENT_CENTER,600,32,Color("ffcf87"))
	draw_string(font,Vector2(size.x*.5-360,size.y-242),feedback,HORIZONTAL_ALIGNMENT_CENTER,720,20,Color("85e6b4"))
	draw_string(font,Vector2(25,size.y-25),"W / ↑ acelerar   Espaço / RB marcha   Shift / A nitro   Q / B abandonar",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("d4d9da"))

func _panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(.035,.045,.055,.92)
	box.corner_radius_top_left = 12
	box.corner_radius_top_right = 12
	box.corner_radius_bottom_left = 12
	box.corner_radius_bottom_right = 12
	return box
