extends Node3D
## Sand Lancer - proof-of-concept duel. Builds the whole scene in code:
## world, lighting, fighters, mechs, camera, effects and game flow.

const Mocap := preload("res://scripts/mocap.gd")
const PlayerS := preload("res://scripts/player.gd")
const BossS := preload("res://scripts/boss.gd")
const HudS := preload("res://scripts/hud.gd")
const InputS := preload("res://scripts/gesture_input.gd")
const SfxS := preload("res://scripts/sfx.gd")

enum G { TITLE, HOWTO, INTRO, FIGHT, DEAD, WIN }
const ARENA_R := 15.0

var gstate: int = G.TITLE
var quality := 1
var player: CharacterBody3D
var boss: CharacterBody3D
var cam: Camera3D
var hud: Control
var input: Node
var sfx: Node
var env: Environment
var sun: DirectionalLight3D
var bounce: DirectionalLight3D
var dust: CPUParticles3D
var lancer: Node3D
var garuda: Node3D
var fight_time := 0.0
var hits_taken := 0

var _state_t := 0.0
var _shake := 0.0
var _hit_until := 0
var _slow_until := 0
var _slow_scale := 1.0
var _arc_mesh: ArrayMesh
var _bolts: Array = []
var _strikes: Array = []
var _said := {}
var _pending: Array = []
var _rng := RandomNumberGenerator.new()
var _autotest := false
var _bot_t := 0.0
var _shot_at := -1.0
var _shot_path := ""
var _elapsed := 0.0
var _test_hp := 0.0
var _closeup := false
var sword_rot := Vector3(-999, 0, 0)
var combo := 0
var best_combo := 0
var combo_t := 0.0
var _fov_kick := 0.0

const GRADES := ["D", "C", "B", "A", "S"]


func _ready() -> void:
	_rng.randomize()
	var args := OS.get_cmdline_user_args()
	_autotest = "--autotest" in args
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		if a.begins_with("--shot-at="):
			_shot_at = float(a.substr(10))
	_closeup = "--closeup" in args
	for a in args:
		if a.begins_with("--sword="):
			var parts := a.substr(8).split(",")
			sword_rot = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	_load_settings()
	_arc_mesh = _make_arc_mesh()
	_build_world()

	sfx = SfxS.new()
	add_child(sfx)
	player = PlayerS.new()
	boss = BossS.new()
	player.game = self
	boss.game = self
	player.boss = boss
	boss.player = player
	add_child(player)
	add_child(boss)
	if sword_rot.x > -900.0:
		player.vis.joints["sword"].rotation_degrees = sword_rot
	player.reset(Vector3(0, 0, 8))
	boss.reset(Vector3(0, 0, -5))

	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 900.0
	add_child(cam)
	cam.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudS.new()
	hud.game = self
	layer.add_child(hud)

	input = InputS.new()
	add_child(input)
	input.tap.connect(_on_tap)
	input.flick.connect(func(d): if gstate == G.FIGHT: player.on_flick(d))
	input.guard_changed.connect(func(on): player.on_guard(on and gstate == G.FIGHT))
	input.dual_flick.connect(func(up): if gstate == G.FIGHT: player.on_ability(0 if up else 1))
	input.dual_hold.connect(func(): if gstate == G.FIGHT: player.on_limit())
	input.flask.connect(func(): if gstate == G.FIGHT: player.on_flask())

	_apply_quality()
	if "--hp=" in " ".join(args):
		for a in args:
			if a.begins_with("--hp="):
				_test_hp = float(a.substr(5))
	if _autotest or (_shot_path != "" and not ("--title" in args)):
		_start_fight()


# ---- world -------------------------------------------------------------------

