class_name Recordable
extends Node
## Makes its parent Node3D rewindable. Add it as a child of the object to record.
## RecordManager calls capture() every tick while recording and apply() every tick
## while rewinding. See misc/RecordMechanic.md.
##
## State that is not a transform or a velocity (timers, flags, AI state...) is recorded
## through two optional methods on the target:
##   func _record_state() -> Dictionary      # called on every capture
##   func _apply_state(state: Dictionary)    # called on every apply
##
## A RigidBody3D target is frozen during the rewind and gets its frame 0 velocities back
## when released (record_velocity also records its angular velocity and sleep state).
## An AnimatableBody3D target with record_transform and record_velocity ends the rewind
## moving at its frame 0 velocity, so characters standing on it are carried correctly.
##
## Spawning and destroying during a record: an object that enters the tree mid-record is
## hidden when the rewind passes its spawn, and freed for good at the end of the rewind.
## Destroy recordable objects with Recordable.despawn(node) instead of queue_free(): during
## a record it only deactivates the object, so the rewind can bring it back.

## Record the parent's global transform (position, rotation and scale).
@export var record_transform : bool = true
## Record the parent's velocity (CharacterBody3D.velocity or RigidBody3D.linear_velocity).
@export var record_velocity : bool = false

## The object being recorded.
@onready var target : Node3D = get_parent()

# One entry per frame, packed: 12 floats per transform, 3 floats per velocity
var _transforms : PackedFloat32Array
var _velocities : PackedFloat32Array
# RigidBody3D only: 3 floats of angular velocity and 1 byte of sleep state per frame
var _angular_velocities : PackedFloat32Array
var _sleeping : PackedByteArray
# Per-frame Dictionaries from the target's _record_state(), if it has one
var _states : Array[Dictionary] = []
var _has_state_hooks : bool = false
var _frames_written : int = 0

# Rewind: the target is held at recorded states, and the last frame applied
var _held : bool = false
var _last_applied_frame : int = 0
# RigidBody3D freeze settings to put back on release
var _was_frozen : bool = false
var _freeze_mode : RigidBody3D.FreezeMode

# Lifetime within the current record: the object exists for spawn_frame <= frame <
# despawn_frame (-1: not despawned). 0 for anything that existed when the record started.
var _spawn_frame : int = 0
var _despawn_frame : int = -1
var _active : bool = true
var _active_process_mode : ProcessMode

func _ready() -> void:
	_has_state_hooks = target.has_method(&"_record_state") and target.has_method(&"_apply_state")
	if RecordManager.state == RecordManager.State.RECORDING:
		# Spawned mid-record, during the tick after frame frames_recorded - 1 was captured:
		# its first frame is the next one
		_allocate_buffers()
		_spawn_frame = RecordManager.frames_recorded

## Removes `node`: during a record, if it has a Recordable, it is only deactivated, so a
## rewind can bring it back. Otherwise it is freed.
static func despawn(node: Node) -> void:
	var recordable := find(node)
	if recordable and RecordManager.state == RecordManager.State.RECORDING:
		recordable._despawn_frame = RecordManager.frames_recorded
		# Deferred: despawns usually come from physics callbacks, where bodies can't be
		# removed from the physics space. It still happens before the next capture.
		recordable._set_active.call_deferred(false)
	else:
		node.queue_free()

## The Recordable child of `node`, or null.
static func find(node: Node) -> Recordable:
	for child in node.get_children():
		if child is Recordable:
			return child
	return null

func _enter_tree() -> void:
	RecordManager.register(self)
	RecordManager.state_changed.connect(_on_state_changed)
	RecordManager.rewind_finished.connect(_on_rewind_finished)

func _exit_tree() -> void:
	RecordManager.unregister(self)
	RecordManager.state_changed.disconnect(_on_state_changed)
	RecordManager.rewind_finished.disconnect(_on_rewind_finished)

## Writes the target's current state into frame `frame`.
func capture(frame: int) -> void:
	if not _active:
		return
	if record_transform:
		var t := target.global_transform
		var i := frame * 12
		for axis in 3:
			_transforms[i + axis * 3] = t.basis[axis].x
			_transforms[i + axis * 3 + 1] = t.basis[axis].y
			_transforms[i + axis * 3 + 2] = t.basis[axis].z
		_transforms[i + 9] = t.origin.x
		_transforms[i + 10] = t.origin.y
		_transforms[i + 11] = t.origin.z
	if record_velocity:
		_write_vector(_velocities, frame, _get_velocity())
		if target is RigidBody3D:
			_write_vector(_angular_velocities, frame, target.angular_velocity)
			_sleeping[frame] = 1 if target.sleeping else 0
	if _has_state_hooks:
		_states[frame] = target._record_state()
	_frames_written = maxi(_frames_written, frame + 1)

## Restores frame `frame` onto the target. Frames outside the record are clamped.
## approach: the next apply is the last one of the rewind (see RecordManager._rewind_tick).
func apply(frame: int, approach: bool = false) -> void:
	# Hidden outside its lifetime: before it spawned, or after it was despawned
	var alive := frame >= _spawn_frame and (_despawn_frame < 0 or frame < _despawn_frame)
	_set_active(alive)
	if not alive or _frames_written == 0:
		return
	frame = clampi(frame, _spawn_frame, _frames_written - 1)
	_last_applied_frame = frame
	if record_transform:
		target.global_transform = _read_transform(frame)
	# A frozen rigid body ignores velocities: they are set when it is released
	if record_velocity and not target is RigidBody3D:
		_set_velocity(_read_vector(_velocities, frame))
	if _has_state_hooks:
		target._apply_state(_states[frame])
	if approach and target is AnimatableBody3D and record_transform and record_velocity:
		# One tick back along the recorded velocity: the final apply then moves it into
		# this frame at exactly that velocity, instead of the rewind's backwards motion
		var t := _read_transform(frame)
		t.origin -= _read_vector(_velocities, frame) / Engine.physics_ticks_per_second
		target.global_transform = t

