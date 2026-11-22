extends CharacterBody3D

## Emitted when health reaches 0 from live damage (D22). The player respawns right after.
signal died
## Placed back at the checkpoint (or spawn) after dying: followers should jump there, not slide.
signal respawned

## Health at spawn and after a respawn.
@export var max_health : int = 3

## Top horizontal speed, in meters per second (reached with the stick fully pushed).
@export var max_speed : float = 6.0
## How fast speed builds up while there is input, in m/s^2.
@export var acceleration : float = 30.0
## How fast speed drops to zero when there is no input, in m/s^2.
@export var deceleration : float = 50.0
## Max angle (degrees) between the velocity and the input for the velocity to snap onto
## the input direction. Beyond it, the player brakes with turn_deceleration first.
@export_range(0.0, 180.0, 1.0) var snap_angle : float = 50.0
## How fast speed drops, in m/s^2, while the input is outside snap_angle of the velocity.
@export var turn_deceleration : float = 80.0
## Multiplier on acceleration and turn_deceleration while airborne (1 = same as on the
## ground, lower = slower to change direction mid-jump, 0 = no steering in the air).
@export_range(0.0, 1.0, 0.01) var air_control : float = 0.4
## How quickly the player turns to face the movement direction (higher = snappier).
@export var turn_speed : float = 15.0

## Height reached at the peak of a full (button held) jump, in meters.
@export var jump_height : float = 2.0
## Seconds from takeoff to the peak of the jump.
@export var jump_time_to_peak : float = 0.4
## Gravity multiplier while falling (1.0 = symmetric to the ascent).
@export var fall_gravity_multiplier : float = 1.5
## Gravity multiplier while rising with the jump button released (shorter jump).
@export var jump_cut_gravity_multiplier : float = 3.0
## Seconds a jump press is remembered before landing.
@export var jump_buffer_window : float = 0.1
## Seconds after leaving a ledge during which a jump is still allowed.
@export var coyote_window : float = 0.1

# Derived from jump_height and jump_time_to_peak:
#   h = g * t^2 / 2  =>  g = 2h / t^2
#   v = g * t        =>  v = 2h / t
var jump_gravity : float
var jump_velocity : float

var jump_buffer_timer : float = 0.0
var coyote_timer : float = 0.0

var health : int
# Where to respawn when no checkpoint has been reached
var _spawn_transform : Transform3D

# is_on_floor() is only updated by move_and_slide(), which doesn't run during a rewind.
# After a rewind, the first tick reads the recorded floor flag instead of the stale one.
var _floor_restored : bool = false
var _restored_on_floor : bool = false

# Optional: without it the player can't record (the ability may come from an item later)
@onready var _rewind_ability := get_node_or_null("RewindAbility") as RewindAbility
@onready var _attack := get_node_or_null("PlayerAttack") as PlayerAttack
@onready var _interact_sensor := get_node_or_null("InteractSensor") as InteractSensor
@onready var _animator := get_node_or_null("PlayerAnimator") as PlayerAnimator

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	jump_gravity = 2.0 * jump_height / (jump_time_to_peak * jump_time_to_peak)
	jump_velocity = 2.0 * jump_height / jump_time_to_peak
	health = max_health
	_spawn_transform = global_transform

