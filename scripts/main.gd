extends Node3D
## Cloud Climb 3D — game flow, UI, saving, effects. Everything is built in code from primitives.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const TouchScript := preload("res://scripts/touch.gd")

const MAX_HEARTS := 5
const SAVE_PATH := "user://cloudclimb.cfg"
const HATS := [
	["No Hat", 0], ["Sky Cap", 10], ["Party Cone", 25], ["Top Hat", 40],
	["Propeller", 60], ["Viking Helm", 80], ["Royal Crown", 120], ["Halo", 160],
]
enum { TITLE, PLAYING, PAUSED, COMPLETE, FAILED, SHOP }

var state := TITLE
var world
var player
var sfx
var touch
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D

var stage := 0
var hearts := MAX_HEARTS
var stage_time := 0.0
var timer_on := false
var stage_coins := 0
var respawn_pos := Vector3.ZERO
var current_cp = null
var dying := false
var captured_once := false
var knock_cd := 0.0

# save data
var coins := 0
var unlocked := 1
var best: Array = []
var best_coins: Array = []
var owned: Array = [0]
var hat := 0
var sound_on := true
var deaths := 0

# ui
var ui_root: Control
var screens := {}
var theme_res: Theme
var hud_stage: Label
var hud_timer: Label
var hud_best: Label
var hud_coins: Label
var hearts_ctrl: Control
var toast: Label
var banner: Label
var hint: Label
var title_coins: Label
var sound_btns: Array = []
var stage_grid: GridContainer
var hat_grid: GridContainer
var hat_coins: Label
var res_title: Label
var res_body: Label
var res_next: Button
var fail_body: Label
var pmats := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load()
	_build_env()
	sfx = SfxScript.new()
	add_child(sfx)
	world = WorldScript.new()
	world.game = self
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.build_all()
	player = PlayerScript.new()
	player.game = self
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.set_hat(hat)
	_build_ui()
	get_window().size_changed.connect(_on_resize)
	_on_resize()
	sfx.set_enabled(sound_on)
	if not sound_on:
		sfx.music.stop()
	_enter_stage(clampi(unlocked - 1, 0, 7), false)
	_go_title()
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		if q.begins_with("?shot="):
			_showcase(clampi(int(q.substr(6)), 1, 8) - 1)
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke_test()


# ------------------------------------------------------------------ input
func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_key("left", [KEY_A, KEY_LEFT])
	_add_key("right", [KEY_D, KEY_RIGHT])
	_add_key("forward", [KEY_W, KEY_UP])
	_add_key("back", [KEY_S, KEY_DOWN])
	_add_key("jump", [KEY_SPACE])
	_add_key("pause", [KEY_ESCAPE, KEY_P])
	_add_key("respawn", [KEY_R])
	_add_key("cam_left", [KEY_Q])
	_add_key("cam_right", [KEY_E])


func is_playing() -> bool:
	return state == PLAYING


func get_move_input() -> Vector2:
	var v := Vector2(Input.get_axis("left", "right"), Input.get_axis("back", "forward"))
	v += touch.move
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() > 0.1:
		_start_timer()
	return v


func jump_just_pressed() -> bool:
	var j: bool = Input.is_action_just_pressed("jump") or touch.jump_pressed
	touch.jump_pressed = false
	if j:
		_start_timer()
	return j


func jump_held() -> bool:
	return Input.is_action_pressed("jump") or touch.jump_held


func get_cam_turn() -> float:
	return Input.get_axis("cam_left", "cam_right")


func consume_touch_cam() -> Vector2:
	var d: Vector2 = touch.cam_delta
	touch.cam_delta = Vector2.ZERO
	return d


func _start_timer() -> void:
	if state == PLAYING and not timer_on and stage_time == 0.0:
		timer_on = true


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		if state == PLAYING:
			_pause()
		elif state == PAUSED:
			_resume()
		return
	if state == PLAYING:
		if e.is_action_pressed("respawn") and not dying:
			_respawn_now()
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not touch.used:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			captured_once = true