func _mat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _glow_mat(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _fx_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.disable_fog = true
	return m


func _add_mesh(parent: Node, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	return mi


func _build_world() -> void:
	# Sky: dusty amber horizon under a cold, pale zenith.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.42, 0.52)
	sky_mat.sky_horizon_color = Color(0.96, 0.7, 0.44)
	sky_mat.sky_curve = 0.09
	sky_mat.ground_horizon_color = Color(0.96, 0.7, 0.44)
	sky_mat.ground_bottom_color = Color(0.5, 0.32, 0.2)
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.62, 0.42)
	env.fog_density = 0.013
	env.fog_sun_scatter = 0.35
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.86
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low sun behind the far side of the arena: figures read as rim-lit silhouettes.
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 1.75
	sun.rotation_degrees = Vector3(-24, 150, 0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_fade_start = 0.7
	sun.shadow_blur = 1.5
	add_child(sun)
	# Fake global illumination: warm light bouncing up off the sand.
	bounce = DirectionalLight3D.new()
	bounce.light_color = Color(1.0, 0.62, 0.38)
	bounce.light_energy = 0.4
	bounce.rotation_degrees = Vector3(62, -30, 0)
	bounce.shadow_enabled = false
	bounce.light_specular = 0.0
	add_child(bounce)

	# Sand: rolling dune terrain with a procedural rippled-sand shader.
	var sand := ShaderMaterial.new()
	sand.shader = load("res://shaders/sand.gdshader")
	sand.set_shader_parameter("grain_n", load("res://assets/textures/sand_normal.jpg"))
	sand.set_shader_parameter("drift_n", _noise_tex(0.012, 4, true, 5))
	sand.set_shader_parameter("vary", _noise_tex(0.02, 4, false, 9))
	var terrain := MeshInstance3D.new()
	terrain.mesh = _make_terrain()
	terrain.material_override = sand
	add_child(terrain)

	# Arena edge: weathered rock outcrops, kept low so the mechs stay visible.
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.82, 0.66, 0.56)
	rock.albedo_texture = load("res://assets/textures/rock_albedo.jpg")
	rock.normal_enabled = true
	rock.normal_texture = load("res://assets/textures/rock_normal.png")
	rock.normal_scale = 1.4
	rock.roughness_texture = load("res://assets/textures/rock_rough.jpg")
	rock.ao_enabled = true
	rock.ao_texture = load("res://assets/textures/rock_ao.jpg")
	rock.uv1_triplanar = true
	rock.uv1_scale = Vector3(0.22, 0.22, 0.22)
	var rock_meshes: Array = []
	for i in 4:
		rock_meshes.append(_make_rock(100 + i))
	for i in 26:
		var ang := TAU * i / 26.0 + r.randf_range(-0.09, 0.09)
		var d := ARENA_R + r.randf_range(1.8, 5.5)
		var tall := r.randf() < 0.22
		var sc := Vector3(r.randf_range(1.0, 2.4), r.randf_range(2.2, 4.6) if tall else r.randf_range(0.6, 1.4), r.randf_range(1.0, 2.2))
		_add_mesh(self, rock_meshes[i % 4], Vector3(cos(ang) * d, sc.y * 0.25, sin(ang) * d), rock, Vector3(r.randf_range(-12, 12), r.randf() * 360.0, r.randf_range(-12, 12)), sc)
	# A few far mesas for depth
	var far_rock: StandardMaterial3D = rock.duplicate()
	far_rock.uv1_scale = Vector3(0.02, 0.02, 0.02)
	for i in 7:
		var ang := r.randf() * TAU
		var d := r.randf_range(120.0, 260.0)
		var w := r.randf_range(18.0, 40.0)
		_add_mesh(self, rock_meshes[i % 4], Vector3(cos(ang) * d, 6.0, sin(ang) * d), far_rock, Vector3(0, r.randf() * 360.0, 0), Vector3(w, r.randf_range(14.0, 30.0), w * 0.8))

	# The Broken Ring on the horizon
	var ring := TorusMesh.new()
	ring.inner_radius = 150.0
	ring.outer_radius = 172.0
	ring.rings = 48
	ring.ring_segments = 8
	_add_mesh(self, ring, Vector3(-190, -30, -330), _mat(Color(0.22, 0.2, 0.2), 0.6, 0.5), Vector3(82, 24, 8))
	# Pale moon
	var moon := SphereMesh.new()
	moon.radius = 95.0
	moon.height = 190.0
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.86, 0.74, 0.62)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color.a = 0.55
	mm.disable_fog = true
	_add_mesh(self, moon, Vector3(170, 190, -560), mm)

	# Gantry towers behind the enemy mech
	var steel := _mat(Color(0.16, 0.14, 0.14), 0.6, 0.6)
	for i in 5:
		var tm := BoxMesh.new()
		tm.size = Vector3(r.randf_range(3, 6), r.randf_range(14, 34), r.randf_range(3, 6))
		var tp := Vector3(24.0 + i * 9.0 + r.randf_range(-2, 2), tm.size.y * 0.5, -52.0 - r.randf_range(0, 20))
		_add_mesh(self, tm, tp, steel)
		var lm := BoxMesh.new()
		lm.size = Vector3(0.5, 0.3, 0.3)
		_add_mesh(self, lm, tp + Vector3(0, tm.size.y * 0.3, tm.size.z * 0.5 + 0.2), _glow_mat(Color(1.0, 0.7, 0.35), 4.0))

	# The two machines watch their pilots settle it on foot.
	lancer = _build_mech("res://assets/characters/ran/character.fbx", Color(0.78, 0.74, 0.66), Color(0.35, 0.62, 1.0), false)
	lancer.position = Vector3(-13, 0, 33)
	lancer.rotation.y = 0.35
	garuda = _build_mech("res://assets/characters/kite/character.fbx", Color(0.2, 0.08, 0.07), Color(1.0, 0.35, 0.15), true)
	garuda.position = Vector3(21, 0, -38)
	garuda.rotation.y = PI - 0.3

	# Blowing dust
	dust = CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(1.0, 0.85, 0.65, 0.5)
	qm.material = dm
	dust.mesh = qm
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(22, 3, 22)
	dust.direction = Vector3(1, 0.05, 0.3)
	dust.spread = 12.0
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 7.0
	dust.gravity = Vector3.ZERO
	dust.lifetime = 5.0
	dust.preprocess = 5.0
	dust.position.y = 2.5
	add_child(dust)


