class_name PlayerAnimator
extends Node
## Picks the player's animation from its movement. Driven by the player's
## _physics_process (update()), after move_and_slide().
##
##   standing still       idle animation, looping; after fun_idle_cooldown seconds of
##                        it, one of the fun idle animations once, then idle again
##   running              run animation, looping
##   jump pressed         anticipation pose, for anticipation_time
##   going up             rising pose
##   going down           falling animation, looping
##   touching the floor   landing pose, for landing_time
##   standing, charging   charge pose, while the attack button is held
##   shooting             attack pose, for attack_time, whatever the movement (standing,
##                        running, jumping, falling), shown at once (no crossfade).
##                        A jump cuts it short.

## The model's AnimationPlayer.
@export var animation_player : AnimationPlayer

@export_group("Animations")
@export var idle_animation : StringName = &"Anim_IDLE_1"
@export var run_animation : StringName = &"Anim_Correr"
@export var anticipation_animation : StringName = &"Anim_SaltoAnticipacion"
@export var rise_animation : StringName = &"Anim_SaltoMidSt"
@export var fall_animation : StringName = &"Anim_SaltoCaida"
@export var land_animation : StringName = &"Anim_SaltoMidEnd"
@export var charge_animation : StringName = &"Anim_Carga"
@export var attack_animation : StringName = &"Anim_Ataque"
## Played once, picked at random, after standing idle for fun_idle_cooldown seconds.
@export var fun_idle_animations : Array[StringName] = [&"Anim_IDLE_2", &"Anim_IDLE_3", &"Anim_IDLE_4"]

@export_group("Timing")
## Seconds the anticipation pose is shown after the jump is pressed.
@export var anticipation_time : float = 0.06
## Seconds the landing pose is shown after touching the floor.
@export var landing_time : float = 0.1
## Seconds the attack pose is shown after a shot.
@export var attack_time : float = 0.25
## Seconds of standing idle before a fun idle animation plays (0 = never). Counted again
## from zero after each one.
@export var fun_idle_cooldown : float = 10.0
## Seconds of crossfade between animations (0 = instant).
@export var blend_time : float = 0.05

@export_group("Running")
## Horizontal speed (m/s) above which the player counts as running.
@export var run_threshold : float = 0.1
## Play the run animation slower when moving slower (analog stick), relative to max speed.
@export var scale_run_with_speed : bool = true
## Slowest run animation speed when scaling with speed.
@export var min_run_speed_scale : float = 0.4

# New poses go at the end: the pose is recorded as a number
enum Pose { NONE, RUN, ANTICIPATION, RISE, FALL, LAND, CHARGE, ATTACK, FUN_IDLE }

var pose : Pose = Pose.NONE
## Seconds spent in the current pose.
var pose_time : float = 0.0
## Left the floor since the last landing: the landing pose is due, even if the attack
## pose was showing in the air.
var airborne : bool = false

var _skeleton : Skeleton3D
var _rng := RandomNumberGenerator.new()
## The fun idle animation playing (or last played, so the next one is a different one).
var _fun_idle : StringName

func _ready() -> void:
	_skeleton = find_skeleton(animation_player)
	# The imported animations don't loop. The charge and attack poses are one frame long:
	# looping keeps them playing, so they are recorded (a stopped player records nothing)
	for looping in [idle_animation, run_animation, fall_animation, charge_animation, attack_animation]:
		animation_player.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	animation_player.play(idle_animation, blend_time)
	animation_player.animation_finished.connect(_on_animation_finished)

# A fun idle ends inside the AnimationPlayer's own step, before the next update(): go back
# to the idle loop right there, or the next tick would record a stopped player
func _on_animation_finished(animation: StringName) -> void:
	if pose == Pose.FUN_IDLE and animation == _fun_idle:
		_set_pose(Pose.NONE)