# ------------------------------------------------------------------ environment
func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.92)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.05
	env.fog_enabled = true
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)


func _apply_palette(p: Dictionary) -> void:
	sky_mat.sky_top_color = p.sky
	sky_mat.sky_horizon_color = p.hor
	sky_mat.ground_horizon_color = p.hor
	sky_mat.ground_bottom_color = p.hor.lerp(Color.WHITE, 0.4)
	env.fog_light_color = p.hor
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(p.hor, 0.25)


# ------------------------------------------------------------------ effects
func _pmat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if pmats.has(k):
		return pmats[k]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmats[k] = mt
	return mt


func burst(pos: Vector3, c: Color, n: int, spd := 6.0, sz := 0.18, grav := -12.0, life := 0.9) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = n
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = spd * 0.5
	p.initial_velocity_max = spd
	p.gravity = Vector3(0, grav, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * sz
	bm.material = _pmat(c)
	p.mesh = bm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3, true).timeout.connect(p.queue_free)


func puff(pos: Vector3, c: Color, n: int) -> void:
	burst(pos + Vector3(0, 0.1, 0), c, n, 2.5, 0.22, 1.5, 0.45)


func blink_poof(pos: Vector3, c: Color) -> void:
	burst(pos, c, 10, 3.0, 0.25, -6.0, 0.6)
	sfx.play("poof", 1.3)


func confetti(pos: Vector3) -> void:
	for c in [Color(1, 0.3, 0.4), Color(1, 0.85, 0.2), Color(0.3, 0.8, 1), Color(0.5, 1, 0.5)]:
		burst(pos, c, 14, 9.0, 0.2, -9.0, 1.4)


# ------------------------------------------------------------------ gameplay
func _enter_stage(i: int, play := true) -> void:
	for k in world.stages.size():
		world.set_stage_active(k, k == i)
	stage = i
	world.reset_stage(i)
	var s: Dictionary = world.stages[i]
	_apply_palette(s.pal)
	current_cp = s.start
	s.start.set_active(true)
	respawn_pos = s.start.spawn
	hearts = MAX_HEARTS
	stage_time = 0.0
	timer_on = false
	stage_coins = 0
	dying = false
	player.frozen = false
	player.visible = true
	player.teleport(respawn_pos, 0.0)
	player.cam_pitch = -0.3
	if play:
		state = PLAYING
		player.menu_orbit = false
		player.view_offset = 0.0
		player.cam_dist = 7.5
		_show("hud")
		_update_hud()
		_banner("STAGE %d\n%s" % [i + 1, s.name])
		hint.modulate.a = 1.0 if i == 0 else 0.0
		if i == 0:
			var tw := create_tween()
			tw.tween_interval(9.0)
			tw.tween_property(hint, "modulate:a", 0.0, 1.0)
		get_tree().paused = false


func on_coin(c: Node) -> void:
	coins += 1
	stage_coins += 1
	sfx.play("coin", 1.0 + 0.04 * (stage_coins % 6))
	burst(c.global_position, Color(1, 0.85, 0.2), 10, 5.0, 0.14, -10.0, 0.6)
	_update_hud()
	_pop(hud_coins)


func on_checkpoint(cp: Node) -> void:
	if cp == current_cp or state != PLAYING:
		return
	if current_cp:
		current_cp.set_active(false)
	current_cp = cp
	cp.set_active(true)
	respawn_pos = cp.spawn
	hearts = MAX_HEARTS
	sfx.play("checkpoint")
	confetti(cp.global_position + Vector3(0, 1.5, 0))
	_toast("CHECKPOINT!  Hearts refilled", Color(0.5, 1.0, 0.6))
	_update_hud()
	_save()


