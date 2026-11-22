class_name InteractSensor
extends Area3D
## Interaction reach, shared by the player and the phantom (D21). Its CollisionShape3D is
## the reach, and its collision_mask selects what can be interacted with.
##
## interact() queries the physics space with the shape at call time, instead of reading
## the area's overlap lists: those are updated by the physics step, a tick late for a
## moving actor. The query makes the phantom reach exactly what the player reached on
## the same tick of the record.

@onready var _shape_node : CollisionShape3D = $CollisionShape3D

## Calls interact(actor) on the nearest interactable in reach. An interactable is an
## area on the mask whose script, or whose parent's script, has interact(actor).
## Returns whether one was found.
func interact(actor: Node3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape_node.shape
	query.transform = _shape_node.global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var nearest : Node3D = null
	var nearest_distance := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		var interactable := _find_interactable(hit.collider)
		if not interactable:
			continue
		var distance := global_position.distance_squared_to(interactable.global_position)
		if distance < nearest_distance:
			nearest = interactable
			nearest_distance = distance

	if nearest:
		nearest.interact(actor)
		return true
	return false

func _find_interactable(collider: Object) -> Node3D:
	if collider.has_method(&"interact"):
		return collider
	var parent : Node = collider.get_parent()
	if parent is Node3D and parent.has_method(&"interact"):
		return parent
	return null
