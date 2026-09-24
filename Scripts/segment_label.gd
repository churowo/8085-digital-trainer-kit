class_name SevenSegmentDisplay
extends Control

## String to display, e.g. "2000", "FFFF", "----". Characters outside
## 0-9/A-F render as fully blank (all segments off) -- including "-",
## which matches how your existing code uses it as an unfilled placeholder.
@export var text: String = "0000":
	set(value):
		text = value
		queue_redraw()

@export var digit_count: int = 4:
	set(value):
		digit_count = value
		queue_redraw()

@export var on_color: Color = Color(1.0, 0.15, 0.1)
@export var off_color: Color = Color(0.15, 0.03, 0.02)
@export var background_color: Color = Color(0.05, 0.05, 0.05)
@export var digit_gap: float = 10.0
@export var segment_thickness_ratio: float = 0.16 # relative to digit height

# Segment order: a(top) b(top-right) c(bottom-right) d(bottom)
# e(bottom-left) f(top-left) g(middle)
const SEGMENT_MAP := {
	"0": [true, true, true, true, true, true, false],
	"1": [false, true, true, false, false, false, false],
	"2": [true, true, false, true, true, false, true],
	"3": [true, true, true, true, false, false, true],
	"4": [false, true, true, false, false, true, true],
	"5": [true, false, true, true, false, true, true],
	"6": [true, false, true, true, true, true, true],
	"7": [true, true, true, false, false, false, false],
	"8": [true, true, true, true, true, true, true],
	"9": [true, true, true, true, false, true, true],
	"A": [true, true, true, false, true, true, true],
	"B": [false, false, true, true, true, true, true],
	"C": [true, false, false, true, true, true, false],
	"D": [false, true, true, true, true, false, true],
	"E": [true, false, false, true, true, true, true],
	"F": [true, false, false, false, true, true, true],
}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)

	var digit_width: float = (size.x - digit_gap * (digit_count - 1)) / float(digit_count)
	var padded: String = text
	if padded.length() < digit_count:
		padded = padded.rpad(digit_count, " ")
	elif padded.length() > digit_count:
		padded = padded.substr(padded.length() - digit_count, digit_count)

	for i in range(digit_count):
		var rect := Rect2(Vector2(i * (digit_width + digit_gap), 0), Vector2(digit_width, size.y))
		_draw_digit(padded[i], rect)

func _draw_digit(ch: String, rect: Rect2) -> void:
	var segs: Array = SEGMENT_MAP.get(ch.to_upper(), [false, false, false, false, false, false, false])
	var w: float = rect.size.x
	var h: float = rect.size.y
	var t: float = h * segment_thickness_ratio
	var ox: float = rect.position.x
	var oy: float = rect.position.y

	var polys := [
		_h_segment(ox, oy, w, t),                       # a
		_v_segment(ox + w - t, oy, oy + h / 2, t),       # b
		_v_segment(ox + w - t, oy + h / 2, oy + h, t),   # c
		_h_segment(ox, oy + h - t, w, t),                # d
		_v_segment(ox, oy + h / 2, oy + h, t),           # e
		_v_segment(ox, oy, oy + h / 2, t),               # f
		_h_segment(ox, oy + h / 2 - t / 2, w, t),        # g
	]

	for i in range(7):
		draw_colored_polygon(polys[i], on_color if segs[i] else off_color)

func _h_segment(ox: float, oy: float, w: float, t: float) -> PackedVector2Array:
	var x1: float = ox + t * 0.6
	var x2: float = ox + w - t * 0.6
	var cy: float = oy + t / 2.0
	return PackedVector2Array([
		Vector2(x1 + t / 2, cy), Vector2(x1 + t, cy - t / 2),
		Vector2(x2 - t, cy - t / 2), Vector2(x2 - t / 2, cy),
		Vector2(x2 - t, cy + t / 2), Vector2(x1 + t, cy + t / 2),
	])

func _v_segment(x: float, y_start: float, y_end: float, t: float) -> PackedVector2Array:
	var cx: float = x + t / 2.0
	var y1: float = y_start + t * 0.6
	var y2: float = y_end - t * 0.6
	return PackedVector2Array([
		Vector2(cx, y1 + t / 2), Vector2(cx - t / 2, y1 + t),
		Vector2(cx - t / 2, y2 - t), Vector2(cx, y2 - t / 2),
		Vector2(cx + t / 2, y2 - t), Vector2(cx + t / 2, y1 + t),
	])