func knock(v: Vector3) -> void:
	if state != PLAYING or knock_cd > 0.0 or dying:
		return
	knock_cd = 0.4
	player.knock(v)
	player.add_shake(0.35)
	sfx.play("knock")
	burst(player.global_position + Vector3(0, 1, 0), Color(1, 1, 1), 8, 5.0, 0.15, -8.0, 0.5)


func die(_reason: String) -> void:
	if state != PLAYING or dying:
		return
	dying = true
	hearts -= 1
	deaths += 1
	player.frozen = true
	player.add_shake(0.5)
	sfx.play("die")
	burst(player.global_position + Vector3(0, 1, 0), Color(1.0, 0.45, 0.25), 18, 7.0, 0.22, -6.0, 0.8)
	player.visible = false
	_update_hud()
	_pop(hearts_ctrl)
	await get_tree().create_timer(0.7, false).timeout
	if state != PLAYING:
		return
	if hearts <= 0:
		_fail()
	else:
		_respawn_now()


func _respawn_now() -> void:
	dying = false
	player.frozen = false
	player.visible = true
	var yaw: float = player.cam_yaw
	player.teleport(respawn_pos, yaw)
	puff(respawn_pos, Color(1, 1, 1, 0.9), 12)
	sfx.play("poof")


func on_goal() -> void:
	if state != PLAYING or dying:
		return
	state = COMPLETE
	timer_on = false
	player.frozen = true
	var s: Dictionary = world.stages[stage]
	confetti(s.goal_ring.global_position)
	confetti(player.global_position + Vector3(0, 2, 0))
	sfx.play("win")
	var t := stage_time
	var prev: float = best[stage]
	var new_best := prev < 0.0 or t < prev
	if new_best:
		best[stage] = t
	best_coins[stage] = maxi(best_coins[stage], stage_coins)
	unlocked = clampi(maxi(unlocked, stage + 2), 1, 8)
	_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var total: int = s.coins.size()
	await get_tree().create_timer(1.1, false).timeout
	if state != COMPLETE:
		return
	if stage == 7:
		res_title.text = "SKY CHAMPION!"
		var sum := 0.0
		for b in best:
			sum += maxf(0.0, b)
		res_body.text = "You conquered all 8 sky islands!\nFinal stage: %s%s\nBest-time total: %s\nCoins this run: %d / %d   Wallet: %d" % [
			_fmt(t), "  NEW BEST!" if new_best else "", _fmt(sum), stage_coins, total, coins]
		res_next.text = "Stage Select"
	else:
		res_title.text = "STAGE CLEAR!"
		res_body.text = "Time: %s%s\nBest: %s\nCoins: %d / %d   Wallet: %d\nFalls: %d hearts lost" % [
			_fmt(t), "   NEW BEST!" if new_best else "", _fmt(best[stage]), stage_coins, total, coins, MAX_HEARTS - hearts]
		res_next.text = "Next Stage"
	_show("result")


func _fail() -> void:
	state = FAILED
	timer_on = false
	sfx.play("fail")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fail_body.text = "You ran out of hearts on\nStage %d · %s.\nCheckpoints refill your hearts — try again!" % [stage + 1, world.stages[stage].name]
	_save()
	_show("fail")


func _pause() -> void:
	state = PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	touch.release_all()
	_show("pause")
	sfx.play("click")


func _resume() -> void:
	state = PLAYING
	get_tree().paused = false
	captured_once = false
	_show("hud")
	sfx.play("click")


func _process(delta: float) -> void:
	knock_cd -= delta
	if state == PLAYING:
		if timer_on:
			stage_time += delta
		hud_timer.text = _fmt(stage_time)
		var s: Dictionary = world.stages[stage]
		var root: Node3D = s.root
		if player.global_position.y < root.position.y + s.min_y - 14.0 and not dying:
			die("fall")
		if captured_once and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			captured_once = false
			_pause()
		touch.visible = touch.used
		touch.queue_redraw()
	else:
		touch.visible = false
	var ring = world.stages[stage].get("goal_ring")
	if ring:
		ring.rotation.y += delta * 1.2


