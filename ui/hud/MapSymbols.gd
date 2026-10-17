extends RefCounted
## Small, cached vector pictograms. No font-dependent emoji or external service.
const LABELS := {"player":"Jogador","objective":"Missão","waypoint":"Destino","workshop":"Oficina","fuel":"Posto","bank":"Banco","hospital":"Hospital","police":"Polícia","fire":"Bombeiros","shop":"Mercado","clothing":"Roupas","weapons":"Armas","port":"Porto","home":"Casa / chalé","ski":"Esqui","lift":"Teleférico","cave":"Caverna","plane":"Avião","forge":"Forja","fishing":"Pesca","race":"Corrida","jeep":"Jipe","mine":"Mineração","bus":"Ônibus","train":"Estações de trem","food":"Restaurante","lock":"Passagem fechada","sewer":"Bueiro","place":"Local"}
const PATHS := {
	"fishing":'<path d="M3 21 11 3l8 1v10a4 4 0 0 1-8 0v-2l3 2M12 3l-1 9"/><path d="m4 6 2 3-2 3-3-3Z"/>',
	"train":'<rect x="5" y="2" width="14" height="16" rx="3"/><path d="M5 7h14M5 12h14M9 3v8M15 3v8M8 18l-4 5M16 18l4 5M6 21h12"/><circle cx="9" cy="15" r="1"/><circle cx="15" cy="15" r="1"/>',
	"fire":'<path d="M13 1c5 6-2 7 4 12l3-4c6 16-24 17-16 1l3 4c4-4-2-6 6-13Z"/>',
	"shop":'<path d="M2 9h20l-3 12H5ZM7 9l4-7M17 9l-4-7M8 13v4M12 13v4M16 13v4"/>',
	"player":'<path d="M12 2 21 21 12 17 3 21Z"/>',
	"objective":'<path d="m12 2 10 10-10 10L2 12Z"/>',
	"waypoint":'<path d="M18 9c0 5-6 12-6 12S6 14 6 9a6 6 0 1 1 12 0Z"/><circle cx="12" cy="9" r="2"/>',
	"workshop":'<path d="M21 3 16 8l-3-3 5-4a7 7 0 0 0-8 9L2 18a3 3 0 0 0 4 4l8-9a7 7 0 0 0 7-10Z"/>',
	"fuel":'<path d="M3 22V3h11v19M2 22h14M5 6h7v6H5zM14 10h3v9a2 2 0 0 0 4 0V8l-4-5M18 5v5h3"/>',
	"bank":'<path d="M2 8 12 2l10 6ZM3 21h18M4 18h16M6 9v9M12 9v9M18 9v9"/>',
	"hospital":'<path d="M9 2h6v7h7v6h-7v7H9v-7H2V9h7Z"/>',
	"police":'<path d="m12 2 8 3v7c0 5-8 10-8 10S4 17 4 12V5ZM12 6l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1Z"/>',
	"clothing":'<path d="m8 3-6 3-1 6 5 1v9h12v-9l5-1-1-6-6-3c0 5-8 5-8 0Z"/>',
	"weapons":'<path d="M2 5h20v6H10l-3 10H2l4-11H2ZM10 11v4h6l2-4"/>',
	"port":'<circle cx="12" cy="5" r="3"/><path d="M12 8v14M7 12h10M2 15c0 9 20 9 20 0M2 15l-1 5M22 15l1 5"/>',
	"home":'<path d="m2 11 10-9 10 9M5 9v13h14V9M10 22v-8h4v8"/>',
	"ski":'<circle cx="15" cy="3" r="2"/><path d="m12 7-4 6 6 3-4 5M12 7l4 5h6M18 10l-1 12M2 20l14 3 5-2M8 8 3 17"/>',
	"lift":'<path d="m1 4 22-3M12 3v6M4 11h16v11H4ZM4 16h16M9 11v5M15 11v5"/>',
	"cave":'<path d="M2 22 5 9l7-7 7 7 3 13h-6v-8l-4-4-4 4v8Z"/>',
	"plane":'<path d="m12 1 2 8 9 6v3l-9-3v5l3 2H7l3-2v-5l-9 3v-3 0l9-6Z"/>',
	"forge":'<path d="M2 8h15c0 3 2 4 5 4-3 1-5 2-6 4H9c-1-2-3-3-4-4M8 16l-2 6h12l-2-6"/><path d="M14 2l-3 4M18 3l-2 3"/>',
	"race":'<path d="M3 23V2h18v13H3M3 6h18M3 11h18M8 2v13M15 2v13"/><path d="M3 2h5v4H3zM8 6h7v5H8zM15 2h6v4h-6zM15 11h6v4h-6z" fill="white"/>',
	"jeep":'<path d="m3 9 3-6h12l3 6v10H3ZM3 11h18M8 4v7M16 4v7M5 19v3M19 19v3"/><circle cx="7" cy="15" r="1"/><circle cx="17" cy="15" r="1"/>',
	"mine":'<path d="m3 2 18 20M21 2 3 22M1 7c5-7 9-6 12-5M11 2c5-1 9 1 12 5"/>',
	"bus":'<rect x="4" y="2" width="16" height="18" rx="3"/><path d="M4 6h16M4 13h16M6 20v3M18 20v3M12 6v7"/><circle cx="8" cy="16" r="1"/><circle cx="16" cy="16" r="1"/>',
	"food":'<path d="M5 1v9M1 1v6c0 5 8 5 8 0V1M5 11v12M20 1c-8 4-7 11-3 11h3M20 1v22"/>',
	"lock":'<rect x="4" y="10" width="16" height="12" rx="2"/><path d="M7 10V6a5 5 0 0 1 10 0v4M12 15v3"/>',
	"sewer":'<circle cx="12" cy="12" r="9"/><path d="M5.5 9h13M4 12h16M5.5 15h13M9 4.5v15M15 4.5v15"/>',
	"place":'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2"/>'
}
static var _textures := {}

static func texture(kind: String) -> Texture2D:
	if not PATHS.has(kind): kind="place"
	if not _textures.has(kind):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="-2 -2 28 28"><g fill="none" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+str(PATHS[kind])+'</g></svg>'
		var image := Image.new()
		if image.load_svg_from_string(svg)!=OK: return null
		_textures[kind]=ImageTexture.create_from_image(image)
	return _textures[kind]

static func tint(kind: String) -> Color:
	if kind=="player": return Color("64d5ef")
	if kind in ["objective","waypoint","lock"]: return Color("edc45a")
	if kind=="hospital": return Color("f27e79")
	if kind in ["race","jeep","ski","mine"]: return Color("dec590")
	if kind=="sewer": return Color("9fc9a8")
	if kind=="forge": return Color("f0a35a")
	return Color("e4e9e7")

static func draw(canvas: CanvasItem, point: Vector2, kind: String, radius := 14.0, selected := false) -> void:
	canvas.draw_circle(point+Vector2(0,2),radius+2,Color(0,0,0,.3),true,-1,true)
	canvas.draw_circle(point,radius,Color("112833"),true,-1,true)
	canvas.draw_circle(point,radius,Color("edc45a") if selected else Color("9aaeb4"),false,2.0 if selected else 1.0,true)
	canvas.draw_texture_rect(texture(kind),Rect2(point-Vector2.ONE*radius*.75,Vector2.ONE*radius*1.5),false,tint(kind))

