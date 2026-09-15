extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 root.size = Vector2i(1280,720)
 var popup := preload("res://world/harbor/monaliza/MonalizaIntroduction.gd").new()
 root.add_child(popup)
 await create_timer(0.5).timeout
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/geteco/artifacts/monaliza-introduction.png")
 popup.advance()
 popup.advance()
 popup.advance()
 quit()
