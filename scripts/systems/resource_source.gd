class_name ResourceSource
extends StaticBody3D


@export var resource_id: String = "food"
@export var remaining_amount: int = 30
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene

# Размеры препятствия и безопасных слотов V4
@export var obstacle_half_size: Vector2 = Vector2(2.55, 3.05)
@export var gather_clearance: float = 0.68
@export var waiting_extra_clearance: float = 0.95

@export var gather_slot_count: int = 10
@export var waiting_slot_count: int = 16

@onready var gather_slots: SafeInteractionSlots = $GatherSlots
@onready var waiting_slots: SafeInteractionSlots = $WaitingSlots
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")


func _ready() -> void:
	# V4: Хлеб блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
	# 1 | 8 = 9
	collision_layer = 1 | 8
	collision_mask = 0

	# Настройка препятствия avoidance
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

	# Настройка прямоугольных безопасных слотов снаружи хлеба
	if gather_slots != null:
		gather_slots.shape = SafeInteractionSlots.SlotShape.RECTANGLE
		gather_slots.rect_half_size = obstacle_half_size + Vector2(gather_clearance, gather_clearance)
		gather_slots.slot_count = gather_slot_count
		gather_slots.reach_distance = 0.40
		gather_slots.rebuild_slots()

	if waiting_slots != null:
		waiting_slots.shape = SafeInteractionSlots.SlotShape.RECTANGLE
		var total_waiting_clearance: float = gather_clearance + waiting_extra_clearance
		waiting_slots.rect_half_size = obstacle_half_size + Vector2(total_waiting_clearance, total_waiting_clearance)
		waiting_slots.slot_count = waiting_slot_count
		waiting_slots.reach_distance = 0.40
		waiting_slots.rebuild_slots()


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


# Проверка: находится ли муравей вплотную к краю ресурса (fallback-страховка)
func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var local_x: float = abs(pos.x - global_position.x)
	var local_z: float = abs(pos.z - global_position.z)
	var dx: float = max(0.0, local_x - obstacle_half_size.x)
	var dz: float = max(0.0, local_z - obstacle_half_size.y)
	var dist: float = sqrt(dx * dx + dz * dz)
	return dist <= max_dist
