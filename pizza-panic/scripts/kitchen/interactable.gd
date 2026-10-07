class_name Interactable
extends Node3D
## Anything the player can walk up to and press E on: kitchen stations, the
## phone, the car, front doors, Tony...
## Override prompt() and use(). The player picks the closest one in front of them.

@export var reach := 1.6

## Text shown on screen, e.g. "[E] Grab dough". Return "" to hide/disable.
func prompt(_player: Node) -> String:
	return ""


func use(_player: Node) -> void:
	pass


func _enter_tree() -> void:
	add_to_group("interactable")
