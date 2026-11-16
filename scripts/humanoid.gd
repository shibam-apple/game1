extends Node3D
## Procedural placeholder fighter: a jointed figure built from primitives and
## animated by blending between key poses. Swap for a rigged, mocap-driven
## model in the art pass; the gameplay code only calls play()/stop().

const JN := ["torso", "head", "sh_r", "el_r", "sh_l", "el_l", "hip_r", "kn_r", "hip_l", "kn_l"]

const IDLE := {
	"torso": Vector3(6, -22, 0), "head": Vector3(-2, 18, 0),
	"sh_r": Vector3(42, 0, -10), "el_r": Vector3(38, 0, 0),
	"sh_l": Vector3(18, 0, 12), "el_l": Vector3(45, 0, 0),
	"hip_r": Vector3(-16, 0, -4), "kn_r": Vector3(-18, 0, 0),
	"hip_l": Vector3(24, 0, 4), "kn_l": Vector3(-30, 0, 0),
}

const CLIPS := {
	"slash_r": {
		"wind": {"torso": Vector3(0, -55, 0), "sh_r": Vector3(115, -40, -35), "el_r": Vector3(75, 0, 0), "sh_l": Vector3(40, 0, 20)},
		"strike": {"torso": Vector3(12, 45, 0), "sh_r": Vector3(72, 62, 0), "el_r": Vector3(8, 0, 0), "hip_l": Vector3(40, 0, 0), "kn_l": Vector3(-42, 0, 0), "py": -0.06},
		"follow": {"torso": Vector3(10, 62, 0), "sh_r": Vector3(45, 85, 0), "el_r": Vector3(22, 0, 0)},
	},
	"slash_l": {
		"wind": {"torso": Vector3(0, 55, 0), "sh_r": Vector3(95, 75, 0), "el_r": Vector3(85, 0, 0)},
		"strike": {"torso": Vector3(12, -42, 0), "sh_r": Vector3(74, -42, 0), "el_r": Vector3(6, 0, 0), "hip_l": Vector3(38, 0, 0), "kn_l": Vector3(-40, 0, 0), "py": -0.06},
		"follow": {"torso": Vector3(10, -60, 0), "sh_r": Vector3(50, -70, 0), "el_r": Vector3(20, 0, 0)},
	},
	"overhead": {
		"wind": {"torso": Vector3(-16, 0, 0), "sh_r": Vector3(172, 0, 0), "el_r": Vector3(45, 0, 0), "sh_l": Vector3(165, 0, 0), "el_l": Vector3(40, 0, 0), "py": 0.04},
		"strike": {"torso": Vector3(34, 0, 0), "sh_r": Vector3(42, 0, 0), "el_r": Vector3(0, 0, 0), "sh_l": Vector3(45, 0, 0), "el_l": Vector3(10, 0, 0), "hip_l": Vector3(50, 0, 0), "kn_l": Vector3(-60, 0, 0), "py": -0.16},
		"follow": {"torso": Vector3(38, 0, 0), "sh_r": Vector3(30, 0, 0), "el_r": Vector3(0, 0, 0), "py": -0.18},
	},
	"thrust": {
		"wind": {"torso": Vector3(0, -45, 0), "sh_r": Vector3(30, 0, -20), "el_r": Vector3(115, 0, 0), "py": -0.08},
		"strike": {"torso": Vector3(16, 28, 0), "sh_r": Vector3(86, 0, 0), "el_r": Vector3(0, 0, 0), "hip_l": Vector3(52, 0, 0), "kn_l": Vector3(-48, 0, 0), "hip_r": Vector3(-34, 0, 0), "py": -0.14},
		"follow": {"torso": Vector3(14, 24, 0), "sh_r": Vector3(80, 0, 0), "el_r": Vector3(6, 0, 0), "py": -0.1},
	},
	"raise_plant": {
		"wind": {"torso": Vector3(-14, 0, 0), "sh_r": Vector3(176, 0, -12), "sh_l": Vector3(176, 0, 12), "el_r": Vector3(10, 0, 0), "el_l": Vector3(10, 0, 0), "head": Vector3(-20, 0, 0)},
		"strike": {"torso": Vector3(38, 0, 0), "sh_r": Vector3(48, 0, 0), "sh_l": Vector3(48, 0, 0), "hip_l": Vector3(60, 0, 0), "kn_l": Vector3(-80, 0, 0), "hip_r": Vector3(20, 0, 0), "kn_r": Vector3(-70, 0, 0), "py": -0.3},
	},
	"kneel": {
		"strike": {"torso": Vector3(32, 0, 0), "head": Vector3(26, 0, 0), "sh_r": Vector3(18, 0, -18), "el_r": Vector3(20, 0, 0), "sh_l": Vector3(30, 0, 10), "el_l": Vector3(60, 0, 0), "hip_l": Vector3(82, 0, 0), "kn_l": Vector3(-96, 0, 0), "hip_r": Vector3(-8, 0, 0), "kn_r": Vector3(-100, 0, 0), "py": -0.42},
	},
	"hurt": {
		"strike": {"torso": Vector3(-22, 24, 0), "head": Vector3(-16, 0, 0), "sh_r": Vector3(10, 0, -40), "sh_l": Vector3(-10, 0, 40), "py": -0.05},
	},
	"death": {
		"strike": {"torso": Vector3(-84, 0, 0), "head": Vector3(-10, 30, 0), "sh_r": Vector3(-20, 0, -70), "sh_l": Vector3(-20, 0, 70), "hip_r": Vector3(70, 0, -10), "hip_l": Vector3(60, 0, 10), "kn_r": Vector3(-30, 0, 0), "kn_l": Vector3(-50, 0, 0), "py": -0.78},
	},
	"guard": {
		"strike": {"torso": Vector3(6, -12, 0), "sh_r": Vector3(84, 38, 0), "el_r": Vector3(62, 0, 0), "sh_l": Vector3(72, -34, 0), "el_l": Vector3(72, 0, 0), "py": -0.07},
	},
	"crouch": {
		"strike": {"torso": Vector3(44, 0, 0), "head": Vector3(-20, 0, 0), "sh_r": Vector3(-20, 0, -20), "sh_l": Vector3(-20, 0, 20), "hip_r": Vector3(64, 0, 0), "hip_l": Vector3(70, 0, 0), "kn_r": Vector3(-95, 0, 0), "kn_l": Vector3(-95, 0, 0), "py": -0.32},
	},
	"drink": {
		"strike": {"torso": Vector3(-6, 0, 0), "head": Vector3(-24, 0, 0), "sh_l": Vector3(118, 0, -10), "el_l": Vector3(118, 0, 0)},
	},
}

