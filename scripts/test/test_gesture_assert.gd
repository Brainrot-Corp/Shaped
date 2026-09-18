extends SceneTree
## Headless self-check for the gesture recognizer:
## godot --headless --path . --script res://scripts/test/test_gesture_assert.gd
## Exits 0 on success, 1 on any failure.

var _fails := 0


func _init() -> void:
	var rec := GestureRecognizer.new()
	GestureTemplates.install_defaults(rec)

	_check(rec, "circle stroke -> circle", _circle_stroke(), "circle", 0.80)
	_check(rec, "square stroke -> square", _square_stroke(), "square", 0.60)
	_check(rec, "v stroke -> v", _v_stroke(), "v", 0.0)
	_check_not_closed(rec, "line stroke -> no closed shapes", _line_stroke())

	if _fails == 0:
		print("ALL GESTURE TESTS PASSED")
	else:
		printerr("%d GESTURE TEST(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _check(rec: GestureRecognizer, label: String, stroke: PackedVector2Array,
		expected: String, min_score: float) -> void:
	var ranked := rec.rank(stroke)
	var top: Dictionary = ranked[0] if ranked.size() > 0 else {}
	var id: String = top.get("id", "")
	var score: float = top.get("score", 0.0)
	_print_top(ranked, label)
	if id != expected or score < min_score:
		_fail(label, "expected '%s' >= %.2f, got '%s' %.2f" % [expected, min_score, id, score])
	else:
		print("PASS: %s" % label)


func _check_not_closed(rec: GestureRecognizer, label: String, stroke: PackedVector2Array) -> void:
	var ranked := rec.rank(stroke)
	_print_top(ranked, label)
	var closed_ids := ["circle", "triangle", "square"]
	for r in ranked:
		if closed_ids.has(r["id"]):
			_fail(label, "closed shape '%s' ranked for an open stroke" % r["id"])
			return
	print("PASS: %s" % label)


func _fail(label: String, detail: String) -> void:
	_fails += 1
	printerr("FAIL: %s (%s)" % [label, detail])


func _print_top(ranked: Array, label: String) -> void:
	var parts := PackedStringArray()
	for r in ranked.slice(0, 3):
		parts.append("%s %.2f" % [r["id"], r["score"]])
	print("  %s -> %s" % [label, " | ".join(parts)])


# --- synthetic strokes (screen space, y down, all deterministic) -----------

func _noisy_path(base: PackedVector2Array, amount: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var out := PackedVector2Array()
	for p in base:
		out.append(p + Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount)))
	return out


func _circle_stroke() -> PackedVector2Array:
	var base := PackedVector2Array()
	for i in 73:
		var a := TAU * i / 72.0 - PI * 0.5
		base.append(Vector2(300, 300) + Vector2(cos(a), sin(a)) * 100.0)
	return _noisy_path(base, 3.0)


func _square_stroke() -> PackedVector2Array:
	var base := PackedVector2Array()
	for i in 19:
		base.append(Vector2(200 + 200.0 * i / 18.0, 200))
	for i in 19:
		base.append(Vector2(400, 200 + 200.0 * i / 18.0))
	for i in 19:
		base.append(Vector2(400 - 200.0 * i / 18.0, 400))
	for i in 19:
		base.append(Vector2(200, 400 - 200.0 * i / 18.0))
	base.append(base[0])
	return _noisy_path(base, 4.0)


func _v_stroke() -> PackedVector2Array:
	var base := PackedVector2Array()
	for i in 20:
		var t := i / 19.0
		base.append(Vector2(-80, -80).lerp(Vector2(0, 80), t) + Vector2(400, 400))
	for i in 20:
		var t := i / 19.0
		base.append(Vector2(0, 80).lerp(Vector2(80, -80), t) + Vector2(400, 400))
	return _noisy_path(base, 2.0)


func _line_stroke() -> PackedVector2Array:
	var base := PackedVector2Array()
	for i in 40:
		base.append(Vector2(100 + 400.0 * i / 39.0, 300))
	return _noisy_path(base, 1.0)