func _input(event):
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	# Get inputs
	var input_jump := Input.is_action_just_pressed("jump")
	var input_move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_dir := _camera_relative(input_move)
	var on_floor := _restored_on_floor if _floor_restored else is_on_floor()
	_floor_restored = false

	# Start a record, or stop the running one early (refused while a rewind, phantom or
	# cooldown runs)
	if _rewind_ability and Input.is_action_just_pressed("record"):
		_rewind_ability.try_use()

	# Interact with whatever is in reach. The press is recorded even if nothing is there:
	# the phantom presses on the same tick and gets whatever is in reach then.
	if _interact_sensor and Input.is_action_just_pressed("interact"):
		_interact_sensor.interact(self)
		RecordManager.record_event({"type": &"interact"})

	# Charge and shoot the attack
	if _attack:
		_attack.update(delta)

	# Update jump buffer (a press is remembered, even if it happens on the floor)
	jump_buffer_timer -= delta
	if input_jump:
		jump_buffer_timer = jump_buffer_window

	# Update coyote time (refilled while grounded, drains once in the air)
	if on_floor:
		coyote_timer = coyote_window
	else:
		coyote_timer -= delta

	# Jump if there is a pending press and we are on the floor or within coyote time
	var jumped := jump_buffer_timer > 0.0 and coyote_timer > 0.0
	if jumped:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0 # consume it so the jump can't be repeated in mid-air

		# Launch toward the input: rotate the horizontal velocity onto it, keeping the speed
		if move_dir != Vector2.ZERO:
			var launch_velocity := move_dir.normalized() * Vector2(velocity.x, velocity.z).length()
			velocity.x = launch_velocity.x
			velocity.z = launch_velocity.y

	# Split gravity: rising, rising with button released (jump cut), falling
	var gravity := jump_gravity
	if velocity.y < 0.0:
		gravity *= fall_gravity_multiplier
	elif not Input.is_action_pressed("jump"):
		gravity *= jump_cut_gravity_multiplier
	velocity.y -= gravity * delta

	# Horizontal movement. The input is scaled by its magnitude, so an analog stick
	# controls the speed.
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if move_dir == Vector2.ZERO:
		# No input: brake to a stop
		horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, deceleration * delta)
	else:
		# Steering is scaled down in the air, so direction changes are slower mid-jump
		var control := 1.0 if on_floor else air_control
		var current_speed := horizontal_velocity.length()
		var aligned := current_speed < 0.01 \
			or absf(horizontal_velocity.angle_to(move_dir)) <= deg_to_rad(snap_angle)
		if aligned:
			# Input is close to the current direction: snap the velocity onto it (keeping
			# the speed) and accelerate, so changes of direction don't feel slippery
			horizontal_velocity = horizontal_velocity.move_toward(move_dir * max_speed, acceleration * control * delta)
		else:
			# Input is far from the current direction: brake until it is within snap_angle
			horizontal_velocity = horizontal_velocity.move_toward(move_dir * max_speed, turn_deceleration * control * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	# Face the direction of the input, keeping the last facing when there is none
	if move_dir != Vector2.ZERO:
		var target_yaw := atan2(-move_dir.x, -move_dir.y) # -Z is forward
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	move_and_slide()

	if _animator:
		var charging := _attack != null and _attack.charge_time >= 0.0
		var attacked := _attack != null and _attack.just_shot
		_animator.update(delta, is_on_floor(), velocity, jumped, max_speed, charging, attacked)

## Standing on the floor. Also right during and after a rewind, when is_on_floor() is stale.
func is_grounded() -> bool:
	return _restored_on_floor if _floor_restored else is_on_floor()

func take_damage(amount: int) -> void:
	# During a rewind the player is placed at recorded states, and may pass through
	# hazards: that is not live damage (D22)
	if health <= 0 or RecordManager.is_rewinding():
		return
	health = maxi(health - amount, 0)
	if health == 0:
		died.emit()
		# Deferred: damage usually arrives from a physics callback
		_respawn.call_deferred()

func _respawn() -> void:
	global_transform = GameState.checkpoint_transform if GameState.has_checkpoint else _spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	if _attack:
		_attack.charge_time = -1.0
	reset_physics_interpolation()
	respawned.emit()

# Record & rewind hooks (see Recordable). The transform and velocity are recorded by the
# Recordable itself; this is the rest of the state the next tick depends on.
func _record_state() -> Dictionary:
	return {
		"jump_buffer_timer": jump_buffer_timer,
		"coyote_timer": coyote_timer,
		"on_floor": is_on_floor(),
		"attack_charge": _attack.charge_time if _attack else -1.0,
		"health": health,
		"anim": _animator.get_anim_state() if _animator else {},
	}

func _apply_state(state: Dictionary) -> void:
	jump_buffer_timer = state.jump_buffer_timer
	coyote_timer = state.coyote_timer
	_restored_on_floor = state.on_floor
	_floor_restored = true
	health = state.health
	if _attack:
		_attack.charge_time = state.attack_charge
	if _animator:
		_animator.apply_anim_state(state.anim)

# Converts a stick/keys input (x = right, y = down) into a horizontal world direction
# (x, z) relative to where the active camera is looking. The camera axes are flattened
# onto the ground so looking down or up doesn't change the speed.
func _camera_relative(input: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null or input == Vector2.ZERO:
		return input

	var cam_basis := camera.global_transform.basis
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	if forward.is_zero_approx(): # looking straight up/down: use the camera's up instead
		forward = Vector3(cam_basis.y.x, 0.0, cam_basis.y.z)
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x) # forward x up

	var world_dir := right * input.x + forward * -input.y
	return Vector2(world_dir.x, world_dir.z)
