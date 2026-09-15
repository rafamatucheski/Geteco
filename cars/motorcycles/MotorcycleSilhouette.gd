extends RefCounted
## Resident silhouette while the normal presentation queue builds detail.
static var _texture: ImageTexture
static func texture() -> ImageTexture:
	if _texture != null: return _texture
	var img := Image.create(64,32,false,Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	img.fill_rect(Rect2i(2,13,13,6),Color("20252a"))
	img.fill_rect(Rect2i(49,13,13,6),Color("20252a"))
	img.fill_rect(Rect2i(12,10,36,12),Color.WHITE)
	img.fill_rect(Rect2i(40,4,3,24),Color("5e6870"))
	img.fill_rect(Rect2i(17,11,16,10),Color("292d35"))
	img.fill_rect(Rect2i(55,14,4,4),Color("ffefcb"))
	_texture = ImageTexture.create_from_image(img)
	return _texture
