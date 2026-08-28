class_name ResourceSource
extends StaticBody3D


@export var resource_id: String = "food"
@export var sync_amount_to_pieces: bool = true
@export var remaining_amount: int = 42
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene
@export var piece_vanish_duration: float = 0.18

# Размеры препятствия и безопасных слотов V5
@export var obstacle_half_size: Vector2 = Vector2(2.55, 3.05)
@export var gather_surface_reach: float = 0.72
@export var gather_clearance: float = 0.68
@export var waiting_extra_clearance: float = 0.95

@export var gather_slot_count: int = 10
@export var waiting_slot_count: int = 16

@onready var gather_slots: SafeInteractionSlots = $GatherSlots
@onready var waiting_slots: SafeInteractionSlots = $WaitingSlots
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")

var available_pieces: Array[Node3D] = []
var active_vanish_count: int = 0


func _ready() -> void:
	# V5: Хлеб блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
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

	# Сбор всех визуальных кусочков хлеба
	collect_visual_pieces(self)

	if sync_amount_to_pieces and not available_pieces.is_empty():
		remaining_amount = available_pieces.size()

	print("[Ресурс: ", name, "] Инициализирован: кусочков=", available_pieces.size(), ", запас=", remaining_amount)


func collect_visual_pieces(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.name.begins_with("BreadPiece_"):
			available_pieces.append(child)
		collect_visual_pieces(child)


func take_from(worker_pos: Vector3, amount: int = 1) -> int:
	if available_pieces.is_empty() or remaining_amount <= 0:
		return 0

	var actual_take: int = min(amount, remaining_amount)
	
	for _i in range(actual_take):
		if available_pieces.is_empty():
			break

		# Ищем ближайший визуальный кусочек именно к позиции этого муравья
		var best_idx: int = -1
		var best_dist_sq: float = INF

		for j in range(available_pieces.size()):
			var piece: Node3D = available_pieces[j]
			if not is_instance_valid(piece):
				continue
			var d_sq: float = worker_pos.distance_squared_to(piece.global_position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_idx = j

		if best_idx != -1:
			var target_piece: Node3D = available_pieces[best_idx]
			available_pieces.remove_at(best_idx)
			remaining_amount -= 1
			animate_piece_vanish(target_piece)

	print("[Ресурс: ", name, "] Отщипнут кусочек! Осталось: ", remaining_amount, " (активных мешей: ", available_pieces.size(), ")")

	if remaining_amount <= 0 or available_pieces.is_empty():
		on_fully_depleted()

	return actual_take


func animate_piece_vanish(piece: Node3D) -> void:
	if not is_instance_valid(piece):
		return

	active_vanish_count += 1
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(piece, "scale", Vector3(0.01, 0.01, 0.01), piece_vanish_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(piece, "position:y", piece.position.y + 0.15, piece_vanish_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		active_vanish_count -= 1
		if is_instance_valid(piece):
			piece.queue_free()
		if remaining_amount <= 0 and active_vanish_count <= 0:
			queue_free()
	)


func on_fully_depleted() -> void:
	print("[Ресурс: ", name, "] Полностью истощён и съеден!")
	# Отключаем физическую коллизию
	collision_layer = 0
	if obstacle != null:
		obstacle.avoidance_enabled = false
		obstacle.affect_navigation_mesh = false

	if active_vanish_count <= 0:
		queue_free()


func harvest(amount: int = 1) -> int:
	return take_from(global_position, amount)


func is_depleted() -> bool:
	return remaining_amount <= 0 or (available_pieces.is_empty() and active_vanish_count <= 0)


func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var local_x: float = abs(pos.x - global_position.x)
	var local_z: float = abs(pos.z - global_position.z)
	var dx: float = max(0.0, local_x - obstacle_half_size.x)
	var dz: float = max(0.0, local_z - obstacle_half_size.y)
	var dist: float = sqrt(dx * dx + dz * dz)
	return dist <= max_dist