func _noise_tex(freq: float, octaves: int, normal: bool, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	t.bump_strength = 6.0
	return t


## Flat duelling ground in the middle, dunes rising around it.
func _make_terrain() -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = 4
	n.frequency = 0.0075
	n.fractal_octaves = 3
	var size := 700.0
	var res := 150
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs: Array = []
	for z in res + 1:
		for x in res + 1:
			# denser grid near the centre
			var fx := float(x) / res * 2.0 - 1.0
			var fz := float(z) / res * 2.0 - 1.0
			var px := signf(fx) * pow(absf(fx), 1.7) * size * 0.5
			var pz := signf(fz) * pow(absf(fz), 1.7) * size * 0.5
			var rad := Vector2(px, pz).length()
			var ridge := 1.0 - absf(n.get_noise_2d(px, pz))
			var h := ridge * ridge * 24.0 * smoothstep(24.0, 120.0, rad)
			h += n.get_noise_2d(px * 3.0 + 50.0, pz * 3.0) * 1.4 * smoothstep(20.0, 60.0, rad)
			hs.append(Vector3(px, h - 0.02, pz))
	for z in res:
		for x in res:
			var i0 := z * (res + 1) + x
			var quad := [i0, i0 + 1, i0 + res + 2, i0, i0 + res + 2, i0 + res + 1]
			for k in quad:
				var v: Vector3 = hs[k]
				st.set_uv(Vector2(v.x, v.z) * 0.1)
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Lumpy boulder: a sphere pushed around by noise.
func _make_rock(seed_v: int) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.9
	n.fractal_octaves = 3
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v := verts[i]
		var dir := v.normalized()
		var k := 1.0 + n.get_noise_3dv(dir * 1.3) * 0.55
		# flatten into strata so it reads as rock, not a blob
		var p := dir * k
		p.y = roundf(p.y * 4.0) / 4.0 * 0.7 + p.y * 0.3
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func _build_mech(model: String, body: Color, glow: Color, winged: bool) -> Node3D:
	var m: Node3D = Mocap.new()
	add_child(m)
	m.build(model, glow, 1.6, body)
	m.scale = Vector3.ONE * 10.0
	var torso: Node3D = m.joints["torso"]
	var dark := _mat(body.darkened(0.5), 0.45, 0.7)
	var core := BoxMesh.new()
	core.size = Vector3(0.16, 0.1, 0.04)
	_add_mesh(torso, core, Vector3(0, 0.3, -0.2), _glow_mat(glow, 4.0))
	var pack := BoxMesh.new()
	pack.size = Vector3(0.44, 0.44, 0.2)
	_add_mesh(torso, pack, Vector3(0, 0.36, 0.2), dark)
	for side in [1.0, -1.0]:
		var pad := BoxMesh.new()
		pad.size = Vector3(0.3, 0.16, 0.34)
		_add_mesh(torso, pad, Vector3(0.3 * side, 0.6, 0), dark, Vector3(0, 0, -14.0 * side))
		if winged:
			var wm := BoxMesh.new()
			wm.size = Vector3(0.12, 1.25, 0.5)
			_add_mesh(torso, wm, Vector3(0.5 * side, 0.6, 0.3), dark, Vector3(-28, 0, -32.0 * side))
	if not winged:
		var lm := BoxMesh.new()
		lm.size = Vector3(0.05, 1.9, 0.07)
		_add_mesh(torso, lm, Vector3(0.12, 0.7, 0.34), dark, Vector3(0, 0, -14))
	return m


func _make_arc_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var a0 := deg_to_rad(-75.0 + 150.0 * i / n)
		var a1 := deg_to_rad(-75.0 + 150.0 * (i + 1) / n)
		var w0 := sin(PI * i / n)
		var w1 := sin(PI * (i + 1) / n)
		var o0 := Vector3(sin(a0), 0, -cos(a0))
		var o1 := Vector3(sin(a1), 0, -cos(a1))
		var i0 := o0 * (1.0 - 0.42 * w0)
		var i1 := o1 * (1.0 - 0.42 * w1)
		for v in [o0, o1, i1, o0, i1, i0]:
			st.add_vertex(v)
	return st.commit()


# ---- settings ----------------------------------------------------------------

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		quality = clampi(int(cf.get_value("gfx", "quality", 1)), 0, 2)


func _apply_quality() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.6, 0.8, 1.0][quality]
	vp.msaa_3d = Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED
	sun.shadow_enabled = quality >= 1
	env.glow_enabled = quality >= 1
	bounce.visible = true
	dust.amount = [50, 110, 200][quality]
	Engine.max_fps = 60
	var cf := ConfigFile.new()
	cf.set_value("gfx", "quality", quality)
	cf.save("user://settings.cfg")


