class_name HoverController
extends Node


const WORLD_MASK: int = 1
const FRIENDLY_MASK: int = 2
const ENEMY_MASK: int = 4
const RESOURCE_MASK: int = 8
const BUILDING_MASK: int = 16

var cursor_manager: CursorManager = null
var current_hovered_object: Node3D = null
var hover_indicator_node: MeshInstance3D = null


func _ready() -> void:
	cursor_manager = CursorManager.new()
	add_child(cursor_manager)
	create_generic_hover_indicator()


func create_generic_hover_indicator() -> void:
	hover_indicator_node = MeshInstance3D.new()
	hover_indicator_node.name = "GlobalHoverIndicator"
	hover_indicator_node.visible = false
	add_child(hover_indicator_node)


func update_hover(camera: Camera3D, mouse_pos: Vector2, has_selection: bool) -> void:
	if camera == null:
		clear_hover()
		return

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_pos)
	var ray_end: Vector3 = ray_origin + ray_direction * 1000.0

	var space_state := camera.get_world_3d().direct_space_state

	# 1. Проверяем врагов (ENEMY_MASK = 4)
	var hit_enemy: Dictionary = raycast(space_state, ray_origin, ray_end, ENEMY_MASK)
	if not hit_enemy.is_empty():
		var enemy = hit_enemy.get("collider")
		if enemy is WorkerAnt and is_instance_valid(enemy) and enemy.state != WorkerAnt.UnitState.DEAD:
			set_hover(enemy, CursorManager.CursorType.ATTACK, Color(1.0, 0.25, 0.25, 0.95), enemy.body_radius * 1.35)
			return

	# 2. Проверяем ресурсы (RESOURCE_MASK = 8)
	var hit_res: Dictionary = raycast(space_state, ray_origin, ray_end, RESOURCE_MASK)
	if not hit_res.is_empty():
		var res = hit_res.get("collider")
		if res is ResourceSource and is_instance_valid(res) and not res.is_depleted():
			set_hover_resource(res)
			return

	# 3. Проверяем здания / муравейник (BUILDING_MASK = 16)
	var hit_building: Dictionary = raycast(space_state, ray_origin, ray_end, BUILDING_MASK)
	if not hit_building.is_empty():
		var bldg = hit_building.get("collider")
		if bldg is Anthill and is_instance_valid(bldg):
			set_hover(bldg, CursorManager.CursorType.DEPOSIT, Color(0.25, 1.0, 0.65, 0.95), bldg.obstacle_radius * 1.25)
			return

	# 4. Проверяем дружественных муравьёв (FRIENDLY_MASK = 2)
	var hit_friendly: Dictionary = raycast(space_state, ray_origin, ray_end, FRIENDLY_MASK)
	if not hit_friendly.is_empty():
		var ally = hit_friendly.get("collider")
		if ally is WorkerAnt and is_instance_valid(ally) and ally.state != WorkerAnt.UnitState.DEAD:
			set_hover(ally, CursorManager.CursorType.SELECT, Color(0.4, 0.85, 1.0, 0.8), ally.body_radius * 1.35)
			return

	# Ничего не под курсором
	clear_hover()


func raycast(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	return space_state.intersect_ray(query)


func set_hover(obj: Node3D, cursor: CursorManager.CursorType, color: Color, radius: float) -> void:
	current_hovered_object = obj
	cursor_manager.set_cursor(cursor)

	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.9
	ring.outer_radius = radius * 1.1
	ring.rings = 32
	ring.ring_segments = 16

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	hover_indicator_node.mesh = ring
	hover_indicator_node.global_position = Vector3(obj.global_position.x, 0.04, obj.global_position.z)
	hover_indicator_node.visible = true


func set_hover_resource(res: ResourceSource) -> void:
	current_hovered_object = res
	cursor_manager.set_cursor(CursorManager.CursorType.GATHER)

	var w: float = res.obstacle_half_size.x * 2.0 + 0.3
	var h: float = res.obstacle_half_size.y * 2.0 + 0.3

	var box := BoxMesh.new()
	box.size = Vector3(w, 0.06, h)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.3, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = mat

	hover_indicator_node.mesh = box
	hover_indicator_node.global_position = Vector3(res.global_position.x, 0.03, res.global_position.z)
	hover_indicator_node.visible = true


func clear_hover() -> void:
	current_hovered_object = null
	if cursor_manager != null:
		cursor_manager.set_cursor(CursorManager.CursorType.DEFAULT)
	if hover_indicator_node != null:
		hover_indicator_node.visible = false
