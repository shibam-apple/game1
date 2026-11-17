extends Node3D
## A rigged character driven by motion-captured animation (Mixamo skeleton).
##
## The capture sets the pace: every clip plays at one steady speed, the body
## travels by the distance the performer actually travelled (root motion), and
## movement picks run / strafe / backpedal clips to match the direction of
## travel, so feet stay planted and nothing snaps.

const ANIM_DIR := "res://assets/characters/anims/gs_"
const REF_HIPS_Y := 1.0613
const SPEED_CAP := 1.45

## gameplay clip -> candidate animation files (one is picked at random)
const MAP := {
	"slash_r": ["slash"], "slash_l": ["slash_3"], "slash_c": ["slash_5"],
	"overhead": ["attack"], "finisher": ["slash_4"],
	"thrust": ["slide_attack"], "spin": ["high_spin_attack"], "leap": ["jump_attack"],
	"raise_plant": ["casting"], "power": ["power_up"], "drink": ["spell_cast"],
	"kneel": ["crouching_3"], "guard": ["blocking_2"],
	"hurt": ["impact", "impact_2", "impact_3", "impact_4", "impact_5"],
	"death": ["death"],
}
const LOOPS := ["idle", "run_2", "run", "strafe_3", "strafe_4", "walk", "walk_2", "strafe", "strafe_2", "blocking_2", "crouching_3"]
## clips whose captured travel moves the body
const ROOT := ["slash", "slash_3", "slash_5", "slash_4", "attack", "slide_attack", "high_spin_attack", "jump_attack"]
## locomotion: [clip, natural ground speed in m/s]
const RUN := {"f": ["run_2", 4.45], "b": ["run", 2.70], "l": ["strafe_3", 2.42], "r": ["strafe_4", 3.24]}
const WALK := {"f": ["walk", 1.12], "b": ["walk_2", 1.05], "l": ["strafe", 1.20], "r": ["strafe_2", 1.29]}

static var _anims := {}
static var _strike := {}
static var _root := {}      # file -> [PackedFloat32Array times, PackedVector2Array xz]

var joints := {}
var blade_color := Color(0.45, 0.85, 1.0)
var walk_amount := 0.0      # legacy, unused by the rigs that set move_local
var walk_rate := 9.0
## ground velocity in the character's own frame: x = to its right, y = forward (m/s)
var move_local := Vector2.ZERO
var blade_mat: StandardMaterial3D

var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _torso: Node3D
var _spine := -1
var _overlay: StandardMaterial3D
var _tint_mat: StandardMaterial3D
var _flash := 0.0
var _clip_on := false
var _clip_t := 0.0
var _clip_total := 0.0
var _hold := false
var _file := ""
var _loco := ""
var _last_root := Vector2.ZERO
var _rm := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func build(model_path: String, blade_col: Color, blade_len: float, tint = null) -> void:
	_rng.randomize()
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
	_ap.playback_default_blend_time = 0.18
	var hips := _skel.find_bone("mixamorig_Hips")
	_model.position.y = _skel.get_bone_global_rest(hips).origin.y - REF_HIPS_Y

	var needed: Array = LOOPS.duplicate()
	for k in MAP:
		for f in MAP[k]:
			if not needed.has(f):
				needed.append(f)
	var lib := AnimationLibrary.new()
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
	if tint != null:
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.albedo_color = tint
		_tint_mat.metallic = 0.75
		_tint_mat.roughness = 0.42
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _overlay
		mi.extra_cull_margin = 2.0
		if _tint_mat:
			mi.material_override = _tint_mat

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

	# upright proxy that follows the chest, for wings and the like
	_spine = _skel.find_bone("mixamorig_Spine2")
	_torso = Node3D.new()
	add_child(_torso)
	joints["torso"] = _torso
	_ap.play("idle")
	_loco = "idle"


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
	# Record where the performer travelled, then pin the hips in place; the
	# game body is moved by that recorded travel instead.
	var times := PackedFloat32Array()
	var xz := PackedVector2Array()
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)).ends_with("mixamorig_Hips"):
			var first: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var v: Vector3 = a.track_get_key_value(i, k)
				times.append(a.track_get_key_time(i, k))
				xz.append(Vector2(v.x - first.x, v.z - first.z))
				a.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))
	_root[f] = [times, xz]
	a.loop_mode = Animation.LOOP_LINEAR if LOOPS.has(f) else Animation.LOOP_NONE
	_anims[f] = a
	return a


static func _root_at(f: String, t: float) -> Vector2:
	var times: PackedFloat32Array = _root[f][0]
	var xz: PackedVector2Array = _root[f][1]
	if times.is_empty():
		return Vector2.ZERO
	var i := times.bsearch(t)
	if i <= 0:
		return xz[0]
	if i >= times.size():
		return xz[times.size() - 1]
	var u := (t - times[i - 1]) / maxf(0.0001, times[i] - times[i - 1])
	return xz[i - 1].lerp(xz[i], u)


