extends Node3D
## Scale (misc/Interactables.md, I15): two linked platforms, Side1 and Side2. Standing on
## one side sinks it and raises the other; both sides always take the same time.
##
## State: balance, from -1 to 1.
##   balance  1   Side1 down max_depth_1,   Side2 up max_height_2
##   balance  0   both at rest (where they are placed)
##   balance -1   Side1 up max_height_1,    Side2 down max_depth_2
##
##   only Side1 occupied   balance goes to  1, the stepped side moving at stepped_speed
##   only Side2 occupied   balance goes to -1, the stepped side moving at stepped_speed
##   both occupied         balance stays where it is
##   nobody                balance goes to  0, the lower side rising at return_speed
##
## Occupants: the player and the phantom only (I4), found in each side's Sensor shape.
## Like InteractSensor, the shape is queried directly every tick instead of reading the
## area's overlap lists (a physics step late), and the scale runs just before the player:
## it sees the player where the record captured it, which is where the phantom is shown,
## so the phantom moves the scale on exactly the same ticks.
## The balance is recorded (Recordable child). Each side has its own Recordable with
## record_velocity, so a player standing on it at the end of a rewind is carried right.
## Not a key (I15).

@export var accepts_player : bool = true
@export var accepts_phantom : bool = true

@export_group("Limits")
## How far Side1 sinks below rest, in meters.
@export var max_depth_1 : float = 1.0
## How far Side1 rises above rest, in meters.
@export var max_height_1 : float = 1.0
## How far Side2 sinks below rest, in meters.
@export var max_depth_2 : float = 1.0
## How far Side2 rises above rest, in meters.
@export var max_height_2 : float = 1.0

@export_group("Speed")
## Speed (m/s) of the side being stepped on, going down.
@export var stepped_speed : float = 1.0
## Speed (m/s) of the lower side going back up when nobody is on the scale.
@export var return_speed : float = 0.5

## -1 to 1: see the table above.
var balance : float = 0.0

@onready var _side_1 : AnimatableBody3D = $Side1
@onready var _side_2 : AnimatableBody3D = $Side2
@onready var _sensor_1 : Area3D = $Side1/Sensor
@onready var _sensor_2 : Area3D = $Side2/Sensor

var _rest_1 : Vector3
var _rest_2 : Vector3

func _ready() -> void:
	# Before the player (priority 0), after the RecordManager places the phantom (-1000)
	process_physics_priority = -1
	_rest_1 = _side_1.position
	_rest_2 = _side_2.position
	_update_sides()

func _physics_process(delta: float) -> void:
	var on_1 := _occupied(_sensor_1)
	var on_2 := _occupied(_sensor_2)
	if on_1 and not on_2:
		# Side1 goes down: through its "up" range first if it is above rest
		var extent := max_depth_1 if balance >= 0.0 else max_height_1
		balance = _step(balance, 1.0, stepped_speed, extent, delta)
	elif on_2 and not on_1:
		var extent := max_depth_2 if balance <= 0.0 else max_height_2
		balance = _step(balance, -1.0, stepped_speed, extent, delta)
	elif not on_1 and not on_2:
		# The lower side rises back to rest
		var extent := max_depth_1 if balance > 0.0 else max_depth_2
		balance = _step(balance, 0.0, return_speed, extent, delta)
	_update_sides()

## Moves `value` towards `to` so that a side spanning `extent` meters over one unit of
## balance moves at `speed` m/s.
static func _step(value: float, to: float, speed: float, extent: float, delta: float) -> float:
	if extent <= 0.0:
		return to
	return move_toward(value, to, speed / extent * delta)

func _occupied(sensor: Area3D) -> bool:
	var shape_node : CollisionShape3D = sensor.get_child(0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = sensor.collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		if PuzzleKey.accepts_actor(hit.collider, accepts_player, accepts_phantom):
			return true
	return false

func _update_sides() -> void:
	var offset_1 := -max_depth_1 * balance if balance >= 0.0 else -max_height_1 * balance
	var offset_2 := max_height_2 * balance if balance >= 0.0 else max_depth_2 * balance
	_side_1.position = _rest_1 + Vector3.UP * offset_1
	_side_2.position = _rest_2 + Vector3.UP * offset_2

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {"balance": balance}

func _apply_state(state: Dictionary) -> void:
	balance = state.balance
	_update_sides()