# ---- flow --------------------------------------------------------------------

func _on_tap(pos: Vector2) -> void:
	match gstate:
		G.TITLE:
			sfx.play("ui")
			if hud.quality_rect.has_point(pos):
				quality = (quality + 1) % 3
				_apply_quality()
			else:
				_set_g(G.HOWTO)
		G.HOWTO:
			sfx.play("ui")
			_start_fight()
		G.FIGHT:
			if hud.flask_rect.has_point(pos):
				player.on_flask()
			elif hud.ability_rects[0].has_point(pos):
				player.on_ability(0)
			elif hud.ability_rects[1].has_point(pos):
				player.on_ability(1)
			else:
				player.on_tap()
		G.DEAD, G.WIN:
			if _state_t > 1.2:
				_start_fight()


func _set_g(s: int) -> void:
	gstate = s
	_state_t = 0.0


func _start_fight() -> void:
	for b in _bolts:
		b["node"].queue_free()
	_bolts.clear()
	for s in _strikes:
		s["node"].queue_free()
	_strikes.clear()
	_pending.clear()
	_hit_until = 0
	_slow_until = 0
	Engine.time_scale = 1.0
	player.reset(Vector3(0, 0, 8))
	boss.reset(Vector3(0, 0, -5))
	garuda.stop()
	lancer.stop()
	input.reset()
	fight_time = 0.0
	hits_taken = 0
	combo = 0
	best_combo = 0
	hud._boss_lag = 1.0
	if _test_hp > 0.0:
		boss.hp = _test_hp
	_set_g(G.INTRO)


