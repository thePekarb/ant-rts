class_name SquadController
extends Node3D


@export var formation_spacing: float = 0.75
const MIN_UNIT_SPACING: float = 0.68


func issue_move(units: Array[WorkerAnt], target: Vector3) -> void:
	var valid_units: Array[WorkerAnt] = filter_valid_units(units)
	if valid_units.is_empty():
		return

	var group_center: Vector3 = get_group_center(valid_units)
	var nav_map: RID = get_world_3d().navigation_map

	# Строим один общий маршрут отряда через навигационную сетку
	var group_path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map,
		group_center,
		target,
		true
	)

	# Направление подхода к цели
	var move_direction: Vector3 = target - group_center
	if group_path.size() >= 2:
		move_direction = group_path[group_path.size() - 1] - group_path[group_path.size() - 2]
	move_direction.y = 0.0

	if move_direction.length_squared() < 0.001:
		move_direction = Vector3.FORWARD

	# Расчёт сотового построения с гарантированным расстоянием
	var actual_spacing: float = max(formation_spacing, MIN_UNIT_SPACING)
	var slots: Array[Vector3] = create_formation_positions(
		target,
		valid_units.size(),
		move_direction,
		actual_spacing
	)

	# Проецируем каждый слот на проходимую поверхность NavMesh
	for i in range(slots.size()):
		slots[i] = snap_to_navigation(slots[i])

	# Назначаем муравьёв в слоты без перекрещивания полос
	assign_units_to_slots(valid_units, slots, move_direction)


func issue_attack(units: Array[WorkerAnt], enemy: WorkerAnt) -> void:
	var valid_units: Array[WorkerAnt] = filter_valid_units(units)
	if valid_units.is_empty() or enemy == null or not is_instance_valid(enemy):
		return

	# Ближайшие к цели юниты получают слоты первыми
	valid_units.sort_custom(
		func(a: WorkerAnt, b: WorkerAnt) -> bool:
			var da: float = a.global_position.distance_squared_to(enemy.global_position)
			var db: float = b.global_position.distance_squared_to(enemy.global_position)
			return da < db
	)

	for unit in valid_units:
		unit.attack(enemy)


func issue_gather(units: Array[WorkerAnt], resource: ResourceSource, anthill: Anthill) -> void:
	var valid_units: Array[WorkerAnt] = filter_valid_units(units)
	if valid_units.is_empty() or resource == null or not is_instance_valid(resource):
		return

	if anthill == null or not is_instance_valid(anthill):
		print("[SquadController] Ошибка: Муравейник не найден для сдачи ресурса!")
		return

	valid_units.sort_custom(
		func(a: WorkerAnt, b: WorkerAnt) -> bool:
			var da: float = a.global_position.distance_squared_to(resource.global_position)
			var db: float = b.global_position.distance_squared_to(resource.global_position)
			return da < db
	)

	print("[SquadController] Отправка отряда (", valid_units.size(), " муравьёв) на сбор ресурса: ", resource.name)
	for unit in valid_units:
		unit.gather(resource, anthill)


func issue_deposit(units: Array[WorkerAnt], anthill: Anthill) -> void:
	var valid_units: Array[WorkerAnt] = filter_valid_units(units)
	if valid_units.is_empty() or anthill == null or not is_instance_valid(anthill):
		return

	valid_units.sort_custom(
		func(a: WorkerAnt, b: WorkerAnt) -> bool:
			var da: float = a.global_position.distance_squared_to(anthill.global_position)
			var db: float = b.global_position.distance_squared_to(anthill.global_position)
			return da < db
	)

	print("[SquadController] Отправка отряда (", valid_units.size(), " муравьёв) на сдачу ресурса в муравейник: ", anthill.name)
	for unit in valid_units:
		unit.deliver(anthill)


func filter_valid_units(units: Array[WorkerAnt]) -> Array[WorkerAnt]:
	var result: Array[WorkerAnt] = []
	for u in units:
		if is_instance_valid(u) and u.state != WorkerAnt.UnitState.DEAD:
			result.append(u)
	return result


func get_group_center(units: Array[WorkerAnt]) -> Vector3:
	var center := Vector3.ZERO
	if units.is_empty():
		return center

	for unit in units:
		center += unit.global_position

	return center / float(units.size())


func snap_to_navigation(target_pos: Vector3) -> Vector3:
	var navigation_map: RID = get_world_3d().navigation_map
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(navigation_map, target_pos)

	if closest.length_squared() < 0.001 and target_pos.length_squared() > 0.01:
		return target_pos

	return closest if closest != Vector3.ZERO else target_pos


func create_formation_positions(
	center: Vector3,
	unit_count: int,
	move_direction: Vector3,
	spacing: float
) -> Array[Vector3]:

	var positions: Array[Vector3] = []
	if unit_count <= 0:
		return positions

	var forward := move_direction.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)

	var columns: int = int(ceil(sqrt(float(unit_count))))
	var rows: int = int(ceil(float(unit_count) / float(columns)))

	for i in range(unit_count):
		var column: int = i % columns
		var row: int = int(i / columns)

		var side_offset: float = (
			float(column) - float(columns - 1) / 2.0
		) * spacing

		var forward_offset: float = (
			float(row) - float(rows - 1) / 2.0
		) * spacing

		# Сотовое смещение чётных рядов
		if row % 2 == 1:
			side_offset += spacing * 0.5

		var position: Vector3 = (
			center
			+ right * side_offset
			+ forward * forward_offset
		)

		positions.append(position)

	return positions


func assign_units_to_slots(
	units: Array[WorkerAnt],
	slots: Array[Vector3],
	move_direction: Vector3
) -> void:

	var group_center: Vector3 = get_group_center(units)
	var forward: Vector3 = move_direction.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)

	# Сортировка муравьёв слева направо и спереди назад относительно направления движения
	var sorted_units: Array[WorkerAnt] = units.duplicate()
	sorted_units.sort_custom(
		func(a: WorkerAnt, b: WorkerAnt) -> bool:
			var a_side: float = (a.global_position - group_center).dot(right)
			var b_side: float = (b.global_position - group_center).dot(right)
			var a_fwd: float = (a.global_position - group_center).dot(forward)
			var b_fwd: float = (b.global_position - group_center).dot(forward)
			# Основной приоритет — боковая полоса, вторичный — ряд
			return (a_side * 10.0 + a_fwd) < (b_side * 10.0 + b_fwd)
	)

	# Сортировка слотов аналогично
	var sorted_slots: Array[Vector3] = slots.duplicate()
	sorted_slots.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			var a_side: float = (a - slots[0]).dot(right)
			var b_side: float = (b - slots[0]).dot(right)
			var a_fwd: float = (a - slots[0]).dot(forward)
			var b_fwd: float = (b - slots[0]).dot(forward)
			return (a_side * 10.0 + a_fwd) < (b_side * 10.0 + b_fwd)
	)

	for i in range(sorted_units.size()):
		if is_instance_valid(sorted_units[i]):
			sorted_units[i].move_to(sorted_slots[i])
