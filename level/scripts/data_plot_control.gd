extends Control

class_name DataPlotControl

enum DrawMode {
	AVERAGE = 0,
	LEFT = 1,
	RIGHT = 2,
	DIFFERENCE = 3,
	BOTH = 4
}

var DrawModeNames = ["average", "left", "right", "difference", "both"]

const default_text = "scroll to zoom, middle to reset"
@export var text: String = default_text
@export var sample_rate: int = 48000
@onready var audio_buffer := CircularBuffer.new(sample_rate*5)
var polyline1: PackedVector2Array = PackedVector2Array()
var polyline2: PackedVector2Array = PackedVector2Array()
var new_data: bool = false
var wave_scale: int = 1
var draw_mode: int = DrawMode.AVERAGE

func append_audio_data(buffer: PackedVector2Array):
	audio_buffer.write_vector2_array(buffer)
		
	new_data = true
	pass

func _get_minimum_size():
	return Vector2(100, 100)

func _gui_input(event):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				wave_scale -= 1
			MOUSE_BUTTON_WHEEL_UP:
				wave_scale += 1
			MOUSE_BUTTON_MIDDLE:
				wave_scale = 1
			MOUSE_BUTTON_LEFT:
				if !event.pressed:
					draw_mode += 1
					if draw_mode > DrawMode.BOTH:
						draw_mode = DrawMode.AVERAGE
		if wave_scale == 0:
			wave_scale = 1

# Called when the node enters the scene tree for the first time.
func _ready():
	if text == default_text:
		text = name + " scroll to zoom, middle to reset"

	for x in range(audio_buffer.capacity):
		audio_buffer.write(0.0)
	
	#for x in range(48000):
		#audio_buffer.write(-1.0 + 2.0*randf())
	
	new_data = true
	pass # Replace with function body.

func create_polyline():
	var width = self.size.x
	var height = self.size.y

	var step = audio_buffer.size() / width
	polyline1.clear()
	
	if draw_mode == DrawMode.BOTH:
		polyline2.clear()
		height *= 0.5

	for x in range(width):
		var sample_index = int(x * step)
		var frame = audio_buffer.peek_vector2(sample_index)
		var sample_value = frame
		match draw_mode:
			DrawMode.LEFT:
				sample_value.x = frame.x
			DrawMode.RIGHT:
				sample_value.x = frame.y
			DrawMode.DIFFERENCE:
				sample_value.x = frame.x - frame.y
			DrawMode.BOTH:
				sample_value = frame
			_:
				sample_value.x = (frame.x + frame.y) * 0.5
				
		sample_value *= wave_scale
		sample_value = sample_value.clampf(-1.0, 1.0)
		
		var y = int((sample_value.x + 1.0) * 0.5 * height)
		var next = Vector2(float(x), y)
		polyline1.append(next)

		if draw_mode == DrawMode.BOTH:
			y = height + int((sample_value.y + 1.0) * 0.5 * height)
			next = Vector2(float(x), y)
			polyline2.append(next)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if new_data:
		create_polyline()		
		queue_redraw()
		new_data = false
	pass

func _draw():
	draw_rect(Rect2(Vector2(0,0), self.size), Color.BLACK)
	
	var num_bars:int = 5;
	var step = size.x / num_bars
	for x in range(num_bars):
		var start = Vector2(x*step, 0)
		var end = Vector2(x*step, size.y)
		draw_dashed_line(start, end, Color.GRAY)
	
	var poly_color: Color = Color.WHITE
	match draw_mode:
		DrawMode.LEFT:
			poly_color = Color.RED
		DrawMode.RIGHT:
			poly_color = Color.GREEN
		DrawMode.DIFFERENCE:
			poly_color = Color.YELLOW
		_:
			poly_color = Color.WHITE		
	
	if polyline1.size() > 1:
		draw_polyline(polyline1, poly_color, 1.0)		
	if polyline2.size() > 1:
		draw_polyline(polyline2, poly_color, 1.0)		

	var default_font = ThemeDB.fallback_font
	var default_font_size = ThemeDB.fallback_font_size
	var display_text = text + " scale: " + str(wave_scale) + " mode: " + DrawModeNames[draw_mode]
	draw_string(default_font, Vector2(10, 10 + default_font_size), display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, default_font_size, Color.WHITE)
