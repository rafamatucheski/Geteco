extends RefCounted
const WEAPON_ICONS := preload("res://ui/v1/WeaponIcon3D.gd")
const MAP_SYMBOLS := preload("res://ui/hud/MapSymbols.gd")
const LOCKPICK_ICON := preload("res://ui/icons/tabler/lock-open-2.svg")
static var textures: Dictionary = {}

static func get_icon(id: String) -> Texture2D:
	if textures.has(id): return textures[id]
	if id == "scrap":
		textures[id] = MAP_SYMBOLS.texture("workshop")
		return textures[id]
	if id == "katana":
		var source := WEAPON_ICONS.new()
		source._load_textures()
		var sword: Texture2D = WEAPON_ICONS.icon_textures.get("katana")
		source.free()
		if sword != null:
			textures[id] = sword
			return sword
	var image := Image.new()
	if id == "lockpick":
		# Reference the imported resource so exports include it; tint once in cache.
		image = LOCKPICK_ICON.get_image()
		if image.is_compressed(): image.decompress()
		var tint := Color("c8b483")
		for y in image.get_height():
			for x in image.get_width():
				var alpha := image.get_pixel(x, y).a
				image.set_pixel(x, y, Color(tint, alpha))
	elif id=="pistol":
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="180" height="100" viewBox="0 0 180 100"><path d="M35 23H157L163 28V43H36Z" fill="#8b9ba5" stroke="#c2ccd0" stroke-width="2"/><path d="M38 26H152V31H38Z" fill="#b8c1c5"/><path d="M39 43H153V51H117L112 66H78L66 88H33L44 52H36Z" fill="#465961" stroke="#829197" stroke-width="2"/><path d="M44 52H75L61 86H35Z" fill="#293a40"/><path d="M80 51H108L103 61H79Z" fill="#182722"/><path d="M88 51Q86 57 92 59" fill="none" stroke="#9ca9af" stroke-width="2"/><path d="M42 59L65 62M39 66L62 69M36 74L59 77" stroke="#586a70" stroke-width="2"/><path d="M42 32V40M48 32V40M54 32V40M60 32V40" stroke="#465b65" stroke-width="3"/><path d="M99 32H116V39H99Z" fill="#394d58"/><path d="M29 87H63V93H29Z" fill="#81919a"/><path d="M38 19H47V24H38ZM144 19H151V24H144Z" fill="#344951"/><path d="M162 30H168V40H162Z" fill="#2f434d"/></svg>')
	elif WEAPON_ICONS.ICON_DATA.has(id):
		var source: Dictionary = WEAPON_ICONS.ICON_DATA[id]
		var bytes := Marshalls.base64_to_raw(source.data)
		if source.ext=="svg":
			if id == "knife":
				var artwork := ""
				for line in bytes.get_string_from_utf8().split("\n"):
					if line.strip_edges().begins_with('<rect x="9"') or line.strip_edges().begins_with('<rect x="11"'): continue
					artwork += line + "\n"
				image.load_svg_from_string(artwork)
			else: image.load_svg_from_buffer(bytes)
		else:
			image.load_png_from_buffer(bytes)
			# Existing exports use alpha 255 for every object pixel and 220/230/80
			# for the embedded card. Preserve the full canvas so tips are not clipped.
			if image.get_size() == Vector2i(256, 128):
				for y in image.get_height():
					for x in image.get_width():
						var pixel := image.get_pixel(x, y)
						if pixel.a < .99: image.set_pixel(x, y, Color.TRANSPARENT)
	else:
		var paths := {
			"fish":'<path d="M72 49L92 29V71Z" fill="#b48b5f" stroke="#dbb989" stroke-width="2"/><path d="M9 50Q32 17 61 32L78 50Q53 81 25 68Z" fill="#86a29b" stroke="#c5d1bc" stroke-width="2"/><path d="M31 31L48 16L58 30M34 70L50 83L58 69" fill="#5d8178"/><path d="M32 35Q44 50 32 65" fill="none" stroke="#4f7069" stroke-width="3"/><circle cx="23" cy="45" r="4" fill="#192c2c"/><circle cx="24" cy="44" r="1" fill="#ece8cf"/>',
			"cooked_fish":'<ellipse cx="50" cy="58" rx="44" ry="27" fill="#c8cebb" stroke="#edf0dd" stroke-width="3"/><path d="M70 54L87 40V69Z" fill="#93613d"/><path d="M15 55Q33 31 57 40L75 54Q53 78 29 68Z" fill="#c48b4e" stroke="#8e5d38" stroke-width="2"/><path d="M37 44L32 62M48 43L43 65M59 47L54 64" stroke="#784f32" stroke-width="3"/><circle cx="24" cy="52" r="3" fill="#483a29"/><path d="M34 22Q29 16 35 10M51 25Q45 19 51 13M67 26Q61 20 67 14" fill="none" stroke="#cbd4c6" stroke-width="2"/>',
			"juice":'<path d="M31 11H65L77 28V82H23V28Z" fill="#e5a554" stroke="#f2d09a" stroke-width="2"/><path d="M31 11V27H65L77 28M23 29H77" fill="none" stroke="#f2d09a" stroke-width="2"/><path d="M24 38H76V69H24Z" fill="#ede3b5"/><circle cx="50" cy="54" r="13" fill="#d98a3d"/><path d="M50 40Q49 29 62 34Q60 43 50 40" fill="#6f944d"/>',
			"yogurt":'<path d="M22 28H78L68 81H32Z" fill="#ede2cd" stroke="#c6b9a4" stroke-width="2"/><ellipse cx="50" cy="27" rx="30" ry="8" fill="#ab6270" stroke="#d99baa" stroke-width="2"/><path d="M28 43H73L69 68H31Z" fill="#ba7080"/><path d="M41 51Q50 39 59 51L51 63Z" fill="#e6b5ae"/>',
			"bread":'<path d="M13 69V37Q15 12 42 12H60Q87 12 89 37V69Q80 84 51 83Q25 85 13 69Z" fill="#b88549" stroke="#e3b974" stroke-width="3"/><path d="M22 69V38Q26 22 43 22H60Q76 23 80 38V69Q58 81 22 69" fill="#dfb77d"/><path d="M32 28L39 44M48 25L55 41M64 29L71 44" stroke="#a77b49" stroke-width="5" stroke-linecap="round"/>',
			"cereal_bar":'<path d="M8 31L17 23L25 28H78L86 23L93 31L87 69L78 64H25L17 69L8 60Z" fill="#708e63" stroke="#a9bc88" stroke-width="2"/><path d="M27 30H76V62H27Z" fill="#d7bb7b"/><path d="M33 37H69V56H33Z" fill="#ad834e"/><path d="M38 41L43 46M49 40L53 46M60 42L65 47M38 50L43 54M52 50L57 54" stroke="#e4cb8f" stroke-width="3"/>',
			"armor":'<path d="M25 10H40L43 26H57L60 10H75L83 36L76 44V81H24V44L17 36Z" fill="#536d72" stroke="#9bb4b5" stroke-width="2"/><path d="M29 42H71V58H29ZM29 62H47V74H29ZM53 62H71V74H53Z" fill="#30474e" stroke="#789499"/><path d="M48 29H52V79" stroke="#afc4bb" stroke-width="2"/>',
			"apple":'<path d="M50 29C20 11 9 48 25 70Q37 88 50 76Q67 88 80 64C94 37 75 15 50 29Z" fill="#be6957" stroke="#e1a48a" stroke-width="2"/><path d="M51 28Q49 15 58 9" stroke="#aa9270" stroke-width="4" fill="none"/><path d="M54 20Q63 4 77 12Q70 26 54 20" fill="#8fa971"/><path d="M31 34Q22 42 26 54" fill="none" stroke="#eaaa8b" stroke-width="4"/>',
			"water":'<path d="M41 8H59V23L68 33V75Q50 84 32 75V33L41 23Z" fill="#6e99a1" stroke="#b8d1cf" stroke-width="2"/><path d="M34 42H66V62H34Z" fill="#d5ddcd"/><path d="M39 7H61V18H39Z" fill="#537483"/>',
			"med":'<rect x="19" y="18" width="63" height="59" rx="12" fill="#ab7068" stroke="#d99b8e" stroke-width="2"/><path d="M39 18V10H63V18" fill="none" stroke="#c68a7f" stroke-width="5"/><path d="M45 39H57V49H67V61H57V71H45V61H35V49H45Z" fill="#eee6cf"/>',
			"ammo":'<path d="M13 34L32 19H85V65L67 80H13Z" fill="#958364" stroke="#cbbb8d" stroke-width="2"/><path d="M13 34H67L85 19M67 34V80" fill="none" stroke="#dbc89a"/><path d="M22 46H59V68H22Z" fill="#394741"/><path d="M28 51V64M39 51V64M50 51V64" stroke="#d3c69b" stroke-width="5"/>',
			"sandwich":'<path d="M16 62L44 15Q49 8 58 17L88 64Z" fill="#d6b67e" stroke="#f5d9a2" stroke-width="4"/><path d="M15 64L85 65L76 77H22Z" fill="#839365"/><path d="M18 74H78V82H22Z" fill="#d0956e"/>',
			"key":'<circle cx="35" cy="30" r="17" fill="none" stroke="#c8b483" stroke-width="8"/><path d="M46 43L79 77M62 59L72 49M71 69L81 59" stroke="#c8b483" stroke-width="7"/>',
			"quest":'<path d="M25 9H66L80 25V82H25Z" fill="#c8baa0"/><path d="M65 9V27H80M35 40H67M35 51H67M35 62H57" stroke="#736957" stroke-width="3" fill="none"/>',
			"bag":'<path d="M40 22V14H60V22" fill="none" stroke="#59412f" stroke-width="5"/><rect x="24" y="23" width="52" height="59" rx="10" fill="#79573d" stroke="#a17a57" stroke-width="2"/><path d="M25 29Q50 36 75 29V39Q50 45 25 39Z" fill="#947050"/><rect x="31" y="55" width="38" height="21" rx="5" fill="#62452f"/><path d="M36 57V63M64 57V63" stroke="#b4a080" stroke-width="3"/>',
			"case":'<path d="M37 25V14H63V25" fill="none" stroke="#b59470" stroke-width="6"/><rect x="10" y="25" width="80" height="55" rx="8" fill="#896f52" stroke="#b59874" stroke-width="2"/><path d="M12 42H88M29 26V79M71 26V79" stroke="#4d4439" stroke-width="5"/>',
		}
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="90" viewBox="0 0 100 90">'+str(paths.get(id,paths.quest))+'</svg>')
	# Weapon exports include large transparent margins; crop once so a 4-cell
	# rifle actually fills the row instead of looking like a tiny pistol icon.
	var used:=image.get_used_rect()
	if used.has_area(): image=image.get_region(used.grow(2).intersection(Rect2i(Vector2i.ZERO,image.get_size())))
	var texture := ImageTexture.create_from_image(image)
	textures[id]=texture
	return texture
