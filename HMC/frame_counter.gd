class_name FrameCounter

var last_receive_time : int = 0
var last_rate_check : int = 0
var rate_check_period_sec : int = 5
var frames_per_period : int = 0
var total_frames: int = 0
var frames_per_second : int = 0
var last_receive_time_delta : int = 0

func _init(period_sec: int = 2):
	rate_check_period_sec = period_sec

func add(frames:int):
	var time_now = Time.get_ticks_msec()
	last_receive_time_delta = time_now - last_receive_time
	last_receive_time = time_now
	frames_per_period += frames
	total_frames += frames
	var time_since_last_check = time_now - last_rate_check
	if time_since_last_check > (rate_check_period_sec * 1000):
		var fps:int = (frames_per_period * 1000.0) / time_since_last_check
		frames_per_period = 0
		last_rate_check = time_now
		frames_per_second = fps
		#frames_per_second = 0.98*frames_per_second + 0.02*fps
