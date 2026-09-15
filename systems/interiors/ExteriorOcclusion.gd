extends Area2D
## Repaint cached scenery only over actors whose feet are behind its ground edge.
## Physics is supplied separately by the visual geometry's projected footprint.
const MASK = preload("res://systems/interiors/ExteriorOcclusion.gdshader")
var source: Sprite2D
var overlay: CanvasItem
var front_y := 0.0
var margin := 200.0
## Cenário desenhado por _draw (árvores procedurais) não tem textura para
## reaproveitar: o overlay chama o mesmo desenho, e o retângulo vem de fora.
var painter := Callable()
var drawn_rect := Rect2()
var bodies: Array[Node2D] = []

static func attach(sprite: Sprite2D, floor_edge: float, zone_margin := 200.0) -> Area2D:
 var zone = load("res://systems/interiors/ExteriorOcclusion.gd").new()
 zone.source = sprite
 zone.front_y = floor_edge
 zone.margin = zone_margin
 sprite.get_parent().add_child(zone)
 return zone

## `rect` e `floor_edge` estão no espaço local de `owner`; `paint` recebe o
## CanvasItem onde desenhar e deve repetir só a parte em pé (sem sombra/chão).
static func attach_drawn(owner: Node2D, rect: Rect2, floor_edge: float, paint: Callable, zone_margin := 80.0) -> Area2D:
 var zone = load("res://systems/interiors/ExteriorOcclusion.gd").new()
 zone.painter = paint
 zone.drawn_rect = rect
 zone.front_y = floor_edge
 zone.margin = zone_margin
 owner.add_child(zone)
 return zone

func _ready() -> void:
 collision_layer = 0
 collision_mask = 7
 monitoring = true
 monitorable = false
 var bounds := drawn_rect if painter.is_valid() else source.transform * source.get_rect()
 var shape := CollisionShape2D.new()
 var rectangle := RectangleShape2D.new()
 rectangle.size = bounds.size + Vector2(margin, margin)
 shape.shape = rectangle
 shape.position = bounds.get_center()
 add_child(shape)
 if painter.is_valid():
  var canvas := Node2D.new()
  canvas.name = "ActorOcclusion"
  canvas.draw.connect(func(): painter.call(canvas))
  overlay = canvas
  add_child(canvas)
 else:
  var sprite := Sprite2D.new()
  sprite.name = "ActorOcclusion"
  sprite.texture = source.texture
  sprite.centered = source.centered
  sprite.offset = source.offset
  overlay = sprite
  source.add_child(sprite)
 overlay.z_as_relative = false
 overlay.z_index = 30
 overlay.material = ShaderMaterial.new()
 overlay.material.shader = MASK
 overlay.hide()
 body_entered.connect(func(body: Node2D):
  if body is CharacterBody2D or body is RigidBody2D:
   bodies.append(body)
   set_process(true))
 body_exited.connect(func(body: Node2D): bodies.erase(body))
 set_process(false)

func _covered_rect() -> Rect2:
 if painter.is_valid(): return global_transform * drawn_rect
 return source.global_transform * source.get_rect()

func _process(_delta: float) -> void:
 var behind := PackedVector4Array()
 var ahead := PackedVector4Array()
 var covered := _covered_rect()
 for body in bodies:
  if not is_instance_valid(body) or not body.is_visible_in_tree(): continue
  var sprite: Sprite2D
  for key in ["sprite_3d_display", "presentation_sprite", "visual", "sprite_3d"]:
   sprite = body.get(key) as Sprite2D
   if sprite != null: break
  if sprite == null or not sprite.is_visible_in_tree(): continue
  var rect := sprite.global_transform * sprite.get_rect()
  if not rect.intersects(covered): continue
  var item := Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y)
  if body.global_position.y < global_position.y + front_y:
   if behind.size() < 16: behind.append(item)
  elif ahead.size() < 16: ahead.append(item)
 overlay.visible = not behind.is_empty()
 if not painter.is_valid(): (overlay as Sprite2D).texture = source.texture
 overlay.material.set_shader_parameter("behind_count",behind.size())
 overlay.material.set_shader_parameter("ahead_count",ahead.size())
 behind.resize(16)
 ahead.resize(16)
 overlay.material.set_shader_parameter("behind",behind)
 overlay.material.set_shader_parameter("ahead",ahead)
 if bodies.is_empty(): set_process(false)
