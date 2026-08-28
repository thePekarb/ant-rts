class_name SafeInteractionSlots
extends Node3D


enum SlotShape {
	CIRCLE,
	RECTANGLE,
	CUSTOM_MARKERS
}

@export var shape: SlotShape = SlotShape.CIRCLE
@export var slot_count: int = 8
@export var radius: float = 1.0
@export var rect_half_size: Vector2 = Vector2(2.5, 2.5)
@export var reach_distance: float = 0.35
@export var snap_to_navmesh: bool = true

var slot_owners: Array = []
var computed_positions: Array[Vector3] = []


func _ready() -> void:
	rebuild_slots()


func rebuild_slots() -> void:
	slot_owners.clear()
	computed_positions.clear()

	match shape:
		SlotShape.CUSTOM_MARKERS:
			for child in get_children():
				if child is Marker3D:
					computed_positions.append(child.global_position)
			slot_count = computed_positions.size()

		SlotShape.RECTANGLE:
			computed_positions = generate_rectangle_slots(rect_half_size, slot_count)

		SlotShape.CIRCLE:
			computed_positions = generate_circle_slots(radius, slot_count)

	if snap_to_navmesh:
		var nav_map: RID = get_world_3d().navigation_map
		for i in range(computed_positions.size()):
			var snapped_pos: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, computed_positions[i])
			if snapped_pos.length_squared() > 0.001:
				computed_positions[i] = snapped_pos

	slot_owners.resize(computed_positions.size())
	slot_owners.fill(null)


func generate_circle_slots(r: float, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var c: int = max(1, count)
	for i in range(c):
		var angle: float = TAU * float(i) / float(c)
		var offset := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		result.append(global_position + offset)
	return result


func generate_rectangle_slots(half_sz: Vector2, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var c: int = max(4, count)

	# Периметр прямоугольника: 2 * (w + h)
	var w: float = half_sz.x * 2.0
	var h: float = half_sz.y * 2.0
	var perimeter: float = 2.0 * (w + h)
	var step: float = perimeter / float(c)

	for i in range(c):
		var d: float = step * float(i)
		var local_pt := Vector2.ZERO

		# 1. Верхняя грань (слева направо: x от -half_sz.x до +half_sz.x, z = -half_sz.y)
		if d < w:
			local_pt = Vector2(-half_sz.x + d, -half_sz.y)
		# 2. Правая грань (сверху вниз: x = half_sz.x, z от -half_sz.y до +half_sz.y)
		elif d < w + h:
			local_pt = Vector2(half_sz.x, -half_sz.y + (d - w))
		# 3. Нижняя грань (справа налево: x от +half_sz.x до -half_sz.x, z = half_sz.y)
		elif d < 2.0 * w + h:
			local_pt = Vector2(half_sz.x - (d - (w + h)), half_sz.y)
		# 4. Левая грань (снизу вверх: x = -half_sz.x, z от +half_sz.y до -half_sz.y)
		else:
			local_pt = Vector2(-half_sz.x, half_sz.y - (d - (2.0 * w + h)))

		result.append(global_position + Vector3(local_pt.x, 0.0, local_pt.y))

	return result


func reserve_slot(unit: Node3D) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1

	# Если юнит уже владеет слотом
	for i in range(slot_owners.size()):
		if slot_owners[i] == unit:
			return i

	var best_slot: int = -1
	var best_dist_sq: float = INF

	for i in range(slot_owners.size()):
		var owner_node = slot_owners[i]
		if owner_node != null and is_instance_valid(owner_node):
			continue

		var slot_pos: Vector3 = get_slot_position(i)
		var dist_sq: float = unit.global_position.distance_squared_to(slot_pos)

		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_slot = i

	if best_slot != -1:
		slot_owners[best_slot] = unit

	return best_slot


func get_slot_position(index: int) -> Vector3:
	if index >= 0 and index < computed_positions.size():
		return computed_positions[index]
	return global_position


func release_slot(unit: Node3D) -> void:
	if unit == null:
		return
	for i in range(slot_owners.size()):
		if slot_owners[i] == unit:
			slot_owners[i] = null


func release_slot_index(index: int, unit: Node3D) -> void:
	if index >= 0 and index < slot_owners.size():
		if slot_owners[index] == unit:
			slot_owners[index] = null


func has_free_slot() -> bool:
	for owner_node in slot_owners:
		if owner_node == null or not is_instance_valid(owner_node):
			return true
	return false


func get_slot_owner(index: int) -> Node3D:
	if index >= 0 and index < slot_owners.size():
		var owner_node = slot_owners[index]
		if owner_node != null and is_instance_valid(owner_node):
			return owner_node
	return null
