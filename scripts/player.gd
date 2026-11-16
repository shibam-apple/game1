extends CharacterBody3D
## Ran Sen, pilot of the Sand Lancer, fighting on foot. Fast, fragile, built
## around combos, precise dodges, parries and calling the mech in.

const Humanoid := preload("res://scripts/humanoid.gd")

enum S { IDLE, ATTACK, DODGE, GUARD, HURT, ABILITY, DRINK, DEAD }

const MAX_HP := 100.0
const MAX_STAMINA := 100.0
const MAX_FLASKS := 3
const MOVE_SPEED := 5.6
const MELEE_RANGE := 3.2
const CD_MAX := [8.0, 13.0]
const COMBO := [
	{"clip": "slash_r", "hit": 0.13, "dur": 0.40, "dmg": 9.0, "will": 8.0},
	{"clip": "slash_l", "hit": 0.13, "dur": 0.40, "dmg": 9.0, "will": 8.0},
	{"clip": "slash_r", "hit": 0.15, "dur": 0.44, "dmg": 11.0, "will": 10.0},
	{"clip": "overhead", "hit": 0.24, "dur": 0.68, "dmg": 21.0, "will": 22.0},
]

var game: Node
var boss: CharacterBody3D
var vis: Node3D

var hp := MAX_HP
var stamina := MAX_STAMINA
var flasks := MAX_FLASKS
var limit := 0.0
var limit_active := 0.0
var cd := [0.0, 0.0]
var state: int = S.IDLE
var guard_held := false
var move_input := Vector2.ZERO
var hits_landed := 0

var _t := 0.0
var _dur := 0.0
var _events: Array = []
var _combo := 0
var _combo_reset := 0.0
var _buffer_t := 0.0
var _dash_vel := Vector3.ZERO
var _dash_until := 0.0
var _iframes := 0.0
var _dodge_credit := false
var _guard_t := 0.0
var _counter_window := 0.0
var _stam_delay := 0.0
var _spin := false
var _leap := false
var _armor := false
var _cape: Node3D
var _cape_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	vis = Humanoid.new()
	add_child(vis)
	vis.build(Color(0.8, 0.76, 0.68), Color(0.6, 0.22, 0.16), Color(0.35, 0.62, 1.0), 1.15, 1.0)
	# wind-torn cape
	_cape = Node3D.new()
	_cape.position = Vector3(0, 0.5, 0.14)
	vis.joints["torso"].add_child(_cape)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.7, 0.58, 0.4)
	cm.roughness = 1.0
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.52, 0.95, 0.02)
	var cmi := MeshInstance3D.new()
	cmi.mesh = cmesh
	cmi.material_override = cm
	cmi.position = Vector3(0, -0.45, 0)
	_cape.add_child(cmi)


func reset(pos: Vector3) -> void:
	global_position = pos
	hp = MAX_HP
	stamina = MAX_STAMINA
	flasks = MAX_FLASKS
	limit = 0.0
	limit_active = 0.0
	cd = [0.0, 0.0]
	hits_landed = 0
	_combo = 0
	_buffer_t = 0.0
	_counter_window = 0.0
	_iframes = 0.0
	guard_held = false
	collision_mask = 1
	vis.position = Vector3.ZERO
	vis.rotation = Vector3.ZERO
	vis.set_blade(vis.blade_color, 1.6)
	vis.stop()
	_set_state(S.IDLE)


func _set_state(s: int) -> void:
	state = s
	_t = 0.0
	_events = []
	_spin = false
	_leap = false
	_armor = false
	_dash_vel = Vector3.ZERO


func _to_boss() -> Vector3:
	var d := boss.global_position - global_position
	d.y = 0.0
	return d