## Style grade from the running hit chain. Higher grades fill the link gauge faster.
func grade() -> int:
	if combo >= 30: return 4
	if combo >= 20: return 3
	if combo >= 12: return 2
	if combo >= 5: return 1
	return 0


func style_mult() -> float:
	return 1.0 + 0.15 * grade()


func add_combo(n: int) -> void:
	combo += n
	best_combo = maxi(best_combo, combo)
	combo_t = 3.2


func buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)


func rank() -> String:
	if hits_taken <= 2 and best_combo >= 20:
		return "S"
	if hits_taken <= 5:
		return "A"
	if hits_taken <= 9:
		return "B"
	return "C"


func _once(key: String, who: String, text: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	hud.say(who, text)


func _after(delay: float, fn: Callable) -> void:
	_pending.append({"t": delay, "fn": fn})


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _hit_until:
		Engine.time_scale = 0.05
	elif now < _slow_until:
		Engine.time_scale = _slow_scale
	else:
		Engine.time_scale = 1.0
	_state_t += delta
	player.move_input = input.move if gstate == G.FIGHT else Vector2.ZERO

	var i := 0
	while i < _pending.size():
		_pending[i]["t"] -= delta
		if _pending[i]["t"] <= 0.0:
			var fn: Callable = _pending[i]["fn"]
			_pending.remove_at(i)
			fn.call()
		else:
			i += 1

	match gstate:
		G.INTRO:
			if _state_t > 2.2:
				boss.active = true
				boss._hover()
				_set_g(G.FIGHT)
				hud.say("LANCER", "He's airborne. Swipe up to reach him.")
		G.FIGHT:
			fight_time += delta
			if combo > 0:
				combo_t -= delta
				if combo_t <= 0.0:
					combo = 0
			if player.hp < 35.0 and player.flasks > 0:
				_once("low", "LANCER", "Vitals critical. Tap a cell, bottom left.")
			if _autotest:
				_bot(delta)
	_update_camera(delta)
	dust.position = Vector3(player.global_position.x, 2.5, player.global_position.z)

	_elapsed += delta
	if _shot_path != "" and _shot_at >= 0.0 and _elapsed >= _shot_at:
		_shot_at = -1.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot_path)
		get_tree().quit()


func _update_camera(delta: float) -> void:
	var k := minf(1.0, 6.0 * delta / maxf(0.05, Engine.time_scale))
	var pos: Vector3
	var look: Vector3
	if gstate == G.TITLE or gstate == G.HOWTO:
		var a := Time.get_ticks_msec() / 1000.0 * 0.12
		pos = Vector3(sin(a) * 4.0 + 3.0, 1.3, 14.5)
		look = Vector3(1.5, 2.6, 0)
		k = 1.0
	else:
		var pp := player.global_position
		var d := pp - boss.global_position
		d.y = 0.0
		if d.length() < 0.3:
			d = cam.global_position - pp
			d.y = 0.0
		d = d.normalized()
		var right := Vector3(d.z, 0, -d.x)
		var gap := (pp - boss.global_position).length()
		pos = pp + d * (5.6 + clampf(gap * 0.14, 0.0, 1.8)) + Vector3(0, 2.5 + player.vis.position.y * 0.7, 0) + right * 1.9
		look = pp.lerp(boss.global_position, 0.42) + Vector3(0, 1.3 + boss.alt * 0.42, 0)
		if gstate == G.INTRO:
			var u := clampf(_state_t / 2.2, 0.0, 1.0)
			pos = pos.lerp(boss.global_position + Vector3(2.5, boss.alt + 1.0, 5.0), 1.0 - smoothstep(0.0, 1.0, u))
			look = look.lerp(boss.chest(), 1.0 - u)
			k = 1.0
	_fov_kick = maxf(0.0, _fov_kick - delta * 18.0 / maxf(0.05, Engine.time_scale))
	cam.fov = 58.0 + _fov_kick
	cam.global_position = cam.global_position.lerp(pos, k)
	var target := look
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2 / maxf(0.05, Engine.time_scale))
		target += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * 0.5
	if _closeup:
		cam.global_position = player.global_position + Vector3(1.6, 1.5, -2.8)
		target = player.global_position + Vector3(0, 1.1, 0)
	if cam.global_position.distance_to(target) > 0.1:
		cam.look_at(target, Vector3.UP)