func _fmt(t: float) -> String:
	if t < 0.0:
		return "--:--.-"
	var mnt := int(t / 60.0)
	var sec := fmod(t, 60.0)
	return "%d:%04.1f" % [mnt, sec]


# ------------------------------------------------------------------ save
func _load() -> void:
	best = []
	best_coins = []
	for i in 8:
		best.append(-1.0)
		best_coins.append(0)
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	coins = int(cf.get_value("save", "coins", 0))
	unlocked = clampi(int(cf.get_value("save", "unlocked", 1)), 1, 8)
	var b = cf.get_value("save", "best", best)
	if b is Array and b.size() == 8:
		best = b
	var bc = cf.get_value("save", "best_coins", best_coins)
	if bc is Array and bc.size() == 8:
		best_coins = bc
	var o = cf.get_value("save", "owned", owned)
	if o is Array:
		owned = o
	hat = int(cf.get_value("save", "hat", 0))
	sound_on = bool(cf.get_value("save", "sound", true))
	deaths = int(cf.get_value("save", "deaths", 0))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "coins", coins)
	cf.set_value("save", "unlocked", unlocked)
	cf.set_value("save", "best", best)
	cf.set_value("save", "best_coins", best_coins)
	cf.set_value("save", "owned", owned)
	cf.set_value("save", "hat", hat)
	cf.set_value("save", "sound", sound_on)
	cf.set_value("save", "deaths", deaths)
	cf.save(SAVE_PATH)


# ------------------------------------------------------------------ UI building
func _sb(c: Color, r := 16, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.shadow_color = Color(0, 0, 0, 0.2)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	return s


func _build_theme() -> void:
	theme_res = Theme.new()
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.7
	theme_res.default_font = fv
	theme_res.default_font_size = 22
	theme_res.set_stylebox("normal", "Button", _sb(Color(1, 1, 1, 0.92), 16, Color(0.2, 0.35, 0.7), 3))
	theme_res.set_stylebox("hover", "Button", _sb(Color(1, 0.93, 0.55), 16, Color(0.2, 0.35, 0.7), 3))
	theme_res.set_stylebox("pressed", "Button", _sb(Color(1, 0.82, 0.25), 16, Color(0.2, 0.35, 0.7), 3))
	theme_res.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), 16, Color(1, 0.85, 0.2), 3))
	theme_res.set_stylebox("disabled", "Button", _sb(Color(0.7, 0.74, 0.82, 0.8), 16, Color(0.4, 0.45, 0.6), 3))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme_res.set_color(k, "Button", Color(0.1, 0.15, 0.35))
	theme_res.set_color("font_disabled_color", "Button", Color(0.3, 0.33, 0.45))
	var panel := _sb(Color(0.07, 0.12, 0.32, 0.9), 22, Color(1, 1, 1, 0.85), 3)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	theme_res.set_stylebox("panel", "PanelContainer", panel)
	theme_res.set_color("font_outline_color", "Label", Color(0.06, 0.1, 0.3))
	theme_res.set_constant("outline_size", "Label", 6)