func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	_t += delta
	_iframes = maxf(0.0, _iframes - delta)
	_counter_window = maxf(0.0, _counter_window - delta)
	_buffer_t = maxf(0.0, _buffer_t - delta)
	_stam_delay = maxf(0.0, _stam_delay - delta)
	for i in 2:
		cd[i] = maxf(0.0, cd[i] - delta)
	if _stam_delay <= 0.0:
		stamina = minf(MAX_STAMINA, stamina + (10.0 if state == S.GUARD else 30.0) * delta)
	if limit_active > 0.0:
		limit_active = maxf(0.0, limit_active - delta)
		if limit_active <= 0.0:
			vis.set_blade(vis.blade_color, 1.6)
	if _combo_reset > 0.0 and state != S.ATTACK:
		_combo_reset -= delta
		if _combo_reset <= 0.0:
			_combo = 0

	var to_boss := _to_boss()
	if state != S.DODGE and to_boss.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-to_boss.x, -to_boss.z), minf(1.0, 14.0 * delta))

	var vel := Vector3.ZERO
	var walking := 0.0
	match state:
		S.IDLE:
			if move_input.length() > 0.05:
				vel = game.screen_dir_to_world(move_input) * MOVE_SPEED * minf(1.0, move_input.length())
				walking = minf(1.0, move_input.length())
			if guard_held:
				_enter_guard()
			elif _buffer_t > 0.0:
				_buffer_t = 0.0
				_start_attack()
		S.GUARD:
			_guard_t += delta
			if move_input.length() > 0.05:
				vel = game.screen_dir_to_world(move_input) * 1.6
			if not guard_held:
				vis.stop()
				_set_state(S.IDLE)
		S.ATTACK, S.ABILITY:
			_run_events()
			if _t < _dash_until:
				vel = _dash_vel
			if _spin:
				vis.rotation.y += delta * 22.0
			if _leap:
				var u := clampf(_t / 0.6, 0.0, 1.0)
				vis.position.y = sin(u * PI) * 2.3
			if _t >= _dur:
				_end_action()
			elif state == S.ATTACK and _buffer_t > 0.0 and _events.is_empty() and _t >= _dur * 0.62:
				_buffer_t = 0.0
				_start_attack()
		S.DODGE:
			vel = _dash_vel
			if _t >= _dur:
				collision_mask = 1
				vis.stop()
				_set_state(S.IDLE)
		S.HURT:
			vel = _dash_vel * maxf(0.0, 1.0 - _t / _dur)
			if _t >= _dur:
				_set_state(S.IDLE)
		S.DRINK:
			_run_events()
			if _t >= _dur:
				_set_state(S.IDLE)

	# Exosuit boost: strikes rise to meet an airborne target.
	if not _leap:
		var ty := 0.0
		if (state == S.ATTACK or state == S.ABILITY) and to_boss.length() < 4.8 and not boss.is_dead():
			ty = boss.alt * 0.85
		vis.position.y = move_toward(vis.position.y, ty, (16.0 if ty > vis.position.y else 9.0) * delta)
	_cape_t += delta
	var flare := 14.0 + vel.length() * 5.0 + vis.position.y * 10.0
	_cape.rotation_degrees.x = lerpf(_cape.rotation_degrees.x, -(minf(flare, 75.0) + sin(_cape_t * 7.0) * 5.0), minf(1.0, 8.0 * delta))
	vis.walk_amount = lerpf(vis.walk_amount, walking, minf(1.0, 12.0 * delta))
	velocity = vel
	move_and_slide()
	var p := global_position
	p.y = 0.0
	var flat := Vector2(p.x, p.z)
	if flat.length() > game.ARENA_R:
		flat = flat.normalized() * game.ARENA_R
		p.x = flat.x
		p.z = flat.y
	global_position = p


func _end_action() -> void:
	vis.rotation.y = 0.0
	_combo_reset = 0.7
	_set_state(S.IDLE)


func _run_events() -> void:
	while not _events.is_empty() and _t >= float(_events[0]["t"]):
		var ev: Dictionary = _events.pop_front()
		match ev["kind"]:
			"melee":
				_melee(ev)
			"heal":
				hp = minf(MAX_HP, hp + 45.0)
				game.number(global_position + Vector3(0, 2.1, 0), "+45", Color(0.5, 1.0, 0.6))
				game.sfx.play("heal")


