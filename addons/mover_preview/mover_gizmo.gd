@tool
extends EditorNode3DGizmoPlugin
## Draws a translucent "phantom" of a selected Mover at pose B (its meshes, moved by
## `offset` and turned by `rotation_offset`) and a line from pose A to pose B.
##
## The phantom is a subgizmo: click it (with the Mover selected) and the editor's own
## move/rotate gizmo (W / E, local or global, with snapping) drives it. Every change is
## converted back into the Mover's `offset` and `rotation_offset`, so pose B always
## matches what Mover._pose() computes at progress 1.
##
## Mover is not a @tool script: in the editor its node transform is pose A, and its
## exported properties are read and written with get()/set().

## Matched by path, not preloaded: preloading would compile the game scripts it depends on
## (autoloads included) inside the editor plugin.
const MOVER_SCRIPT_PATH := "res://scripts/interactables/mover.gd"
const PHANTOM_ID := 0

var _undo_redo : EditorUndoRedoManager
## Property values when the current drag started, to restore on cancel and for undo
var _drag_node : Node3D
var _drag_offset : Vector3
var _drag_rotation : Vector3

func _init(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	create_material("phantom", Color(0.3, 0.85, 1.0, 0.3))
	create_material("phantom_selected", Color(1.0, 0.75, 0.2, 0.4))
	create_material("path", Color(0.3, 0.85, 1.0))

func _get_gizmo_name() -> String:
	return "Mover Pose B"

func _has_gizmo(node: Node3D) -> bool:
	return is_mover(node)

static func is_mover(node: Object) -> bool:
	var script := node.get_script() as Script
	while script:
		if script.resource_path == MOVER_SCRIPT_PATH:
			return true
		script = script.get_base_script()
	return false

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if not EditorInterface.get_selection().get_selected_nodes().has(node):
		return

	var pose_b := local_pose_b(node)
	var material_name := "phantom_selected" if gizmo.is_subgizmo_selected(PHANTOM_ID) else "phantom"
	var material := get_material(material_name, gizmo)
	for item in _collect_meshes(node):
		gizmo.add_mesh(item.mesh, material, pose_b * item.transform)
	gizmo.add_lines(PackedVector3Array([Vector3.ZERO, pose_b.origin]), get_material("path", gizmo))

# --- Subgizmo: the phantom ---

func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, screen_pos: Vector2) -> int:
	var node := gizmo.get_node_3d()
	var to_phantom := (node.global_transform * local_pose_b(node)).affine_inverse()
	var from := to_phantom * camera.project_ray_origin(screen_pos)
	var dir := to_phantom.basis * camera.project_ray_normal(screen_pos)
	return PHANTOM_ID if _phantom_aabb(node).intersects_ray(from, dir) != null else -1

func _subgizmos_intersect_frustum(gizmo: EditorNode3DGizmo, _camera: Camera3D, frustum_planes: Array[Plane]) -> PackedInt32Array:
	var node := gizmo.get_node_3d()
	var center := node.global_transform * local_pose_b(node) * _phantom_aabb(node).get_center()
	for plane in frustum_planes:
		if plane.is_point_over(center):
			return PackedInt32Array()
	return PackedInt32Array([PHANTOM_ID])

func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, _subgizmo_id: int) -> Transform3D:
	return local_pose_b(gizmo.get_node_3d())

func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, _subgizmo_id: int, transform: Transform3D) -> void:
	var node := gizmo.get_node_3d()
	if _drag_node != node:
		_drag_node = node
		_drag_offset = node.get(&"offset")
		_drag_rotation = node.get(&"rotation_offset")
	set_local_pose_b(node, transform)
	node.update_gizmos()

