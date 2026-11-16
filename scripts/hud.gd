extends Control
## Heads-up display, drawn in code. Thin angled bars, letter-spaced caps.

const INK := Color(0.96, 0.94, 0.9)
const DIM := Color(0.96, 0.94, 0.9, 0.55)
const BLUE := Color(0.45, 0.75, 1.0)
const GOLD := Color(1.0, 0.78, 0.3)
const REDC := Color(0.95, 0.22, 0.25)
const BACK := Color(0.05, 0.05, 0.07, 0.55)

var game: Node
var font: Font
var flask_rect := Rect2()
var ability_rects: Array = [Rect2(), Rect2()]
var quality_rect := Rect2()

var _line := ""
var _line_who := ""
var _line_t := 0.0
var _flash := ""
var _flash_t := 0.0
var _flash_col := INK
var _boss_lag := 1.0
var _hurt := 0.0
var _time := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func say(who: String, text: String) -> void:
	_line_who = who
	_line = text
	_line_t = 3.4


func flash(text: String, col: Color) -> void:
	_flash = text
	_flash_col = col
	_flash_t = 0.9


func hurt() -> void:
	_hurt = 1.0


func _process(delta: float) -> void:
	# unscaled time so UI keeps moving during slow motion
	var d := delta / maxf(0.05, Engine.time_scale)
	_time += d
	_line_t = maxf(0.0, _line_t - d)
	_flash_t = maxf(0.0, _flash_t - d)
	_hurt = maxf(0.0, _hurt - d * 2.5)
	if game.boss:
		var f: float = game.boss.hp / game.boss.MAX_HP
		_boss_lag = maxf(f, _boss_lag - d * 0.25) if _boss_lag > f else f
	queue_redraw()


func _sp(text: String, pos: Vector2, size: int, col: Color, spacing := 3.0, align := 0) -> void:
	var w := 0.0
	for ch in text:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	var x := pos.x
	if align == 1:
		x -= w * 0.5
	elif align == 2:
		x -= w
	for ch in text:
		draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing


func _bar(pos: Vector2, w: float, h: float, frac: float, col: Color, back := BACK) -> void:
	var sk := h * 0.9
	draw_colored_polygon(PackedVector2Array([pos + Vector2(sk, 0), pos + Vector2(w + sk, 0), pos + Vector2(w, h), pos + Vector2(0, h)]), back)
	var fw := w * clampf(frac, 0.0, 1.0)
	if fw > 1.0:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(sk, 0), pos + Vector2(fw + sk, 0), pos + Vector2(fw, h), pos + Vector2(0, h)]), col)


func _draw() -> void:
	var sz := get_viewport_rect().size
	var g: int = game.gstate
	if _hurt > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.8, 0.05, 0.05, 0.22 * _hurt))
	match g:
		game.G.TITLE:
			_draw_title(sz)
		game.G.HOWTO:
			_draw_howto(sz)
		_:
			_draw_fight(sz)
			if g == game.G.DEAD:
				_overlay(sz, "PILOT DOWN", "TAP TO RISE AGAIN", REDC)
			elif g == game.G.WIN:
				_draw_win(sz)


func _draw_title(sz: Vector2) -> void:
	draw_rect(Rect2(0, sz.y * 0.56, sz.x, sz.y * 0.44), Color(0.03, 0.03, 0.05, 0.45))
	_sp("SAND LANCER", Vector2(72, sz.y * 0.72), 64, INK, 14.0)
	_sp("A DUEL IN THE DEEP DESERT", Vector2(76, sz.y * 0.72 + 34), 16, GOLD, 6.0)
	var a := 0.55 + 0.45 * sin(_time * 3.0)
	_sp("TAP TO BEGIN", Vector2(76, sz.y * 0.72 + 86), 18, Color(INK, a), 6.0)
	var q: String = ["LOW", "MEDIUM", "HIGH"][game.quality]
	quality_rect = Rect2(sz.x - 330, sz.y - 84, 290, 52)
	draw_rect(quality_rect, BACK)
	draw_rect(quality_rect, DIM, false, 1.0)
	_sp("GRAPHICS  " + q, quality_rect.position + Vector2(145, 33), 15, INK, 4.0, 1)