## The recorded transforms, from frame 0. Used to build the phantom's tape.
func get_transforms() -> Array[Transform3D]:
	var result : Array[Transform3D] = []
	if record_transform:
		for frame in _frames_written:
			result.append(_read_transform(frame))
	return result

## The recorded _record_state() Dictionaries, from frame 0. Used to animate the phantom.
func get_states() -> Array[Dictionary]:
	return _states.slice(0, _frames_written)

func _read_transform(frame: int) -> Transform3D:
	var i := frame * 12
	var b := _transforms
	return Transform3D(
		Vector3(b[i], b[i + 1], b[i + 2]),
		Vector3(b[i + 3], b[i + 4], b[i + 5]),
		Vector3(b[i + 6], b[i + 7], b[i + 8]),
		Vector3(b[i + 9], b[i + 10], b[i + 11]))

func _on_state_changed(old_state: RecordManager.State, new_state: RecordManager.State) -> void:
	match new_state:
		RecordManager.State.RECORDING:
			_allocate_buffers()
		RecordManager.State.REWINDING:
			_hold_target()
		RecordManager.State.IDLE:
			# Cancelled record: nothing is undone, so what was despawned goes for good
			if not _active:
				target.queue_free()

	if old_state == RecordManager.State.REWINDING:
		# Rigid bodies are released here, at the top of the first REPLAY tick (or on a
		# reset mid-rewind). Others were already released by rewind_finished.
		_release_target()

	if new_state == RecordManager.State.IDLE or old_state == RecordManager.State.REWINDING:
		# Release the buffers once the rewind is done (or the record was cancelled)
		_transforms = PackedFloat32Array()
		_velocities = PackedFloat32Array()
		_angular_velocities = PackedFloat32Array()
		_sleeping = PackedByteArray()
		_states.clear()
		_frames_written = 0
		_spawn_frame = 0
		_despawn_frame = -1

# Buffers only exist during a record
func _allocate_buffers() -> void:
	var frames := RecordManager.RECORD_FRAMES
	var rigid := record_velocity and target is RigidBody3D
	_transforms.resize(frames * 12 if record_transform else 0)
	_velocities.resize(frames * 3 if record_velocity else 0)
	_angular_velocities.resize(frames * 3 if rigid else 0)
	_sleeping.resize(frames if rigid else 0)
	_states.resize(frames if _has_state_hooks else 0)
	_frames_written = 0

# Hides the target and takes it out of processing and physics (a disabled
# CollisionObject3D is removed from the physics space), or puts it back
func _set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	target.visible = active
	if active:
		target.process_mode = _active_process_mode
	else:
		_active_process_mode = target.process_mode
		target.process_mode = Node.PROCESS_MODE_DISABLED

# Nodes re-enabled during a tick only process from the next tick, the first REPLAY tick,
# so scripted targets are released now. A rigid body would instead be stepped by the
# physics engine at the end of this very tick, one step ahead of the world: it waits for
# the REPLAY state change.
func _on_rewind_finished() -> void:
	if _spawn_frame > 0:
		# Didn't exist at frame 0: it is gone for good
		target.queue_free()
	elif not target is RigidBody3D:
		_release_target()

# Recorded states are applied from now on: the target must not simulate
func _hold_target() -> void:
	_held = true
	target.set_physics_process(false)
	if target is RigidBody3D:
		var body : RigidBody3D = target
		_was_frozen = body.freeze
		_freeze_mode = body.freeze_mode
		# Static, not kinematic: placing a kinematic body moves it with a velocity that
		# pushes others, while a static one just teleports to the recorded transform
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	target.reset_physics_interpolation()

# The target is at the last applied frame (frame 0 after a full rewind): simulate from there
func _release_target() -> void:
	if not _held:
		return
	_held = false
	target.set_physics_process(true)
	if target is RigidBody3D:
		var body : RigidBody3D = target
		body.freeze = _was_frozen
		body.freeze_mode = _freeze_mode
		if record_velocity and _frames_written > 0:
			body.linear_velocity = _read_vector(_velocities, _last_applied_frame)
			body.angular_velocity = _read_vector(_angular_velocities, _last_applied_frame)
			body.sleeping = _sleeping[_last_applied_frame] == 1
	target.reset_physics_interpolation()

func _get_velocity() -> Vector3:
	if target is CharacterBody3D:
		return target.velocity
	if target is RigidBody3D:
		return target.linear_velocity
	if target is AnimatableBody3D:
		# The velocity the physics engine gave it on its last move
		return PhysicsServer3D.body_get_direct_state(target.get_rid()).linear_velocity
	return Vector3.ZERO

func _set_velocity(v: Vector3) -> void:
	if target is CharacterBody3D:
		target.velocity = v
	elif target is RigidBody3D:
		target.linear_velocity = v

static func _write_vector(buffer: PackedFloat32Array, frame: int, v: Vector3) -> void:
	buffer[frame * 3] = v.x
	buffer[frame * 3 + 1] = v.y
	buffer[frame * 3 + 2] = v.z

static func _read_vector(buffer: PackedFloat32Array, frame: int) -> Vector3:
	return Vector3(buffer[frame * 3], buffer[frame * 3 + 1], buffer[frame * 3 + 2])
