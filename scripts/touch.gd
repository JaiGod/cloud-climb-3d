extends Control
## On-screen controls for phones: floating joystick (left), jump button (right), drag anywhere else to look.

const R := 64.0

var move := Vector2.ZERO
var jump_pressed := false
var jump_held := false
var cam_delta := Vector2.ZERO
var used := false
var stick_idx := -1
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var cam_idx := -1
var cam_last := Vector2.ZERO
var jump_idx := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func jump_center() -> Vector2:
	return Vector2(size.x - 96.0, size.y - 110.0)


func stick_home() -> Vector2:
	return Vector2(110.0, size.y - 120.0)


func release_all() -> void:
	stick_idx = -1
	cam_idx = -1
	jump_idx = -1
	move = Vector2.ZERO
	jump_held = false
	queue_redraw()


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		used = true
		if not is_visible_in_tree():
			return
		var p: Vector2 = e.position
		if e.pressed:
			if p.distance_to(jump_center()) < 78.0 and jump_idx == -1:
				jump_idx = e.index
				jump_pressed = true
				jump_held = true
			elif p.x < size.x * 0.45 and p.y > size.y * 0.3 and stick_idx == -1:
				stick_idx = e.index
				stick_center = p
				stick_pos = p
			elif cam_idx == -1 and p.y > 64.0:
				cam_idx = e.index
				cam_last = p
		else:
			if e.index == jump_idx:
				jump_idx = -1
				jump_held = false
			if e.index == stick_idx:
				stick_idx = -1
				move = Vector2.ZERO
			if e.index == cam_idx:
				cam_idx = -1
		queue_redraw()
	elif e is InputEventScreenDrag and is_visible_in_tree():
		var p: Vector2 = e.position
		if e.index == stick_idx:
			stick_pos = p
			var v := (stick_pos - stick_center) / R
			if v.length() > 1.0:
				v = v.normalized()
			move = Vector2(v.x, -v.y)
			queue_redraw()
		elif e.index == cam_idx:
			cam_delta += p - cam_last
			cam_last = p


func _draw() -> void:
	if not used:
		return
	var c := stick_center if stick_idx >= 0 else stick_home()
	draw_circle(c, R + 6.0, Color(0.05, 0.1, 0.25, 0.25))
	draw_arc(c, R, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	var k := c + Vector2(move.x, -move.y) * R
	draw_circle(k, 28.0, Color(1, 1, 1, 0.75 if stick_idx >= 0 else 0.45))
	var j := jump_center()
	draw_circle(j, 52.0, Color(0.3, 0.85, 0.5, 0.75 if jump_held else 0.5))
	draw_arc(j, 52.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 3.0, true)
	var pts := PackedVector2Array([j + Vector2(0, -22), j + Vector2(20, 4), j + Vector2(7, 4), j + Vector2(7, 20), j + Vector2(-7, 20), j + Vector2(-7, 4), j + Vector2(-20, 4)])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.95))
