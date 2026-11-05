extends Node3D
## Builds the 8 sky-island obstacle courses from primitives and runs their obstacles.

const STAGE_NAMES := [
	"Meadow Steps", "Breezy Bridges", "Blink Blocks", "Fan Falls",
	"Spin Cycle", "Lava Lagoon", "Storm Gauntlet", "Crown of Clouds",
]
const PAL := [
	{"top": Color(0.42, 0.85, 0.38), "side": Color(0.55, 0.38, 0.24), "plat": Color(0.98, 0.84, 0.4), "acc": Color(0.3, 0.7, 1.0), "sky": Color(0.3, 0.55, 0.96), "hor": Color(0.78, 0.9, 1.0)},
	{"top": Color(0.5, 0.9, 0.55), "side": Color(0.5, 0.36, 0.28), "plat": Color(0.45, 0.8, 1.0), "acc": Color(1.0, 0.55, 0.3), "sky": Color(0.28, 0.6, 0.95), "hor": Color(0.8, 0.94, 1.0)},
	{"top": Color(0.6, 0.85, 0.45), "side": Color(0.45, 0.35, 0.3), "plat": Color(0.75, 0.5, 1.0), "acc": Color(0.95, 0.35, 0.75), "sky": Color(0.42, 0.45, 0.92), "hor": Color(0.9, 0.82, 1.0)},
	{"top": Color(0.35, 0.8, 0.6), "side": Color(0.4, 0.4, 0.45), "plat": Color(0.4, 0.95, 0.85), "acc": Color(0.9, 0.9, 1.0), "sky": Color(0.22, 0.62, 0.9), "hor": Color(0.75, 0.97, 0.98)},
	{"top": Color(0.95, 0.75, 0.35), "side": Color(0.6, 0.38, 0.25), "plat": Color(1.0, 0.6, 0.35), "acc": Color(0.95, 0.25, 0.3), "sky": Color(0.95, 0.55, 0.4), "hor": Color(1.0, 0.85, 0.65)},
	{"top": Color(0.45, 0.4, 0.42), "side": Color(0.25, 0.2, 0.22), "plat": Color(0.62, 0.58, 0.6), "acc": Color(1.0, 0.45, 0.1), "sky": Color(0.55, 0.25, 0.3), "hor": Color(1.0, 0.6, 0.4)},
	{"top": Color(0.4, 0.55, 0.65), "side": Color(0.3, 0.3, 0.38), "plat": Color(0.55, 0.65, 0.85), "acc": Color(0.95, 0.95, 0.4), "sky": Color(0.15, 0.2, 0.38), "hor": Color(0.45, 0.5, 0.65)},
	{"top": Color(1.0, 0.92, 0.6), "side": Color(0.85, 0.7, 0.45), "plat": Color(1.0, 1.0, 1.0), "acc": Color(1.0, 0.78, 0.2), "sky": Color(0.55, 0.45, 0.9), "hor": Color(1.0, 0.85, 0.75)},
]

var game
var stages: Array = []
var cur: Node3D
var info: Dictionary
var pal: Dictionary
var mats := {}
var lava_mat: StandardMaterial3D
var kill_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var clock := 0.0


# ------------------------------------------------------------------ obstacles
class Coin extends Area3D:
	var game
	var mesh: Node3D
	var taken := false
	var ph := 0.0

	func _ready() -> void:
		ph = position.x * 0.7 + position.z * 0.37
		body_entered.connect(_hit)

	func _process(d: float) -> void:
		mesh.rotation.y += d * 3.2
		mesh.position.y = sin(Time.get_ticks_msec() * 0.003 + ph) * 0.15

	func _hit(b) -> void:
		if taken or not b.is_in_group("player"):
			return
		taken = true
		visible = false
		game.on_coin(self)

	func reset() -> void:
		taken = false
		visible = true


class Mover extends AnimatableBody3D:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var period := 4.0
	var phase := 0.0
	var tt := 0.0

	func _ready() -> void:
		sync_to_physics = true
		reset()

	func reset() -> void:
		tt = phase * period
		position = a.lerp(b, 0.5 - 0.5 * cos(tt / period * TAU))

	func _physics_process(d: float) -> void:
		tt += d
		position = a.lerp(b, 0.5 - 0.5 * cos(tt / period * TAU))


