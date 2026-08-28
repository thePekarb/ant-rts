class_name RadialSlots
extends Node3D


@export var radius: float = 1.0
@export var slot_count: int = 8
@export var reach_distance: float = 0.2

var slot_owners: Array = []


func _ready() -> void:
	slot_owners.resize(slot_count)
	slot_owners.fill(null)


func reserve_slot(unit: Node3D) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1

	# Если юнит уже владеет слотом — возвращаем его же
	for i in range(slot_owners.size()):
		if slot_owners[i] == unit:
			return i

	var best_slot: int = -1
	var best_distance: float = INF

	# Ищем ближайший свободный слот
	for i in range(slot_owners.size()):
		var owner_node = slot_owners[i]
		if owner_node != null and is_instance_valid(owner_node):
			continue

		var slot_pos: Vector3 = get_slot_position(i)
		var dist: float = unit.global_position.distance_squared_to(slot_pos)

		if dist < best_distance:
			best_distance = dist
			best_slot = i

	if best_slot != -1:
		slot_owners[best_slot] = unit

	return best_slot


func get_slot_position(index: int) -> Vector3:
	var count: int = max(1, slot_count)
	var angle: float = TAU * float(index) / float(count)
	var offset := Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)
	return global_position + offset


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
