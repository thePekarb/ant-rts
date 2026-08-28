class_name Anthill
extends StaticBody3D


@export var obstacle_radius: float = 1.15
@export var deposit_clearance: float = 0.62
@export var waiting_extra_clearance: float = 0.90

@export var deposit_slot_count: int = 8
@export var waiting_slot_count: int = 14

@onready var deposit_slots: SafeInteractionSlots = $DepositSlots
@onready var deposit_waiting_slots: SafeInteractionSlots = get_node_or_null("DepositWaitingSlots")
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")

var stored_resources: Dictionary = {
	"food": 0
}


func _ready() -> void:
	# Муравейник на Collision Layer 5 (маска 16) и Layer 1 (Здания/Препятствия) -> 1 | 16 = 17
	collision_layer = 17
	collision_mask = 0

	if obstacle != null:
		obstacle.radius = obstacle_radius
		obstacle.affect_navigation_mesh = true
		obstacle.avoidance_enabled = true
		obstacle.use_3d_avoidance = false

	if deposit_slots != null:
		deposit_slots.shape = SafeInteractionSlots.SlotShape.CIRCLE
		deposit_slots.radius = obstacle_radius + deposit_clearance
		deposit_slots.slot_count = deposit_slot_count
		deposit_slots.reach_distance = 0.40
		deposit_slots.rebuild_slots()

	if deposit_waiting_slots != null:
		deposit_waiting_slots.shape = SafeInteractionSlots.SlotShape.CIRCLE
		deposit_waiting_slots.radius = obstacle_radius + deposit_clearance + waiting_extra_clearance
		deposit_waiting_slots.slot_count = waiting_slot_count
		deposit_waiting_slots.reach_distance = 0.40
		deposit_waiting_slots.rebuild_slots()


func deposit(resource_id: String, amount: int) -> void:
	stored_resources[resource_id] = stored_resources.get(resource_id, 0) + amount
	print("[Муравейник] Сдано ", amount, " ед. ", resource_id, "! Всего в хранилище: ", stored_resources[resource_id])


func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var dist: float = Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	return max(0.0, dist - obstacle_radius) <= max_dist