class Blinker extends StaticBody3D:
	var cyclic := false
	var period := 3.0
	var phase := 0.0
	var state := 0
	var timer := 0.0
	var tt := 0.0
	var meshes: Array = []
	var shape: CollisionShape3D
	var matl: StandardMaterial3D
	var base_col := Color.WHITE
	var game

	func _physics_process(d: float) -> void:
		if cyclic:
			tt += d
			var f := fposmod(tt / period + phase, 1.0)
			set_state(0 if f < 0.55 else (1 if f < 0.72 else 2))
		elif state == 1:
			timer -= d
			if timer <= 0.0:
				set_state(2)
				timer = 2.0
		elif state == 2:
			timer -= d
			if timer <= 0.0:
				set_state(0)
		if state == 1:
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.035)
			matl.albedo_color = base_col.lerp(Color.WHITE, k * 0.8)
			for m in meshes:
				m.scale = Vector3.ONE * (1.0 + 0.03 * k)

	func trigger(b) -> void:
		if b.is_in_group("player") and not cyclic and state == 0:
			set_state(1)
			timer = 0.65

	func set_state(s: int) -> void:
		if s == state:
			return
		if s == 2 and game:
			game.blink_poof(global_position + Vector3(0, 0.3, 0), base_col)
		state = s
		shape.set_deferred("disabled", s == 2)
		for m in meshes:
			m.visible = s != 2
			m.scale = Vector3.ONE
		if s != 1:
			matl.albedo_color = base_col

	func reset() -> void:
		tt = 0.0
		timer = 0.0
		set_state(0)


class Spinner extends Node3D:
	var speed := 1.5
	var game

	func _physics_process(d: float) -> void:
		rotation.y += speed * d

	func hit(b) -> void:
		if not b.is_in_group("player"):
			return
		var rel: Vector3 = b.global_position - global_position
		rel.y = 0.0
		if rel.length() < 0.1:
			rel = Vector3.FORWARD
		var tang := Vector3.UP.cross(rel).normalized() * signf(speed)
		game.knock(tang * 12.0 + rel.normalized() * 3.0 + Vector3.UP * 8.0)

	func reset() -> void:
		rotation.y = 0.0


class Fan extends Area3D:
	var push := Vector3.UP
	var strength := 48.0
	var max_up := 10.0
	var blades: Node3D

	func _ready() -> void:
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)

	func _on_enter(b) -> void:
		if b.is_in_group("player") and not b.fans.has(self):
			b.fans.append(self)

	func _on_exit(b) -> void:
		if b.is_in_group("player"):
			b.fans.erase(self)

	func _process(d: float) -> void:
		if blades:
			blades.rotate_object_local(Vector3.UP, d * 16.0)


class Checkpoint extends Area3D:
	var game
	var flag: MeshInstance3D
	var active := false
	var spawn := Vector3.ZERO

	func _ready() -> void:
		body_entered.connect(_hit)

	func _hit(b) -> void:
		if b.is_in_group("player"):
			game.on_checkpoint(self)

	func set_active(on: bool) -> void:
		active = on
		var m := flag.material_override as StandardMaterial3D
		m.albedo_color = Color(0.25, 1.0, 0.45) if on else Color(0.95, 0.3, 0.3)
		m.emission = m.albedo_color


# ------------------------------------------------------------------ helpers
func m(c: Color, emit := 0.0) -> StandardMaterial3D:
	var k := c.to_html() + str(emit)
	if mats.has(k):
		return mats[k]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.9
	if emit > 0.0:
		mt.emission_enabled = true
		mt.emission = c
		mt.emission_energy_multiplier = emit
	mats[k] = mt
	return mt


