extends CharacterBody3D
## Blocky third-person climber: movement, jump feel, camera rig and procedural animation.

const SPEED := 8.0
const GROUND_ACCEL := 70.0
const AIR_ACCEL := 32.0
const JUMP_V := 12.5
const GRAVITY := 30.0
const FALL_MULT := 1.3
const COYOTE := 0.12
const BUFFER := 0.15
const MAX_FALL := 42.0

var game
var cam_yaw := 0.0
var cam_pitch := -0.32
var cam_dist := 7.5
var coyote := 0.0
var buffer := 0.0
var fans: Array = []
var ext_vel := Vector3.ZERO
var knock_t := 0.0
var frozen := false
var boosted := false
var menu_orbit := false
var was_floor := true
var last_vy := 0.0
var walk_t := 0.0
var shake := 0.0
var view_offset := 0.0
var hat_id := -1
var shirt_col := Color(1.0, 0.42, 0.29)

var visual: Node3D
var legs: Array = []
var arms: Array = []
var head: Node3D
var hat_holder: Node3D
var hat_spin: Node3D
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var mats := {}


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.9
	cs.shape = cap
	cs.position.y = 0.95
	add_child(cs)
	_build_visual()
	_build_camera()


func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var k := c.to_html() + str(emit)
	if mats.has(k):
		return mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	mats[k] = m
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, c: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, pos: Vector3, tr: float, br: float, h: float, c: Color, segs := 12, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tr
	cm.bottom_radius = br
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var skin := Color(1.0, 0.85, 0.62)
	var pants := Color(0.2, 0.32, 0.62)
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.2 * side, 0.85, 0)
		visual.add_child(hip)
		_box(hip, Vector3(0, -0.42, 0), Vector3(0.34, 0.84, 0.36), pants)
		_box(hip, Vector3(0, -0.8, -0.06), Vector3(0.36, 0.14, 0.48), Color(0.15, 0.15, 0.2))
		legs.append(hip)
	_box(visual, Vector3(0, 1.27, 0), Vector3(0.8, 0.84, 0.44), shirt_col).name = "Torso"
	_box(visual, Vector3(0, 1.0, 0), Vector3(0.82, 0.14, 0.46), Color(0.25, 0.2, 0.15))
	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(0.53 * side, 1.62, 0)
		visual.add_child(sh)
		_box(sh, Vector3(0, -0.32, 0), Vector3(0.26, 0.5, 0.3), shirt_col)
		_box(sh, Vector3(0, -0.66, 0), Vector3(0.24, 0.22, 0.28), skin)
		arms.append(sh)
	head = Node3D.new()
	head.position = Vector3(0, 1.72, 0)
	visual.add_child(head)
	_box(head, Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.6), skin)
	_box(head, Vector3(-0.14, 0.36, -0.305), Vector3(0.09, 0.14, 0.02), Color(0.1, 0.1, 0.12))
	_box(head, Vector3(0.14, 0.36, -0.305), Vector3(0.09, 0.14, 0.02), Color(0.1, 0.1, 0.12))
	_box(head, Vector3(0, 0.18, -0.305), Vector3(0.22, 0.05, 0.02), Color(0.55, 0.2, 0.2))
	_box(head, Vector3(-0.24, 0.24, -0.305), Vector3(0.08, 0.05, 0.015), Color(1.0, 0.6, 0.55))
	_box(head, Vector3(0.24, 0.24, -0.305), Vector3(0.08, 0.05, 0.015), Color(1.0, 0.6, 0.55))
	hat_holder = Node3D.new()
	hat_holder.position = Vector3(0, 0.6, 0)
	head.add_child(hat_holder)
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func set_hat(id: int) -> void:
	hat_id = id
	hat_spin = null
	for c in hat_holder.get_children():
		c.queue_free()
	var h := Node3D.new()
	hat_holder.add_child(h)
	match id:
		1: # Sky cap
			_cyl(h, Vector3(0, 0.12, 0), 0.3, 0.34, 0.24, Color(0.2, 0.55, 1.0))
			_box(h, Vector3(0, 0.02, -0.38), Vector3(0.5, 0.05, 0.34), Color(0.15, 0.42, 0.85))
		2: # Party cone
			_cyl(h, Vector3(0, 0.36, 0), 0.0, 0.3, 0.72, Color(1.0, 0.3, 0.7), 10)
			_box(h, Vector3(0, 0.76, 0), Vector3(0.14, 0.14, 0.14), Color(1.0, 0.9, 0.2), 0.6)
		3: # Top hat
			_cyl(h, Vector3(0, 0.02, 0), 0.5, 0.5, 0.05, Color(0.1, 0.1, 0.12))
			_cyl(h, Vector3(0, 0.33, 0), 0.3, 0.3, 0.6, Color(0.12, 0.12, 0.15))
			_cyl(h, Vector3(0, 0.12, 0), 0.31, 0.31, 0.1, Color(0.85, 0.15, 0.2))
		4: # Propeller beanie
			_cyl(h, Vector3(0, 0.1, 0), 0.24, 0.34, 0.2, Color(1.0, 0.8, 0.2))
			_box(h, Vector3(0, 0.27, 0), Vector3(0.05, 0.16, 0.05), Color(0.3, 0.3, 0.3))
			hat_spin = Node3D.new()
			hat_spin.position.y = 0.36
			h.add_child(hat_spin)
			_box(hat_spin, Vector3.ZERO, Vector3(0.9, 0.03, 0.12), Color(1.0, 0.25, 0.25))
			_box(hat_spin, Vector3.ZERO, Vector3(0.12, 0.031, 0.9), Color(0.25, 0.5, 1.0))
		5: # Viking helm
			_cyl(h, Vector3(0, 0.08, 0), 0.26, 0.34, 0.22, Color(0.62, 0.64, 0.7))
			for s in [-1, 1]:
				var horn := _cyl(h, Vector3(0.4 * s, 0.22, 0), 0.0, 0.09, 0.42, Color(0.98, 0.95, 0.85), 8)
				horn.rotation.z = -0.8 * s
		6: # Crown
			_cyl(h, Vector3(0, 0.1, 0), 0.32, 0.32, 0.2, Color(1.0, 0.8, 0.15), 10, 0.3)
			for i in 5:
				var a := TAU * i / 5.0
				_box(h, Vector3(sin(a) * 0.28, 0.27, cos(a) * 0.28), Vector3(0.1, 0.16, 0.1), Color(1.0, 0.82, 0.2), 0.3)
			_box(h, Vector3(0, 0.12, -0.32), Vector3(0.1, 0.1, 0.03), Color(0.9, 0.1, 0.3), 0.8)
		7: # Halo
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.26
			tm.outer_radius = 0.34
			tm.rings = 16
			tm.ring_segments = 6
			t.mesh = tm
			t.material_override = _mat(Color(1.0, 0.95, 0.55), 2.0)
			t.position.y = 0.32
			h.add_child(t)
		_:
			pass


