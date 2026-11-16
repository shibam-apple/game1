extends Node3D
## A rigged character driven by motion-captured animation (Mixamo skeleton).
## Same interface as the old placeholder rig: play(), stop(), walk_amount,
## set_blade(), flash(). Gameplay code does not know which one it is using.

const ANIM_DIR := "res://assets/characters/anims/"
const REF_HIPS_Y := 1.0613

## gameplay clip -> animation file
const MAP := {
	"slash_r": "slash1", "slash_l": "slash3", "slash_c": "slash4", "overhead": "attack",
	"thrust": "slide_attack", "spin": "spin", "leap": "jump_attack",
	"raise_plant": "casting", "kneel": "crouch", "hurt": "impact", "death": "death",
	"guard": "block", "crouch": "jump", "drink": "spell", "power": "power_up",
}
const LOOPS := ["idle", "run"]

static var _anims := {}     # file -> Animation (shared by every character)
static var _strike := {}    # file -> seconds at which the weapon hand moves fastest

var joints := {}
var blade_color := Color(0.45, 0.85, 1.0)
var walk_amount := 0.0
var walk_rate := 9.0
var blade_mat: StandardMaterial3D

var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _torso: Node3D
var _spine := -1
var _overlay: StandardMaterial3D
var _flash := 0.0
var _clip_on := false
var _clip_t := 0.0
var _clip_total := 0.0
var _hit_at := 0.0
var _post_speed := 1.0
var _hold := false
var _past := false
var _cur_file := ""


func build(model_path: String, blade_col: Color, blade_len: float, tint = null) -> void:
	blade_color = blade_col
	_pivot = Node3D.new()
	_pivot.rotation.y = PI   # Mixamo faces +Z, the game faces -Z
	add_child(_pivot)
	_model = load(model_path).instantiate()
	_pivot.add_child(_model)
	_skel = _model.find_child("Skeleton3D", true, false)
	var old: Node = _model.find_child("AnimationPlayer", true, false)
	if old:
		old.free()
	_ap = AnimationPlayer.new()
	_model.add_child(_ap)
	var hips := _skel.find_bone("mixamorig_Hips")
	_model.position.y = _skel.get_bone_global_rest(hips).origin.y - REF_HIPS_Y

	var lib := AnimationLibrary.new()
	var needed := LOOPS.duplicate()
	for k in MAP:
		if not needed.has(MAP[k]):
			needed.append(MAP[k])
	for f in needed:
		lib.add_animation(f, _get_anim(f))
	_ap.add_animation_library("", lib)
	for f in needed:
		if not _strike.has(f):
			_strike[f] = _find_strike(f)

	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 1, 1, 0)
	var tint_mat: StandardMaterial3D = null
	if tint != null:
		tint_mat = StandardMaterial3D.new()
		tint_mat.albedo_color = tint
		tint_mat.metallic = 0.75
		tint_mat.roughness = 0.42
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _overlay
		mi.extra_cull_margin = 2.0
		if tint_mat:
			mi.material_override = tint_mat

	# sword in the right hand
	blade_mat = StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.9, 0.95, 1.0)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.15
	blade_mat.emission_enabled = true
	set_blade(blade_col, 1.6)
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.08, 0.08, 0.09)
	grip_mat.metallic = 0.8
	grip_mat.roughness = 0.4
	var att := BoneAttachment3D.new()
	_skel.add_child(att)
	att.bone_name = "mixamorig_RightHand"
	var sword := Node3D.new()
	att.add_child(sword)
	sword.position = Vector3(0, 0.09, 0.03)
	sword.rotation_degrees = Vector3(0, 90, 0)
	_box(sword, Vector3(0.035, 0.035, 0.34), Vector3(0, 0, 0.02), grip_mat)
	_box(sword, Vector3(0.24, 0.04, 0.04), Vector3(0, 0, 0.2), grip_mat)
	_box(sword, Vector3(0.055, 0.014, blade_len), Vector3(0, 0, 0.22 + blade_len * 0.5), blade_mat)
	joints["sword"] = sword

	# upright proxy that follows the chest, for capes, wings and the like
	_spine = _skel.find_bone("mixamorig_Spine2")
	_torso = Node3D.new()
	add_child(_torso)
	joints["torso"] = _torso
	_loco(0.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


static func _get_anim(f: String) -> Animation:
	if _anims.has(f):
		return _anims[f]
	var scene: Node = load(ANIM_DIR + f + ".fbx").instantiate()
	var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate()
	scene.free()
	# Gameplay moves the body, so pin the hips in place horizontally.
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)).ends_with("mixamorig_Hips"):
			var first: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))
	a.loop_mode = Animation.LOOP_LINEAR if LOOPS.has(f) else Animation.LOOP_NONE
	_anims[f] = a
	return a