func mbox(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func mcyl(parent: Node3D, pos: Vector3, tr: float, br: float, h: float, segs: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tr
	cm.bottom_radius = br
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func msphere(parent: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func box_shape(parent: Node3D, size: Vector3, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	parent.add_child(cs)
	return cs


func area(pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	a.position = pos
	return a


func track(y: float) -> void:
	info.min_y = minf(info.min_y, y)


## Static platform; p is the centre of the TOP face.
func plat(p: Vector3, s: Vector3, col = null) -> StaticBody3D:
	var c: Color = pal.plat if col == null else col
	var b := StaticBody3D.new()
	b.position = p - Vector3(0, s.y * 0.5, 0)
	cur.add_child(b)
	box_shape(b, s)
	mbox(b, Vector3.ZERO, s, m(c.darkened(0.25)))
	mbox(b, Vector3(0, s.y * 0.5 - 0.1 + 0.015, 0), Vector3(s.x + 0.1, 0.2, s.z + 0.1), m(c))
	track(p.y)
	return b


## Floating island: grass disk with a rocky underside. p = centre of the top.
func island(p: Vector3, r: float, trees := 2) -> void:
	var b := StaticBody3D.new()
	b.position = p
	cur.add_child(b)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = 1.2
	cs.shape = cy
	cs.position.y = -0.6
	b.add_child(cs)
	mcyl(b, Vector3(0, -0.25, 0), r, r, 0.5, 10, m(pal.top))
	mcyl(b, Vector3(0, -0.85, 0), r * 0.97, r * 0.9, 0.7, 10, m(pal.side))
	mcyl(b, Vector3(0, -1.2 - r * 0.55, 0), r * 0.9, r * 0.18, r * 1.1, 9, m(pal.side.darkened(0.3)))
	track(p.y)
	for i in trees:
		var side := -1.0 if i % 2 == 0 else 1.0
		var tp := Vector3(side * r * rng.randf_range(0.6, 0.75), 0, rng.randf_range(-r * 0.4, r * 0.4))
		tree(b, tp)
	for i in 3:
		var a := rng.randf() * TAU
		var rp := Vector3(cos(a) * r * 0.85, 0.12, sin(a) * r * 0.85)
		var rock := mbox(b, rp, Vector3(0.5, 0.35, 0.45) * rng.randf_range(0.7, 1.4), m(Color(0.7, 0.7, 0.72)))
		rock.rotation.y = rng.randf() * TAU


func tree(parent: Node3D, p: Vector3) -> void:
	mcyl(parent, p + Vector3(0, 0.6, 0), 0.14, 0.2, 1.2, 6, m(Color(0.5, 0.33, 0.2)))
	var leaf: Color = pal.top.darkened(0.15)
	if rng.randf() < 0.5:
		mcyl(parent, p + Vector3(0, 1.8, 0), 0.0, 0.95, 1.7, 6, m(leaf))
		mcyl(parent, p + Vector3(0, 2.5, 0), 0.0, 0.65, 1.1, 6, m(leaf.lightened(0.1)))
	else:
		var s := msphere(parent, p + Vector3(0, 1.9, 0), 0.95, m(leaf))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func coin(p: Vector3) -> void:
	var a := Coin.new()
	a.game = game
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	a.position = p + Vector3(0, 1.0, 0)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.75
	cs.shape = sp
	a.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.1
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m(Color(1.0, 0.8, 0.15), 0.55)
	var holder := Node3D.new()
	a.add_child(holder)
	holder.add_child(mi)
	mi.rotation.x = PI * 0.5
	mbox(mi, Vector3(0, 0.06, 0), Vector3(0.12, 0.03, 0.45), m(Color(1.0, 0.95, 0.55), 0.8))
	a.mesh = holder
	cur.add_child(a)
	info.coins.append(a)


func coin_line(a: Vector3, b: Vector3, n: int) -> void:
	for i in n:
		coin(a.lerp(b, float(i) / maxf(1.0, n - 1.0)))


func checkpoint(p: Vector3) -> Checkpoint:
	var cp := Checkpoint.new()
	cp.game = game
	cp.collision_layer = 0
	cp.collision_mask = 2
	cp.monitorable = false
	cp.position = p
	cp.spawn = cur.position + p + Vector3(0, 0.15, 0)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 1.5
	cy.height = 3.0
	cs.shape = cy
	cs.position.y = 1.5
	cp.add_child(cs)
	mcyl(cp, Vector3(0, 0.06, 0), 1.25, 1.35, 0.14, 14, m(Color(0.95, 0.95, 1.0)))
	mcyl(cp, Vector3(0, 0.1, 0), 0.9, 0.9, 0.12, 14, m(pal.acc, 0.3))
	mbox(cp, Vector3(1.05, 1.4, 0), Vector3(0.12, 2.8, 0.12), m(Color(0.9, 0.9, 0.95)))
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.95, 0.3, 0.3)
	fm.emission_enabled = true
	fm.emission = fm.albedo_color
	fm.emission_energy_multiplier = 0.35
	cp.flag = mbox(cp, Vector3(1.55, 2.5, 0), Vector3(0.9, 0.55, 0.06), fm)
	cur.add_child(cp)
	info.checkpoints.append(cp)
	return cp


func mover(a: Vector3, b: Vector3, s: Vector3, period: float, phase := 0.0) -> void:
	var mv := Mover.new()
	mv.a = a - Vector3(0, s.y * 0.5, 0)
	mv.b = b - Vector3(0, s.y * 0.5, 0)
	mv.period = period
	mv.phase = phase
	mv.position = mv.a
	box_shape(mv, s)
	var c: Color = pal.acc
	mbox(mv, Vector3.ZERO, s, m(c.darkened(0.3)))
	mbox(mv, Vector3(0, s.y * 0.5 - 0.09 + 0.015, 0), Vector3(s.x + 0.1, 0.18, s.z + 0.1), m(c))
	for sx in [-1, 1]:
		mbox(mv, Vector3(sx * s.x * 0.3, s.y * 0.5 + 0.03, 0), Vector3(0.18, 0.04, s.z * 0.7), m(Color(1, 1, 1), 0.4))
	cur.add_child(mv)
	info.resets.append(mv)
	track(minf(a.y, b.y))


func blinker(p: Vector3, s: Vector3, cyclic := false, period := 3.0, phase := 0.0) -> void:
	var bl := Blinker.new()
	bl.game = game
	bl.cyclic = cyclic
	bl.period = period
	bl.phase = phase
	bl.position = p - Vector3(0, s.y * 0.5, 0)
	bl.shape = box_shape(bl, s)
	bl.base_col = Color(0.65, 0.45, 1.0) if not cyclic else Color(1.0, 0.45, 0.75)
	bl.matl = StandardMaterial3D.new()
	bl.matl.albedo_color = bl.base_col
	bl.matl.roughness = 0.6
	bl.meshes.append(mbox(bl, Vector3.ZERO, s, bl.matl))
	bl.meshes.append(mbox(bl, Vector3(0, s.y * 0.5 + 0.01, 0), Vector3(s.x * 0.7, 0.03, s.z * 0.7), m(Color(1, 1, 1), 0.6)))
	if not cyclic:
		var det := area(Vector3(0, s.y * 0.5 + 0.15, 0))
		box_shape(det, Vector3(s.x * 0.95, 0.3, s.z * 0.95))
		det.body_entered.connect(bl.trigger)
		bl.add_child(det)
	cur.add_child(bl)
	info.resets.append(bl)
	track(p.y)


func spinner(p: Vector3, radius: float, speed: float, arms := 1, h := 0.75) -> void:
	var sp := Spinner.new()
	sp.game = game
	sp.speed = speed
	sp.position = p
	var hub := StaticBody3D.new()
	sp.add_child(hub)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.45
	cy.height = 1.6
	cs.shape = cy
	cs.position.y = 0.8
	hub.add_child(cs)
	mcyl(hub, Vector3(0, 0.8, 0), 0.4, 0.5, 1.6, 10, m(Color(0.3, 0.3, 0.35)))
	mcyl(hub, Vector3(0, 1.65, 0), 0.25, 0.4, 0.15, 10, m(pal.acc, 0.5))
	for i in arms:
		var arm := Node3D.new()
		arm.rotation.y = PI * i / float(arms)
		sp.add_child(arm)
		var bar := mbox(arm, Vector3(0, h, 0), Vector3(radius * 2.0, 0.42, 0.42), m(Color(0.95, 0.25, 0.3)))
		for k in [-1, 1]:
			mbox(bar, Vector3(k * radius * 0.5, 0, 0), Vector3(0.3, 0.44, 0.44), m(Color(1, 1, 1)))
		var ar := area(Vector3(0, h, 0))
		box_shape(ar, Vector3(radius * 2.0, 0.5, 0.55))
		ar.body_entered.connect(sp.hit)
		arm.add_child(ar)
	cur.add_child(sp)
	info.resets.append(sp)


## Round platform for spinners.
func disc(p: Vector3, r: float) -> void:
	var b := StaticBody3D.new()
	b.position = p - Vector3(0, 0.4, 0)
	cur.add_child(b)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = 0.8
	cs.shape = cy
	b.add_child(cs)
	mcyl(b, Vector3.ZERO, r, r, 0.8, 16, m(pal.plat.darkened(0.25)))
	mcyl(b, Vector3(0, 0.32, 0), r + 0.05, r + 0.05, 0.18, 16, m(pal.plat))
	mcyl(b, Vector3(0, -0.9, 0), r * 0.8, 0.3, 1.0, 10, m(pal.side.darkened(0.2)))
	track(p.y)


func fan_up(p: Vector3, height: float, strength := 46.0, max_up := 10.0) -> void:
	var f := Fan.new()
	f.collision_layer = 0
	f.collision_mask = 2
	f.monitorable = false
	f.push = Vector3.UP
	f.strength = strength
	f.max_up = max_up
	f.position = p
	box_shape(f, Vector3(2.4, height, 2.4), Vector3(0, height * 0.5 + 0.1, 0))
	mcyl(f, Vector3(0, 0.08, 0), 1.25, 1.35, 0.2, 12, m(Color(0.35, 0.38, 0.45)))
	mcyl(f, Vector3(0, 0.2, 0), 1.1, 1.1, 0.05, 12, m(Color(0.15, 0.17, 0.2)))
	f.blades = Node3D.new()
	f.blades.position.y = 0.24
	f.add_child(f.blades)
	for i in 3:
		var bl := mbox(f.blades, Vector3.ZERO, Vector3(2.0, 0.04, 0.32), m(Color(0.9, 0.95, 1.0)))
		bl.rotation.y = TAU * i / 3.0
	streaks(f, Vector3(0, 0.4, 0), Vector3(1.0, 0.1, 1.0), Vector3.UP, height)
	cur.add_child(f)


func wind(center: Vector3, size: Vector3, dir: Vector3, speed := 5.5) -> void:
	var f := Fan.new()
	f.collision_layer = 0
	f.collision_mask = 2
	f.monitorable = false
	f.push = dir.normalized()
	f.strength = speed
	f.position = center
	box_shape(f, size)
	var src := -f.push * (maxf(size.x, size.z) * 0.5 + 0.8)
	var housing := Node3D.new()
	housing.position = src + Vector3(0, -size.y * 0.5 + 1.2, 0)
	f.add_child(housing)
	housing.basis = Basis.looking_at(f.push, Vector3.UP)
	mbox(housing, Vector3(0, -1.0, 0), Vector3(0.4, 1.0, 0.4), m(Color(0.35, 0.38, 0.45)))
	var ring := mcyl(housing, Vector3.ZERO, 1.1, 1.1, 0.5, 12, m(Color(0.35, 0.38, 0.45)))
	ring.rotation.x = PI * 0.5
	var bl := Node3D.new()
	bl.rotation.x = PI * 0.5
	bl.position.z = -0.3
	housing.add_child(bl)
	for i in 3:
		var b := mbox(bl, Vector3.ZERO, Vector3(1.8, 0.04, 0.3), m(Color(0.9, 0.95, 1.0)))
		b.rotation.y = TAU * i / 3.0
	f.blades = bl
	streaks(f, src + f.push * 0.6, Vector3(0.2, size.y * 0.35, size.z * 0.4) if absf(f.push.x) > 0.5 else Vector3(size.x * 0.4, size.y * 0.35, 0.2), f.push, maxf(size.x, size.z) + 1.0)
	cur.add_child(f)


func streaks(parent: Node3D, pos: Vector3, ext: Vector3, dir: Vector3, dist: float) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 18
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = ext
	p.direction = dir
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = dist * 0.9
	p.initial_velocity_max = dist * 1.1
	var qm := BoxMesh.new()
	qm.size = Vector3(0.05, 0.05, 0.05) + dir.abs() * 0.6
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = Color(1, 1, 1, 0.55)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = mt
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)


func lava(p: Vector3, s: Vector3) -> void:
	var a := area(p - Vector3(0, s.y * 0.5, 0))
	box_shape(a, s + Vector3(0, 0.5, 0), Vector3(0, 0.25, 0))
	a.body_entered.connect(_kill)
	var mi := mbox(a, Vector3.ZERO, s, lava_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in int(s.x * s.z / 18.0):
		var bp := Vector3(rng.randf_range(-s.x, s.x) * 0.45, s.y * 0.5, rng.randf_range(-s.z, s.z) * 0.45)
		var bub := msphere(a, bp, rng.randf_range(0.2, 0.45), m(Color(1.0, 0.85, 0.3), 1.6))
		bub.scale.y = 0.5
	cur.add_child(a)


func kill_brick(p: Vector3, s: Vector3) -> void:
	var a := area(p - Vector3(0, s.y * 0.5, 0))
	box_shape(a, s + Vector3(0.05, 0.1, 0.05))
	a.body_entered.connect(_kill)
	mbox(a, Vector3.ZERO, s, kill_mat)
	cur.add_child(a)


func jump_pad(p: Vector3, power := 21.0) -> void:
	var a := area(p)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.95
	cy.height = 0.7
	cs.shape = cy
	cs.position.y = 0.35
	a.add_child(cs)
	mcyl(a, Vector3(0, 0.08, 0), 1.0, 1.1, 0.16, 14, m(Color(0.3, 0.3, 0.35)))
	var top := mcyl(a, Vector3(0, 0.22, 0), 0.85, 0.85, 0.12, 14, m(Color(0.2, 1.0, 0.55), 0.9))
	a.body_entered.connect(func(b) -> void:
		if b.is_in_group("player"):
			b.launch(power)
			game.sfx.play("boing")
			var tw := create_tween()
			tw.tween_property(top, "scale", Vector3(1.2, 2.5, 1.2), 0.06)
			tw.tween_property(top, "scale", Vector3.ONE, 0.25))
	cur.add_child(a)


func goal(p: Vector3) -> void:
	var a := area(p)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 1.5
	cy.height = 3.0
	cs.shape = cy
	cs.position.y = 1.5
	a.add_child(cs)
	a.body_entered.connect(func(b) -> void:
		if b.is_in_group("player"):
			game.on_goal())
	mcyl(a, Vector3(0, 0.1, 0), 1.8, 1.9, 0.2, 16, m(Color(1, 1, 1)))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 2.0
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = m(Color(1.0, 0.82, 0.2), 1.2)
	ring.position.y = 2.2
	ring.rotation.x = PI * 0.5
	a.add_child(ring)
	var beam := mcyl(a, Vector3(0, 4.0, 0), 1.35, 1.35, 8.0, 16, null)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.95, 0.5, 0.22)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	info.goal_ring = ring
	cur.add_child(a)
	sign_at(p + Vector3(0, 5.2, 0), "FINISH", Color(1.0, 0.9, 0.3))


func sign_at(p: Vector3, text: String, col := Color.WHITE, size := 96) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 18
	l.modulate = col
	l.outline_modulate = Color(0.1, 0.12, 0.25)
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = p
	cur.add_child(l)


func _kill(b) -> void:
	if b.is_in_group("player"):
		game.die("lava")


func cloud(parent: Node3D, p: Vector3, s: float) -> void:
	var cm := m(Color(1, 1, 1))
	var n := rng.randi_range(3, 5)
	for i in n:
		var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.8, 0.8)) * s
		var sp := msphere(parent, p + off, s * rng.randf_range(0.8, 1.3), cm)
		sp.scale.y = 0.7


func deco(length: float) -> void:
	var cl := Node3D.new()
	cl.name = "Clouds"
	cur.add_child(cl)
	info.clouds = cl
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * rng.randf_range(14.0, 40.0), rng.randf_range(-22.0, 8.0), -rng.randf_range(-10.0, length + 10.0))
		cloud(cl, p, rng.randf_range(1.5, 3.5))
	for i in 10:
		var p := Vector3(rng.randf_range(-30.0, 30.0), info.min_y - rng.randf_range(14.0, 22.0), -rng.randf_range(-10.0, length + 10.0))
		cloud(cl, p, rng.randf_range(3.0, 5.0))


