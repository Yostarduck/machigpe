class_name CameraRig
extends Node3D
## Follow camera (misc/Camera.md, follow mode).
##
## The rig holds the camera's rotation and position; the Camera3D is its child.
## The camera never rotates, so everything is computed in 2D on the camera plane:
## a world point P is at (P · right, P · up) metres on screen.
##
##   feet inside the inner rectangle    camera still
##   between inner and outer            camera moves towards the player, faster the
##                                      further past the inner edge (follow_curve)
##   feet at the outer rectangle        hard wall: the player can't cross it
##
## Look-ahead: the rig frames a point ahead of the feet instead of the feet themselves.
## While the player moves, that point drifts ahead in the movement direction (on the
## ground plane) up to max_lead; when the player stops, it drifts back to the feet. So
## more of the level is visible in front of the player than behind. The wall still uses
## the real feet.
##
## The screen position alone sets the image (orthographic camera), so the camera is
## placed on its view ray at the height reference_height + offset.y. Walking on flat
## ground only moves it on X and Z; it moves on Y only when the framed height changes
## (landing higher or lower, falling). Its distance to the player along the view axis
## stays constant, so the scene never drifts towards the near or far clip planes.

## Node followed. Its origin is the feet. Defaults to the first node in the "player" group.
@export var target : Node3D
## The orthographic camera; its size gives the visible area.
@export var camera : Camera3D
## Camera position relative to the focus point.
@export var offset : Vector3 = Vector3(10, 10, 10)

@export_group("Follow")
## Inner rectangle, as a fraction of the screen width and height.
@export var inner_rect : Vector2 = Vector2(0.25, 0.3)
## Outer rectangle (wall), as a fraction of the screen width and height.
@export var outer_rect : Vector2 = Vector2(0.7, 0.75)
## Camera speed (m/s) when the feet are on the outer rectangle.
@export var max_follow_speed : float = 12.0
## Speed (0-1, times max_follow_speed) by how far the feet are past the inner edge,
## from 0 (inner edge) to 1 (outer edge). Empty = ease-in (slow near the inner edge).
@export var follow_curve : Curve

@export_group("Look ahead")
## Distance (m, on the ground plane) the framed point gets ahead of the feet while moving.
## Keep it below the inner plus outer half widths, or the wall holds the feet at the edge.
@export var max_lead : float = 4.0
## How fast (m/s) the framed point gets ahead while the player moves.
@export var lead_speed : float = 4.0
## How fast (m/s) it comes back to the feet once the player stops.
@export var lead_return_speed : float = 2.0
## Horizontal speed (m/s) below which the player counts as stopped.
@export var lead_min_speed : float = 0.5

@export_group("Vertical framing")
## How fast (m/s) the framed height reaches the floor height after landing somewhere new.
@export var height_follow_speed : float = 6.0
## How far (m) the feet can fall below the framed height before the camera follows them down.
@export var fall_threshold : float = 2.0

## Focus point on the camera plane (metres along right, up).
var focus : Vector2
## Height framed instead of the feet height: jumps don't move the camera.
var reference_height : float
## Fell more than fall_threshold: the reference height follows the feet until landing.
var _falling : bool = false
## Offset (world X/Z) of the framed point from the feet: the look-ahead.
var lead : Vector3 = Vector3.ZERO
var _last_feet : Vector3

var _right : Vector3
var _up : Vector3
var _back : Vector3

func _ready() -> void:
	# Run after the player has moved this tick
	process_physics_priority = 100
	if camera == null:
		for child in get_children():
			if child is Camera3D:
				camera = child
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if follow_curve == null:
		follow_curve = Curve.new()
		# Ease-in that still starts with some slope, so the camera settles on the
		# inner edge instead of creeping towards it for seconds
		follow_curve.add_point(Vector2(0, 0), 0.0, 0.5)
		follow_curve.add_point(Vector2(1, 1), 1.5, 0.0)
	var b := global_transform.basis.orthonormalized()
	_right = b.x
	_up = b.y
	_back = b.z
	if target:
		# Level start
		snap()
		if target.has_signal(&"respawned"):
			target.connect(&"respawned", snap)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var feet := target.global_position
	_update_reference_height(feet.y, delta)
	_update_lead(feet, delta)
	var framed := Vector3(feet.x + lead.x, reference_height, feet.z + lead.z)
	_follow(_to_plane(framed), _to_plane(feet), delta)
	_apply()

