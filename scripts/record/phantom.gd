extends Node3D
## Plays back the player's tape, driven by RecordManager. It has no collision with the
## world, so it can't be blocked, pushed or hurt. Its Sensor area (groups "phantom" and
## "actor") is what puzzle elements detect.

## Material applied to every mesh of the model. Its albedo alpha is the phantom's opacity.
@export var material : StandardMaterial3D
## Seconds of the fade in and the fade out.
@export var fade_time : float = 0.25

@onready var _sensor : Area3D = $Sensor
@onready var _interact_sensor : InteractSensor = $InteractSensor
@onready var _animation_player : AnimationPlayer = $Model/AnimationPlayer
@onready var _skeleton := PlayerAnimator.find_skeleton(_animation_player)

var _material : StandardMaterial3D
var _alpha : float
var _placed : bool = false
## Warm-up copy (see warm_up): never seen, never detected.
var _warming : bool = false

func _ready() -> void:
	# Driven only by the recorded animation states
	_animation_player.speed_scale = 0.0
	# Own copy, so fading this phantom doesn't affect the shared resource
	_material = material.duplicate()
	_alpha = _material.albedo_color.a
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _material
	if _warming:
		return
	_fade(0.0, _alpha)

## Turns this instance into a warm-up copy, before it enters the tree. The first time
## the phantom's look (a transparent material on a skinned mesh) is drawn, the GPU
## compiles its shaders, which shows as a hiccup when the first phantom appears. A
## warm-up copy is drawn for `frames` frames at the start of the level, nearly fully
## transparent and undetectable, then freed, so that compile happens during loading.
func warm_up(frames: int = 3) -> void:
	_warming = true
	# Not detected by plates, scales or anything else
	$Sensor.collision_layer = 0
	$Sensor.monitorable = false
	ready.connect(func() -> void:
		var color := _material.albedo_color
		# Not 0: a fully transparent draw could be skipped, and nothing would compile
		color.a = 0.01
		_material.albedo_color = color
		for i in frames:
			await get_tree().process_frame
		queue_free())

## Places the phantom at a recorded transform, with the animation recorded in `state`
## (the player's _record_state()).
func show_frame(frame_transform: Transform3D, state: Dictionary) -> void:
	global_transform = frame_transform
	# Godot sends a moved area's transform to the physics server at the end of the tick.
	# Send it now, so shape queries made this tick (the scale's occupancy) find the phantom
	# where it is shown, as they find the player's body right after it moves.
	PhysicsServer3D.area_set_transform(_sensor.get_rid(), _sensor.global_transform)
	var anim : Dictionary = state.get("anim", {})
	if anim.has("animation"):
		PlayerAnimator.show_animation(_animation_player, _skeleton, anim.animation, anim.position)
	if not _placed:
		# Don't interpolate from wherever it was spawned
		_placed = true
		reset_physics_interpolation()

## Performs a recorded action (see RecordManager.record_event). Like the original, it only
## has an effect if something is there: a lever in reach, an enemy in the shot's path.
func perform(event: Dictionary) -> void:
	match event.type:
		&"interact":
			_interact_sensor.interact(self)
		&"shoot":
			PlayerAttack.spawn_projectile(event.shot, self)

## Ends the playback: stops interacting, fades out and frees itself.
func finish() -> void:
	_sensor.set_deferred("monitorable", false)
	_fade(_alpha, 0.0).finished.connect(queue_free)

func _fade(from: float, to: float) -> Tween:
	var color := _material.albedo_color
	color.a = from
	_material.albedo_color = color
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color:a", to, fade_time)
	return tween
