extends PuzzleKey
## On while at least one accepted actor stands on it: the player, the phantom, or both (I4).
## Not recorded: its state follows who is on it, which the rewind already restores.

@export var accepts_player : bool = true
@export var accepts_phantom : bool = true
## How far the plate sinks when pressed, in meters.
@export var press_depth : float = 0.03
@export var color_released : Color = Color(0.8, 0.25, 0.2)
@export var color_pressed : Color = Color(0.3, 0.85, 0.3)

@onready var _top : MeshInstance3D = $Top
@onready var _area : Area3D = $Area3D

var _actors : Array[Node] = []
var _material := StandardMaterial3D.new()
var _rest_y : float

func _ready() -> void:
	_rest_y = _top.position.y
	_top.material_override = _material
	# The player is detected as a body, the phantom as an area (its Sensor)
	_area.body_entered.connect(_on_actor_entered)
	_area.body_exited.connect(_on_actor_exited)
	_area.area_entered.connect(_on_actor_entered)
	_area.area_exited.connect(_on_actor_exited)
	super()

func _on_actor_entered(node: Node) -> void:
	if accepts_actor(node, accepts_player, accepts_phantom) and not _actors.has(node):
		_actors.append(node)
		set_on(true)

func _on_actor_exited(node: Node) -> void:
	_actors.erase(node)
	set_on(not _actors.is_empty())

func _update_visuals() -> void:
	_top.position.y = _rest_y - press_depth if on else _rest_y
	_material.albedo_color = color_pressed if on else color_released
