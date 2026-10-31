extends RefCounted
## Pictogramas pequenos compartilhados: matrizes vetoriais suaves, rasterizadas uma vez em 4x.
## Mipmaps preservam detalhes finos quando a UI é escalada; sem viewports vivas.
const PATHS := {
	"heart": '<path d="M12 21S2.5 15 2.5 8.5C2.5 5.5 4.7 3.5 7.4 3.5 9.3 3.5 11 4.5 12 6.1 13 4.5 14.7 3.5 16.6 3.5 19.3 3.5 21.5 5.5 21.5 8.5 21.5 15 12 21 12 21Z"/>',
	"shield": '<path d="M12 2 21 5v6c0 5.1-4.4 8.7-9 11-4.6-2.3-9-5.9-9-11V5Z"/>',
	"rage": '<path d="M13.7 1.8 4.2 13.3h6.2L8.8 22.2 20.1 8.7h-6.5Z"/>',
	"cold": '<g fill="none" stroke="white" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20M3.34 7l17.32 10M3.34 17 20.66 7M9 4.5 12 7l3-2.5M9 19.5l3-2.5 3 2.5M4 10.5l3.67-1.75L7 5M17 19l-.67-3.75L20 13.5M4 13.5l3.67 1.75L7 19M17 5l-.67 3.75L20 10.5"/></g>',
	"bag": '<g fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="6.5" width="15" height="15.5" rx="3"/><path d="M8.5 6.5V5a3.5 3.5 0 0 1 7 0v1.5M8 7v3M16 7v3"/><rect x="7.5" y="13" width="9" height="6" rx="1.5"/></g>',
	"money": '<g transform="rotate(-10 12 12)" fill="none" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="5.5" width="19" height="13" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 11v2M18 11v2"/></g>',
	"shirt": '<path d="m7.2 3.2-5.7 4.4 3.4 4.5 2.3-1.8V21h9.6V10.3l2.3 1.8 3.4-4.5-5.7-4.4c-1 3.4-8.6 3.4-9.6 0Z"/>',
	"health_cross": '<path d="M9 2h6v7h7v6h-7v7H9v-7H2V9h7Z"/>',
	"shield_outline": '<path d="M12 2 21 5v6c0 5.1-4.4 8.7-9 11-4.6-2.3-9-5.9-9-11V5Z" fill="none" stroke="white" stroke-width="1.8" stroke-linejoin="round"/>',
	"player": '<path d="M22 12 6 6l3 6-3 6Z"/>',
	"diamond": '<path d="m12 2 10 10-10 10L2 12Z"/>',
	"weather_sun": '<g fill="none" stroke="#d9e3e5" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42"/></g>',
	"weather_moon": '<path d="M15.9 2.6A9.9 9.9 0 1 0 21.4 18 9.5 9.5 0 0 1 15.9 2.6Z" fill="#d9e3e5"/>',
	"weather_cloud": '<path d="M6.5 18a5 5 0 0 1-.8-9.9 6.5 6.5 0 0 1 12.4-.4A5.2 5.2 0 0 1 18.5 18Z" fill="#d9e3e5"/>',
	"weather_rain": '<path d="M5.5 14.5a4.1 4.1 0 0 1-.6-8.1A5.8 5.8 0 0 1 16 6a4.3 4.3 0 0 1 .5 8.5Z" fill="#d9e3e5"/><path d="m7 18-1.5 3M13 18l-1.5 3M19 18l-1.5 3" fill="none" stroke="#9dc8da" stroke-width="1.7" stroke-linecap="round"/>',
	"weather_storm": '<path d="M5.5 14.5a4.1 4.1 0 0 1-.6-8.1A5.8 5.8 0 0 1 16 6a4.3 4.3 0 0 1 .5 8.5Z" fill="#d9e3e5"/><path d="m13.5 16-3 3h3l-3 3" fill="none" stroke="#e5cf8e" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
	"weather_hail": '<path d="M5.5 14.5a4.1 4.1 0 0 1-.6-8.1A5.8 5.8 0 0 1 16 6a4.3 4.3 0 0 1 .5 8.5Z" fill="#d9e3e5"/><g fill="#d9e3e5"><circle cx="6.5" cy="19.5" r="1.4"/><circle cx="12.5" cy="19.5" r="1.4"/><circle cx="18.5" cy="19.5" r="1.4"/></g>',
	"weather_snow": '<g fill="none" stroke="#d9e3e5" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20M3.34 7l17.32 10M3.34 17 20.66 7M9 4.5 12 7l3-2.5M9 19.5l3-2.5 3 2.5M4 10.5l3.67-1.75L7 5M17 19l-.67-3.75L20 13.5M4 13.5l3.67 1.75L7 19M17 5l-.67 3.75L20 10.5"/></g>',
	"weather_wind": '<g fill="none" stroke="#d9e3e5" stroke-width="1.7" stroke-linecap="round"><path d="M3 7h12a2.5 2.5 0 1 0-2.5-2.5M2 12h17a2.5 2.5 0 1 0-2.5-2.5M5 17h10a2.5 2.5 0 1 1-2.5 2.5"/></g>'
}
static var _textures: Dictionary = {}

static func texture(kind: String) -> Texture2D:
	if not PATHS.has(kind): return null
	if not _textures.has(kind):
		var source := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="white">' + str(PATHS[kind]) + '</g></svg>'
		var image := Image.new()
		if image.load_svg_from_string(source, 4.0) != OK: return null
		image.fix_alpha_edges()
		image.generate_mipmaps()
		_textures[kind] = ImageTexture.create_from_image(image)
	return _textures[kind]

static func draw_rotated(canvas: CanvasItem, kind: String, center: Vector2, extent: float, angle: float, ink: Color) -> void:
	canvas.draw_set_transform(center, angle)
	canvas.draw_texture_rect(texture(kind), Rect2(Vector2.ONE * -extent * .5, Vector2.ONE * extent), false, ink)
	canvas.draw_set_transform(Vector2.ZERO)