# ------------------------------------------------------------------ stages
func build_all() -> void:
	rng.seed = 20261105
	lava_mat = StandardMaterial3D.new()
	lava_mat.albedo_color = Color(1.0, 0.35, 0.05)
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(1.0, 0.3, 0.0)
	lava_mat.emission_energy_multiplier = 1.4
	kill_mat = StandardMaterial3D.new()
	kill_mat.albedo_color = Color(1.0, 0.1, 0.15)
	kill_mat.emission_enabled = true
	kill_mat.emission = Color(1.0, 0.05, 0.1)
	kill_mat.emission_energy_multiplier = 1.5
	for i in 8:
		cur = Node3D.new()
		cur.name = "Stage%d" % (i + 1)
		cur.position = Vector3(i * 180.0, i * 40.0, 0)
		add_child(cur)
		pal = PAL[i]
		info = {"index": i, "root": cur, "name": STAGE_NAMES[i], "coins": [], "checkpoints": [], "resets": [],
			"min_y": 0.0, "length": 70.0, "pal": pal}
		island(Vector3.ZERO, 6.5, 2)
		var start := checkpoint(Vector3(0, 0, 2.5))
		info.start = start
		sign_at(Vector3(-5.0, 3.6, -1.0), "%d · %s" % [i + 1, STAGE_NAMES[i]], Color(1, 1, 1), 64)
		call("stage_%d" % (i + 1))
		deco(info.length)
		stages.append(info)
		set_stage_active(i, false)