func screen_dir_to_world(v: Vector2) -> Vector3:
	var b := cam.global_transform.basis
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var fwd := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var w := right * v.x + fwd * -v.y
	return w.normalized() if w.length() > 0.001 else Vector3.ZERO


# ---- projectiles and mech strikes ---------------------------------------------

func spawn_bolt(from: Vector3, dmg: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var n := _add_mesh(self, sm, from, _glow_mat(Color(1.0, 0.62, 0.15), 6.0))
	var to := player.global_position + Vector3(0, 1.1, 0)
	_bolts.append({"node": n, "vel": (to - from).normalized() * 15.0, "mine": false, "dmg": dmg, "life": 4.0})


func spawn_strike(radius: float, delay: float, dmg: float) -> void:
	garuda.play("raise_plant", delay, delay + 0.8)
	var root := Node3D.new()
	add_child(root)
	root.global_position = player.global_position
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	var outer := _add_mesh(root, disc, Vector3(0, 0.04, 0), _fx_mat(Color(1.0, 0.1, 0.05, 0.22)), Vector3.ZERO, Vector3(radius, 1, radius))
	var inner := _add_mesh(root, disc, Vector3(0, 0.06, 0), _fx_mat(Color(1.0, 0.25, 0.1, 0.4)), Vector3.ZERO, Vector3(0.01, 1, 0.01))
	_strikes.append({"node": root, "inner": inner, "outer": outer, "t": 0.0, "delay": delay, "radius": radius, "dmg": dmg})


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _bolts.size():
		var b: Dictionary = _bolts[i]
		var n: MeshInstance3D = b["node"]
		b["life"] -= delta
		var gone: bool = b["life"] <= 0.0
		if not gone:
			if b["mine"]:
				b["vel"] = (boss.chest() - n.global_position).normalized() * 30.0
				if n.global_position.distance_to(boss.chest()) < 1.2:
					boss.take_hit(15.0, 32.0)
					gone = true
			else:
				var tp := player.global_position + Vector3(0, 1.1 + player.vis.position.y, 0)
				var want := (tp - n.global_position).normalized() * 15.0
				b["vel"] = (b["vel"] as Vector3).lerp(want, minf(1.0, 1.6 * delta))
				if n.global_position.distance_to(tp) < 0.95:
					var res: String = player.receive_hit(b["dmg"], false, n.global_position)
					if res == "parried":
						b["mine"] = true
						b["life"] = 3.0
						n.material_override = _glow_mat(Color(0.4, 0.75, 1.0), 6.0)
					elif res != "dodged":
						gone = true
			n.global_position += (b["vel"] as Vector3) * delta
		if gone:
			n.queue_free()
			_bolts.remove_at(i)
		else:
			i += 1

	i = 0
	while i < _strikes.size():
		var s: Dictionary = _strikes[i]
		var root: Node3D = s["node"]
		s["t"] += delta
		var u: float = s["t"] / s["delay"]
		if u < 0.45:
			root.global_position = root.global_position.lerp(player.global_position, minf(1.0, 10.0 * delta))
		(s["inner"] as MeshInstance3D).scale = Vector3(s["radius"] * u, 1, s["radius"] * u)
		if u >= 1.0:
			var at := root.global_position
			_pillar(at, s["radius"])
			ring(at, s["radius"] * 1.3, 0.4, Color(1.0, 0.3, 0.1))
			shake(0.7)
			sfx.play("heavy")
			var d := player.global_position - at
			d.y = 0.0
			if d.length() <= s["radius"] and gstate == G.FIGHT:
				player.receive_hit(s["dmg"], true, at)
			root.queue_free()
			_strikes.remove_at(i)
		else:
			i += 1


func _pillar(at: Vector3, radius: float, col := Color(1.0, 0.45, 0.15, 0.85)) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.75
	cm.bottom_radius = radius * 0.75
	cm.height = 60.0
	cm.radial_segments = 16
	var mat := _fx_mat(col)
	var n := _add_mesh(self, cm, at + Vector3(0, 30, 0), mat)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(n, "scale", Vector3(0.2, 1, 0.2), 0.45)
	tw.chain().tween_callback(n.queue_free)
	spark(at + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.4), 24)


