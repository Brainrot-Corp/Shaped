class_name GestureRecognizer
extends RefCounted
## Unistroke shape recognizer based on the $1 algorithm
## (Wobbrock, Wilson & Li, 2007).
##
## Feed it raw screen points, get back a ranked list of
## { "id": String, "score": float, "distance": float }.
## score is 0.0 (nothing alike) .. 1.0 (perfect match).

const NUM_POINTS := 64             ## every stroke is resampled to this many points
const SQUARE_SIZE := 250.0         ## strokes are normalised into this box
const HALF_DIAGONAL := 176.7767    ## 0.5 * sqrt(SQUARE_SIZE^2 * 2)
const GOLDEN := 0.6180339887498949
const ANGLE_PRECISION := 0.0349066 ## 2 degrees, in radians
const THIN_RATIO := 0.25           ## below this aspect ratio, scale uniformly instead

## When true, a shape matches at any orientation (a rotated "V" still reads as "V").
## For a combat system you usually want this OFF, so that ^ and V are different spells.
var rotation_invariant := false:
	set(value):
		if rotation_invariant == value:
			return
		rotation_invariant = value
		_rebuild()

## Slack allowed (in degrees) when rotation_invariant is false.
## Bigger = more forgiving of a crooked hand, but shapes start bleeding into each other.
var rotation_tolerance_deg := 18.0

var _raw := {}     # String -> Array[PackedVector2Array]
var _cooked := {}  # String -> Array[PackedVector2Array]


#region Public API

## Registers one example of a shape. Call it several times with the same id to
## store variants (different drawing directions, different starting corners...).
## The points can be in any coordinate space and any scale.
func add_template(id: String, points: PackedVector2Array) -> void:
	if points.size() < 2:
		push_warning("GestureRecognizer: template '%s' needs at least 2 points." % id)
		return
	if not _raw.has(id):
		_raw[id] = []
		_cooked[id] = []
	_raw[id].append(points)
	_cooked[id].append(_normalize(points))


func remove_template(id: String) -> void:
	_raw.erase(id)
	_cooked.erase(id)


func clear_templates() -> void:
	_raw.clear()
	_cooked.clear()


func get_template_ids() -> Array:
	return _raw.keys()


## Best match for a stroke. Returns { "id", "score", "distance" }.
## Returns an empty id and a score of 0.0 if the stroke or the template set is unusable.
func recognize(points: PackedVector2Array) -> Dictionary:
	var ranked := rank(points)
	if ranked.is_empty():
		return { "id": "", "score": 0.0, "distance": INF }
	return ranked[0]


## Every template scored against the stroke, best first.
## Useful for debugging ("why did my fireball come out as a shield?").
func rank(points: PackedVector2Array) -> Array:
	var out: Array = []
	if points.size() < 2 or _cooked.is_empty():
		return out

	var candidate := _normalize(points)
	var bound := deg_to_rad(45.0) if rotation_invariant else deg_to_rad(rotation_tolerance_deg)

	for id in _cooked:
		var best := INF
		for tpl in _cooked[id]:
			best = minf(best, _distance_at_best_angle(candidate, tpl, -bound, bound))
		out.append({
			"id": id,
			"score": clampf(1.0 - best / HALF_DIAGONAL, 0.0, 1.0),
			"distance": best,
		})

	out.sort_custom(func(a, b): return a["score"] > b["score"])
	return out


## Turns a drawn stroke into a line you can paste into your template table.
func to_template_literal(points: PackedVector2Array, sample_count := 24) -> String:
	var pts := _resample(points, sample_count)
	var centre := _centroid(pts)
	var parts := PackedStringArray()
	for p in pts:
		parts.append("Vector2(%d, %d)" % [roundi(p.x - centre.x), roundi(p.y - centre.y)])
	return "PackedVector2Array([%s])" % ", ".join(parts)

#endregion


#region $1 pipeline