func set_shirt(c: Color) -> void:
	shirt_col = c


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = cam_dist
	spring.collision_mask = 1
	spring.margin = 0.3
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	spring.shape = sph
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 600.0
	spring.add_child(camera)
	camera.current = true


func snap_camera() -> void:
	cam_pivot.global_position = global_position + Vector3(0, 1.7, 0)


func add_shake(a: float) -> void:
	shake = max(shake, a)


func teleport(p: Vector3, yaw := 0.0) -> void:
	global_position = p
	velocity = Vector3.ZERO
	ext_vel = Vector3.ZERO
	fans.clear()
	knock_t = 0.0
	cam_yaw = yaw
	visual.rotation.y = yaw
	snap_camera()


func knock(v: Vector3) -> void:
	ext_vel = Vector3(v.x, 0, v.z)
	velocity.y = v.y
	knock_t = 0.45
	coyote = 0.0


func launch(vy: float) -> void:
	velocity.y = vy
	boosted = true
	coyote = 0.0
	buffer = 0.0
	visual.scale = Vector3(0.8, 1.3, 0.8)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.0032
		cam_pitch = clampf(cam_pitch - mm.relative.y * 0.0028, -1.25, 0.45)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = clampf(cam_dist - 0.6, 4.0, 12.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clampf(cam_dist + 0.6, 4.0, 12.0)


func _physics_process(delta: float) -> void:
	var playing: bool = game.is_playing() and not frozen
	var inp := Vector2.ZERO
	if playing:
		inp = game.get_move_input()
		if game.jump_just_pressed():
			buffer = BUFFER
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var wish := right * inp.x + fwd * inp.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var on_floor := is_on_floor()
	if on_floor:
		coyote = COYOTE
		if velocity.y <= 0.0:
			boosted = false
	else:
		coyote -= delta
	buffer -= delta
	knock_t -= delta
	# Horizontal control velocity
	var hv := Vector3(velocity.x - ext_vel.x, 0, velocity.z - ext_vel.z)
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	if knock_t > 0.0:
		accel *= 0.25
	hv = hv.move_toward(wish * SPEED, accel * delta)
	# External velocity (wind, knockback) decays
	var in_wind := false
	for f in fans:
		if not is_instance_valid(f):
			continue
		if f.push.y > 0.5:
			velocity.y = minf(velocity.y + f.strength * delta, f.max_up)
			coyote = 0.0
		else:
			in_wind = true
			ext_vel = ext_vel.move_toward(Vector3(f.push.x, 0, f.push.z) * f.strength, 22.0 * delta)
	if not in_wind:
		ext_vel = ext_vel.move_toward(Vector3.ZERO, (14.0 if on_floor else 4.0) * delta)
	# Gravity
	if not on_floor:
		var g := GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0)
		if velocity.y > 0.0 and playing and not game.jump_held() and knock_t <= 0.0 and fans.is_empty() and not boosted:
			g *= 1.8
		velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)
	# Jump
	if buffer > 0.0 and coyote > 0.0 and playing:
		velocity.y = JUMP_V
		buffer = 0.0
		coyote = 0.0
		visual.scale = Vector3(0.78, 1.28, 0.78)
		game.sfx.play("jump")
		game.puff(global_position, Color(1, 1, 1, 0.8), 6)
	velocity.x = hv.x + ext_vel.x
	velocity.z = hv.z + ext_vel.z
	last_vy = velocity.y
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not was_floor and last_vy < -9.0:
		visual.scale = Vector3(1.3, 0.72, 1.3)
		game.sfx.play("land")
		game.puff(global_position, Color(0.95, 0.95, 0.9, 0.8), 8)
		if last_vy < -22.0:
			add_shake(0.25)
	was_floor = now_floor
	# Face movement
	var flat := Vector2(hv.x, hv.z)
	if flat.length() > 0.5:
		var target := atan2(-hv.x, -hv.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target, minf(1.0, 14.0 * delta))
	_animate(delta, flat.length(), now_floor)


