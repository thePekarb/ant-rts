class_name ColonyResourceHUD
extends CanvasLayer


@export var anthill_path: NodePath

var panel: PanelContainer
var food_label: Label
var float_container: Control


func _ready() -> void:
	build_ui()
	call_deferred("connect_to_anthill")


func build_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(160, 48)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.08, 0.90)
	style.border_color = Color(0.85, 0.65, 0.35, 0.95)
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	var icon_label := Label.new()
	icon_label.text = "🌾 Еда:"
	icon_label.add_theme_font_size_override("font_size", 16)
	icon_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	hbox.add_child(icon_label)

	food_label = Label.new()
	food_label.text = "0"
	food_label.add_theme_font_size_override("font_size", 18)
	food_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	hbox.add_child(food_label)

	add_child(panel)

	# Контейнер для всплывающего текста (+1)
	float_container = Control.new()
	float_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_container.position = Vector2(24, 24)
	add_child(float_container)


func connect_to_anthill() -> void:
	var anthill: Anthill = null

	if not anthill_path.is_empty():
		anthill = get_node_or_null(anthill_path) as Anthill

	if anthill == null:
		var dropoffs := get_tree().get_nodes_in_group("resource_dropoff")
		if not dropoffs.is_empty() and dropoffs[0] is Anthill:
			anthill = dropoffs[0]

	if anthill != null:
		anthill.storage_changed.connect(_on_anthill_storage_changed)
		food_label.text = str(anthill.get_resource_amount("food"))
		print("[ColonyResourceHUD] Подключен к муравейнику: ", anthill.name)


func _on_anthill_storage_changed(resource_id: StringName, current_amount: int, delta_amount: int) -> void:
	if resource_id == StringName("food") or resource_id == StringName(""):
		food_label.text = str(current_amount)
		if delta_amount > 0:
			spawn_floating_popup("+" + str(delta_amount))


func spawn_floating_popup(text_val: String) -> void:
	var popup := Label.new()
	popup.text = text_val
	popup.add_theme_font_size_override("font_size", 16)
	popup.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	popup.position = Vector2(170, 10)
	float_container.add_child(popup)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 24.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(popup.queue_free)
