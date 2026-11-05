extends Node
func _ready():
	await get_tree().create_timer(0.5).timeout
	var g = get_parent().get_node("Main")
	g._enter_stage(0)
	var p = g.player
	p.teleport(g.respawn_pos + Vector3(0,0,3))
	await get_tree().create_timer(0.3).timeout
	Input.action_press("forward")
	await get_tree().create_timer(0.6).timeout
	var z0 = p.global_position.z; var y0 = p.global_position.y
	Input.action_press("jump")
	var maxy = y0
	var t = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	while t < 2.0:
		await get_tree().physics_frame
		t += 1.0/60.0
		maxy = max(maxy, p.global_position.y)
		if p.is_on_floor() and t > 0.1: break
	print("jump apex %.2f  dist %.2f  time %.2f speed %.2f" % [maxy-y0, z0 - p.global_position.z, t, p.velocity.length()])
	get_tree().quit()
