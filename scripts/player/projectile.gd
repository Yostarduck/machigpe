class_name Projectile
extends Area3D
## Flies in a straight line. On hitting a body it tells the body it was hit, pushes it if
## it is a rigid body, and is destroyed. Passing through a shot trigger (an Area3D on the
## shot_trigger layer, e.g. above a torch's pillar) also tells its owner it was hit, but
## the projectile keeps flying. It is destroyed after expire_time seconds.
##
## Telling the body (I8):
##   hit_by_attack(strength, damage)   if the body, or its parent, has it: buttons,
##                                     torches, breakable walls, which react to the
##                                     attack strength
##   take_damage(damage)               otherwise, if the body has it: player, dummy
##                                     (bodies only)

## Impulse given to a rigid body it hits, per point of damage.
@export var push_per_damage : float = 1.5

## PlayerAttack.Strength of the shot (WEAK, NORMAL, STRONG).
var strength : int = PlayerAttack.Strength.WEAK
var damage : int = 1
var velocity : Vector3 = Vector3.ZERO
var expire_time : float = 2.0

var _age : float = 0.0

## Configures the projectile. Call before adding it to the tree.
func setup(p_strength: int, p_damage: int, p_velocity: Vector3, radius: float, p_expire_time: float) -> void:
	strength = p_strength
	damage = p_damage
	velocity = p_velocity
	expire_time = p_expire_time
	# The mesh and the shape are a sphere of radius 0.5: scale them to the radius
	scale = Vector3.ONE * (radius / 0.5)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_trigger_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	# Counted in physics time, not with a Timer, so it is recorded with the state
	_age += delta
	if _age >= expire_time:
		Recordable.despawn(self)

func _on_body_entered(body: Node3D) -> void:
	# During a rewind it is placed at recorded positions: touching something then is not a hit
	if RecordManager.is_rewinding():
		return
	var receiver := find_attack_receiver(body)
	if receiver:
		receiver.hit_by_attack(strength, damage)
	elif body.has_method(&"take_damage"):
		body.take_damage(damage)
	if body is RigidBody3D:
		body.apply_central_impulse(velocity.normalized() * damage * push_per_damage)
	Recordable.despawn(self)

# A shot trigger: a hit that doesn't stop the projectile
func _on_trigger_entered(area: Area3D) -> void:
	if RecordManager.is_rewinding():
		return
	var receiver := find_attack_receiver(area)
	if receiver:
		receiver.hit_by_attack(strength, damage)

## Turns this instance into a warm-up copy, before it enters the tree. The first time
## the projectile's material is drawn, the GPU compiles its shaders, which shows as a
## hiccup on the first shot. A warm-up copy is drawn for `frames` frames at the start of
## the level, shrunk to a dot (hidden inside the player), with no collision, movement or
## recording, then freed, so that compile happens during loading.
func warm_up(frames: int = 3) -> void:
	# Not recorded: freed before it enters the tree, so it never registers
	var recordable := get_node_or_null(^"Recordable")
	if recordable:
		remove_child(recordable)
		recordable.free()
	# No movement, no collision (a disabled area is removed from the physics space)
	process_mode = Node.PROCESS_MODE_DISABLED
	scale = Vector3.ONE * 0.01
	ready.connect(func() -> void:
		for i in frames:
			await get_tree().process_frame
		queue_free())

## The node that handles hits on `body`: the body, or its parent, if it has
## hit_by_attack(). Null otherwise.
static func find_attack_receiver(body: Node) -> Node:
	if body.has_method(&"hit_by_attack"):
		return body
	var parent := body.get_parent()
	if parent and parent.has_method(&"hit_by_attack"):
		return parent
	return null

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {"age": _age}

func _apply_state(state: Dictionary) -> void:
	_age = state.age
