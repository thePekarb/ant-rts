extends Node3D


# Скорость перемещения камеры по карте.
@export var move_speed: float = 10.0

# Насколько сильно приближаемся за один шаг колеса.
@export var zoom_step: float = 1.0

# Минимальное приближение.
@export var min_zoom: float = 4.0

# Максимальное отдаление.
@export var max_zoom: float = 18.0


# Получаем дочернюю камеру.
@onready var camera: Camera3D = $Camera3D


# Текущее расстояние камеры.
var zoom_distance: float = 8.0


func _ready() -> void:
	# Ставим начальное положение камеры.
	update_zoom()


func _process(delta: float) -> void:
	# Получаем WASD как Vector2.
	var input_direction := Input.get_vector(
		"camera_left",
		"camera_right",
		"camera_forward",
		"camera_back"
	)

	# Превращаем 2D-направление клавиатуры
	# в направление по земле X/Z.
	var move_direction := Vector3(
		input_direction.x,
		0.0,
		input_direction.y
	)

	# Двигаем весь CameraRig.
	global_position += move_direction * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:

		# Колесо вверх = приблизить.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_distance -= zoom_step
			update_zoom()

		# Колесо вниз = отдалить.
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_distance += zoom_step
			update_zoom()


func update_zoom() -> void:
	# Не разрешаем приблизиться/отдалиться слишком сильно.
	zoom_distance = clamp(
		zoom_distance,
		min_zoom,
		max_zoom
	)

	# Камера одновременно поднимается
	# и отходит назад.
	camera.position = Vector3(
		0.0,
		zoom_distance,
		zoom_distance
	)
