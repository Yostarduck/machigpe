extends Area3D
## Hurts the live player on contact. The phantom is invulnerable (D12): its mask is the
## player layer and it checks the "player" group.

@export var damage : int = 1

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# The player ignores damage during a rewind itself (see player.gd take_damage)
	if body.is_in_group("player") and body.has_method(&"take_damage"):
		body.take_damage(damage)
