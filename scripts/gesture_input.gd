extends Node
## Touch gestures instead of a virtual gamepad.
##   tap            -> strike
##   flick          -> dodge (flick up = lunge at the enemy)
##   hold still     -> guard (a hold begun just before impact is a parry)
##   drag           -> move (anywhere on screen, no visible stick)
##   both thumbs flick up / down -> Aspect abilities
##   both thumbs hold            -> Stormheart (limit) when the gauge is full
## Keyboard mirrors for desktop testing: WASD, J, Space, L, K, Q, E, R, F.

signal tap(pos: Vector2)
signal flick(dir: Vector2)
signal guard_changed(on: bool)
signal dual_flick(up: bool)
signal dual_hold
signal flask

const DEAD := 22.0
const FLICK_MIN := 46.0
const PENDING_T := 0.19
const RADIUS := 95.0

var move := Vector2.ZERO
var touches := {}
var _move_idx := -1
var _guard_idx := -1
var _dual_fired := false
var _kb_guard := false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = {"start": e.position, "pos": e.position, "origin": e.position, "t0": _now(), "state": "pending"}
		else:
			_release(e.index, e.position)
	elif e is InputEventScreenDrag:
		if touches.has(e.index):
			touches[e.index]["pos"] = e.position
	elif e is InputEventKey and not e.echo:
		_key(e)


func _key(e: InputEventKey) -> void:
	if e.keycode == KEY_K:
		_kb_guard = e.pressed
		guard_changed.emit(e.pressed)
		return
	if not e.pressed:
		return
	match e.keycode:
		KEY_J:
			tap.emit(Vector2(-1, -1))
		KEY_SPACE:
			var d := _kb_move()
			flick.emit(d if d.length() > 0.1 and d.y > -0.7 else Vector2(0, 1))
		KEY_L:
			flick.emit(Vector2(0, -1))
		KEY_Q:
			dual_flick.emit(true)
		KEY_E:
			dual_flick.emit(false)
		KEY_R:
			dual_hold.emit()
		KEY_F:
			flask.emit()


func _kb_move() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): v.y += 1.0
	return v.normalized()


func _process(_delta: float) -> void:
	var now := _now()
	var still_long := 0
	for idx in touches.keys():
		var t: Dictionary = touches[idx]
		var disp: Vector2 = t["pos"] - t["start"]
		var age: float = now - float(t["t0"])
		if t["state"] == "pending" and age >= PENDING_T:
			if disp.length() < DEAD:
				t["state"] = "guard"
				if _guard_idx == -1:
					_guard_idx = idx
					guard_changed.emit(true)
			elif _move_idx == -1:
				t["state"] = "move"
				_move_idx = idx
			else:
				t["state"] = "extra"
		elif t["state"] == "guard" and disp.length() > DEAD * 2.2 and _move_idx == -1:
			# a hold that turns into a drag becomes movement
			t["state"] = "move"
			t["origin"] = t["pos"]
			_move_idx = idx
			if _guard_idx == idx:
				_guard_idx = -1
				guard_changed.emit(false)
		if t["state"] == "guard" and age >= 0.4:
			still_long += 1
	if still_long >= 2:
		if not _dual_fired:
			_dual_fired = true
			dual_hold.emit()
	elif touches.size() < 2:
		_dual_fired = false

	var mv := Vector2.ZERO
	if _move_idx != -1 and touches.has(_move_idx):
		var mt: Dictionary = touches[_move_idx]
		var v: Vector2 = mt["pos"] - mt["origin"]
		if v.length() > RADIUS:
			mt["origin"] = mt["pos"] - v.normalized() * RADIUS
			v = mt["pos"] - mt["origin"]
		if v.length() > 10.0:
			mv = v / RADIUS
	var kb := _kb_move()
	move = kb if kb.length() > 0.1 else mv


func _release(idx: int, pos: Vector2) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	t["pos"] = pos
	var disp: Vector2 = pos - t["start"]
	var age: float = _now() - float(t["t0"])
	var st: String = t["state"]
	touches.erase(idx)
	match st:
		"pending":
			if disp.length() < DEAD:
				tap.emit(pos)
			elif disp.length() >= FLICK_MIN * 0.6:
				_flick(disp)
			else:
				tap.emit(pos)
		"move":
			_move_idx = -1
			if age < 0.34 and disp.length() >= FLICK_MIN:
				_flick(disp)
		"extra":
			if age < 0.34 and disp.length() >= FLICK_MIN:
				_flick(disp)
		"guard":
			if _guard_idx == idx:
				_guard_idx = -1
				if not _kb_guard:
					guard_changed.emit(false)


func _flick(disp: Vector2) -> void:
	# Two thumbs flicking the same vertical way at once = Aspect ability.
	if absf(disp.y) > absf(disp.x):
		var now := _now()
		for o in touches.keys():
			var ot: Dictionary = touches[o]
			var od: Vector2 = ot["pos"] - ot["start"]
			var fresh: bool = now - float(ot["t0"]) < 0.45
			if fresh and ot["state"] in ["pending", "move", "extra"] and od.length() >= FLICK_MIN * 0.6 \
					and absf(od.y) > absf(od.x) and signf(od.y) == signf(disp.y):
				if _move_idx == o:
					_move_idx = -1
				ot["state"] = "consumed"
				dual_flick.emit(disp.y < 0.0)
				return
	flick.emit(disp.normalized())


func reset() -> void:
	touches.clear()
	_move_idx = -1
	if _guard_idx != -1:
		_guard_idx = -1
		guard_changed.emit(false)
	move = Vector2.ZERO