func set_stage_active(i: int, on: bool) -> void:
	var r: Node3D = stages[i].root
	r.visible = on
	r.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func reset_stage(i: int) -> void:
	var s: Dictionary = stages[i]
	for c in s.coins:
		c.reset()
	for cp in s.checkpoints:
		cp.set_active(false)
	for r in s.resets:
		r.reset()


func _process(delta: float) -> void:
	clock += delta
	if lava_mat:
		lava_mat.emission_energy_multiplier = 1.2 + 0.5 * sin(clock * 2.5)
		kill_mat.emission_energy_multiplier = 1.2 + 0.8 * absf(sin(clock * 4.0))


func stage_1() -> void: # Meadow Steps — tutorial jumps
	plat(Vector3(0, 0, -10), Vector3(4, 1, 4))
	coin(Vector3(0, 0, -10))
	plat(Vector3(0, 0.8, -15.5), Vector3(3, 1, 3))
	plat(Vector3(-3, 1.6, -20.5), Vector3(3, 1, 3))
	coin(Vector3(-3, 1.6, -20.5))
	plat(Vector3(0, 2.4, -25.5), Vector3(3, 1, 3))
	coin(Vector3(0, 3.4, -23.0))
	island(Vector3(0, 2.4, -33), 4.0, 2)
	checkpoint(Vector3(0, 2.4, -33))
	plat(Vector3(0, 2.4, -41), Vector3(1.4, 0.6, 8))
	coin_line(Vector3(0, 2.4, -38.5), Vector3(0, 2.4, -43.5), 3)
	mover(Vector3(0, 2.4, -48.5), Vector3(0, 2.4, -53), Vector3(3, 0.6, 3), 4.0)
	coin(Vector3(0, 3.2, -50.7))
	island(Vector3(0, 2.4, -63), 6.0, 2)
	goal(Vector3(0, 2.4, -64))
	coin(Vector3(-3, 2.4, -61))
	coin(Vector3(3, 2.4, -61))
	info.length = 70.0