func _draw_howto(sz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.03, 0.05, 0.78))
	_sp("NO BUTTONS. JUST YOUR THUMBS.", Vector2(sz.x * 0.5, 96), 24, INK, 6.0, 1)
	var rows := [
		["TAP", "Strike. Keep tapping to chain a four-hit combo."],
		["SWIPE", "Dodge that way. Dodge at the last instant to slow time, then tap to counter."],
		["SWIPE UP", "Lunge. Closes the distance and reaches him in the air."],
		["HOLD", "Guard. Start the hold just before an amber strike lands to parry it."],
		["DRAG", "Move. Anywhere on the screen."],
		["BOTH THUMBS UP / DOWN", "Stormrend and Glassfall, your two heavy techniques."],
		["BOTH THUMBS HOLD", "When the link gauge is full: call the Sand Lancer."],
	]
	var y := 160.0
	for r in rows:
		_sp(r[0], Vector2(sz.x * 0.5 - 60, y), 15, GOLD, 4.0, 2)
		draw_string(font, Vector2(sz.x * 0.5 - 30, y), r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
		y += 50.0
	_sp("AMBER BLADE: GUARD OR PARRY", Vector2(sz.x * 0.5 - 30, y + 20), 14, Color(1.0, 0.62, 0.15), 3.0, 2)
	_sp("RED BLADE: MOVE", Vector2(sz.x * 0.5 + 30, y + 20), 14, REDC, 3.0)
	var a := 0.55 + 0.45 * sin(_time * 3.0)
	_sp("TAP TO DEPLOY", Vector2(sz.x * 0.5, sz.y - 50), 18, Color(INK, a), 6.0, 1)


func _draw_fight(sz: Vector2) -> void:
	var p = game.player
	var b = game.boss
	_sp("SAND LANCER", Vector2(36, 40), 12, DIM, 6.0)

	# boss
	var bw := minf(560.0, sz.x * 0.44)
	var bx := sz.x * 0.5 - bw * 0.5
	_sp("KITE  /  ISHAAN VYAS", Vector2(sz.x * 0.5, 38), 14, INK, 5.0, 1)
	_bar(Vector2(bx, 50), bw, 9, _boss_lag, Color(1, 1, 1, 0.6))
	_bar(Vector2(bx, 50), bw, 9, b.hp / b.MAX_HP, REDC, Color(0, 0, 0, 0))
	var staggered: bool = b.state == b.S.STAGGER
	var wf: float = b.will / b.MAX_WILL
	if staggered:
		wf = 1.0 - b._t / b._dur
	_bar(Vector2(bx + bw * 0.5, 64), bw * 0.5, 5, wf, GOLD if not staggered else Color(1, 1, 1, 0.5 + 0.5 * sin(_time * 20.0)))
	_sp("LINK", Vector2(bx + bw * 0.5 - 6, 71), 10, DIM, 3.0, 2)
	if staggered:
		_sp("x%.2f" % b.stagger_mult, Vector2(bx + bw + 20, 71), 16, GOLD, 2.0)
	_sp("PHASE " + ("II" if b.phase == 2 else "I"), Vector2(sz.x - 36, 40), 12, DIM, 4.0, 2)

	# player, bottom right
	var pw := 300.0
	var px := sz.x - pw - 48
	var py := sz.y - 92
	_sp("RAN SEN", Vector2(px + 8, py - 8), 13, INK, 4.0)
	_sp(str(int(ceil(p.hp))), Vector2(px + pw + 8, py - 8), 15, INK, 1.0, 2)
	_bar(Vector2(px, py), pw, 10, p.hp / p.MAX_HP, BLUE if p.hp > 30.0 else REDC)
	_bar(Vector2(px + 20, py + 15), pw - 60, 4, p.stamina / p.MAX_STAMINA, Color(0.75, 0.95, 0.7))
	var lf: float = p.limit / 100.0
	var active: bool = p.limit_active > 0.0
	if active:
		lf = p.limit_active / 8.0
	var lcol := GOLD
	if lf >= 1.0 and not active:
		lcol = Color(1.0, 0.9, 0.5, 0.6 + 0.4 * sin(_time * 8.0))
	_bar(Vector2(px - 30, py + 38), pw - 30, 7, lf, lcol)
	_sp("SAND LANCER", Vector2(px - 24, py + 34), 10, DIM, 3.0)
	if lf >= 1.0 and not active:
		_sp("HOLD BOTH THUMBS", Vector2(px + pw - 60, py + 34), 10, GOLD, 2.0, 2)

	# cells + techniques, bottom left
	var cx := 44.0
	var cy := sz.y - 78.0
	flask_rect = Rect2(cx - 12, cy - 20, 150, 70)
	for i in p.MAX_FLASKS:
		var r := Rect2(cx + i * 30.0, cy, 20, 34)
		if i < p.flasks:
			draw_rect(r, Color(0.5, 1.0, 0.65, 0.9))
		draw_rect(r, DIM, false, 1.0)
	_sp("CELLS  TAP", Vector2(cx, cy + 52), 10, DIM, 3.0)
	var names := ["STORMREND", "GLASSFALL"]
	var hints := ["THUMBS UP", "THUMBS DOWN"]
	for i in 2:
		var r := Rect2(cx + 170 + i * 150.0, cy, 136, 34)
		ability_rects[i] = r.grow(8)
		var ready: bool = p.cd[i] <= 0.0
		draw_rect(r, BACK)
		if not ready:
			draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 - p.cd[i] / p.CD_MAX[i]), r.size.y)), Color(1, 1, 1, 0.12))
		draw_rect(r, BLUE if ready else DIM, false, 1.0)
		_sp(names[i], r.position + Vector2(68, 22), 12, INK if ready else DIM, 3.0, 1)
		_sp(hints[i], r.position + Vector2(68, 52), 9, DIM, 2.0, 1)

	# style chain, right edge
	if game.combo > 1:
		var gr: int = game.grade()
		var gcol: Color = [DIM, INK, BLUE, GOLD, REDC][gr]
		_sp(game.GRADES[gr], Vector2(sz.x - 60, sz.y * 0.42), 58, gcol, 0.0, 2)
		_sp("%d HITS" % game.combo, Vector2(sz.x - 60, sz.y * 0.42 + 26), 14, INK, 4.0, 2)
		_bar(Vector2(sz.x - 190, sz.y * 0.42 + 36), 126, 3, game.combo_t / 3.2, gcol)
	if p._counter_window > 0.0:
		_sp("TAP TO COUNTER", Vector2(sz.x * 0.5, sz.y * 0.62), 20, Color(BLUE, 0.6 + 0.4 * sin(_time * 24.0)), 6.0, 1)
	if _flash_t > 0.0:
		var k := _flash_t / 0.9
		_sp(_flash, Vector2(sz.x * 0.5, sz.y * 0.34), int(30 + 10 * k), Color(_flash_col, minf(1.0, k * 2.0)), 10.0, 1)
	if _line_t > 0.0:
		var a := minf(1.0, _line_t * 2.0)
		var tw := font.get_string_size(_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var lx := sz.x * 0.5 - tw * 0.5
		draw_rect(Rect2(lx - 110, sz.y - 150, tw + 130, 34), Color(0.03, 0.03, 0.05, 0.5 * a))
		_sp(_line_who, Vector2(lx - 14, sz.y - 127), 12, Color(GOLD if _line_who == "LANCER" else REDC, a), 3.0, 2)
		draw_string(font, Vector2(lx, sz.y - 126), _line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(INK, a))
	if g_intro():
		_sp("KITE", Vector2(sz.x * 0.5, sz.y * 0.42), 54, INK, 22.0, 1)
		_sp("PILOT OF THE PROTO-FRAME GARUDA", Vector2(sz.x * 0.5, sz.y * 0.42 + 34), 14, GOLD, 6.0, 1)


func g_intro() -> bool:
	return game.gstate == game.G.INTRO


func _overlay(sz: Vector2, title: String, sub: String, col: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.02, 0.03, 0.6))
	_sp(title, Vector2(sz.x * 0.5, sz.y * 0.46), 52, col, 18.0, 1)
	_sp(sub, Vector2(sz.x * 0.5, sz.y * 0.46 + 48), 16, Color(INK, 0.55 + 0.45 * sin(_time * 3.0)), 6.0, 1)


func _draw_win(sz: Vector2) -> void:
	_overlay(sz, "LINK SEVERED", "TAP TO DUEL AGAIN", GOLD)
	var t: float = game.fight_time
	var txt := "TIME %d:%02d     HITS TAKEN %d     BEST CHAIN %d     RANK %s" % [int(t) / 60, int(t) % 60, game.hits_taken, game.best_combo, game.rank()]
	_sp(txt, Vector2(sz.x * 0.5, sz.y * 0.46 + 96), 15, INK, 4.0, 1)
