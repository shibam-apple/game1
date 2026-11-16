extends CharacterBody3D
## "Kite" - Ishaan Vyas, pilot of the proto-frame GARUDA. He fights from the
## air in a flight harness and commands his mech while he duels.
##   amber blade = can be guarded or parried
##   red blade   = cannot be guarded, move
## Emptying his LINK gauge burns out the harness and drops him to the sand.

const Humanoid := preload("res://scripts/humanoid.gd")

enum S { IDLE, HOVER, ATTACK, GROUNDED, STAGGER, RECOIL, SHIFT, EVADE, DEAD }

const MAX_HP := 1800.0
const MAX_WILL := 300.0
const HOVER_ALT := 2.3
const AMBER := Color(1.0, 0.62, 0.15)
const RED := Color(1.0, 0.1, 0.06)

const ATTACKS := {
	"dive": {"dur": 1.25, "ground": 1.3, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "overhead", "hit": 0.85, "total": 1.25},
		{"t": 0.63, "kind": "dash", "dur": 0.22, "alt": 0.0, "stop": 2.0},
		{"t": 0.85, "kind": "melee", "dmg": 18.0, "range": 3.4, "arc": 160.0, "shock": 1.8, "roll": 1.5}]},
	"swoop": {"dur": 1.8, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "slash_r", "hit": 0.6, "total": 0.75},
		{"t": 0.42, "kind": "dash", "dur": 0.18, "alt": 0.7, "stop": 2.0},
		{"t": 0.6, "kind": "melee", "dmg": 12.0, "range": 3.3, "arc": 180.0, "roll": 0.2},
		{"t": 0.75, "kind": "tele", "clip": "slash_l", "hit": 0.5, "total": 0.9},
		{"t": 1.07, "kind": "dash", "dur": 0.18, "alt": 0.7, "stop": 2.0},
		{"t": 1.25, "kind": "melee", "dmg": 13.0, "range": 3.3, "arc": 180.0, "roll": -0.2},
		{"t": 1.4, "kind": "alt", "alt": 2.3}]},
	"volley": {"dur": 1.6, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "thrust", "hit": 0.5, "total": 1.5},
		{"t": 0.5, "kind": "bolt"}, {"t": 0.8, "kind": "bolt"}, {"t": 1.1, "kind": "bolt"}]},
	"command": {"dur": 1.6, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "raise_plant", "hit": 1.25, "total": 1.6, "unb": true},
		{"t": 0.05, "kind": "strike", "radius": 3.6, "delay": 1.25, "dmg": 28.0}]},
	"skybreaker": {"dur": 1.4, "ground": 1.7, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "overhead", "hit": 1.2, "total": 1.4, "unb": true},
		{"t": 0.0, "kind": "alt", "alt": 5.5},
		{"t": 0.95, "kind": "dash", "dur": 0.25, "alt": 0.0, "stop": 0.6},
		{"t": 1.2, "kind": "melee", "dmg": 30.0, "range": 4.2, "arc": 360.0, "unb": true, "shock": 4.2, "aoe": true}]},
	"barrage": {"dur": 2.0, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "raise_plant", "hit": 1.1, "total": 2.0, "unb": true},
		{"t": 0.05, "kind": "strike", "radius": 3.2, "delay": 1.1, "dmg": 22.0},
		{"t": 0.5, "kind": "strike", "radius": 3.2, "delay": 1.1, "dmg": 22.0},
		{"t": 0.95, "kind": "strike", "radius": 3.2, "delay": 1.1, "dmg": 22.0}]},
	"dive2": {"dur": 1.75, "ground": 1.1, "ev": [
		{"t": 0.0, "kind": "tele", "clip": "overhead", "hit": 0.8, "total": 0.95},
		{"t": 0.58, "kind": "dash", "dur": 0.22, "alt": 0.0, "stop": 2.0},
		{"t": 0.8, "kind": "melee", "dmg": 16.0, "range": 3.4, "arc": 160.0, "shock": 1.8, "roll": 1.5},
		{"t": 0.95, "kind": "tele", "clip": "slash_r", "hit": 0.45, "total": 0.8},
		{"t": 1.4, "kind": "melee", "dmg": 16.0, "range": 3.6, "arc": 200.0, "roll": 0.1}]},
}