func stage_2() -> void: # Breezy Bridges — moving platforms
	mover(Vector3(-4, 0, -10), Vector3(4, 0, -10), Vector3(3, 0.6, 3), 4.0)
	coin(Vector3(0, 0.3, -10))
	plat(Vector3(0, 0, -15), Vector3(3, 1, 3))
	mover(Vector3(4, 0, -20), Vector3(-4, 0, -20), Vector3(3, 0.6, 3), 3.5)
	coin(Vector3(0, 0.3, -20))
	mover(Vector3(0, 0, -25.5), Vector3(0, 4.2, -25.5), Vector3(3, 0.6, 3), 5.0, 0.0)
	coin(Vector3(0, 4.6, -25.5))
	island(Vector3(0, 4, -33), 4.0, 2)
	checkpoint(Vector3(0, 4, -33))
	mover(Vector3(0, 4, -40), Vector3(0, 4, -48), Vector3(3, 0.6, 3), 4.5)
	coin(Vector3(0, 4.3, -44))
	mover(Vector3(-3.5, 4.5, -52), Vector3(3.5, 4.5, -52), Vector3(2.5, 0.6, 2.5), 3.2)
	mover(Vector3(3.5, 4.5, -57), Vector3(-3.5, 4.5, -57), Vector3(2.5, 0.6, 2.5), 3.2)
	coin(Vector3(0, 4.8, -52))
	coin(Vector3(0, 4.8, -57))
	island(Vector3(0, 4.5, -65), 6.0, 2)
	goal(Vector3(0, 4.5, -66))
	coin_line(Vector3(-3, 4.5, -62), Vector3(3, 4.5, -62), 3)
	info.length = 72.0


