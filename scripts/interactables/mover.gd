class_name Mover
extends AnimatableBody3D
## Shared activable for doors and moving platforms (misc/Interactables.md, I11). Moves
## between pose A (where it is placed) and pose B (A plus an offset and/or a rotation),
## driven by its keys. As an AnimatableBody3D it carries and pushes the player (I12).
## The physics engine only carries a rider's position; when the mover turns around the
## vertical axis, it also turns the characters standing on it by the same angle, so they
## keep facing the same way relative to it.
##
##   TOGGLE      each time the input turns on, the target switches between A and B;
##               mid-trip it turns around (I13)
##   HOLD        input on: go to B. Input off: wait return_delay, then back to A.
##               Turning on during the delay cancels it
##   PING_PONG   input on: back and forth between A and B. Input off: stop where it is;
##               turned on again, it keeps its direction (I14)
##
## Input: all keys on (I2). No keys = always on. Keys are read every physics tick.
## Its state is recorded (Recordable child with record_velocity), so a rewind puts it
## exactly where it was, and doesn't count a restored key as a new "on" (last input).

enum Mode { TOGGLE, HOLD, PING_PONG }

@export var mode : Mode = Mode.HOLD
## Keys that drive it; all must be on (I2). Empty = always on.
@export var keys : Array[PuzzleKey] = []

@export_group("Pose B")
## Position of pose B relative to pose A, along the body's own axes (as placed), so a
## rotated door still slides along itself.
@export var offset : Vector3 = Vector3(0, 2, 0)
## Rotation of pose B relative to pose A, in degrees, around the body's own axes and
## origin (hinged doors: put the hinge at the origin).
@export var rotation_offset : Vector3 = Vector3.ZERO

@export_group("Timing")
## Seconds for a full trip from A to B.
@export var move_time : float = 1.0
## Seconds for a full trip from B to A.
@export var return_time : float = 1.0
## HOLD: seconds to wait at B after the input turns off, before returning.
@export var return_delay : float = 0.0
## Ease in and out at the ends of each trip.
@export var smooth : bool = true

## 0 = pose A, 1 = pose B.
var progress : float = 0.0
## Where it is going: 0 (A) or 1 (B). Used by TOGGLE and HOLD.
var target_progress : float = 0.0
## PING_PONG: +1 towards B, -1 towards A.
var direction : int = 1
## HOLD: seconds left before returning to A.
var delay_left : float = 0.0
## Input on the previous tick, to detect when it turns on (TOGGLE).
var last_input : bool = false

var _pose_a : Transform3D

func _ready() -> void:
	_pose_a = transform
	last_input = _read_input()
	_update_transform()

func _physics_process(delta: float) -> void:
	var yaw_before := _yaw_of(_pose().basis)
	var input := _read_input()
	var turned_on := input and not last_input
	last_input = input

	match mode:
		Mode.TOGGLE:
			if turned_on:
				target_progress = 1.0 - target_progress
			_move_to_target(delta)
		Mode.HOLD:
			if input:
				target_progress = 1.0
				delay_left = return_delay
			elif delay_left > 0.0:
				delay_left -= delta
			else:
				target_progress = 0.0
			_move_to_target(delta)
		Mode.PING_PONG:
			if input:
				_ping_pong(delta)
	_update_transform()
	_turn_riders(angle_difference(yaw_before, _yaw_of(_pose().basis)))

## Turns the characters standing on the mover by its turn around the vertical axis
## this tick. Only the yaw: riders stay upright whatever the mover's tilt.
## The turn is computed from the poses, not read back from the node: with sync_to_physics
## the node reports its new transform only after the physics sync.
func _turn_riders(yaw: float) -> void:
	if is_zero_approx(yaw):
		return
	for actor in get_tree().get_nodes_in_group(&"actor"):
		if actor is CharacterBody3D and _is_standing_on_me(actor):
			actor.rotate_y(yaw)

# Heading of the basis' forward axis on the ground plane (in world space)
func _yaw_of(local_basis: Basis) -> float:
	var parent := get_parent_node_3d()
	var b := parent.global_basis * local_basis if parent else local_basis
	var forward := b * Vector3.FORWARD
	return atan2(-forward.x, -forward.z)

func _is_standing_on_me(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	for i in body.get_slide_collision_count():
		if body.get_slide_collision(i).get_collider() == self:
			return true
	return false

## True when all keys are on, or there are no keys.
func _read_input() -> bool:
	for key in keys:
		if key == null or not key.on:
			return false
	return true

func _move_to_target(delta: float) -> void:
	if target_progress > progress:
		progress = minf(progress + delta / maxf(move_time, 0.001), target_progress)
	elif target_progress < progress:
		progress = maxf(progress - delta / maxf(return_time, 0.001), target_progress)

func _ping_pong(delta: float) -> void:
	var trip_time := move_time if direction > 0 else return_time
	progress += direction * delta / maxf(trip_time, 0.001)
	if progress >= 1.0:
		progress = 1.0
		direction = -1
	elif progress <= 0.0:
		progress = 0.0
		direction = 1

func _update_transform() -> void:
	transform = _pose()

## The local transform at the current progress.
func _pose() -> Transform3D:
	var t := progress
	if smooth:
		t = (1.0 - cos(PI * t)) * 0.5
	var rotation_b := Basis.from_euler(rotation_offset * (PI / 180.0) * t)
	var along := _pose_a.basis.orthonormalized() * offset
	return Transform3D(_pose_a.basis * rotation_b, _pose_a.origin + along * t)

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {
		"progress": progress,
		"target_progress": target_progress,
		"direction": direction,
		"delay_left": delay_left,
		"last_input": last_input,
	}

func _apply_state(state: Dictionary) -> void:
	progress = state.progress
	target_progress = state.target_progress
	direction = state.direction
	delay_left = state.delay_left
	last_input = state.last_input
	_update_transform()