func mech_strike() -> void:
	hud.say("LANCER", "Link open. Firing.")
	hud.flash("SAND LANCER", HudS.GOLD)
	sfx.play("limit")
	slowmo(0.25, 0.7)
	lancer.play("thrust", 0.35, 1.6)
	_after(0.16, func():
		if boss.is_dead():
			return
		var at := boss.global_position
		# beam from the mech's chest to the target
		var from := lancer.global_position + Vector3(0, 14, 0)
		var to: Vector3 = boss.chest()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.9
		cm.height = from.distance_to(to)
		cm.radial_segments = 10
		var mat := _fx_mat(Color(0.5, 0.8, 1.0, 0.9))
		var n := _add_mesh(self, cm, (from + to) * 0.5, mat)
		n.look_at(to, Vector3.UP)
		n.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.tween_callback(n.queue_free)
		_pillar(at, 2.6, Color(0.5, 0.8, 1.0, 0.85))
		ring(at, 6.0, 0.5, Color(0.5, 0.8, 1.0))
		shake(1.0)
		sfx.play("heavy")
		sfx.play("stagger")
		boss.take_hit(170.0, 150.0))


# ---- effects -----------------------------------------------------------------

func hitstop(d: float) -> void:
	_hit_until = Time.get_ticks_msec() + int(d * 1000.0)


func slowmo(scale: float, d: float) -> void:
	_slow_scale = scale
	_slow_until = Time.get_ticks_msec() + int(d * 1000.0)


func shake(a: float) -> void:
	_shake = maxf(_shake, a)


func number(at: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.007
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = col
	add_child(l)
	l.global_position = at
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", at + Vector3(0, 1.1, 0), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


func spark(at: Vector3, col: Color, n: int) -> void:
	var p := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var m := _fx_mat(col)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = m
	p.mesh = qm
	p.amount = n if quality > 0 else maxi(4, n / 2)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	add_child(p)
	p.global_position = at
	p.emitting = true
	_after(0.9, p.queue_free)


func slash_fx(at: Vector3, yaw: float, col: Color, scl: float, roll: float) -> void:
	var mat := _fx_mat(Color(col.r, col.g, col.b, 0.85))
	var n := _add_mesh(self, _arc_mesh, at, mat)
	n.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll)
	n.scale = Vector3.ONE * 2.1 * scl
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_property(n, "scale", Vector3.ONE * 2.5 * scl, 0.2)
	tw.chain().tween_callback(n.queue_free)


