class_name PlayerAttack
extends Node
## Charged projectile attack. Hold the attack button to charge, release to shoot a
## projectile in the facing direction. The longer the hold, the stronger the shot.
## Driven by the player's _physics_process (update()), so it pauses during a rewind.
##
## Auto aim: a shot turns towards an aim target (node in the AIM_GROUP group: buttons,
## torches) when the target is both within auto_aim_angle of the facing direction and
## within auto_aim_distance (on the ground plane). Only one of the two is not enough.
## Shots fly flat, so the target must also be hittable by a flat shot: the shot's sphere,
## swept horizontally at shot height towards it, must touch the target first (not a
## wall, and not pass above or below it). Shot triggers (areas shots fly through, like
## the zone above a torch) never block the sweep, and reaching the target's own trigger
## counts as hitting it. Among several, the one closest to the facing
## direction wins. A target is aimed at its "AimPoint" child (Marker3D) if it has one,
## else at its origin; only its horizontal position matters.

enum Strength { WEAK, NORMAL, STRONG }

## Scene of the projectile (scripts/player/projectile.gd).
@export var projectile_scene : PackedScene = preload("res://prefabs/player/projectile.tscn")
## Seconds a projectile lives before it is destroyed.
@export var expire_time : float = 2.0
## Where the projectile appears, relative to the player: height and distance forward.
@export var spawn_height : float = 0.75
@export var spawn_forward : float = 0.4

@export_group("Charge")
## Seconds of hold for a normal shot. Shorter holds shoot a weak one.
@export var normal_charge_time : float = 1.0
## Seconds of hold for a strong shot.
@export var strong_charge_time : float = 4.0

@export_group("Weak")
@export var weak_damage : int = 1
@export var weak_speed : float = 10.0
@export var weak_radius : float = 0.1

@export_group("Normal")
@export var normal_damage : int = 3
@export var normal_speed : float = 12.0
@export var normal_radius : float = 0.2

@export_group("Strong")
@export var strong_damage : int = 5
@export var strong_speed : float = 14.0
@export var strong_radius : float = 0.35

@export_group("Auto aim")
## Largest angle (degrees) between the facing direction and a target for the shot to be
## corrected towards it. 0 turns auto aim off.
@export_range(0.0, 90.0) var auto_aim_angle : float = 15.0
## Farthest distance (meters) from the player to a target for the shot to be corrected.
@export var auto_aim_distance : float = 8.0
## Physics layers a shot collides with, for the hittable check: the world and targets
## (layer 1) and shot triggers (layer 5). Match the projectile's collision mask.
@export_flags_3d_physics var auto_aim_block_mask : int = 1 | 16

## Group of the nodes auto aim can target.
const AIM_GROUP := &"aim_target"

## Seconds the attack button has been held, or -1 when it isn't charging.
var charge_time : float = -1.0
## A shot was fired during this tick's update() (for the attack animation).
var just_shot : bool = false

@onready var _player : Node3D = get_parent()

## Reads the attack input. Call it once per physics tick from the player.
func _ready() -> void:
	_warm_up_projectile.call_deferred()

# Draws a hidden projectile for a few frames, so its shaders are compiled at level start
# instead of on the first shot (see Projectile.warm_up)
func _warm_up_projectile() -> void:
	if not projectile_scene:
		return
	var projectile := projectile_scene.instantiate()
	if not projectile.has_method(&"warm_up"):
		projectile.queue_free()
		return
	projectile.warm_up()
	get_tree().current_scene.add_child(projectile)
	# Inside the player's body, where the camera sees it but the player doesn't
	projectile.global_position = get_parent().global_position + Vector3.UP * spawn_height

func update(delta: float) -> void:
	just_shot = false
	if Input.is_action_just_pressed("attack"):
		charge_time = 0.0
	elif charge_time >= 0.0:
		if Input.is_action_pressed("attack"):
			charge_time += delta
		else:
			shoot(get_strength(charge_time))
			just_shot = true
			charge_time = -1.0

func get_strength(held_time: float) -> Strength:
	if held_time >= strong_charge_time:
		return Strength.STRONG
	if held_time >= normal_charge_time:
		return Strength.NORMAL
	return Strength.WEAK

## Shoots a projectile of the given strength in the player's facing direction, corrected
## by auto aim, and records the shot so the phantom fires it again.
func shoot(strength: Strength) -> Node3D:
	var shot := get_shot(strength)
	# Recorded with the shot: the phantom fires the same direction, it doesn't aim again
	shot.direction = get_aim_direction(shot)
	RecordManager.record_event({"type": &"shoot", "shot": shot})
	return spawn_projectile(shot, _player)

