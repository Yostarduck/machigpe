extends StaticBody3D
## Breakable wall (misc/Interactables.md). Projectile hits at or above min_strength deal
## their damage; weaker hits do nothing (I16). At 0 health it breaks: hidden and without
## collision, not freed, so a rewind can bring it back. Its health is recorded
## (Recordable child).
##
## Placed with its origin at the bottom centre.

signal broken

@export var max_health : int = 5
## Weakest attack that damages it.
@export var min_strength : PlayerAttack.Strength = PlayerAttack.Strength.WEAK
@export var color_full : Color = Color(0.55, 0.5, 0.45)
@export var color_damaged : Color = Color(0.3, 0.22, 0.18)

var health : int

@onready var _shape : CollisionShape3D = $CollisionShape3D
@onready var _mesh : MeshInstance3D = $MeshInstance3D

var _material := StandardMaterial3D.new()

func _ready() -> void:
	health = max_health
	_mesh.material_override = _material
	_update()

## Hit by a projectile (I8).
func hit_by_attack(strength: int, damage: int) -> void:
	if health <= 0 or strength < min_strength:
		return
	health = maxi(health - damage, 0)
	_update()
	if health == 0:
		broken.emit()

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {"health": health}

func _apply_state(state: Dictionary) -> void:
	health = state.health
	_update()

func _update() -> void:
	var standing := health > 0
	visible = standing
	# Deferred: hits arrive inside a physics callback
	_shape.set_deferred("disabled", not standing)
	_material.albedo_color = color_damaged.lerp(color_full, float(health) / max_health)
