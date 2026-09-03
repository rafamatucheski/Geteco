class_name DemoPedestrianArt
extends RefCounted

const SAFE_TEXTURE_PATH = "res://city_demo/art/pedestrian-directional-safe-v3.png"
const FRAME_SIZE = Vector2i(192, 256)
const IDENTITY_COUNT = 8
const DIRECTION_COUNT = 4

static var _safe_texture: Texture2D

static func texture() -> Texture2D:
	if _safe_texture == null:
		_safe_texture = load(SAFE_TEXTURE_PATH) as Texture2D
		if _safe_texture == null:
			push_error("Não foi possível carregar o atlas seguro de pedestres.")
	return _safe_texture

static func frame(identity: int, direction_row: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = texture()
	atlas_texture.region = Rect2(
		clampi(identity, 0, IDENTITY_COUNT - 1) * FRAME_SIZE.x,
		clampi(direction_row, 0, DIRECTION_COUNT - 1) * FRAME_SIZE.y,
		FRAME_SIZE.x,
		FRAME_SIZE.y
	)
	atlas_texture.filter_clip = true
	return atlas_texture
