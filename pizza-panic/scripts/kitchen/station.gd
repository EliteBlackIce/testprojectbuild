class_name Station
extends Interactable
## An Interactable whose prompt and action are plain functions, so the Kitchen
## can wire up every station in one place.

var prompt_fn: Callable
var use_fn: Callable


static func make(parent: Node3D, pos: Vector3, prompt_callable: Callable, use_callable: Callable, reach_m := 1.6) -> Station:
	var s := Station.new()
	s.prompt_fn = prompt_callable
	s.use_fn = use_callable
	s.reach = reach_m
	s.position = pos
	parent.add_child(s)
	return s


func prompt(player: Node) -> String:
	return prompt_fn.call(player) if prompt_fn.is_valid() else ""


func use(player: Node) -> void:
	if use_fn.is_valid():
		use_fn.call(player)