var game: Node
var player: CharacterBody3D
var vis: Node3D

var hp := MAX_HP
var will := MAX_WILL
var phase := 1
var stagger_mult := 1.0
var state: int = S.IDLE
var active := false
var alt := HOVER_ALT

var _t := 0.0
var _dur := 0.0
var _events: Array = []
var _ground_after := 0.0
var _think := 1.2
var _last := ""
var _dash_vel := Vector3.ZERO
var _dash_until := 0.0
var _alt_target := HOVER_ALT
var _alt_rate := 6.0
var _orbit := 1.0
var _orbit_t := 0.0
var _air_hits := 0
var _base_blade := Color(1.0, 0.7, 0.35)
var _thrusters: Array = []
var _time := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 2.0
	col.shape = cap
	col.position.y = 1.0
	add_child(col)
	vis = Humanoid.new()
	add_child(vis)
	vis.build(Color(0.2, 0.09, 0.08), Color(0.7, 0.55, 0.25), _base_blade, 1.35, 1.1)
	vis.scale = Vector3.ONE * 1.15
	# flight harness: swept wings and thruster pods
	var torso: Node3D = vis.joints["torso"]
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.14, 0.12, 0.13)
	wing_mat.metallic = 0.8
	wing_mat.roughness = 0.35
	for side in [1.0, -1.0]:
		var wm := BoxMesh.new()
		wm.size = Vector3(1.15, 0.05, 0.3)
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.material_override = wing_mat
		w.position = Vector3(0.62 * side, 0.52, 0.22)
		w.rotation_degrees = Vector3(0, -24.0 * side, 26.0 * side)
		torso.add_child(w)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color(1.0, 0.6, 0.25)
		var pm := CylinderMesh.new()
		pm.top_radius = 0.07
		pm.bottom_radius = 0.02
		pm.height = 0.5
		pm.radial_segments = 8
		var th := MeshInstance3D.new()
		th.mesh = pm
		th.material_override = tm
		th.position = Vector3(0.2 * side, 0.1, 0.22)
		torso.add_child(th)
		_thrusters.append(th)
	rng.randomize()


func reset(pos: Vector3) -> void:
	global_position = pos
	hp = MAX_HP
	will = MAX_WILL
	phase = 1
	stagger_mult = 1.0
	active = false
	alt = HOVER_ALT
	_alt_target = HOVER_ALT
	_think = 1.4
	_last = ""
	_air_hits = 0
	_base_blade = Color(1.0, 0.7, 0.35)
	vis.set_blade(_base_blade, 1.4)
	vis.stop()
	_set_state(S.IDLE)


func _set_state(s: int) -> void:
	state = s
	_t = 0.0
	_events = []
	_dash_until = 0.0


func is_dead() -> bool:
	return state == S.DEAD


func chest() -> Vector3:
	return global_position + Vector3(0, alt + 1.3, 0)


func _speed() -> float:
	return 1.2 if phase == 2 else 1.0


func _to_player() -> Vector3:
	var d := player.global_position - global_position
	d.y = 0.0
	return d


func _face(delta: float, rate: float) -> void:
	var d := _to_player()
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(1.0, rate * delta))


func _hover() -> void:
	_alt_target = HOVER_ALT
	_alt_rate = 5.0
	_set_state(S.HOVER)