func stage_3() -> void: # Blink Blocks — vanishing platforms
	blinker(Vector3(0, 0, -10), Vector3(3, 0.8, 3))
	blinker(Vector3(2, 0.5, -15), Vector3(3, 0.8, 3))
	blinker(Vector3(-2, 1.0, -20), Vector3(3, 0.8, 3))
	coin(Vector3(0, 0, -10))
	coin(Vector3(2, 0.5, -15))
	coin(Vector3(-2, 1.0, -20))
	island(Vector3(0, 1, -28), 4.0, 2)
	checkpoint(Vector3(0, 1, -28))
	for k in 4:
		blinker(Vector3(0, 1, -35 - k * 4.0), Vector3(2.5, 0.6, 2.5), true, 3.0, 0.5 * (k % 2))
		coin(Vector3(0, 1, -35 - k * 4.0))
	plat(Vector3(0, 1, -52), Vector3(2.2, 0.6, 2.2))
	blinker(Vector3(3, 1.5, -55), Vector3(2.2, 0.6, 2.2))
	blinker(Vector3(-1, 2.0, -58.5), Vector3(2.2, 0.6, 2.2))
	coin(Vector3(3, 1.5, -55))
	island(Vector3(0, 2, -67), 6.0, 2)
	goal(Vector3(0, 2, -68))
	info.length = 75.0


func stage_4() -> void: # Fan Falls — updrafts and crosswinds
	plat(Vector3(0, 0, -11), Vector3(4, 1, 4))
	fan_up(Vector3(0, 0, -11), 9.0)
	coin_line(Vector3(0, 2.5, -11), Vector3(0, 6.5, -11), 3)
	plat(Vector3(0, 7, -17), Vector3(4, 1, 4))
	wind(Vector3(0, 8.2, -21), Vector3(3.5, 3.0, 4.0), Vector3(1, 0, 0), 5.0)
	plat(Vector3(0, 7, -25), Vector3(3, 1, 3))
	coin(Vector3(-1, 7.3, -21))
	island(Vector3(0, 7, -32), 4.0, 2)
	checkpoint(Vector3(0, 7, -32))
	plat(Vector3(0, 7, -40), Vector3(4, 1, 4))
	fan_up(Vector3(0, 7, -40), 10.5)
	coin_line(Vector3(0, 10, -40), Vector3(0, 14.5, -40), 3)
	plat(Vector3(0, 15, -46.5), Vector3(4, 1, 4))
	plat(Vector3(0, 14, -53), Vector3(3, 1, 3))
	wind(Vector3(0, 15.2, -55.5), Vector3(3.5, 3.0, 2.2), Vector3(-1, 0, 0), 5.5)
	plat(Vector3(0, 13, -58), Vector3(3, 1, 3))
	coin(Vector3(0, 14, -53))
	coin(Vector3(0, 13, -58))
	island(Vector3(0, 13, -66), 6.0, 2)
	goal(Vector3(0, 13, -67))
	info.length = 72.0


func stage_5() -> void: # Spin Cycle — sweeping bars
	disc(Vector3(0, 0, -14), 5.0)
	spinner(Vector3(0, 0, -14), 4.6, 1.4)
	coin(Vector3(3, 0, -14))
	coin(Vector3(-3, 0, -14))
	plat(Vector3(0, 0, -23), Vector3(3, 1, 3))
	disc(Vector3(0, 0.5, -32), 5.0)
	spinner(Vector3(0, 0.5, -32), 4.6, -1.7, 2)
	coin(Vector3(0, 0.5, -28.5))
	coin(Vector3(0, 0.5, -35.5))
	island(Vector3(0, 0.5, -44), 4.0, 2)
	checkpoint(Vector3(0, 0.5, -44))
	plat(Vector3(0, 0.5, -56.5), Vector3(1.8, 0.6, 13))
	spinner(Vector3(0, 0.5, -56.5), 4.5, 2.0, 1, 0.7)
	coin_line(Vector3(0, 0.5, -51.5), Vector3(0, 0.5, -61.5), 4)
	island(Vector3(0, 0.5, -71), 6.0, 2)
	goal(Vector3(0, 0.5, -72))
	info.length = 78.0