func _commit_subgizmos(gizmo: EditorNode3DGizmo, _ids: PackedInt32Array, restores: Array[Transform3D], cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	var old_offset : Vector3 = _drag_offset
	var old_rotation : Vector3 = _drag_rotation
	if _drag_node != node:
		# Nothing was dragged through _set_subgizmo_transform: rebuild from the restore
		var current_offset : Vector3 = node.get(&"offset")
		var current_rotation : Vector3 = node.get(&"rotation_offset")
		set_local_pose_b(node, restores[0])
		old_offset = node.get(&"offset")
		old_rotation = node.get(&"rotation_offset")
		node.set(&"offset", current_offset)
		node.set(&"rotation_offset", current_rotation)
	_drag_node = null

	if cancel:
		node.set(&"offset", old_offset)
		node.set(&"rotation_offset", old_rotation)
		node.update_gizmos()
		return
	_undo_redo.create_action("Move Mover Pose B")
	_undo_redo.add_do_property(node, &"offset", node.get(&"offset"))
	_undo_redo.add_do_property(node, &"rotation_offset", node.get(&"rotation_offset"))
	_undo_redo.add_do_method(node, &"update_gizmos")
	_undo_redo.add_undo_property(node, &"offset", old_offset)
	_undo_redo.add_undo_property(node, &"rotation_offset", old_rotation)
	_undo_redo.add_undo_method(node, &"update_gizmos")
	_undo_redo.commit_action()

# --- Pose B <-> Mover properties (must match Mover._pose() at progress 1) ---

## Pose B in the Mover's local space (pose A is the node's own transform).
static func local_pose_b(node: Node3D) -> Transform3D:
	var pose_a := node.transform
	var offset : Vector3 = node.get(&"offset")
	var rotation_offset : Vector3 = node.get(&"rotation_offset")
	var pose_b := Transform3D(
		pose_a.basis * Basis.from_euler(rotation_offset * (PI / 180.0)),
		pose_a.origin + pose_a.basis.orthonormalized() * offset)
	return pose_a.affine_inverse() * pose_b

## Writes `offset` and `rotation_offset` so that pose B becomes `local_b` (in the Mover's
## local space). Scale in `local_b` is ignored: a Mover only moves and turns.
static func set_local_pose_b(node: Node3D, local_b: Transform3D) -> void:
	# Only write what actually changed, so a pure move doesn't add float noise to the
	# rotation (e.g. -90 -> -90.00001) and a pure rotation doesn't touch the offset
	var current := local_pose_b(node)
	if not current.origin.is_equal_approx(local_b.origin):
		var pose_a := node.transform
		var pose_b_origin := pose_a * local_b.origin
		var offset := pose_a.basis.orthonormalized().inverse() * (pose_b_origin - pose_a.origin)
		node.set(&"offset", _rounded(offset, 10000.0))

	var new_basis := local_b.basis.orthonormalized()
	if not current.basis.orthonormalized().is_equal_approx(new_basis):
		var previous : Vector3 = node.get(&"rotation_offset")
		var euler := _closest_euler(new_basis, previous * (PI / 180.0))
		node.set(&"rotation_offset", _rounded(euler * (180.0 / PI), 1000.0))

## Rounds to 1 / `steps_per_unit` (divides instead of multiplying by the step, so -90 stays
## exactly -90.0).
static func _rounded(v: Vector3, steps_per_unit: float) -> Vector3:
	return (v * steps_per_unit).round() / steps_per_unit

## Euler angles (YXZ, like Basis.from_euler) of `basis`, picked to be the closest to
## `previous`. Mover interpolates the Euler angles themselves, so this keeps the path a
## drag describes: dragging a hinge past 180° gives 270°, not -90° (the other way round).
static func _closest_euler(basis: Basis, previous: Vector3) -> Vector3:
	var e := basis.get_euler()
	# The other YXZ solution of the same rotation
	var alt := Vector3(PI - e.x, e.y + PI, e.z + PI)
	var a := _unwrap_near(e, previous)
	var b := _unwrap_near(alt, previous)
	return a if a.distance_squared_to(previous) <= b.distance_squared_to(previous) else b

static func _unwrap_near(angles: Vector3, reference: Vector3) -> Vector3:
	for i in 3:
		angles[i] = reference[i] + wrapf(angles[i] - reference[i], -PI, PI)
	return angles

# --- Phantom geometry ---

## Every MeshInstance3D under the mover (internal children included), with its transform
## relative to the mover.
static func _collect_meshes(node: Node3D) -> Array[Dictionary]:
	var result : Array[Dictionary] = []
	var stack : Array[Node] = [node]
	while not stack.is_empty():
		var current : Node = stack.pop_back()
		for child in current.get_children(true):
			stack.push_back(child)
			var mesh_instance := child as MeshInstance3D
			if mesh_instance and mesh_instance.mesh and mesh_instance.is_visible_in_tree():
				var relative := node.global_transform.affine_inverse() * mesh_instance.global_transform
				result.append({ "mesh": mesh_instance.mesh, "transform": relative })
	return result

## Bounds of the phantom in its own space (pose B), for click picking.
static func _phantom_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for item in _collect_meshes(node):
		var box : AABB = item.transform * (item.mesh as Mesh).get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	return AABB(Vector3.ONE * -0.25, Vector3.ONE * 0.5) if first else aabb