## Call once per physics tick, after move_and_slide().
## jumped: a jump started this tick. max_speed: the player's top horizontal speed.
## charging: the attack button is held. attacked: a shot was fired this tick.
func update(delta: float, on_floor: bool, velocity: Vector3, jumped: bool, max_speed: float,
		charging: bool = false, attacked: bool = false) -> void:
	pose_time += delta
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if not on_floor:
		airborne = true
	var next := pose
	if attacked:
		next = Pose.ATTACK
		# Shown again from the start, even if the previous attack pose is still showing
		pose = Pose.NONE
	elif pose == Pose.ATTACK and pose_time < attack_time and not jumped:
		pass
	elif jumped:
		next = Pose.ANTICIPATION
	elif not on_floor:
		if pose != Pose.ANTICIPATION or pose_time >= anticipation_time:
			next = Pose.RISE if velocity.y > 0.0 else Pose.FALL
	elif airborne:
		airborne = false
		next = Pose.LAND
	elif pose != Pose.LAND or pose_time >= landing_time:
		if horizontal_speed > run_threshold:
			next = Pose.RUN
		elif charging:
			next = Pose.CHARGE
		else:
			next = _idle_pose()
	_set_pose(next)

	if pose == Pose.RUN and scale_run_with_speed and max_speed > 0.0:
		animation_player.speed_scale = clampf(horizontal_speed / max_speed, min_run_speed_scale, 1.0)
	else:
		animation_player.speed_scale = 1.0

## What is shown now: recorded with the player's state, and played by the phantom.
func get_anim_state() -> Dictionary:
	var playing := animation_player.is_playing()
	return {
		"pose": pose,
		"pose_time": pose_time,
		"airborne": airborne,
		"fun_idle": _fun_idle,
		"animation": animation_player.current_animation if playing else "",
		"position": animation_player.current_animation_position if playing else 0.0,
	}

## Shows a recorded state (during a rewind). The AnimationPlayer is held still, so only
## the applied states move it; the next update() lets it play again.
func apply_anim_state(state: Dictionary) -> void:
	pose = state.pose
	pose_time = state.pose_time
	airborne = state.get("airborne", false)
	_fun_idle = state.get("fun_idle", &"")
	animation_player.speed_scale = 0.0
	show_animation(animation_player, _skeleton, state.animation, state.position)

## Shows `animation` at `position` on a model, or its rest pose for an empty name.
## Shared with the phantom.
static func show_animation(player: AnimationPlayer, skeleton: Skeleton3D, animation: StringName, position: float) -> void:
	if animation.is_empty():
		player.stop()
		skeleton.reset_bone_poses()
		return
	if player.current_animation != animation:
		player.play(animation)
	player.seek(position, true)

## The Skeleton3D animated by `player`.
static func find_skeleton(player: AnimationPlayer) -> Skeleton3D:
	return player.get_node(player.root_node).find_children("*", "Skeleton3D", true, false)[0]

# Standing still: the idle loop, or a fun idle animation once in a while
func _idle_pose() -> Pose:
	if pose == Pose.FUN_IDLE and animation_player.has_animation(_fun_idle):
		# Until it has played once
		var length := animation_player.get_animation(_fun_idle).length
		var playing := animation_player.is_playing() and animation_player.current_animation == _fun_idle
		return Pose.FUN_IDLE if playing and pose_time < length else Pose.NONE
	if pose == Pose.NONE and fun_idle_cooldown > 0.0 and pose_time >= fun_idle_cooldown \
			and not fun_idle_animations.is_empty():
		var choices := fun_idle_animations.filter(func(a): return a != _fun_idle)
		if choices.is_empty():
			choices = fun_idle_animations
		_fun_idle = choices[_rng.randi() % choices.size()]
		return Pose.FUN_IDLE
	return Pose.NONE

func _set_pose(next: Pose) -> void:
	if next == pose:
		return
	pose = next
	pose_time = 0.0
	match pose:
		Pose.NONE:
			animation_player.play(idle_animation, blend_time)
		Pose.RUN:
			animation_player.play(run_animation, blend_time)
		Pose.ANTICIPATION:
			animation_player.play(anticipation_animation, blend_time)
		Pose.RISE:
			animation_player.play(rise_animation, blend_time)
		Pose.FALL:
			animation_player.play(fall_animation, blend_time)
		Pose.LAND:
			animation_player.play(land_animation, blend_time)
		Pose.CHARGE:
			animation_player.play(charge_animation, blend_time)
		Pose.FUN_IDLE:
			animation_player.play(_fun_idle, blend_time)
		Pose.ATTACK:
			# Snaps to the attack pose: no crossfade from the previous animation
			animation_player.play(attack_animation, 0.0)
