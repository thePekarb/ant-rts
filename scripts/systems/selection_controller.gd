class_name SelectionController
extends Node


var selected_units: Array[WorkerAnt] = []


func clean_units() -> void:
	selected_units = selected_units.filter(func(u): return is_instance_valid(u) and u.state != WorkerAnt.UnitState.DEAD)


func replace_selection(new_units: Array[WorkerAnt]) -> void:
	clear_selection()
	for unit in new_units:
		if is_instance_valid(unit) and unit.state != WorkerAnt.UnitState.DEAD and not selected_units.has(unit):
			selected_units.append(unit)
			unit.set_selected(true)


func add_unit(unit: WorkerAnt) -> void:
	clean_units()
	if is_instance_valid(unit) and unit.state != WorkerAnt.UnitState.DEAD and not selected_units.has(unit):
		selected_units.append(unit)
		unit.set_selected(true)


func remove_unit(unit: WorkerAnt) -> void:
	clean_units()
	if is_instance_valid(unit):
		unit.set_selected(false)
		selected_units.erase(unit)


func toggle_unit(unit: WorkerAnt) -> void:
	clean_units()
	if not is_instance_valid(unit) or unit.state == WorkerAnt.UnitState.DEAD:
		return

	if selected_units.has(unit):
		remove_unit(unit)
	else:
		add_unit(unit)


func clear_selection() -> void:
	clean_units()
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected_units.clear()


func get_selected_units() -> Array[WorkerAnt]:
	clean_units()
	return selected_units
