class_name ResourceSource
extends StaticBody3D


@export var resource_id: String = "food"
@export var remaining_amount: int = 30
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene
@export var obstacle_half_size: Vector2 = Vector2(2.8, 3.3)

@onready var gather_slots: RadialSlots = $GatherSlots
@onready var waiting_slots: RadialSlots = $WaitingSlots
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")


func _ready() -> void:
	# V3: Ресурс блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
	# 1 | 8 = 9
	collision_layer = 1 | 8
	collision_mask = 0

	if obstacle != null:
		obstacle.affect_navigation_mesh = true
		obstacle.avoidance_enabled = true
		obstacle.use_3d_avoidance = false
		obstacle.vertices = PackedVector3Array([
			Vector3(-obstacle_half_size.x, 0.0, -obstacle_half_size.y),
			Vector3( obstacle_half_size.x, 0.0, -obstacle_half_size.y),
			Vector3( obstacle_half_size.x, 0.0,  obstacle_half_size.y),
			Vector3(-obstacle_half_size.x, 0.0,  obstacle_half_size.y)
		])


func harvest(amount: int = 1) -> int:
	var actual: int = min(amount, remaining_amount)
	remaining_amount -= actual
	print("[Ресурс: ", resource_id, "] Собрано ", actual, " ед. Осталось: ", remaining_amount)

	if remaining_amount <= 0:
		print("[Ресурс: ", resource_id, "] Полностью истощён!")
		queue_free()

	return actual


func is_depleted() -> bool:
	return remaining_amount <= 0
