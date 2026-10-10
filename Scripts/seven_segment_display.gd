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

func _ready() -> void:
	resized.connect(queue_redraw)

# Segment order: a(top) b(top-right) c(bottom-right) d(bottom)
# e(bottom-left) f(top-left) g(middle)
# B and D are deliberately given their lowercase hex-display shapes
# (not the full uppercase outline) so they can't be confused with 8/0.
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
	"B": [false, false, true, true, true, true, true], # lowercase "b" shape
	"C": [true, false, false, true, true, true, false],
	"D": [false, true, true, true, true, false, true],  # lowercase "d" shape
	"E": [true, false, false, true, true, true, true],
	"F": [true, false, false, false, true, true, true],
}

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), background_color)

	var digit_width: float = (size.x - digit_gap * (digit_count - 1)) / float(digit_count)
	if digit_width <= 0.0:
		return

	var padded: String = text
	if padded.length() < digit_count:
		padded = padded.rpad(digit_count, " ")
	elif padded.length() > digit_count:
		padded = padded.substr(padded.length() - digit_count, digit_count)

	for i in range(digit_count):
		var rect := Rect2(Vector2(i * (digit_width + digit_gap), 0), Vector2(digit_width, size.y))
		_draw_digit(padded[i], rect)

func _draw_digit(ch: String, rect: Rect2) -> void:
	var w: float = rect.size.x
	var h: float = rect.size.y
	if w <= 4.0 or h <= 4.0:
		return # too small to safely form segment polygons

	var t: float = h * segment_thickness_ratio
	# Guard against segments overlapping into a self-intersecting shape
	# when the digit is very narrow or thickness_ratio is too large.
	t = min(t, w / 3.0)
	t = min(t, h / 3.0)
	if t <= 0.5:
		return

	var segs: Array = SEGMENT_MAP.get(ch.to_upper(), [false, false, false, false, false, false, false])
	var ox: float = rect.position.x
	var oy: float = rect.position.y
	var half_h: float = h / 2.0

	# Plain rectangles -- no polygon triangulation involved, so this can't
	# hit the "triangulation failed" crash regardless of digit size.
	var rects := [
		Rect2(ox + t, oy, w - 2 * t, t),                      # a (top)
		Rect2(ox + w - t, oy, t, half_h),                      # b (top-right)
		Rect2(ox + w - t, oy + half_h, t, half_h),             # c (bottom-right)
		Rect2(ox + t, oy + h - t, w - 2 * t, t),               # d (bottom)
		Rect2(ox, oy + half_h, t, half_h),                     # e (bottom-left)
		Rect2(ox, oy, t, half_h),                              # f (top-left)
		Rect2(ox + t, oy + half_h - t / 2, w - 2 * t, t),      # g (middle)
	]

	for i in range(7):
		draw_rect(rects[i], on_color if segs[i] else off_color)
