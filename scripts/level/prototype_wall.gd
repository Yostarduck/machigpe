@tool
class_name PrototypeWall
extends PrototypeBlock
## Blocking-out block drawn as a single BoxMesh with one material (all six faces).
## Resizing changes the BoxMesh size, never the node scale. See PrototypeBlock.

@export var material : Material:
	set(value):
		material = value
		_box.material = value

## Invisible extra collision added on top of the wall (e.g. to keep the player from jumping
## over a low wall). The collision box goes from y = 0 to y = size.y + extra_height.
@export_range(0.0, 10.0, 0.01, "or_greater") var extra_height : float = 0.0:
	set(value):
		extra_height = maxf(value, 0.0)
		_apply()
		update_gizmos()

var _box := BoxMesh.new()

func get_collision_height() -> float:
	return size.y + extra_height

func _update_mesh() -> void:
	_mesh_instance.mesh = _box
	# BoxMesh is centred on its origin: lift it so its bottom sits on the pivot
	_mesh_instance.position = Vector3(0, size.y * 0.5, 0)
	_box.size = size
