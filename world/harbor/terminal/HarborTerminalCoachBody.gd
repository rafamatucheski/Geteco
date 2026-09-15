extends CharacterBody2D
## The scheduled body hands ownership to the normal driving controller on theft.
func enter_vehicle(actor: CharacterBody2D) -> void:
	get_parent().steal_coach(actor)