func _melee(ev: Dictionary) -> void:
	var fwd := -global_transform.basis.z
	var col: Color = Color(1.0, 0.8, 0.4) if limit_active > 0.0 else vis.blade_color
	game.slash_fx(global_position + Vector3(0, 1.15 + vis.position.y, 0), rotation.y, col, float(ev.get("fx", 1.0)), float(ev.get("roll", 0.0)))
	game.sfx.play("slash")
	if ev.get("shock", false):
		game.ring(global_position, float(ev["range"]), 0.35, col)
		game.shake(0.45)
		game.sfx.play("heavy")
	if boss.is_dead():
		return
	var d := _to_boss()
	if d.length() > float(ev["range"]) + 0.9:
		return
	if not ev.get("shock", false) and d.length() > 1.2 and fwd.dot(d.normalized()) < 0.2:
		return
	var mult := 1.3 if limit_active > 0.0 else 1.0
	boss.take_hit(float(ev["dmg"]) * mult, float(ev["will"]) * mult)
	hits_landed += 1
	if limit_active > 0.0:
		hp = minf(MAX_HP, hp + 1.5)
	else:
		_gain(float(ev.get("limit", 3.0)))
	game.hitstop(float(ev.get("stop", 0.045)))
	game.shake(float(ev.get("shake", 0.12)))


func _gain(v: float) -> void:
	if limit_active > 0.0:
		return
	var was := limit
	limit = minf(100.0, limit + v)
	if limit >= 100.0 and was < 100.0:
		game.on_limit_ready()


func _speed() -> float:
	return 1.3 if limit_active > 0.0 else 1.0


func _close_gap(reach: float, window: float, cap: float) -> void:
	var d := _to_boss()
	var gap := d.length() - reach
	if gap > 0.0:
		_dash_vel = d.normalized() * minf(gap / window, cap)
		_dash_until = window
	else:
		_dash_until = 0.0


# ---- commands from gestures -------------------------------------------------

func on_tap() -> void:
	match state:
		S.IDLE, S.GUARD:
			_start_attack()
		S.ATTACK, S.ABILITY, S.DODGE, S.HURT:
			_buffer_t = 0.4


func _start_attack() -> void:
	var sp := _speed()
	if _counter_window > 0.0:
		# Mirage Counter: reward for a perfect dodge
		_counter_window = 0.0
		_set_state(S.ATTACK)
		_dur = 0.5
		_close_gap(2.2, 0.1, 60.0)
		vis.play("thrust", 0.1, 0.5)
		_events = [{"t": 0.1, "kind": "melee", "dmg": 30.0, "will": 40.0, "range": MELEE_RANGE, "fx": 1.5, "stop": 0.1, "shake": 0.35, "limit": 8.0}]
		_combo = 1
		return
	var c: Dictionary = COMBO[_combo]
	var hit: float = float(c["hit"]) / sp
	_set_state(S.ATTACK)
	_dur = float(c["dur"]) / sp
	_close_gap(2.3, hit, 15.0)
	vis.play(c["clip"], hit, _dur)
	var heavy := _combo == 3
	_events = [{"t": hit, "kind": "melee", "dmg": c["dmg"], "will": c["will"], "range": MELEE_RANGE,
		"fx": 1.35 if heavy else 1.0, "roll": [0.35, -0.35, 0.15, 1.5][_combo],
		"stop": 0.08 if heavy else 0.04, "shake": 0.3 if heavy else 0.1, "limit": 6.0 if heavy else 3.0}]
	_combo = (_combo + 1) % COMBO.size()


func on_flick(dir: Vector2) -> void:
	if not (state in [S.IDLE, S.GUARD, S.ATTACK]):
		return
	if dir.y < -0.76:
		_lunge()
	else:
		_dodge(dir)


func _dodge(dir: Vector2) -> void:
	if stamina < 5.0:
		return
	stamina = maxf(0.0, stamina - 20.0)
	_stam_delay = 0.55
	vis.rotation.y = 0.0
	vis.position.y = 0.0
	_set_state(S.DODGE)
	_dur = 0.36
	_iframes = 0.27
	_dodge_credit = true
	_dash_vel = game.screen_dir_to_world(dir) * 11.5
	collision_mask = 0
	vis.play("crouch", 0.08, 0.36)
	game.sfx.play("dodge")


func _lunge() -> void:
	if stamina < 5.0:
		return
	stamina = maxf(0.0, stamina - 14.0)
	_stam_delay = 0.5
	_set_state(S.ATTACK)
	var sp := _speed()
	_dur = 0.52 / sp
	var hit := 0.2 / sp
	_close_gap(2.3, hit, 30.0)
	vis.play("thrust", hit, _dur)
	_events = [{"t": hit, "kind": "melee", "dmg": 13.0, "will": 14.0, "range": MELEE_RANGE, "fx": 1.1, "stop": 0.05, "limit": 4.0}]
	_combo = 1
	game.sfx.play("dodge")