## The moment the sword hand moves fastest is treated as the strike.
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
		_ap.advance(0.0)
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


func strike_time(clip: String) -> float:
	return float(_strike[MAP[clip][0]])


## How long after starting `clip` its blow lands, when up to `max_lead`
## seconds of the wind-up are shown at SPEED_CAP.
func lead(clip: String, max_lead: float) -> float:
	return minf(strike_time(clip), max_lead) / SPEED_CAP


func set_detail(_tex: Texture2D, _tiling: float) -> void:
	pass


func set_plating(albedo: Texture2D, normal: Texture2D, orm: Texture2D, tiling: float) -> void:
	if _tint_mat == null:
		return
	_tint_mat.albedo_texture = albedo
	_tint_mat.normal_enabled = true
	_tint_mat.normal_texture = normal
	_tint_mat.roughness_texture = orm
	_tint_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	_tint_mat.roughness = 1.0
	_tint_mat.metallic = 0.6
	_tint_mat.uv1_triplanar = true
	_tint_mat.uv1_scale = Vector3(tiling, tiling, tiling)


func set_blade(col: Color, energy: float) -> void:
	blade_mat.emission = col
	blade_mat.emission_energy_multiplier = energy


func flash(col: Color) -> void:
	_flash = 1.0
	_overlay.albedo_color = Color(col.r, col.g, col.b, 0.0)


## Play a gameplay clip so its blow lands `hit` seconds from now. The whole
## clip runs at one steady speed; `total` is when control returns to movement.
func play(clip: String, hit: float, total: float, hold := false) -> void:
	var files: Array = MAP.get(clip, MAP["hurt"])
	var f: String = files[_rng.randi() % files.size()]
	var a: Animation = _anims[f]
	var st: float = _strike[f]
	var start := 0.0
	var speed := 1.0
	if hold or LOOPS.has(f) or clip in ["hurt", "death", "drink"]:
		speed = 1.0
	else:
		start = maxf(0.0, st - hit * SPEED_CAP)
		speed = clampf((st - start) / maxf(hit, 0.03), 0.5, SPEED_CAP)
	_file = f
	_ap.play(f, 0.14, speed)
	if start > 0.0:
		_ap.seek(start, false)
	_last_root = _root_at(f, start)
	_rm = Vector3.ZERO
	_clip_on = true
	_clip_t = 0.0
	_clip_total = total
	_hold = hold or clip == "death"


## Quick evasive step in a direction given in the character's own frame.
func play_dodge(local_dir: Vector2, dur: float) -> void:
	var f := "run_2"
	if absf(local_dir.x) > absf(local_dir.y):
		f = "strafe_4" if local_dir.x > 0.0 else "strafe_3"
	elif local_dir.y < 0.0:
		f = "run"
	_file = f
	_ap.play(f, 0.07, 2.0)
	_clip_on = true
	_clip_t = 0.0
	_clip_total = dur
	_hold = false
	_rm = Vector3.ZERO
	_last_root = Vector2.ZERO


func stop() -> void:
	_clip_on = false
	_hold = false
	_loco = ""


## Travel captured in the clip since the last call, in the character's frame.
func take_root_motion() -> Vector3:
	var r := _rm
	_rm = Vector3.ZERO
	return r


func _locomotion() -> void:
	var sp := move_local.length()
	var want := "idle"
	var rate := 1.0
	if sp > 0.25:
		var set_: Dictionary = RUN if sp > 2.0 else WALK
		var key := "f"
		# stick with the current direction unless another clearly dominates
		if absf(move_local.x) > absf(move_local.y) * 1.25:
			key = "r" if move_local.x > 0.0 else "l"
		elif move_local.y < 0.0:
			key = "b"
		want = set_[key][0]
		rate = clampf(sp / float(set_[key][1]), 0.6, 1.5)
	if want != _loco:
		_ap.play(want, 0.22)
		_loco = want
	_ap.speed_scale = rate


func _process(delta: float) -> void:
	if _clip_on:
		_clip_t += delta
		if ROOT.has(_file) and _ap.current_animation == _file:
			var cur := _root_at(_file, _ap.current_animation_position)
			var d := cur - _last_root
			_last_root = cur
			# model space (+Z forward, +X left) -> character frame (-Z forward, +X right)
			_rm += Vector3(-d.x, 0, -d.y) * scale.x
		if not _hold and (_clip_t >= _clip_total or not _ap.is_playing()):
			_clip_on = false
			_loco = ""
			_locomotion()
	else:
		_locomotion()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_overlay.albedo_color.a = _flash * 0.6
	if _spine >= 0:
		var p := _skel.get_bone_global_pose(_spine).origin
		_torso.position = Vector3(-p.x, p.y + _model.position.y - 0.36, -p.z)