## Puts the focus on the target at once (level start, respawn).
func snap() -> void:
	focus = _to_plane(target.global_position)
	reference_height = target.global_position.y
	_falling = false
	lead = Vector3.ZERO
	_last_feet = target.global_position
	_apply()

## Visible area of the camera in metres (width, height).
func view_size() -> Vector2:
	var viewport := get_viewport().get_visible_rect().size
	var aspect := viewport.x / viewport.y if viewport.y > 0.0 else 1.0
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return Vector2(camera.size, camera.size / aspect)
	return Vector2(camera.size * aspect, camera.size)

## Where the feet are relative to the screen centre, in metres on the camera plane.
func screen_offset(world_point: Vector3) -> Vector2:
	return _to_plane(world_point) - _center()

## Moves the lead towards max_lead in the movement direction, or back to zero when the
## player stands still (or only moves vertically).
func _update_lead(feet: Vector3, delta: float) -> void:
	var velocity : Vector3
	if target is CharacterBody3D:
		velocity = target.velocity
	elif delta > 0.0:
		velocity = (feet - _last_feet) / delta
	_last_feet = feet
	velocity.y = 0.0
	if velocity.length() > lead_min_speed:
		lead = lead.move_toward(velocity.normalized() * max_lead, lead_speed * delta)
	else:
		lead = lead.move_toward(Vector3.ZERO, lead_return_speed * delta)

## On the floor it moves to the feet height; in the air it stays (jumps), unless the
## feet fall more than fall_threshold below it.
func _update_reference_height(feet_height: float, delta: float) -> void:
	if _is_grounded():
		reference_height = move_toward(reference_height, feet_height, height_follow_speed * delta)
	elif feet_height < reference_height - fall_threshold or _falling:
		# A real fall: frame the feet themselves until landing. The camera speed is
		# limited, so this catches up smoothly instead of jumping.
		_falling = true
		reference_height = feet_height
	if _is_grounded():
		_falling = false

func _is_grounded() -> bool:
	if target.has_method(&"is_grounded"):
		return target.is_grounded()
	if target is CharacterBody3D:
		return target.is_on_floor()
	return true

## framed: the feet at the reference height, for the smooth follow.
## feet: the real feet, for the wall, so even a jump can't leave the outer rectangle.
func _follow(framed: Vector2, feet: Vector2, delta: float) -> void:
	var half_inner := inner_rect * view_size() * 0.5
	var half_outer := outer_rect * view_size() * 0.5
	var center := _center()
	for axis in 2:
		# Smooth follow: speed by how far past the inner edge
		var rel := framed[axis] - center[axis]
		var excess := absf(rel) - half_inner[axis]
		if excess > 0.0:
			var gap := maxf(half_outer[axis] - half_inner[axis], 0.001)
			var speed := max_follow_speed * follow_curve.sample(clampf(excess / gap, 0.0, 1.0))
			center[axis] += signf(rel) * minf(speed * delta, excess)
		# Wall: never let the feet past the outer edge
		rel = feet[axis] - center[axis]
		if absf(rel) > half_outer[axis]:
			center[axis] += signf(rel) * (absf(rel) - half_outer[axis])
	focus = center - _plane_offset()

## Screen centre on the camera plane: where the camera is.
func _center() -> Vector2:
	return focus + _plane_offset()

## The offset seen on the camera plane (almost zero when it points along the view axis).
func _plane_offset() -> Vector2:
	return _to_plane(offset)

func _to_plane(p: Vector3) -> Vector2:
	return Vector2(p.dot(_right), p.dot(_up))

func _apply() -> void:
	var center := _center()
	# A point with that screen position, then slid along the view axis (which doesn't
	# change the image) to the camera height
	var pos := _right * center.x + _up * center.y
	if absf(_back.y) > 0.001:
		pos += _back * ((reference_height + offset.y - pos.y) / _back.y)
	global_position = pos