func _rebuild() -> void:
	for id in _raw:
		var cooked: Array = []
		for pts in _raw[id]:
			cooked.append(_normalize(pts))
		_cooked[id] = cooked


func _normalize(points: PackedVector2Array) -> PackedVector2Array:
	var pts := _resample(points, NUM_POINTS)
	if rotation_invariant:
		pts = _rotate_by(pts, -_indicative_angle(pts))
	pts = _scale_to_square(pts)
	return _translate_to_origin(pts)


## Rewrites the stroke as n evenly spaced points, so that drawing speed
## and mouse polling rate stop mattering.
func _resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var pts := points.duplicate()
	var interval := _path_length(pts) / float(n - 1)
	var out := PackedVector2Array()

	if interval <= 0.0:
		# Degenerate stroke (a tap): just repeat the single point.
		for i in n:
			out.append(pts[0])
		return out

	out.append(pts[0])
	var accumulated := 0.0
	var i := 1
	while i < pts.size():
		var d := pts[i - 1].distance_to(pts[i])
		if accumulated + d >= interval:
			var t := (interval - accumulated) / d
			var q := pts[i - 1].lerp(pts[i], t)
			out.append(q)
			pts.insert(i, q)  # continue measuring from the point we just emitted
			accumulated = 0.0
		else:
			accumulated += d
		i += 1

	# Floating point drift can leave us one short or one long.
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	if out.size() > n:
		out = out.slice(0, n)
	return out


func _scale_to_square(points: PackedVector2Array) -> PackedVector2Array:
	var box := _bounding_box(points)
	var w: float = maxf(box.size.x, 0.0001)
	var h: float = maxf(box.size.y, 0.0001)
	var sx := SQUARE_SIZE / w
	var sy := SQUARE_SIZE / h

	# A near-straight stroke has almost no thickness; stretching it to a full
	# square would turn hand jitter into a mountain range. Scale it uniformly.
	if minf(w, h) / maxf(w, h) < THIN_RATIO:
		var uniform := SQUARE_SIZE / maxf(w, h)
		sx = uniform
		sy = uniform

	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x * sx, p.y * sy))
	return out


func _translate_to_origin(points: PackedVector2Array) -> PackedVector2Array:
	var c := _centroid(points)
	var out := PackedVector2Array()
	for p in points:
		out.append(p - c)
	return out


func _rotate_by(points: PackedVector2Array, angle: float) -> PackedVector2Array:
	var c := _centroid(points)
	var out := PackedVector2Array()
	for p in points:
		out.append(c + (p - c).rotated(angle))
	return out


func _indicative_angle(points: PackedVector2Array) -> float:
	var c := _centroid(points)
	return (c - points[0]).angle()


## Golden section search for the rotation that makes the two strokes line up best.
func _distance_at_best_angle(points: PackedVector2Array, tpl: PackedVector2Array, a: float, b: float) -> float:
	var x1 := GOLDEN * a + (1.0 - GOLDEN) * b
	var f1 := _distance_at_angle(points, tpl, x1)
	var x2 := (1.0 - GOLDEN) * a + GOLDEN * b
	var f2 := _distance_at_angle(points, tpl, x2)

	while absf(b - a) > ANGLE_PRECISION:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = GOLDEN * a + (1.0 - GOLDEN) * b
			f1 = _distance_at_angle(points, tpl, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - GOLDEN) * a + GOLDEN * b
			f2 = _distance_at_angle(points, tpl, x2)
	return minf(f1, f2)


func _distance_at_angle(points: PackedVector2Array, tpl: PackedVector2Array, angle: float) -> float:
	return _path_distance(_rotate_by(points, angle), tpl)


## Average distance between matching points of two normalised strokes.
func _path_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n == 0:
		return INF
	var total := 0.0
	for i in n:
		total += a[i].distance_to(b[i])
	return total / float(n)


func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


func _bounding_box(points: PackedVector2Array) -> Rect2:
	var min_p := points[0]
	var max_p := points[0]
	for p in points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2(min_p, max_p - min_p)

#endregion
