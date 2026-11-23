@tool
extends EditorNode3DGizmoPlugin
## Draws the box outline and the resize handles on every PrototypeBlock (platforms and
## walls). The pivot is the bottom centre, so there is no -Y handle: +Y changes the height
## from the base, and the X/Z handles change the width symmetrically, keeping the box
## centred in X/Z. Size handle ids: axis = id >> 1, positive face when id is even (id 3,
## -Y, is never added).
##
## PrototypeWall also gets the "extra height" handle (id 6) on a top corner of its
## collision box, and the extra collision volume is outlined in a second colour.

const Block := preload("res://scripts/level/prototype_block.gd")
const Wall := preload("res://scripts/level/prototype_wall.gd")

const HANDLE_NAMES : PackedStringArray = ["Size +X", "Size -X", "Size +Y", "Size -Y", "Size +Z", "Size -Z", "Extra Height"]
const SIZE_HANDLE_IDS : PackedInt32Array = [0, 1, 2, 4, 5]
const EXTRA_HEIGHT_ID := 6

var _undo_redo : EditorUndoRedoManager

func _init(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	create_material("lines", Color(1.0, 0.6, 0.1))
	create_material("extra_lines", Color(0.2, 0.8, 1.0))
	create_handle_material("handles")

func _get_gizmo_name() -> String:
	return "PrototypeBlock"

func _has_gizmo(node: Node3D) -> bool:
	return node is Block

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var block := gizmo.get_node_3d() as Block
	var size := block.size

	var lines := _box_lines(Vector3(-size.x * 0.5, 0, -size.z * 0.5), size)
	gizmo.add_lines(lines, get_material("lines", gizmo))

	# Click-selection in the viewport only hits gizmo collision: the real mesh is an
	# internal child, which the editor never picks. Register the whole box (bottom included).
	var box := BoxMesh.new()
	box.size = size
	var faces := box.get_faces()
	for i in faces.size():
		faces[i].y += size.y * 0.5  # BoxMesh is centred; the pivot is the bottom centre
	var tri_mesh := TriangleMesh.new()
	tri_mesh.create_from_faces(faces)
	gizmo.add_collision_triangles(tri_mesh)
	gizmo.add_collision_segments(lines)

	var handles := PackedVector3Array()
	var ids := SIZE_HANDLE_IDS.duplicate()
	for id in ids:
		handles.push_back(_handle_position(id, size))

	if block is Wall:
		var extra := (block as Wall).extra_height
		if extra > 0.0:
			var extra_lines := _box_lines(Vector3(-size.x * 0.5, size.y, -size.z * 0.5), Vector3(size.x, extra, size.z))
			gizmo.add_lines(extra_lines, get_material("extra_lines", gizmo))
		ids.push_back(EXTRA_HEIGHT_ID)
		handles.push_back(_extra_handle_origin(size) + Vector3(0, extra, 0))

	gizmo.add_handles(handles, get_material("handles", gizmo), ids)

func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return HANDLE_NAMES[handle_id]

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().get(_handle_property(handle_id))

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var block := gizmo.get_node_3d() as Block
	var to_local := block.global_transform.affine_inverse()
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var seg_a := to_local * ray_from
	var seg_b := to_local * (ray_from + ray_dir * 4096.0)

	if handle_id == EXTRA_HEIGHT_ID:
		# Vertical line through the top corner of the visible box, starting at its top
		var corner := _extra_handle_origin(block.size)
		var extra := _closest_extent(corner, Vector3.UP, seg_a, seg_b)
		if block.resize_snap > 0.0:
			extra = snappedf(extra, block.resize_snap)
		(block as Wall).extra_height = maxf(extra, 0.0)
		return

	# X/Z axes pass through the box centre; the Y axis starts at the base (the pivot)
	var axis := handle_id >> 1
	var dir := _face_dir(handle_id)
	var origin := Vector3.ZERO if axis == Vector3.AXIS_Y else Vector3(0, block.size.y * 0.5, 0)
	var extent := _closest_extent(origin, dir, seg_a, seg_b)

	# Height grows from the base; width/depth grow on both sides of the centre
	var new_size := extent if axis == Vector3.AXIS_Y else extent * 2.0
	if block.resize_snap > 0.0:
		new_size = snappedf(new_size, block.resize_snap)
	var size := block.size
	size[axis] = maxf(new_size, Block.MIN_SIZE)
	block.size = size

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var block := gizmo.get_node_3d()
	var property := _handle_property(handle_id)
	if cancel:
		block.set(property, restore)
		return
	_undo_redo.create_action("Resize Prototype Block")
	_undo_redo.add_do_property(block, property, block.get(property))
	_undo_redo.add_undo_property(block, property, restore)
	_undo_redo.commit_action()

static func _handle_property(handle_id: int) -> StringName:
	return &"extra_height" if handle_id == EXTRA_HEIGHT_ID else &"size"

## Signed distance along `dir` from `origin` to the point of that axis closest to the ray.
static func _closest_extent(origin: Vector3, dir: Vector3, seg_a: Vector3, seg_b: Vector3) -> float:
	var closest := Geometry3D.get_closest_points_between_segments(origin - dir * 4096.0, origin + dir * 4096.0, seg_a, seg_b)
	return (closest[0] - origin).dot(dir)

## Top (+X, +Z) corner of the visible box; the extra height handle sits above it.
static func _extra_handle_origin(size: Vector3) -> Vector3:
	return Vector3(size.x * 0.5, size.y, size.z * 0.5)

static func _handle_position(handle_id: int, size: Vector3) -> Vector3:
	if handle_id >> 1 == Vector3.AXIS_Y:
		return Vector3(0, size.y, 0)
	return Vector3(0, size.y * 0.5, 0) + _face_dir(handle_id) * size * 0.5

static func _face_dir(handle_id: int) -> Vector3:
	var dir := Vector3.ZERO
	dir[handle_id >> 1] = 1.0 if handle_id % 2 == 0 else -1.0
	return dir

## Line pairs for the 12 edges of the box starting at `pos` with extents `box_size`.
static func _box_lines(pos: Vector3, box_size: Vector3) -> PackedVector3Array:
	var lines := PackedVector3Array()
	var aabb := AABB(pos, box_size)
	# AABB edges: pairs of corners differing in exactly one axis
	for a in 8:
		for b in range(a + 1, 8):
			var diff := a ^ b
			if diff == 1 or diff == 2 or diff == 4:
				lines.push_back(aabb.get_endpoint(a))
				lines.push_back(aabb.get_endpoint(b))
	return lines