## The moment the sword hand is moving fastest is treated as the strike.
func _find_strike(f: String) -> float:
	var a: Animation = _anims[f]
	if LOOPS.has(f):
		return 0.0
	var hand := _skel.find_bone("mixamorig_RightHand")
	var best := a.length * 0.4
	var best_v := 0.0
	var prev := Vector3.ZERO
	var steps := int(a.length / 0.033)
	_ap.play(f)
	for i in steps:
		_ap.seek(i * 0.033, true)
		_skel.force_update_all_bone_transforms()
		var p := _skel.get_bone_global_pose(hand).origin
		if i > 2 and i < steps - 2:
			var v := p.distance_to(prev)
			if v > best_v:
				best_v = v
				best = i * 0.033
		prev = p
	_ap.stop()
	return best


func set_detail(_tex: Texture2D, _tiling: float) -> void:
	pass


func set_blade(col: Color, energy: float) -> void:
	blade_mat.emission = col
	blade_mat.emission_energy_multiplier = energy


func flash(col: Color) -> void:
	_flash = 1.0
	_overlay.albedo_color = Color(col.r, col.g, col.b, 0.0)


func play(clip: String, hit: float, total: float, hold := false) -> void:
	var f: String = MAP.get(clip, "impact")
	var a: Animation = _anims[f]
	var st: float = _strike[f]
	if clip == "death":
		st = a.length - 0.05
	elif hold or clip in ["hurt", "crouch", "drink", "raise_plant", "power"]:
		st = minf(a.length * 0.45, maxf(hit, 0.15))
	var start := maxf(0.0, st - hit * 2.2)
	_cur_file = f
	_ap.play(f, 0.09)
	_ap.seek(start, true)
	_ap.speed_scale = (st - start) / maxf(hit, 0.03)
	_post_speed = clampf((a.length - st) / maxf(total - hit, 0.05), 0.7, 2.2)
	_hit_at = st
	_clip_on = true
	_clip_t = 0.0
	_clip_total = total
	_hold = hold
	_past = false


func stop() -> void:
	_clip_on = false
	_loco(0.16)


func _loco(blend: float) -> void:
	var want := "run" if walk_amount > 0.3 else "idle"
	if _ap.current_animation != want:
		_ap.play(want, blend)
	_ap.speed_scale = clampf(0.6 + walk_amount * 0.6, 0.6, 1.3) if want == "run" else 1.0
	_cur_file = want


func _process(delta: float) -> void:
	if _clip_on:
		_clip_t += delta
		if not _past and _ap.current_animation_position >= _hit_at:
			_past = true
			_ap.speed_scale = 0.0 if _hold else _post_speed
		if not _hold and (_clip_t >= _clip_total or not _ap.is_playing()):
			_clip_on = false
			_loco(0.18)
	else:
		_loco(0.18)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_overlay.albedo_color.a = _flash * 0.6
	if _spine >= 0:
		var p := _skel.get_bone_global_pose(_spine).origin
		# model space -> this node's space (pivot is turned 180 degrees)
		_torso.position = Vector3(-p.x, p.y + _model.position.y - 0.36, -p.z)
