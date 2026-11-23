@tool
class_name PrototypePlatform
extends PrototypeBlock
## Blocking-out block built from planes: the four lateral faces use `wall_material` and the
## top face uses `floor_material` (no bottom face). Both default materials are
## world-triplanar, so the texture density stays the same at any size. See PrototypeBlock.

## Material of the four lateral faces
@export var wall_material : Material:
	set(value):
		wall_material = value
		_apply_materials()

## Material of the top face
@export var floor_material : Material:
	set(value):
		floor_material = value
		_apply_materials()

const SURFACE_WALLS := 0
const SURFACE_TOP := 1

var _mesh := ArrayMesh.new()

func _update_mesh() -> void:
	_mesh_instance.mesh = _mesh
	_build_mesh()

func _apply_materials() -> void:
	if _mesh.get_surface_count() == 2:
		_mesh.surface_set_material(SURFACE_WALLS, wall_material)
		_mesh.surface_set_material(SURFACE_TOP, floor_material)

func _build_mesh() -> void:
	var h := size * 0.5
	var mid := Vector3(0, h.y, 0)  # centre of the box, in local space

	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_plane(walls, mid + Vector3(h.x, 0, 0), Vector3.RIGHT, Vector3(0, 0, -h.z), Vector3(0, h.y, 0))
	_add_plane(walls, mid - Vector3(h.x, 0, 0), Vector3.LEFT, Vector3(0, 0, h.z), Vector3(0, h.y, 0))
	_add_plane(walls, mid + Vector3(0, 0, h.z), Vector3.BACK, Vector3(h.x, 0, 0), Vector3(0, h.y, 0))
	_add_plane(walls, mid - Vector3(0, 0, h.z), Vector3.FORWARD, Vector3(-h.x, 0, 0), Vector3(0, h.y, 0))

	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_plane(top, Vector3(0, size.y, 0), Vector3.UP, Vector3(h.x, 0, 0), Vector3(0, 0, -h.z))

	_mesh.clear_surfaces()
	walls.commit(_mesh)  # surface 0 (SURFACE_WALLS)
	top.commit(_mesh)    # surface 1 (SURFACE_TOP)
	_apply_materials()

## Adds a quad centred at `center` facing `normal`. `u` and `v` are the half-extent vectors
## along the plane, with u × v pointing along `normal`. Godot treats clockwise triangles as
## front faces, so the corners are emitted clockwise as seen from outside.
static func _add_plane(st: SurfaceTool, center: Vector3, normal: Vector3, u: Vector3, v: Vector3) -> void:
	var corners : Array[Vector3] = [center - u - v, center + u - v, center + u + v, center - u + v]
	var u_dir := u.normalized()
	var v_dir := v.normalized()
	for i : int in [0, 3, 2, 0, 2, 1]:
		var p := corners[i]
		st.set_normal(normal)
		st.set_uv(Vector2(p.dot(u_dir), -p.dot(v_dir)))  # 1 UV unit per metre
		st.add_vertex(p)
