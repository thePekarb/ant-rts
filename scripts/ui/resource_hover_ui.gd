class_name ResourceHoverUI
extends CanvasLayer


@export var raycast_mask: int = 8 # Layer 4 (Resource)
@export var offset_from_cursor: Vector2 = Vector2(20, 15)

var panel: PanelContainer
var title_label: Label
var amount_label: Label
var progress_bar: ProgressBar

var current_hovered_resource: ResourceSource = null


func _ready() -> void:
	build_ui()
	panel.visible = false


func build_ui() -> void:
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(170, 75)

	# Стилизация карточки
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.10, 0.92)
	style.border_color = Color(0.85, 0.65, 0.35, 0.95)
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.text = "Хлеб"
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	vbox.add_child(title_label)

	amount_label = Label.new()
	amount_label.text = "42 / 42 ед."
	amount_label.add_theme_font_size_override("font_size", 13)
	amount_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	vbox.add_child(amount_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(146, 12)
	progress_bar.show_percentage = false
	progress_bar.min_value = 0
	progress_bar.max_value = 42
	progress_bar.value = 42

	var bg_bar := StyleBoxFlat.new()
	bg_bar.bg_color = Color(0.2, 0.18, 0.16, 0.85)
	bg_bar.corner_radius_bottom_left = 3
	bg_bar.corner_radius_bottom_right = 3
	bg_bar.corner_radius_top_left = 3
	bg_bar.corner_radius_top_right = 3
	progress_bar.add_theme_stylebox_override("background", bg_bar)

	var fill_bar := StyleBoxFlat.new()
	fill_bar.bg_color = Color(0.92, 0.68, 0.28, 1.0)
	fill_bar.corner_radius_bottom_left = 3
	fill_bar.corner_radius_bottom_right = 3
	fill_bar.corner_radius_top_left = 3
	fill_bar.corner_radius_top_right = 3
	progress_bar.add_theme_stylebox_override("fill", fill_bar)

	vbox.add_child(progress_bar)
	add_child(panel)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		panel.visible = false
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_pos)
	var ray_end: Vector3 = ray_origin + ray_direction * 1000.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = raycast_mask

	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider is ResourceSource and is_instance_valid(collider) and not collider.is_depleted():
			set_hovered_resource(collider)
			panel.visible = true
			panel.position = mouse_pos + offset_from_cursor
			return

	panel.visible = false
	current_hovered_resource = null


func set_hovered_resource(res: ResourceSource) -> void:
	if current_hovered_resource != res:
		current_hovered_resource = res

	title_label.text = res.display_name
	amount_label.text = "%d / %d ед." % [res.remaining_amount, res.max_amount]
	progress_bar.max_value = res.max_amount
	progress_bar.value = res.remaining_amount