func _lbl(parent: Node, text: String, sz := 22, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _btn(parent: Node, text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", _sb(Color(1, 0.82, 0.22), 16, Color(0.55, 0.3, 0.05), 3))
		b.add_theme_stylebox_override("hover", _sb(Color(1, 0.9, 0.45), 16, Color(0.55, 0.3, 0.05), 3))
	b.pressed.connect(func() -> void:
		sfx.play("click")
		cb.call())
	parent.add_child(b)
	return b


func _screen(name: String, dim := 0.0) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim > 0.0:
		var cr := ColorRect.new()
		cr.color = Color(0.02, 0.05, 0.15, dim)
		cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.add_child(cr)
	ui_root.add_child(c)
	screens[name] = c
	c.visible = false
	return c


func _panel(scr: Control, title: String, width := 440.0) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	if title != "":
		_lbl(vb, title, 38, Color(1, 0.88, 0.3))
	return vb


func _build_ui() -> void:
	_build_theme()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = theme_res
	layer.add_child(ui_root)
	touch = TouchScript.new()
	touch.visible = false
	ui_root.add_child(touch)

	# ---- Title
	var t := _screen("title")
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	vb.custom_minimum_size = Vector2(320, 0)
	cc.add_child(vb)
	var logo := _lbl(vb, "CLOUD CLIMB", 58, Color(1, 1, 1))
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.add_theme_constant_override("outline_size", 16)
	var sub := _lbl(vb, "3D  ·  SKY ISLAND OBBY", 24, Color(1, 0.86, 0.3))
	sub.add_theme_constant_override("outline_size", 10)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 2)
	vb.add_child(sp)
	_btn(vb, "PLAY", _on_play, true).custom_minimum_size.y = 50
	_btn(vb, "Stage Select", func() -> void: _open_stages()).custom_minimum_size.y = 44
	_btn(vb, "Hat Shop", func() -> void: _open_shop()).custom_minimum_size.y = 44
	_btn(vb, "How to Play", func() -> void: _show("howto")).custom_minimum_size.y = 44
	var sb := _btn(vb, "", _toggle_sound)
	sb.custom_minimum_size.y = 44
	sound_btns.append(sb)
	title_coins = _lbl(vb, "", 18, Color(1, 0.9, 0.4))
	title_coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	var foot := _lbl(t, "Made by Jaineil Rana (JaKing) · JaiGod", 16, Color(1, 1, 1, 0.85))
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -26
	foot.offset_bottom = -4
	var tw := create_tween().set_loops()
	tw.tween_property(logo, "position:y", -6.0, 1.2).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(logo, "position:y", 6.0, 1.2).as_relative().set_trans(Tween.TRANS_SINE)

	# ---- How to play
	var h := _panel(_screen("howto", 0.35), "HOW TO PLAY")
	_lbl(h, "Climb 8 floating sky islands. Reach the golden FINISH ring on each one as fast as you can!", 19)
	_lbl(h, "Keyboard: WASD / Arrows move · Space jump (hold = higher) · Click, then mouse to look · Q/E turn · Wheel zoom · R respawn · Esc pause", 17, Color(0.8, 0.9, 1))
	_lbl(h, "Phone: left thumb joystick · green JUMP button · drag right side to look", 17, Color(0.8, 0.9, 1))
	_lbl(h, "Flags = checkpoints (refill hearts). Purple blocks vanish when touched, pink ones blink on a beat. Fans lift you, red bars knock you, lava and neon-red bricks cost a heart. Spend coins on hats!", 17, Color(1, 0.92, 0.7))
	_btn(h, "Got it!", func() -> void: _go_title(), true)

	# ---- Stage select
	var st := _panel(_screen("stages", 0.35), "STAGE SELECT", 460)
	stage_grid = GridContainer.new()
	stage_grid.columns = 2
	stage_grid.add_theme_constant_override("h_separation", 10)
	stage_grid.add_theme_constant_override("v_separation", 10)
	st.add_child(stage_grid)
	_btn(st, "Back", func() -> void: _go_title())

	# ---- Hat shop
	var hs := _screen("shop")
	var hvb := VBoxContainer.new()
	var hpc := PanelContainer.new()
	hs.add_child(hpc)
	hpc.custom_minimum_size = Vector2(440, 0)
	hpc.anchor_left = 0.5
	hpc.anchor_right = 0.5
	hpc.anchor_top = 1.0
	hpc.anchor_bottom = 1.0
	hpc.offset_left = -220
	hpc.offset_right = 220
	hpc.offset_top = -12
	hpc.offset_bottom = -12
	hpc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hpc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hvb.add_theme_constant_override("separation", 10)
	hpc.add_child(hvb)
	_lbl(hvb, "HAT SHOP", 32, Color(1, 0.88, 0.3))
	hat_coins = _lbl(hvb, "", 20, Color(1, 0.9, 0.4))
	hat_grid = GridContainer.new()
	hat_grid.columns = 2
	hat_grid.add_theme_constant_override("h_separation", 8)
	hat_grid.add_theme_constant_override("v_separation", 8)
	hvb.add_child(hat_grid)
	_btn(hvb, "Done", func() -> void: _go_title(), true)

	# ---- HUD
	var hud := _screen("hud")
	var tl := VBoxContainer.new()
	tl.position = Vector2(14, 10)
	tl.add_theme_constant_override("separation", 0)
	hud.add_child(tl)
	hud_stage = _lbl(tl, "", 18, Color(1, 0.9, 0.5))
	hud_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud_stage.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud_timer = _lbl(tl, "0:00.0", 40)
	hud_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud_timer.add_theme_constant_override("outline_size", 10)
	hud_best = _lbl(tl, "", 16, Color(0.85, 0.92, 1))
	hud_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var tr := HBoxContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_left = -300
	tr.offset_right = -12
	tr.offset_top = 12
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.add_theme_constant_override("separation", 10)
	hud.add_child(tr)
	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 4)
	tr.add_child(rvb)
	hud_coins = _lbl(rvb, "0", 26, Color(1, 0.88, 0.3))
	hud_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_coins.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud_coins.pivot_offset = Vector2(60, 16)
	hearts_ctrl = Control.new()
	hearts_ctrl.custom_minimum_size = Vector2(5 * 26, 24)
	hearts_ctrl.draw.connect(_draw_hearts)
	rvb.add_child(hearts_ctrl)
	var pb := Button.new()
	pb.text = "II"
	pb.focus_mode = Control.FOCUS_NONE
	pb.custom_minimum_size = Vector2(54, 54)
	pb.pressed.connect(func() -> void:
		if state == PLAYING:
			_pause())
	tr.add_child(pb)
	toast = _lbl(hud, "", 28, Color(0.5, 1, 0.6))
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left = -260
	toast.offset_right = 260
	toast.offset_top = 120
	toast.add_theme_constant_override("outline_size", 10)
	toast.modulate.a = 0.0
	banner = _lbl(hud, "", 46, Color(1, 1, 1))
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.offset_top = -150
	banner.offset_bottom = -40
	banner.add_theme_constant_override("outline_size", 14)
	banner.modulate.a = 0.0
	hint = _lbl(hud, "", 17, Color(1, 1, 1))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -250
	hint.offset_right = 250
	hint.offset_top = -230
	hint.offset_bottom = -180
	hint.modulate.a = 0.0

	# ---- Pause
	var pv := _panel(_screen("pause", 0.5), "PAUSED", 380)
	_btn(pv, "Resume", _resume, true)
	_btn(pv, "Respawn at Checkpoint", func() -> void:
		_resume()
		_respawn_now())
	_btn(pv, "Restart Stage", func() -> void: _enter_stage(stage))
	sound_btns.append(_btn(pv, "", _toggle_sound))
	_btn(pv, "Main Menu", func() -> void: _go_title())

	# ---- Result
	var rv := _panel(_screen("result", 0.35), "", 420)
	res_title = _lbl(rv, "STAGE CLEAR!", 42, Color(1, 0.88, 0.3))
	res_body = _lbl(rv, "", 20)
	res_next = _btn(rv, "Next Stage", _on_next, true)
	_btn(rv, "Replay Stage", func() -> void: _enter_stage(stage))
	_btn(rv, "Main Menu", func() -> void: _go_title())

	# ---- Fail
	var fv := _panel(_screen("fail", 0.45), "OUT OF HEARTS", 420)
	fail_body = _lbl(fv, "", 20)
	_btn(fv, "Try Again", func() -> void: _enter_stage(stage), true)
	_btn(fv, "Main Menu", func() -> void: _go_title())
	_refresh_sound_btns()


