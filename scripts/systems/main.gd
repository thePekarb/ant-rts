extends Node3D


@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var selection_box: ColorRect = $UI/SelectionBox
@onready var squad_controller: SquadController = $SquadController
@onready var anthill: Anthill = $Anthill

var selection_controller: SelectionController = SelectionController.new()
var hover_controller: HoverController = HoverController.new()

# Начальная точка протягивания рамки.
var selection_start: Vector2
var selecting: bool = false
var dragging_selection: bool = false
var additive_selection: bool = false

const DRAG_THRESHOLD: float = 6.0

# ---------------------------------------------------------
# БИТОВЫЕ МАСКИ СЛОЕВ КОЛЛИЗИЙ
# ---------------------------------------------------------
const WORLD_MASK: int = 1       # Layer 1 = Земля, камни, блокирующий хлеб
const FRIENDLY_MASK: int = 2    # Layer 2 = Наши муравьи
const ENEMY_MASK: int = 4       # Layer 3 = Враги (1 << 2 = 4)
const RESOURCE_MASK: int = 8    # Layer 4 = Ресурсы (1 << 3 = 8)
const BUILDING_MASK: int = 16   # Layer 5 = Здания / Муравейник (1 << 4 = 16)


func _ready() -> void:
	add_child(selection_controller)
	add_child(hover_controller)


func _process(_delta: float) -> void:
	var selected_units: Array[WorkerAnt] = selection_controller.get_selected_units()
	hover_controller.update_hover(camera, get_viewport().get_mouse_position(), not selected_units.is_empty())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# ЛКМ нажали
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selection_start = event.position
			selecting = true
			dragging_selection = false
			additive_selection = event.shift_pressed

		# ЛКМ отпустили
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if selecting:
				if dragging_selection:
					select_units_in_box(selection_start, event.position, additive_selection)
				else:
					select_unit_at_mouse(event.position, additive_selection)

			selecting = false
			dragging_selection = false
			selection_box.visible = false

		# ПКМ = контекстный приказ (Атака -> Сбор -> Сдача в муравейник -> Движение)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			command_right_click(event.position)

	elif event is InputEventMouseMotion and selecting:
		var distance: float = selection_start.distance_to(event.position)
		if distance > DRAG_THRESHOLD:
			dragging_selection = true
			update_selection_box(selection_start, event.position)


func update_selection_box(start: Vector2, end: Vector2) -> void:
	selection_box.visible = true

	var top_left := Vector2(
		min(start.x, end.x),
		min(start.y, end.y)
	)

	var box_size := Vector2(
		abs(end.x - start.x),
		abs(end.y - start.y)
	)

	selection_box.position = top_left
	selection_box.size = box_size


func select_unit_at_mouse(mouse_position: Vector2, additive: bool) -> void:
	var result: Dictionary = raycast_from_mouse(mouse_position, FRIENDLY_MASK)

	if not additive:
		selection_controller.clear_selection()

	if result:
		var collider = result.get("collider")
		if collider is WorkerAnt and is_instance_valid(collider) and collider.state != WorkerAnt.UnitState.DEAD:
			if additive:
				selection_controller.toggle_unit(collider)
			else:
				selection_controller.add_unit(collider)


func select_units_in_box(start: Vector2, end: Vector2, additive: bool) -> void:
	var rect := Rect2(start, end - start).abs()
	var units := get_tree().get_nodes_in_group("selectable_units")
	var boxed_units: Array[WorkerAnt] = []

	for node in units:
		if node is not WorkerAnt or not is_instance_valid(node) or node.state == WorkerAnt.UnitState.DEAD:
			continue

		if node.collision_layer != 2:
			continue

		var unit: WorkerAnt = node
		if camera.is_position_behind(unit.global_position):
			continue

		var screen_position: Vector2 = camera.unproject_position(unit.global_position)
		if rect.has_point(screen_position):
			boxed_units.append(unit)

	if additive:
		for u in boxed_units:
			selection_controller.add_unit(u)
	else:
		selection_controller.replace_selection(boxed_units)


# ---------------------------------------------------------
# КОНТЕКСТНЫЙ ПКМ: ВРАГ -> РЕСУРС -> МУРАВЕЙНИК -> ЗЕМЛЯ
# ---------------------------------------------------------

func command_right_click(mouse_position: Vector2) -> void:
	var selected_units: Array[WorkerAnt] = selection_controller.get_selected_units()
	if selected_units.is_empty():
		return

	# 1. СНАЧАЛА ВРАГ (Layer 3, ENEMY_MASK = 4)
	var enemy_hit: Dictionary = raycast_from_mouse(mouse_position, ENEMY_MASK)
	if not enemy_hit.is_empty():
		var enemy = enemy_hit.get("collider")
		if enemy is WorkerAnt and enemy not in selected_units and is_instance_valid(enemy) and enemy.state != WorkerAnt.UnitState.DEAD:
			squad_controller.issue_attack(selected_units, enemy)
			return

	# 2. ПОТОМ РЕСУРС (Layer 4, RESOURCE_MASK = 8)
	var resource_hit: Dictionary = raycast_from_mouse(mouse_position, RESOURCE_MASK)
	if not resource_hit.is_empty():
		var resource = resource_hit.get("collider")
		if resource is ResourceSource and is_instance_valid(resource):
			squad_controller.issue_gather(selected_units, resource, anthill)
			return

	# 3. ПОТОМ МУРАВЕЙНИК / ЗДАНИЯ (Layer 5, BUILDING_MASK = 16)
	var building_hit: Dictionary = raycast_from_mouse(mouse_position, BUILDING_MASK)
	if not building_hit.is_empty():
		var bldg = building_hit.get("collider")
		if bldg is Anthill and is_instance_valid(bldg):
			squad_controller.issue_deposit(selected_units, bldg)
			return

	# 4. И ТОЛЬКО ПОТОМ ЗЕМЛЯ / МИР (Layer 1, WORLD_MASK = 1)
	var ground_hit: Dictionary = raycast_from_mouse(mouse_position, WORLD_MASK)
	if not ground_hit.is_empty():
		var target: Vector3 = ground_hit["position"]
		squad_controller.issue_move(selected_units, target)


func raycast_from_mouse(mouse_position: Vector2, mask: int) -> Dictionary:
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_position)
	var ray_end: Vector3 = ray_origin + ray_direction * 1000.0

	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end
	)

	query.collision_mask = mask

	return get_world_3d().direct_space_state.intersect_ray(query)