func on_guard(on: bool) -> void:
	guard_held = on
	if on and state == S.IDLE:
		_enter_guard()


func _enter_guard() -> void:
	_set_state(S.GUARD)
	_guard_t = 0.0
	vis.play("guard", 0.07, 0.2, true)


func on_ability(i: int) -> void:
	if not (state in [S.IDLE, S.GUARD, S.ATTACK]) or cd[i] > 0.0:
		return
	cd[i] = CD_MAX[i]
	_set_state(S.ABILITY)
	_armor = true
	if i == 0:
		# Stormrend: whirling triple cut that shreds the Will gauge
		_dur = 0.95
		_spin = true
		_close_gap(2.2, 0.2, 26.0)
		vis.play("slash_r", 0.18, 0.95, true)
		for k in 3:
			_events.append({"t": 0.2 + 0.2 * k, "kind": "melee", "dmg": 10.0, "will": 18.0, "range": 3.6, "fx": 1.5, "roll": 0.3 * (k - 1), "shock": k == 2, "stop": 0.05, "limit": 3.0})
		game.sfx.play("limit")
	else:
		# Glassfall: leap and crash down
		_dur = 1.0
		_leap = true
		_close_gap(1.9, 0.58, 20.0)
		vis.play("overhead", 0.6, 1.0)
		_events = [{"t": 0.6, "kind": "melee", "dmg": 38.0, "will": 45.0, "range": 4.2, "fx": 1.8, "roll": 1.5, "shock": true, "stop": 0.12, "shake": 0.6, "limit": 6.0}]
		game.sfx.play("limit")


func on_limit() -> void:
	if state == S.DEAD or limit < 100.0 or limit_active > 0.0:
		return
	limit = 0.0
	limit_active = 8.0
	vis.set_blade(Color(1.0, 0.75, 0.3), 4.0)
	vis.flash(Color(1.0, 0.8, 0.4))
	game.ring(global_position, 5.0, 0.5, Color(1.0, 0.8, 0.4))
	game.mech_strike()


func on_flask() -> void:
	if not (state in [S.IDLE, S.GUARD]) or flasks <= 0 or hp >= MAX_HP:
		return
	flasks -= 1
	_set_state(S.DRINK)
	_dur = 0.9
	vis.play("drink", 0.3, 0.9)
	_events = [{"t": 0.5, "kind": "heal"}]


# ---- being hit ---------------------------------------------------------------

## Returns "dodged", "parried", "blocked", "hit" or "none".
func receive_hit(dmg: float, unblockable: bool, from: Vector3) -> String:
	if state == S.DEAD:
		return "none"
	if _iframes > 0.0:
		if _dodge_credit:
			_dodge_credit = false
			_counter_window = 1.3
			_gain(12.0)
			game.perfect_dodge(global_position)
		return "dodged"
	var away := global_position - from
	away.y = 0.0
	away = away.normalized()
	if state == S.GUARD and not unblockable:
		if _guard_t <= 0.25:
			_gain(10.0)
			game.parry_fx(global_position - away * 1.0 + Vector3(0, 1.3, 0))
			return "parried"
		stamina -= dmg * 1.3
		_stam_delay = 0.8
		hp -= dmg * 0.15
		game.spark(global_position - away * 0.6 + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.6), 8)
		game.sfx.play("block")
		game.shake(0.15)
		if hp <= 0.0:
			_die()
		elif stamina <= 0.0:
			stamina = 0.0
			_stagger(away, 0.8)
		return "blocked"
	if _armor:
		dmg *= 0.5
	hp -= dmg
	game.on_player_hit(dmg, global_position)
	vis.flash(Color(1.0, 0.25, 0.2))
	if hp <= 0.0:
		_die()
	elif not _armor:
		_stagger(away, 0.42)
	return "hit"


func _stagger(away: Vector3, dur: float) -> void:
	vis.rotation.y = 0.0
	vis.position.y = 0.0
	collision_mask = 1
	_combo = 0
	_set_state(S.HURT)
	_dur = dur
	_dash_vel = away * 7.0
	vis.play("hurt", 0.06, dur)


func _die() -> void:
	hp = 0.0
	vis.rotation.y = 0.0
	vis.position.y = 0.0
	_set_state(S.DEAD)
	vis.play("death", 0.5, 1.0, true)
	game.on_player_dead()


func is_dead() -> bool:
	return state == S.DEAD