func _animate(delta: float, hspeed: float, on_floor: bool) -> void:
	visual.scale = visual.scale.lerp(Vector3.ONE, minf(1.0, 10.0 * delta))
	var k := clampf(hspeed / SPEED, 0.0, 1.0)
	if on_floor:
		walk_t += delta * (4.0 + 9.0 * k)
		var sw := sin(walk_t) * 0.85 * k
		legs[0].rotation.x = sw
		legs[1].rotation.x = -sw
		arms[0].rotation.x = -sw * 0.9
		arms[1].rotation.x = sw * 0.9
		arms[0].rotation.z = lerpf(arms[0].rotation.z, 0.0, 10.0 * delta)
		arms[1].rotation.z = lerpf(arms[1].rotation.z, 0.0, 10.0 * delta)
		visual.position.y = absf(sin(walk_t)) * 0.08 * k
	else:
		legs[0].rotation.x = lerpf(legs[0].rotation.x, 0.5, 8.0 * delta)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, -0.3, 8.0 * delta)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, -2.6, 8.0 * delta)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, -2.6, 8.0 * delta)
		arms[0].rotation.z = lerpf(arms[0].rotation.z, -0.35, 8.0 * delta)
		arms[1].rotation.z = lerpf(arms[1].rotation.z, 0.35, 8.0 * delta)
		visual.position.y = 0.0
	if hat_spin:
		hat_spin.rotation.y += delta * (6.0 + 18.0 * k)


func _process(delta: float) -> void:
	if menu_orbit:
		cam_yaw += delta * 0.18
	elif game.is_playing():
		var turn: float = game.get_cam_turn()
		cam_yaw -= turn * 2.4 * delta
		var td: Vector2 = game.consume_touch_cam()
		cam_yaw -= td.x * 0.006
		cam_pitch = clampf(cam_pitch - td.y * 0.005, -1.25, 0.45)
	var target := global_position + Vector3(0, 1.7, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, minf(1.0, 12.0 * delta))
	cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	spring.spring_length = lerpf(spring.spring_length, cam_dist, minf(1.0, 6.0 * delta))
	shake = maxf(0.0, shake - delta * 1.6)
	var s := shake * shake
	camera.h_offset = randf_range(-1.0, 1.0) * s
	camera.v_offset = view_offset + randf_range(-1.0, 1.0) * s