var joints := {}
var pelvis: Node3D
var body_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D
var blade_mat: StandardMaterial3D
var blade_color := Color(0.45, 0.85, 1.0)
var walk_amount := 0.0
var walk_rate := 9.0

var _phase := 0.0
var _time := 0.0
var _clip: Array = []
var _clip_t := 0.0
var _hold := false
var _from := {}
var _cur := {}
var _blend := 1.0
var _blend_len := 0.1
var _flash := 0.0
var _flash_col := Color.WHITE
var _pelvis_y := 0.95


func build(body_col: Color, trim_col: Color, blade_col: Color, blade_len: float, bulk: float) -> void:
	blade_color = blade_col
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = body_col
	body_mat.roughness = 0.55
	body_mat.metallic = 0.35
	trim_mat = StandardMaterial3D.new()
	trim_mat.albedo_color = trim_col
	trim_mat.roughness = 0.35
	trim_mat.metallic = 0.8
	blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.9, 0.95, 1.0)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.15
	blade_mat.emission_enabled = true
	set_blade(blade_col, 1.6)

	pelvis = Node3D.new()
	pelvis.position.y = _pelvis_y
	add_child(pelvis)
	_box(pelvis, Vector3(0.34 * bulk, 0.16, 0.22 * bulk), Vector3(0, 0.02, 0), body_mat)

	var torso := _joint("torso", pelvis, Vector3(0, 0.08, 0))
	_box(torso, Vector3(0.40 * bulk, 0.34, 0.24 * bulk), Vector3(0, 0.33, 0), body_mat)
	_box(torso, Vector3(0.32 * bulk, 0.18, 0.20 * bulk), Vector3(0, 0.1, 0), body_mat)
	_box(torso, Vector3(0.30 * bulk, 0.16, 0.05), Vector3(0, 0.36, -0.13 * bulk), trim_mat)

	var head := _joint("head", torso, Vector3(0, 0.56, 0))
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.26
	hm.radial_segments = 14
	hm.rings = 7
	_mesh(head, hm, Vector3(0, 0.1, 0), body_mat)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = blade_col
	visor_mat.emission_enabled = true
	visor_mat.emission = blade_col
	visor_mat.emission_energy_multiplier = 2.0
	_box(head, Vector3(0.17, 0.03, 0.06), Vector3(0, 0.12, -0.1), visor_mat)

	for side in [1.0, -1.0]:
		var sfx := "r" if side > 0.0 else "l"
		var sh := _joint("sh_" + sfx, torso, Vector3(0.25 * bulk * side, 0.46, 0))
		_capsule(sh, 0.058 * bulk, 0.32, Vector3(0, -0.15, 0), body_mat)
		_box(sh, Vector3(0.17 * bulk, 0.09, 0.2 * bulk), Vector3(0.02 * side, 0.02, 0), trim_mat)
		var el := _joint("el_" + sfx, sh, Vector3(0, -0.3, 0))
		_capsule(el, 0.05 * bulk, 0.3, Vector3(0, -0.14, 0), body_mat)
		_box(el, Vector3(0.11 * bulk, 0.16, 0.11 * bulk), Vector3(0, -0.14, 0), trim_mat)
		if side > 0.0:
			var hand := Node3D.new()
			hand.position = Vector3(0, -0.3, 0)
			el.add_child(hand)
			_box(hand, Vector3(0.035, 0.035, 0.24), Vector3(0, 0, 0.02), body_mat)
			_box(hand, Vector3(0.2, 0.03, 0.03), Vector3(0, 0, -0.11), trim_mat)
			_box(hand, Vector3(0.05, 0.012, blade_len), Vector3(0, 0, -0.12 - blade_len * 0.5), blade_mat)

		var hip := _joint("hip_" + sfx, pelvis, Vector3(0.11 * bulk * side, -0.04, 0))
		_capsule(hip, 0.078 * bulk, 0.46, Vector3(0, -0.21, 0), body_mat)
		var kn := _joint("kn_" + sfx, hip, Vector3(0, -0.44, 0))
		_capsule(kn, 0.062 * bulk, 0.44, Vector3(0, -0.21, 0), body_mat)
		_box(kn, Vector3(0.12 * bulk, 0.2, 0.13 * bulk), Vector3(0, -0.2, -0.01), trim_mat)
		_box(kn, Vector3(0.1 * bulk, 0.07, 0.24), Vector3(0, -0.44, -0.05), body_mat)

	_cur = IDLE.duplicate()
	_cur["py"] = 0.0
	_from = _cur.duplicate()
	_apply(_cur)


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	joints[n] = j
	return j


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, pos, mat)


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 3
	return _mesh(parent, m, pos, mat)


