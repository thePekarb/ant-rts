class_name CursorManager
extends Node


enum CursorType {
	DEFAULT,
	ATTACK,
	GATHER,
	DEPOSIT,
	SELECT
}

var current_cursor: CursorType = CursorType.DEFAULT

var tex_default: ImageTexture
var tex_attack: ImageTexture
var tex_gather: ImageTexture
var tex_deposit: ImageTexture
var tex_select: ImageTexture


func _ready() -> void:
	generate_cursor_textures()
	set_cursor(CursorType.DEFAULT)


func generate_cursor_textures() -> void:
	tex_default = create_default_cursor()
	tex_attack = create_attack_cursor()
	tex_gather = create_gather_cursor()
	tex_deposit = create_deposit_cursor()
	tex_select = create_select_cursor()


func set_cursor(type: CursorType) -> void:
	if current_cursor == type:
		return
	current_cursor = type

	match type:
		CursorType.DEFAULT:
			Input.set_custom_mouse_cursor(tex_default, Input.CURSOR_ARROW, Vector2(0, 0))
		CursorType.ATTACK:
			Input.set_custom_mouse_cursor(tex_attack, Input.CURSOR_ARROW, Vector2(16, 16))
		CursorType.GATHER:
			Input.set_custom_mouse_cursor(tex_gather, Input.CURSOR_ARROW, Vector2(16, 16))
		CursorType.DEPOSIT:
			Input.set_custom_mouse_cursor(tex_deposit, Input.CURSOR_ARROW, Vector2(16, 16))
		CursorType.SELECT:
			Input.set_custom_mouse_cursor(tex_select, Input.CURSOR_ARROW, Vector2(0, 0))


# ---------------------------------------------------------
# ГЕНЕРАЦИЯ КУРСОРОВ (32x32 RGBA)
# ---------------------------------------------------------

func create_default_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Белая RTS-стрелка с черным контуром
	for y in range(20):
		for x in range(15):
			if x <= y * 0.75:
				if x == 0 or y == 0 or x == int(y * 0.75) or (y > 14 and (x == y - 14 or y == 19)):
					img.set_pixel(x, y, Color(0.08, 0.08, 0.08, 1.0))
				else:
					img.set_pixel(x, y, Color(0.96, 0.96, 0.96, 1.0))

	# Хвостик стрелки
	for i in range(8):
		var px: int = 7 + int(i * 0.7)
		var py: int = 12 + i
		if px < 31 and py < 31:
			img.set_pixel(px, py, Color(0.96, 0.96, 0.96, 1.0))
			img.set_pixel(px + 1, py, Color(0.08, 0.08, 0.08, 1.0))
			img.set_pixel(px - 1, py, Color(0.08, 0.08, 0.08, 1.0))

	return ImageTexture.create_from_image(img)


func create_attack_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Меч / боевой прицел красного цвета
	var col_red := Color(1.0, 0.22, 0.22, 1.0)
	var col_dark := Color(0.2, 0.0, 0.0, 1.0)
	var col_silver := Color(0.95, 0.95, 1.0, 1.0)

	# Лезвие меча по диагонали
	for i in range(18):
		var x: int = 7 + i
		var y: int = 24 - i
		if x >= 0 and x < 32 and y >= 0 and y < 32:
			img.set_pixel(x, y, col_silver)
			if x + 1 < 32: img.set_pixel(x + 1, y, col_dark)
			if y + 1 < 32: img.set_pixel(x, y + 1, col_dark)
			if x - 1 >= 0: img.set_pixel(x - 1, y, col_red)
			if y - 1 >= 0: img.set_pixel(x, y - 1, col_red)

	# Гарда
	for g in range(-4, 5):
		var gx: int = 11 + g
		var gy: int = 20 + g
		if gx >= 0 and gx < 32 and gy >= 0 and gy < 32:
			img.set_pixel(gx, gy, Color(0.9, 0.75, 0.2, 1.0))

	# Рукоять
	for h in range(4):
		var hx: int = 8 - h
		var hy: int = 23 + h
		if hx >= 0 and hx < 32 and hy >= 0 and hy < 32:
			img.set_pixel(hx, hy, Color(0.5, 0.25, 0.1, 1.0))

	return ImageTexture.create_from_image(img)


func create_gather_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Золотой серп / шестеренка добычи
	var col_gold := Color(1.0, 0.82, 0.25, 1.0)
	var col_dark := Color(0.22, 0.15, 0.05, 1.0)
	var center := Vector2(16, 16)

	for y in range(32):
		for x in range(32):
			var d: float = center.distance_to(Vector2(x, y))
			if d >= 7.0 and d <= 12.0:
				var angle: float = atan2(y - center.y, x - center.x)
				if angle > -2.4 and angle < 1.8:
					if d < 8.0 or d > 11.0:
						img.set_pixel(x, y, col_dark)
					else:
						img.set_pixel(x, y, col_gold)

	# Рукоятка
	for i in range(7):
		var hx: int = 10 - i
		var hy: int = 22 + i
		if hx >= 0 and hx < 32 and hy >= 0 and hy < 32:
			img.set_pixel(hx, hy, Color(0.55, 0.35, 0.15, 1.0))
			if hx + 1 < 32: img.set_pixel(hx + 1, hy, col_dark)

	return ImageTexture.create_from_image(img)


func create_deposit_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Изумрудная стрелка сдачи / домик
	var col_green := Color(0.25, 1.0, 0.5, 1.0)
	var col_dark := Color(0.05, 0.25, 0.1, 1.0)

	# Крыша домика
	for y in range(6, 15):
		var w: int = (y - 6) * 2
		for x in range(16 - w / 2, 16 + w / 2 + 1):
			if x >= 0 and x < 32 and y >= 0 and y < 32:
				if x == 16 - w / 2 or x == 16 + w / 2 or y == 6:
					img.set_pixel(x, y, col_dark)
				else:
					img.set_pixel(x, y, col_green)

	# База домика
	for y in range(15, 25):
		for x in range(10, 23):
			if x == 10 or x == 22 or y == 24:
				img.set_pixel(x, y, col_dark)
			elif x >= 14 and x <= 18 and y >= 18:
				img.set_pixel(x, y, col_dark) # Дверь
			else:
				img.set_pixel(x, y, col_green)

	return ImageTexture.create_from_image(img)


func create_select_cursor() -> ImageTexture:
	return create_default_cursor()
