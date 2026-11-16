extends Node3D
## A towering mech built from a single static model. It cannot bend its limbs,
## so it acts with weight instead: a slow lean into each command, a reactor
## flare, and a settle back. Same play()/stop() calls as the animated rigs.

var _model: Node3D
var _light: OmniLight3D
var _t := 0.0
var _lean := 0.0
var _lean_target := 0.0
var _flare := 0.0
var _down := false
var joints := {}


func build(path: String, height: float, glow: Color) -> void:
	_model = load(path).instantiate()
	add_child(_model)
	# measure, then scale to the wanted height and stand it on the ground
	var box := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
		mi.extra_cull_margin = 4.0
	var s := height / maxf(0.01, box.size.y)
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	_light = OmniLight3D.new()
	_light.light_color = glow
	_light.light_energy = 3.0
	_light.omni_range = height * 0.9
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0, height * 0.62, -height * 0.22)


func play(clip: String, hit: float, _total: float, hold := false) -> void:
	_lean_target = 0.16 if clip != "kneel" else 0.3
	_flare = 1.0
	_down = hold
	if not hold:
		get_tree().create_timer(maxf(0.2, hit) + 0.5).timeout.connect(func(): _lean_target = 0.0)


func stop() -> void:
	_lean_target = 0.0
	_down = false


func _process(delta: float) -> void:
	_t += delta
	_lean = lerpf(_lean, _lean_target, minf(1.0, delta * 2.2))
	rotation.x = -_lean + sin(_t * 0.5) * 0.008
	_flare = maxf(0.0, _flare - delta * 0.8)
	_light.light_energy = (0.6 if _down else 3.0) + _flare * 9.0 + sin(_t * 2.0) * 0.4
