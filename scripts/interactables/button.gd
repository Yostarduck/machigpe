extends TimedKey
## Wall button (misc/Interactables.md). Pressed for a while, then pops back out:
##
##   player or phantom interacts    short_time
##   weak attack                    short_time
##   normal attack                  normal_time
##   strong attack                  long_time
##
## Pressing it again keeps the longer time (I6). See TimedKey.
##
## Placed with its origin on the wall surface, facing out along +Z.

@export var accepts_player : bool = true
@export var accepts_phantom : bool = true

@export_group("Look")
## How far the cap sinks into the wall when pressed, in meters.
@export var press_depth : float = 0.06
@export var color_off : Color = Color(0.8, 0.25, 0.2)
@export var color_on : Color = Color(0.3, 0.85, 0.3)

@onready var _cap : MeshInstance3D = $Cap

var _material := StandardMaterial3D.new()
var _cap_rest_z : float

func _ready() -> void:
	_cap_rest_z = _cap.position.z
	_cap.material_override = _material
	super()

## Pressed by the player or the phantom (InteractSensor).
func interact(actor: Node3D) -> void:
	if accepts_actor(actor, accepts_player, accepts_phantom):
		press(short_time)

func _update_visuals() -> void:
	_cap.position.z = _cap_rest_z - press_depth if on else _cap_rest_z
	_material.albedo_color = color_on if on else color_off