func set_blade(col: Color, energy: float) -> void:
	blade_mat.emission = col
	blade_mat.emission_energy_multiplier = energy


func flash(col: Color) -> void:
	_flash = 1.0
	_flash_col = col


## Play a clip. `hit` is the moment (seconds) the strike pose lands, `total`
## the whole length. With hold=true the figure stays in the strike pose.
func play(clip: String, hit: float, total: float, hold := false) -> void:
	var c: Dictionary = CLIPS[clip]
	var keys: Array = []
	if c.has("wind"):
		keys.append([hit * 0.55, c["wind"]])
		keys.append([hit * 0.82, c["wind"]])
	keys.append([hit, c["strike"]])
	if c.has("follow"):
		keys.append([hit + (total - hit) * 0.3, c["follow"]])
	if not hold:
		keys.append([maxf(total, hit + 0.05), {}])
	_clip = keys
	_clip_t = 0.0
	_hold = hold
	_from = _cur.duplicate()
	_blend = 0.0
	_blend_len = clampf(float(keys[0][0]), 0.05, 0.3)


func stop() -> void:
	_clip = []
	_hold = false
	_from = _cur.duplicate()
	_blend = 0.0
	_blend_len = 0.14


func _process(delta: float) -> void:
	_time += delta
	_phase += delta * walk_rate * walk_amount
	var target: Dictionary
	if _clip.size() > 0:
		_clip_t += delta
		target = _sample(_clip_t)
		if not _hold and _clip_t >= float(_clip[-1][0]):
			_clip = []
	else:
		target = _locomotion()
	_blend = minf(1.0, _blend + delta / _blend_len)
	_cur = _lp(_from, target, smoothstep(0.0, 1.0, _blend))
	_apply(_cur)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		body_mat.emission_enabled = _flash > 0.0
		body_mat.emission = _flash_col
		body_mat.emission_energy_multiplier = _flash * 2.5


func _sample(t: float) -> Dictionary:
	if t <= float(_clip[0][0]):
		return _clip[0][1]
	for i in range(_clip.size() - 1):
		var t1 := float(_clip[i + 1][0])
		if t <= t1:
			var t0 := float(_clip[i][0])
			var u := smoothstep(0.0, 1.0, (t - t0) / maxf(0.001, t1 - t0))
			return _lp(_clip[i][1], _clip[i + 1][1], u)
	return _clip[-1][1]


func _locomotion() -> Dictionary:
	var p := IDLE.duplicate()
	var w := walk_amount
	var s := sin(_phase)
	var c := cos(_phase)
	var breathe := sin(_time * 2.2) * 1.5
	p["torso"] = IDLE["torso"] + Vector3(breathe + 6.0 * w, 8.0 * s * w, 0)
	p["hip_r"] = IDLE["hip_r"].lerp(Vector3(38.0 * s, 0, 0), w)
	p["hip_l"] = IDLE["hip_l"].lerp(Vector3(-38.0 * s, 0, 0), w)
	p["kn_r"] = IDLE["kn_r"].lerp(Vector3(-12.0 - 38.0 * maxf(0.0, c), 0, 0), w)
	p["kn_l"] = IDLE["kn_l"].lerp(Vector3(-12.0 - 38.0 * maxf(0.0, -c), 0, 0), w)
	p["sh_l"] = IDLE["sh_l"] + Vector3(22.0 * s * w, 0, 0)
	p["py"] = -0.03 * absf(s) * w
	return p


static func _lp(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var o := {}
	for n in JN:
		var va: Vector3 = a.get(n, IDLE[n])
		var vb: Vector3 = b.get(n, IDLE[n])
		o[n] = va.lerp(vb, t)
	o["py"] = lerpf(float(a.get("py", 0.0)), float(b.get("py", 0.0)), t)
	return o


func _apply(p: Dictionary) -> void:
	for n in JN:
		var j: Node3D = joints[n]
		j.rotation_degrees = p[n]
	pelvis.position.y = _pelvis_y + float(p.get("py", 0.0))