func _draw_hearts() -> void:
	for i in MAX_HEARTS:
		var c := Vector2(i * 26 + 12, 12)
		var col := Color(1, 0.3, 0.4) if i < hearts else Color(0.2, 0.25, 0.4, 0.7)
		var out := Color(0.08, 0.1, 0.28)
		for pass_i in 2:
			var r := 6.5 if pass_i == 1 else 8.0
			var cc := col if pass_i == 1 else out
			draw_circle_at(hearts_ctrl, c + Vector2(-r * 0.62, -2), r * 0.72, cc)
			draw_circle_at(hearts_ctrl, c + Vector2(r * 0.62, -2), r * 0.72, cc)
			hearts_ctrl.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.3, 0), c + Vector2(r * 1.3, 0), c + Vector2(0, r * 1.45)]), cc)


func draw_circle_at(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_circle(p, r, c)


func _on_resize() -> void:
	var w := get_window()
	var s := Vector2(w.size)
	var dpr := maxf(1.0, DisplayServer.screen_get_scale())
	var css := s / dpr
	var short := minf(css.x, css.y)
	var target := 540.0 if short < 620.0 else 648.0
	if s.y > s.x:
		w.content_scale_size = Vector2i(int(target), int(target))
	else:
		w.content_scale_size = Vector2i(int(target * 16.0 / 9.0), int(target))
	get_viewport().scaling_3d_scale = clampf(1.6 / dpr, 0.5, 1.0)
	if player:
		player.camera.keep_aspect = Camera3D.KEEP_WIDTH if s.y > s.x else Camera3D.KEEP_HEIGHT
		player.camera.fov = 78.0 if s.y > s.x else 70.0


func _show(name: String) -> void:
	for k in screens:
		screens[k].visible = k == name


func _toast(text: String, col: Color) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", col)
	toast.scale = Vector2.ONE
	var tw := create_tween()
	toast.modulate.a = 1.0
	tw.tween_interval(1.4)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)