func stage_6() -> void: # Lava Lagoon — floor is lava
	lava(Vector3(0, -1.6, -24), Vector3(16, 0.6, 32))
	plat(Vector3(0, 0, -10), Vector3(2.5, 1, 2.5))
	plat(Vector3(2.5, 0.4, -14.5), Vector3(2.5, 1, 2.5))
	plat(Vector3(-1, 0.8, -19.5), Vector3(2.5, 1, 2.5))
	coin(Vector3(2.5, 0.4, -14.5))
	plat(Vector3(0, 0.8, -29), Vector3(4, 1, 10))
	kill_brick(Vector3(0, 1.3, -26.5), Vector3(4, 0.5, 0.5))
	kill_brick(Vector3(0, 1.3, -30.5), Vector3(4, 0.5, 0.5))
	coin(Vector3(0, 1.2, -28.5))
	coin(Vector3(0, 1.2, -32.5))
	island(Vector3(0, 0.8, -41), 4.0, 0)
	checkpoint(Vector3(0, 0.8, -41))
	lava(Vector3(0, -1.6, -57), Vector3(16, 0.6, 22))
	mover(Vector3(-3, 0.8, -48.5), Vector3(3, 0.8, -48.5), Vector3(3, 0.6, 3), 3.4)
	mover(Vector3(3, 0.8, -53.5), Vector3(-3, 0.8, -53.5), Vector3(3, 0.6, 3), 3.0)
	mover(Vector3(-3, 0.8, -58.5), Vector3(3, 0.8, -58.5), Vector3(3, 0.6, 3), 2.6)
	coin(Vector3(0, 1.0, -48.5))
	coin(Vector3(0, 1.0, -53.5))
	coin(Vector3(0, 1.0, -58.5))
	island(Vector3(0, 0.8, -67), 6.0, 0)
	goal(Vector3(0, 0.8, -68))
	info.length = 74.0


func stage_7() -> void: # Storm Gauntlet — a bit of everything
	blinker(Vector3(0, 0, -10), Vector3(3, 0.8, 3))
	blinker(Vector3(0, 0.8, -14.5), Vector3(3, 0.8, 3))
	coin(Vector3(0, 0.8, -14.5))
	plat(Vector3(0, 0.8, -20), Vector3(4, 1, 4))
	fan_up(Vector3(0, 0.8, -20), 9.0)
	coin(Vector3(0, 6, -20))
	plat(Vector3(0, 8, -26), Vector3(4, 1, 4))
	disc(Vector3(0, 8, -35), 5.0)
	spinner(Vector3(0, 8, -35), 4.6, 2.0, 2)
	coin(Vector3(3.2, 8, -35))
	island(Vector3(0, 8, -46), 4.0, 2)
	checkpoint(Vector3(0, 8, -46))
	mover(Vector3(0, 8, -53), Vector3(0, 8, -59), Vector3(3, 0.6, 3), 3.6)
	coin(Vector3(0, 8.3, -56))
	blinker(Vector3(0, 8.5, -64), Vector3(2.5, 0.6, 2.5), true, 2.6, 0.0)
	blinker(Vector3(0, 8.5, -68), Vector3(2.5, 0.6, 2.5), true, 2.6, 0.5)
	wind(Vector3(0, 9.8, -66), Vector3(4.0, 3.0, 8.0), Vector3(1, 0, 0), 3.5)
	coin(Vector3(0, 8.5, -68))
	island(Vector3(0, 8.5, -77), 6.0, 2)
	goal(Vector3(0, 8.5, -78))
	info.length = 84.0


func stage_8() -> void: # Crown of Clouds — the final climb
	plat(Vector3(0, 0, -9), Vector3(3, 1, 3))
	jump_pad(Vector3(0, 0, -9))
	coin(Vector3(0, 4.0, -12.5))
	plat(Vector3(0, 6, -16), Vector3(4, 1, 4))
	plat(Vector3(0, 6, -25), Vector3(1.6, 0.6, 14))
	spinner(Vector3(0, 6, -25), 4.0, 2.2, 1, 0.7)
	coin_line(Vector3(0, 6, -21), Vector3(0, 6, -29), 3)
	blinker(Vector3(0, 6.5, -35), Vector3(2.5, 0.6, 2.5))
	blinker(Vector3(0, 7, -39.5), Vector3(2.5, 0.6, 2.5))
	coin(Vector3(0, 7, -39.5))
	island(Vector3(0, 7, -47), 4.0, 2)
	checkpoint(Vector3(0, 7, -47))
	plat(Vector3(0, 7, -55), Vector3(4, 1, 4))
	fan_up(Vector3(0, 7, -55), 10.0)
	coin_line(Vector3(0, 10, -55), Vector3(0, 14, -55), 3)
	plat(Vector3(0, 14, -61), Vector3(4, 1, 4))
	mover(Vector3(-3, 14, -66.5), Vector3(3, 14, -66.5), Vector3(3, 0.6, 3), 3.0)
	coin(Vector3(0, 14.3, -66.5))
	plat(Vector3(0, 14, -74.25), Vector3(3, 1, 9.5))
	kill_brick(Vector3(0, 14.5, -72.5), Vector3(3, 0.5, 0.5))
	kill_brick(Vector3(0, 14.5, -76.0), Vector3(3, 0.5, 0.5))
	coin(Vector3(0, 14.3, -78))
	island(Vector3(0, 14, -86), 6.5, 2)
	goal(Vector3(0, 14, -87))
	for k in 5:
		var a := TAU * k / 5.0
		coin(Vector3(sin(a) * 4.0, 14, -86 + cos(a) * 4.0))
	info.length = 92.0