## Everything needed to spawn a shot of the given strength. The tape stores this, so the
## phantom fires exactly what was fired.
func get_shot(strength: Strength) -> Dictionary:
	var shot := {
		"scene": projectile_scene,
		"expire_time": expire_time,
		"spawn_height": spawn_height,
		"spawn_forward": spawn_forward,
		"strength": strength,
	}
	match strength:
		Strength.WEAK:
			shot.merge({"damage": weak_damage, "speed": weak_speed, "radius": weak_radius})
		Strength.NORMAL:
			shot.merge({"damage": normal_damage, "speed": normal_speed, "radius": normal_radius})
		Strength.STRONG:
			shot.merge({"damage": strong_damage, "speed": strong_speed, "radius": strong_radius})
	return shot

## Flat direction for a shot from the player: towards the best aim target (see the class
## description), or straight ahead when there is none.
func get_aim_direction(shot: Dictionary) -> Vector3:
	var forward := facing(_player)
	var origin := spawn_position(shot, _player)
	if auto_aim_angle <= 0.0 or auto_aim_distance <= 0.0:
		return forward

	var best_direction := forward
	var best_angle := deg_to_rad(auto_aim_angle)
	var space := _player.get_world_3d().direct_space_state
	for target in _player.get_tree().get_nodes_in_group(AIM_GROUP):
		var node := target as Node3D
		if node == null or not node.is_visible_in_tree():
			continue
		var aim_point := get_aim_point(node)
		var to_target := aim_point - origin
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.is_zero_approx() or flat.length() > auto_aim_distance:
			continue
		var direction := flat.normalized()
		var angle := forward.angle_to(direction)
		if angle > best_angle:
			continue
		if not _flat_shot_hits(space, shot, origin, direction, flat.length(), node):
			continue
		best_angle = angle
		best_direction = direction
	return best_direction

## Where auto aim points at on `target`: its AimPoint child, or its origin.
static func get_aim_point(target: Node3D) -> Vector3:
	var marker := target.get_node_or_null(^"AimPoint") as Node3D
	return marker.global_position if marker else target.global_position

## Flat facing direction of `shooter` (-Z is forward).
static func facing(shooter: Node3D) -> Vector3:
	var forward := -shooter.global_basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()

## Where a shot from `shooter` appears.
static func spawn_position(shot: Dictionary, shooter: Node3D) -> Vector3:
	return shooter.global_position + Vector3.UP * shot.spawn_height + facing(shooter) * shot.spawn_forward

## Spawns the projectile described by `shot` (see get_shot()). It flies along
## shot.direction if set (auto aim), else in the facing direction of `shooter`. Used by
## the player and by the phantom.
static func spawn_projectile(shot: Dictionary, shooter: Node3D) -> Node3D:
	var direction : Vector3 = shot.get("direction", facing(shooter))

	var projectile : Node3D = shot.scene.instantiate()
	projectile.setup(shot.strength, shot.damage, direction * shot.speed, shot.radius, shot.expire_time)
	# In the level, not under the shooter, so it doesn't turn with the shooter
	shooter.get_parent().add_child(projectile)
	projectile.global_position = spawn_position(shot, shooter)
	return projectile

# Sweeps the shot's sphere flat from `origin` along `direction`, a bit past the target's
# distance: true if the first thing it touches is the target (or a part of it).
func _flat_shot_hits(space: PhysicsDirectSpaceState3D, shot: Dictionary, origin: Vector3,
		direction: Vector3, distance: float, target: Node) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = shot.radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = direction * (distance + 1.0)
	query.collision_mask = auto_aim_block_mask
	query.collide_with_areas = true
	var motion := query.motion
	var excluded : Array[RID] = []
	# A few times: each shot trigger of another object is skipped and swept again
	for attempt in 8:
		query.exclude = excluded
		query.transform.origin = origin
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[1] >= 1.0:
			return false # touches nothing: passes above, below or beside it
		# Where it first touches, and what
		query.transform.origin = origin + motion * fractions[1]
		query.motion = Vector3.ZERO
		var hit := space.get_rest_info(query)
		if hit.is_empty():
			return false
		var collider := instance_from_id(hit.collider_id) as Node
		if collider == null:
			return false
		if collider == target or target.is_ancestor_of(collider):
			return true
		if not collider is Area3D:
			return false # blocked by a body
		excluded.append(hit.rid)
	return false