func _banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.6)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)


func _pop(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(1.35, 1.35), 0.07)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _update_hud() -> void:
	var s: Dictionary = world.stages[stage]
	hud_stage.text = "STAGE %d · %s" % [stage + 1, s.name]
	hud_best.text = "Best %s" % _fmt(best[stage])
	hud_coins.text = "Coins %d  ·  +%d/%d" % [coins, stage_coins, s.coins.size()]
	hearts_ctrl.queue_redraw()
	if touch.used:
		hint.text = "Left stick to move · green button to jump · drag to look around"
		hint.offset_top = -250
		hint.offset_bottom = -200
	else:
		hint.text = "WASD to move · Space to jump · Click the game, then move the mouse to look"
		hint.offset_top = -90
		hint.offset_bottom = -40


func _refresh_sound_btns() -> void:
	for b in sound_btns:
		b.text = "Sound: ON" if sound_on else "Sound: OFF"


func _toggle_sound() -> void:
	sound_on = not sound_on
	sfx.set_enabled(sound_on)
	_refresh_sound_btns()
	_save()


func _go_title() -> void:
	state = TITLE
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.frozen = false
	player.visible = true
	player.menu_orbit = true
	player.view_offset = 0.0
	player.cam_dist = 9.0
	player.cam_pitch = -0.28
	title_coins.text = "Coins: %d   ·   Stages unlocked: %d / 8" % [coins, unlocked]
	_show("title")
	sfx.start_music()


func _on_play() -> void:
	sfx.start_music()
	_enter_stage(clampi(unlocked - 1, 0, 7))


func _on_next() -> void:
	if stage >= 7:
		_open_stages()
	else:
		_enter_stage(stage + 1)