func _physics_process(delta: float) -> void:
	_time += delta
	var flying := alt > 0.3 and state != S.DEAD
	for th in _thrusters:
		th.visible = flying
		th.scale.y = 0.8 + 0.4 * sin(_time * 40.0)
	if state == S.DEAD or not active:
		alt = move_toward(alt, _alt_target if state != S.DEAD else 0.0, 4.0 * delta)
		vis.position.y = alt + (sin(_time * 2.4) * 0.12 if flying else 0.0)
		return
	_t += delta
	var vel := Vector3.ZERO
	var d := _to_player()
	var dist := d.length()
	match state:
		S.IDLE, S.HOVER:
			_face(delta, 6.0)
			_think -= delta
			_orbit_t -= delta
			if _orbit_t <= 0.0:
				_orbit_t = rng.randf_range(1.5, 3.5)
				_orbit = -_orbit if rng.randf() < 0.5 else _orbit
			if dist > 0.1 and not player.is_dead():
				var n := d / dist
				var tangent := Vector3(-n.z, 0, n.x) * _orbit
				var want := 6.0
				vel = tangent * 3.4 + n * clampf(dist - want, -3.5, 5.0)
				if _think <= 0.0:
					_start_attack(_choose(dist))
		S.ATTACK:
			_run_events(dist)
			if _t < _dash_until:
				vel = _dash_vel
			else:
				_face(delta, 8.0)
			if _t >= _dur:
				vis.set_blade(_base_blade, 1.4)
				_think = rng.randf_range(0.9, 1.6) if phase == 1 else rng.randf_range(0.5, 1.0)
				if _ground_after > 0.0:
					_set_state(S.GROUNDED)
					_dur = _ground_after
					_alt_target = 0.0
				else:
					_hover()
		S.GROUNDED, S.RECOIL, S.SHIFT:
			if _t >= _dur:
				vis.stop()
				_hover()
		S.EVADE:
			vel = _dash_vel
			if _t >= _dur:
				_think = 0.25
				_hover()
		S.STAGGER:
			if _t >= _dur:
				will = MAX_WILL
				stagger_mult = 1.0
				vis.stop()
				vis.set_blade(_base_blade, 1.4)
				_think = 0.6
				_hover()

	alt = move_toward(alt, _alt_target, _alt_rate * delta)
	vis.position.y = alt + (sin(_time * 2.4) * 0.12 if alt > 0.3 else 0.0)
	velocity = vel
	move_and_slide()
	var p := global_position
	p.y = 0.0
	var flat := Vector2(p.x, p.z)
	if flat.length() > game.ARENA_R - 0.5:
		flat = flat.normalized() * (game.ARENA_R - 0.5)
		p.x = flat.x
		p.z = flat.y
	global_position = p


func _choose(dist: float) -> String:
	var pool := ["dive", "dive", "swoop", "volley", "command", "skybreaker"]
	if phase == 2:
		pool = ["dive2", "dive2", "swoop", "volley", "barrage", "barrage", "skybreaker", "command"]
	var pick: String = pool[rng.randi() % pool.size()]
	if pick == _last or (pick == "volley" and dist < 4.0):
		pick = pool[rng.randi() % pool.size()]
	return pick


func _start_attack(n: String) -> void:
	_last = n
	var a: Dictionary = ATTACKS[n]
	var sp := _speed()
	_set_state(S.ATTACK)
	_dur = float(a["dur"]) / sp
	_ground_after = float(a.get("ground", 0.0))
	for e in a["ev"]:
		var c: Dictionary = e.duplicate()
		c["t"] = float(c["t"]) / sp
		for k in ["dur", "hit", "total", "delay"]:
			if c.has(k):
				c[k] = float(c[k]) / sp
		_events.append(c)


func _run_events(dist: float) -> void:
	while not _events.is_empty() and _t >= float(_events[0]["t"]):
		var e: Dictionary = _events.pop_front()
		match e["kind"]:
			"tele":
				var unb: bool = e.get("unb", false)
				vis.play(e["clip"], float(e["hit"]), float(e["total"]))
				vis.set_blade(RED if unb else AMBER, 6.0)
				game.sfx.play("warn_red" if unb else "warn")
				if unb:
					game.on_red_warning()
			"alt":
				_alt_target = float(e["alt"])
				_alt_rate = 9.0
			"dash":
				var d := _to_player()
				var gap := maxf(0.0, d.length() - float(e["stop"]))
				_dash_vel = d.normalized() * (gap / float(e["dur"]))
				_dash_until = _t + float(e["dur"])
				_alt_target = float(e["alt"])
				_alt_rate = 26.0
				rotation.y = atan2(-d.x, -d.z)
				game.sfx.play("dodge")
			"melee":
				_resolve(e)
			"bolt":
				game.spawn_bolt(chest() - global_transform.basis.z * 0.8, 9.0)
				game.sfx.play("bolt")
			"strike":
				game.spawn_strike(float(e["radius"]), float(e["delay"]), float(e["dmg"]))


