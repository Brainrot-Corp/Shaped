class_name GestureTemplates
extends RefCounted
## A starter set of shapes for GestureRecognizer.
##
## Coordinates are in screen space (y grows downward) and the scale is
## arbitrary — the recognizer normalises everything anyway. Only the
## *shape* and the *drawing direction* matter.

const LOOP_SAMPLES := 64


static func install_defaults(rec: GestureRecognizer) -> void:
	# --- open strokes ------------------------------------------------------
	rec.add_template("swipe_right", PackedVector2Array([
		Vector2(-100, 0), Vector2(100, 0)]))
	rec.add_template("swipe_left", PackedVector2Array([
		Vector2(100, 0), Vector2(-100, 0)]))
	rec.add_template("swipe_down", PackedVector2Array([
		Vector2(0, -100), Vector2(0, 100)]))
	rec.add_template("swipe_up", PackedVector2Array([
		Vector2(0, 100), Vector2(0, -100)]))

	rec.add_template("v", PackedVector2Array([
		Vector2(-80, -80), Vector2(0, 80), Vector2(80, -80)]))
	rec.add_template("caret", PackedVector2Array([
		Vector2(-80, 80), Vector2(0, -80), Vector2(80, 80)]))

	rec.add_template("z", PackedVector2Array([
		Vector2(-80, -60), Vector2(80, -60), Vector2(-80, 60), Vector2(80, 60)]))
	rec.add_template("lightning", PackedVector2Array([
		Vector2(40, -90), Vector2(-25, -10), Vector2(25, 5), Vector2(-40, 90)]))

	rec.add_template("arrow_up", PackedVector2Array([
		Vector2(0, 90), Vector2(0, -90), Vector2(-45, -35),
		Vector2(0, -90), Vector2(45, -35)]))

	# --- closed shapes -----------------------------------------------------
	# The player will not always start a closed shape at the same place or
	# trace it in the same direction, so each is registered with the same
	# number of variants: 4 starting points x 2 directions = 8 each. Keeping
	# the counts equal stops shapes with more variants from winning by volume.
	var circle := circle_points(90.0, 32)
	add_closed_shape(rec, "circle", circle, 4)
	add_closed_shape(rec, "circle", reverse_loop(circle), 4)

	var triangle := PackedVector2Array([
		Vector2(0, -90), Vector2(78, 45), Vector2(-78, 45), Vector2(0, -90)])
	add_closed_shape(rec, "triangle", triangle, 4)
	add_closed_shape(rec, "triangle", reverse_loop(triangle), 4)

	var square := PackedVector2Array([
		Vector2(-70, -70), Vector2(70, -70), Vector2(70, 70),
		Vector2(-70, 70), Vector2(-70, -70)])
	add_closed_shape(rec, "square", square, 4)
	add_closed_shape(rec, "square", reverse_loop(square), 4)


## Registers a closed shape `variants` times, each starting from a different
## point along the outline. Pass vertices whose last point equals the first.
static func add_closed_shape(rec: GestureRecognizer, id: String, vertices: PackedVector2Array, variants := 4) -> void:
	var loop := sample_path(vertices, LOOP_SAMPLES)
	for k in variants:
		var offset := int(float(k) / float(variants) * LOOP_SAMPLES)
		var rotated := loop.slice(offset)
		rotated.append_array(loop.slice(0, offset))
		rotated.append(rotated[0])  # close the outline again
		rec.add_template(id, rotated)


## Walks a polyline and returns `count` evenly spaced points along it.
static func sample_path(vertices: PackedVector2Array, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if vertices.size() < 2 or count < 2:
		return vertices.duplicate()

	var total := 0.0
	for i in range(1, vertices.size()):
		total += vertices[i - 1].distance_to(vertices[i])
	if total <= 0.0:
		return vertices.duplicate()

	var step := total / float(count)
	var seg := 1
	var seg_start := 0.0
	for i in count:
		var target := float(i) * step
		while seg < vertices.size() - 1:
			var seg_len := vertices[seg - 1].distance_to(vertices[seg])
			if seg_start + seg_len >= target:
				break
			seg_start += seg_len
			seg += 1
		var length := vertices[seg - 1].distance_to(vertices[seg])
		var t := 0.0 if length <= 0.0 else clampf((target - seg_start) / length, 0.0, 1.0)
		out.append(vertices[seg - 1].lerp(vertices[seg], t))
	return out


## Same outline traced the other way around (expects a closed loop).
static func reverse_loop(vertices: PackedVector2Array) -> PackedVector2Array:
	var out := vertices.duplicate()
	out.reverse()
	return out


static func circle_points(radius: float, segments := 32, counter_clockwise := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var direction := -1.0 if counter_clockwise else 1.0
	for i in segments + 1:
		var angle := direction * TAU * float(i) / float(segments) - PI * 0.5
		out.append(Vector2(cos(angle), sin(angle)) * radius)
	return out
