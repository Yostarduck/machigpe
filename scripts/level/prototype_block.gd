@tool
class_name PrototypeBlock
extends StaticBody3D
## Base for the level blocking-out prefabs (PrototypePlatform, PrototypeWall). `size`
## drives the visible mesh and the BoxShape3D, so the block is resized instead of scaled.
## The pivot is the bottom centre: the block is centred in X/Z and rises from y = 0 to
## y = size.y. The "prototype_platform" editor plugin adds the resize handles.
##
## The MeshInstance3D and CollisionShape3D are internal children built from code: they are
## not saved in the scene, so every instance gets its own mesh/shape instead of sharing
## the prefab's sub-resources, and only the exported properties end up in the level file.
## Subclasses build the visuals in `_update_mesh()`.

@export var size : Vector3 = Vector3(2, 1, 2):
	set(value):
		size = value.max(Vector3.ONE * MIN_SIZE)
		_apply()
		update_gizmos()

## Step used when dragging the handles in the editor. 0 disables snapping.
@export_range(0.0, 1.0, 0.01, "or_greater") var resize_snap : float = 0.25

const MIN_SIZE := 0.01

var _mesh_instance : MeshInstance3D
var _collision_shape : CollisionShape3D
## A box given by its 8 corners instead of a BoxShape3D: a BoxShape3D is centred on its
## node, which would have to sit at half the collision height. The editor's selection box
## merges every child's origin (internal ones included), so with a tall collision (e.g. a
## wall's extra height) that origin poked above the mesh and stretched the selection box.
## With corner points the collision node stays at the pivot, always inside the mesh bounds.
var _shape := ConvexPolygonShape3D.new()

func _init() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = &"Mesh"
	add_child(_mesh_instance, false, INTERNAL_MODE_FRONT)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = &"Collision"
	_collision_shape.shape = _shape
	add_child(_collision_shape, false, INTERNAL_MODE_FRONT)
	_apply()

func _apply() -> void:
	# Pivot is the bottom centre: the collision box goes from y = 0 to the collision height
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := get_collision_height()
	_shape.points = PackedVector3Array([
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
		Vector3(-hx, top, -hz), Vector3(hx, top, -hz), Vector3(hx, top, hz), Vector3(-hx, top, hz),
	])
	_update_mesh()

## Height of the collision box (it always starts at the base). Override to make it differ
## from the visible height.
func get_collision_height() -> float:
	return size.y

## Override: rebuild `_mesh_instance`'s mesh for the current `size`.
func _update_mesh() -> void:
	pass