func _resolve(e: Dictionary) -> void:
	var unb: bool = e.get("unb", false)
	var col := RED if unb else AMBER
	vis.set_blade(_base_blade, 1.4)
	game.slash_fx(global_position + Vector3(0, alt + 1.2, 0), rotation.y, col, 1.7, float(e.get("roll", 0.0)))
	game.sfx.play("slash_big")
	if e.has("shock"):
		game.ring(global_position, float(e["shock"]), 0.3, col)
		game.shake(0.4)
		game.sfx.play("heavy")
	var d := _to_player()
	if d.length() > float(e["range"]):
		return
	if not e.get("aoe", false) and d.length() > 1.5:
		var fwd := -global_transform.basis.z
		if rad_to_deg(fwd.angle_to(d.normalized())) > float(e["arc"]) * 0.5:
			return
	var res: String = player.receive_hit(float(e["dmg"]), unb, global_position)
	if res == "parried":
		parried()


## Called when the player parries a blade strike.
func parried() -> void:
	_take_will(60.0)
	if state != S.STAGGER and state != S.DEAD:
		_set_state(S.RECOIL)
		_dur = 1.15
		_alt_target = 0.4
		_alt_rate = 8.0
		vis.set_blade(_base_blade, 1.4)
		vis.play("hurt", 0.1, 1.15)


func take_hit(dmg: float, will_dmg: float) -> void:
	if state == S.DEAD or not active:
		return
	var crit := state == S.STAGGER
	if crit:
		dmg *= stagger_mult
		stagger_mult = minf(1.5, stagger_mult + 0.04)
	hp -= dmg
	vis.flash(Color(1.0, 0.9, 0.7))
	var at := chest() + Vector3(rng.randf_range(-0.5, 0.5), 0.9 + rng.randf_range(0.0, 0.4), 0)
	game.number(at, str(int(round(dmg))), Color(1.0, 0.85, 0.3) if crit else Color.WHITE)
	game.spark(chest(), Color(1.0, 0.8, 0.5), 10)
	game.sfx.play("hit")
	if hp <= 0.0:
		_die()
		return
	if not crit:
		_take_will(will_dmg)
	if state == S.STAGGER:
		return
	if phase == 1 and hp <= MAX_HP * 0.5:
		_shift()
		return
	# He will not sit still in the air and be carved up.
	if state == S.HOVER:
		_air_hits += 1
		if _air_hits >= 5:
			_air_hits = 0
			var d := _to_player()
			var n := d.normalized()
			var side := Vector3(-n.z, 0, n.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			_set_state(S.EVADE)
			_dur = 0.32
			_dash_vel = (side * 0.8 - n * 0.6).normalized() * 20.0
			game.sfx.play("dodge")


func _take_will(amount: float) -> void:
	if state == S.STAGGER or state == S.DEAD:
		return
	will -= amount
	if will <= 0.0:
		will = 0.0
		stagger_mult = 1.0
		_air_hits = 0
		vis.set_blade(_base_blade, 0.5)
		_set_state(S.STAGGER)
		_dur = 5.5
		_alt_target = 0.0
		_alt_rate = 14.0
		vis.play("kneel", 0.35, 1.0, true)
		game.on_boss_stagger(global_position)


func _shift() -> void:
	phase = 2
	_base_blade = Color(1.0, 0.22, 0.12)
	vis.set_blade(_base_blade, 3.0)
	_set_state(S.SHIFT)
	_dur = 1.6
	_alt_target = 3.2
	_alt_rate = 5.0
	vis.play("raise_plant", 0.8, 1.6)
	game.on_boss_shift(global_position)


func _die() -> void:
	hp = 0.0
	_set_state(S.DEAD)
	_alt_target = 0.0
	vis.set_blade(_base_blade, 0.2)
	vis.play("death", 0.9, 1.5, true)
	game.on_boss_dead()