func _open_stages() -> void:
	state = TITLE
	for c in stage_grid.get_children():
		c.queue_free()
	for i in 8:
		var locked := i >= unlocked
		var txt := "%d · %s\n%s" % [i + 1, WorldScript.STAGE_NAMES[i], "LOCKED" if locked else ("Best " + _fmt(best[i]))]
		var idx := i
		var b := _btn(stage_grid, txt, func() -> void: _enter_stage(idx))
		b.custom_minimum_size = Vector2(196, 64)
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = locked
	_show("stages")


func _open_shop() -> void:
	state = SHOP
	player.menu_orbit = true
	player.cam_dist = 4.6
	player.cam_pitch = -0.1
	player.view_offset = -1.9
	_refresh_shop()
	_show("shop")


func _refresh_shop() -> void:
	for c in hat_grid.get_children():
		c.queue_free()
	hat_coins.text = "Coins: %d" % coins
	for i in HATS.size():
		var nm: String = HATS[i][0]
		var cost: int = HATS[i][1]
		var tag := "EQUIPPED" if hat == i else ("Owned" if owned.has(i) else "%d coins" % cost)
		var idx := i
		var b := _btn(hat_grid, "%s\n%s" % [nm, tag], func() -> void: _hat_pressed(idx), hat == i)
		b.custom_minimum_size = Vector2(190, 58)
		b.add_theme_font_size_override("font_size", 16)


func _hat_pressed(i: int) -> void:
	if not owned.has(i):
		var cost: int = HATS[i][1]
		if coins < cost:
			sfx.play("deny")
			hat_coins.text = "Need %d more coins!" % (cost - coins)
			return
		coins -= cost
		owned.append(i)
		sfx.play("buy")
		confetti(player.global_position + Vector3(0, 2.4, 0))
	hat = i
	player.set_hat(i)
	_save()
	_refresh_shop()


## Showcase deep link (?shot=N): jump straight to a stage's mid checkpoint for screenshots.
func _showcase(i: int) -> void:
	_enter_stage(i)
	var cps: Array = world.stages[i].checkpoints
	if cps.size() > 1:
		player.teleport(cps[1].spawn + Vector3(0, 0, 3.2), 0.0)
	player.cam_pitch = -0.42
	player.cam_dist = 10.0
	player.view_offset = -2.5
	hint.modulate.a = 0.0


# ------------------------------------------------------------------ smoke test (headless CI / local)
func _smoke_test() -> void:
	var ok := true
	await get_tree().process_frame
	for i in 8:
		_enter_stage(i)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var s: Dictionary = world.stages[i]
		# coin pickup
		var c0: Node3D = s.coins[0]
		player.teleport(c0.global_position - Vector3(0, 1.0, 0))
		for f in 6:
			await get_tree().physics_frame
		if stage_coins < 1:
			print("SMOKE FAIL stage %d: coin not collected" % (i + 1))
			ok = false
		# fall death
		var h0 := hearts
		player.teleport(Vector3(s.root.position.x, s.root.position.y + s.min_y - 30.0, 0))
		for f in 4:
			await get_tree().process_frame
		await get_tree().create_timer(0.9).timeout
		if hearts != h0 - 1:
			print("SMOKE FAIL stage %d: fall did not cost a heart (%d -> %d)" % [i + 1, h0, hearts])
			ok = false
		# goal
		var g: Node3D = s.goal_ring
		player.teleport(g.global_position - Vector3(0, 2.0, 0))
		for f in 8:
			await get_tree().physics_frame
		if state != COMPLETE:
			print("SMOKE FAIL stage %d: goal not reached (state %d)" % [i + 1, state])
			ok = false
		await get_tree().create_timer(1.3).timeout
		print("stage %d ok: coins=%d total=%d cps=%d" % [i + 1, stage_coins, s.coins.size(), s.checkpoints.size()])
	_pause()
	_resume()
	_open_shop()
	_hat_pressed(1)
	_go_title()
	print("SMOKE %s unlocked=%d coins=%d" % ["PASS" if ok else "FAIL", unlocked, coins])
	get_tree().quit(0 if ok else 1)