func ring(at: Vector3, radius: float, dur: float, col: Color) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 4
	var mat := _fx_mat(Color(col.r, col.g, col.b, 0.9))
	var n := _add_mesh(self, tm, Vector3(at.x, 0.12, at.z), mat, Vector3.ZERO, Vector3(0.3, 0.3, 0.3))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "scale", Vector3(radius, 0.4, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(n.queue_free)


# ---- combat events -----------------------------------------------------------

func perfect_dodge(at: Vector3) -> void:
	slowmo(0.22, 0.55)
	add_combo(3)
	buzz(40)
	_fov_kick = 9.0
	sfx.play("perfect")
	hud.flash("PERFECT DODGE", HudS.BLUE)
	ring(at, 3.0, 0.4, Color(0.5, 0.8, 1.0))
	_once("pd", "LANCER", "Clean. Tap now to counter.")


func parry_fx(at: Vector3) -> void:
	hitstop(0.12)
	add_combo(3)
	buzz(60)
	_fov_kick = 5.0
	shake(0.35)
	sfx.play("parry")
	spark(at, Color(1.0, 0.95, 0.7), 22)
	hud.flash("PARRY", HudS.GOLD)


func on_player_hit(_dmg: float, at: Vector3) -> void:
	hits_taken += 1
	combo = 0
	buzz(120)
	hud.hurt()
	shake(0.5)
	hitstop(0.06)
	sfx.play("hit")
	spark(at + Vector3(0, 1.2, 0), Color(1.0, 0.3, 0.2), 12)


func on_red_warning() -> void:
	_once("red", "LANCER", "Red means move. Guarding won't hold.")


func on_limit_ready() -> void:
	hud.say("LANCER", "Link ready. Hold both thumbs and I'm yours.")


func on_boss_stagger(at: Vector3) -> void:
	buzz(150)
	_fov_kick = 8.0
	slowmo(0.3, 0.6)
	shake(0.6)
	sfx.play("stagger")
	ring(at, 5.0, 0.5, Color(1.0, 0.8, 0.4))
	hud.flash("LINK BREAK", HudS.GOLD)
	hud.say("LANCER", "His harness is out. Everything you have.")


func on_boss_shift(at: Vector3) -> void:
	slowmo(0.4, 0.8)
	shake(0.8)
	sfx.play("stagger")
	ring(at, 9.0, 0.7, Color(1.0, 0.2, 0.1))
	garuda.play("overhead", 0.8, 2.0)
	hud.say("KITE", "Garuda. Weapons free.")


func on_player_dead() -> void:
	slowmo(0.3, 1.0)
	sfx.play("stagger")
	_after(0.5, func(): _set_g(G.DEAD))
	if _autotest:
		print("AUTOTEST player died at t=%.1f boss_hp=%d" % [fight_time, int(boss.hp)])


func on_boss_dead() -> void:
	slowmo(0.15, 1.4)
	shake(1.0)
	sfx.play("stagger")
	garuda.play("kneel", 1.5, 2.0, true)
	hud.say("LANCER", "Link severed. It's over, Ran.")
	_after(0.6, func(): _set_g(G.WIN))
	if _autotest:
		print("AUTOTEST boss died at t=%.1f hits_taken=%d rank=%s" % [fight_time, hits_taken, rank()])


# ---- headless self-test bot ---------------------------------------------------

func _bot(delta: float) -> void:
	_bot_t -= delta
	var d := boss.global_position - player.global_position
	player.move_input = Vector2(0, -1) if d.length() > 3.0 else Vector2.ZERO
	if _bot_t > 0.0:
		return
	_bot_t = 0.16
	var r := _rng.randf()
	if player.hp < 40.0 and player.flasks > 0:
		player.on_flask()
	elif player.limit >= 100.0:
		player.on_limit()
	elif r < 0.5:
		player.on_tap()
	elif r < 0.62:
		player.on_flick(Vector2(0, -1))
	elif r < 0.78:
		player.on_flick(Vector2(1 if _rng.randf() < 0.5 else -1, 0.2).normalized())
	elif r < 0.86:
		player.on_guard(true)
		_after(0.35, func(): player.on_guard(false))
	elif r < 0.93:
		player.on_ability(0)
	else:
		player.on_ability(1)
