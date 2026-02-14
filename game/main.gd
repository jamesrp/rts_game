extends Node2D

var player_pos := Vector2(400, 300)
var player_speed := 200.0
var player_size := 20.0
var trail := PackedVector2Array()
var max_trail := 50
var hue := 0.0

func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()
		player_pos += direction * player_speed * delta
		# Keep in bounds
		player_pos.x = clamp(player_pos.x, player_size, 800 - player_size)
		player_pos.y = clamp(player_pos.y, player_size, 600 - player_size)

	# Update trail
	trail.append(player_pos)
	if trail.size() > max_trail:
		trail = trail.slice(trail.size() - max_trail)

	# Cycle hue
	hue = fmod(hue + delta * 0.2, 1.0)

	queue_redraw()

func _draw() -> void:
	# Draw background grid
	var grid_color := Color(0.15, 0.15, 0.2)
	for x in range(0, 801, 40):
		draw_line(Vector2(x, 0), Vector2(x, 600), grid_color)
	for y in range(0, 601, 40):
		draw_line(Vector2(0, y), Vector2(800, y), grid_color)

	# Draw trail
	for i in range(trail.size()):
		var t := float(i) / float(trail.size())
		var trail_hue := fmod(hue + t * 0.5, 1.0)
		var color := Color.from_hsv(trail_hue, 0.7, 0.9, t * 0.6)
		var radius := player_size * 0.3 * t
		draw_circle(trail[i], radius, color)

	# Draw player
	var player_color := Color.from_hsv(hue, 0.8, 1.0)
	draw_circle(player_pos, player_size, player_color)
	draw_circle(player_pos, player_size * 0.6, Color.WHITE)

	# Draw instructions
	draw_string(ThemeDB.fallback_font, Vector2(10, 30),
		"Arrow keys to move!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(1, 1, 1, 0.7))
