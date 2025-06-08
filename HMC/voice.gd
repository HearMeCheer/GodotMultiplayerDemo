extends Node

class_name Voice

enum ConnectionState { ERROR, NONE, READY, HAND_SHAKE, EVENTS}

var TAG = "Voice"
var state = ConnectionState.NONE
var request_result = 0

var HMC_API = load("res://HMC/HMC_API.gd")

#signal event_list_changed()
signal audio_recorded(buffer: PackedVector2Array)
signal audio_played(buffer: PackedVector2Array)
signal audio_received(buffer: PackedVector2Array)

signal stats_changed(key: String, value: Variant)
signal connection_state_changed(state: WebRTCPeerConnection.ConnectionState)

var is_closing: bool = false

var playback: AudioStreamPlayback = null

var record_effect: AudioEffectRecord
var capture_effect: AudioEffectCapture
var record_bus_index: int = -1

@export var audio_frames_recorded: int
@export var audio_frames_received: int
@export var audio_playback_buffer_size: int
@export var hmc_events: Array[String]
@export var last_connection_state: WebRTCPeerConnection.ConnectionState = WebRTCPeerConnection.STATE_NEW
@export var last_signaling_state: WebRTCPeerConnection.SignalingState = WebRTCPeerConnection.SIGNALING_STATE_STABLE
@export var last_gathering_state: WebRTCPeerConnection.GatheringState = WebRTCPeerConnection.GATHERING_STATE_NEW

var stats: Dictionary

var audio_buffer_mutex = Mutex.new()
var audio_buffer = PackedVector2Array()
var audio_buffer_channels = 1
var audio_buffer_sr = 48000
var audio_ring_buffer = CircularBuffer.new(audio_buffer_sr)

var rtc_connection = WebRTCPeerConnection.new()
var rtc_channel: WebRTCDataChannel
var participant_data: HmcApi.Participant = null
var participant_connection_url: String = ""

var received_frame_counter = FrameCounter.new()
var recorded_frame_counter = FrameCounter.new()

var recorded_audio_gain: float = 1.0
var playback_gain: float = 1.0

func _logS(msg: String):
	print(TAG + ": " + msg)

func is_playing() -> bool:
	return $Player.playing

func mute(enable: bool):
	if enable:
		recorded_audio_gain = 0.0
	else:
		recorded_audio_gain = 1.0

func speaker(gain: float):
	playback_gain = gain

func _update_stats(key:String, value: Variant):
	stats[key] = value
	stats_changed.emit(key, value)
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	$HmcApi.http_error_signal.connect(http_error_handler)
	$HmcApi.hand_shake(hand_shake_complete)

	rtc_connection.ice_candidate_created.connect(self._on_ice_candidate)
	rtc_connection.session_description_created.connect(self._on_session)
	rtc_connection.data_channel_received.connect(self._on_data_channel_received)
	rtc_connection.track_data_received.connect(self._on_track_data_received)

	pass # Replace with function body.

func initialize():
	pass

func initialize_audio(voice_file: String):
	if not $Player.is_playing():
		$Player.stream.mix_rate = audio_buffer_sr
		$Player.play()
		playback = $Player.get_stream_playback()
		audio_playback_buffer_size = playback.get_frames_available()
		var generator = $Player.stream as AudioStreamGenerator
		_logS("AudioStreamGenerator generator buffer length(s): " + str(generator.buffer_length))
		_logS("AudioStreamGenerator playback buffer size: " + str(audio_playback_buffer_size))
		_logS("AudioStreamGenerator mix rate: " + str(generator.mix_rate))
	
	if voice_file.is_empty():
		_logS("Setting up recording...")
		if _set_up_recording() == false:
			_logS("Failed to set up recording!")	
	else:
		_logS("Setting up voice file...")
		_set_up_voice_file(voice_file)

func get_connnection_state() -> String:
	match last_connection_state:
		WebRTCPeerConnection.STATE_NEW: return "New"
		WebRTCPeerConnection.STATE_CONNECTING: return "Connecting"
		WebRTCPeerConnection.STATE_CONNECTED: return "Connected"
		WebRTCPeerConnection.STATE_DISCONNECTED: return "Disconnected"
		WebRTCPeerConnection.STATE_FAILED: return "Failed"
		WebRTCPeerConnection.STATE_CLOSED: return "Closed"
		_: return "Unknown"

func get_channel_state() -> String:
	if rtc_channel:
		match rtc_channel.get_ready_state():
			WebRTCDataChannel.STATE_CONNECTING: return "Connecting"
			WebRTCDataChannel.STATE_OPEN: return "Open"
			WebRTCDataChannel.STATE_CLOSING: return "Closing"
			WebRTCDataChannel.STATE_CLOSED: return "Closed"
			_: return "Unknown"
	else:
		return "No channel"

func validate(err: Error, msg: String):
	if err != OK:
		push_error("Error %d: %s", err, msg)
		
# region Playback
func get_playback_frames():
	return playback.get_frames_available()

var buffer_filled = false
func _fill_buffer():
	var to_fill = playback.get_frames_available()
	
	if !buffer_filled:
		buffer_filled = audio_ring_buffer.size() > 960
		return
		
	var buf : PackedVector2Array
	for x in range(to_fill):
		if audio_ring_buffer.is_empty():
			break;
		else:
			buf.push_back(audio_ring_buffer.read_vector2())
	
	if playback_gain != 1.0:
		for i in range(buf.size()):
			buf[i] *= playback_gain

	playback.push_buffer(buf)
	audio_played.emit(buf)
#endregion 

#region Recording
func _set_up_voice_file(file_path: String) -> bool:
	if capture_effect:
		return true

	var bus_index = AudioServer.get_bus_index("Speech")
	if bus_index == -1:
		_logS("Speech bus missing!")
		return false

	_create_capture_effect(bus_index)

	if file_path.ends_with(".ogg"):
		$SpeechPlayer.stream = AudioStreamOggVorbis.load_from_file(file_path)
	else:
		var file = FileAccess.open(file_path, FileAccess.READ)
		var sound = AudioStreamMP3.new()
		sound.data = file.get_buffer(file.get_length())
		$SpeechPlayer.stream = sound

	$SpeechPlayer.stream.loop = true
	$SpeechPlayer.play()

	return true

func _create_capture_effect(bus_index: int) -> bool:
	if capture_effect:
		return true

	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_index, capture_effect)
	_logS("mix rate: " + str(AudioServer.get_mix_rate()))
	_logS("capture buffer length in frames: " + str(capture_effect.get_buffer_length_frames()))
	audio_frames_recorded = 0
	return true

func _set_up_recording() -> bool:
	if capture_effect:
		return true
		
	record_bus_index = AudioServer.get_bus_index("Record")
	if record_bus_index == -1:
		_logS("Record bus missing!")
		return false
	
	record_effect = AudioServer.get_bus_effect(record_bus_index, 0)
	if record_effect == null or record_effect is not AudioEffectRecord:
		_logS("Failed to find AudioEffectRecord")
		return false
	
	_create_capture_effect(record_bus_index)
		
	_logS("selected input device: " + AudioServer.input_device)
	
	#AudioServer.input_device = input_devices[2]
	$Recorder.play()
	record_effect.set_recording_active(true)
	return true

func _get_captured_samples():
	if record_effect && not record_effect.is_recording_active():
		_logS("No recording active.")
		return
		
	# Get the number of frames available in the capture buffer
	var sample_count = capture_effect.get_frames_available()
	
	if sample_count > 0:
		# Capture the audio samples from the buffer
		var buffer: PackedVector2Array = capture_effect.get_buffer(sample_count)
		var _avg = 0
		var pcm_packet = PackedFloat32Array()
		
		for v in buffer:
			pcm_packet.push_back(v[0] * recorded_audio_gain)

		# notify listeners (to visualize in waveform_control)	
		audio_recorded.emit(buffer)
				
		if rtc_connection:
			#print("sending " + str(pcm_packet.size()) + " samples")
			rtc_connection.send_audio_packet(pcm_packet)
			recorded_frame_counter.add(pcm_packet.size())
			audio_frames_recorded = recorded_frame_counter.frames_per_second
			#print("time delta: " + str(recorded_frame_counter.last_receive_time_delta))
			_update_stats("audio_frames_recorded/s", audio_frames_recorded)
		return buffer

#endregion

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		is_closing = true
		_logS("Close request...")
		close_connection()
		_logS("Connection closed")
	if what == NOTIFICATION_PREDELETE:
		_logS("Predelete...")

#region rtc connection
func init_connection(participant:HmcApi.Participant):
	if rtc_connection == null:
		rtc_connection = WebRTCPeerConnection.new()
	
	_logS("start connection url=<%s>"%[participant.iceUrl])
	participant_data = participant
	participant_connection_url = participant.connectionUrl
	
	var response_handler = func(body):
		_logS("received rtc config: " + JSON.stringify(body))
		_logS("initialize...")
		validate(rtc_connection.initialize(body), "initialize() failed")
		rtc_channel = rtc_connection.create_data_channel("data")
		rtc_channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
		if rtc_channel:
			_logS("data channel: %d %s"%[rtc_channel.get_id(), rtc_channel.get_label()])
		else:
			_logS("failed to create data channel")

		_logS("create offer...")
		validate(rtc_connection.create_offer(), "create_offer() failed")
		pass
	
	$HmcApi.get_rtc_config(participant.iceUrl, response_handler)	
		
	pass

func init_connection_with_url(ice_url: String, connection_url: String, cb: Callable):
	if rtc_connection == null:
		rtc_connection = WebRTCPeerConnection.new()
	
	_logS("start connection ice=<%s> url=<%s>"%[ice_url, connection_url])
	participant_connection_url = connection_url
	
	var response_handler = func(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("received rtc config: " + JSON.stringify(r.item))
		_logS("initialize...")
		validate(rtc_connection.initialize(r.item), "initialize() failed")
		rtc_channel = rtc_connection.create_data_channel("data")
		rtc_channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
		if rtc_channel:
			_logS("data channel: %d %s"%[rtc_channel.get_id(), rtc_channel.get_label()])
		else:
			_logS("failed to create data channel")
		_logS("create offer...")
		validate(rtc_connection.create_offer(), "create_offer() failed")
		if cb.is_valid():
			cb.call(rtc_connection)
		pass

	$HmcApi.get_rtc_config(ice_url, response_handler)	
		
	pass

func close_connection():
	if rtc_connection:
		_logS("closing connection...")
		rtc_connection.close()
		rtc_connection = null

		
func _on_ice_candidate(mid, index, sdp):
	_logS("on_ice_candidate mid: " + str(mid) + " index: " + str(index) + " sdp: " + str(sdp))


func _on_session(type, sdp):
	_logS("_on_session type: " + type + "  sdp: " + sdp)
	if !participant_connection_url.is_empty():
		var offer = {
			"type" : "offer",
			"sdp" : sdp
		}
		var offerJson = JSON.stringify(offer)
		var base64offer = Marshalls.utf8_to_base64(offerJson)
		
		var response_handler = func(result):
			if result is HmcApi.GetSingleItemResponse:
				var response = result as HmcApi.GetSingleItemResponse
				var json = response.item
				var remote_type = json.get("type")
				var remote_sdp = json.get("sdp")
				_logS("remote sdp: " + remote_sdp)
				rtc_connection.set_remote_description(remote_type, remote_sdp)
				pass

		$HmcApi.send_offer(participant_connection_url, base64offer, response_handler)	
			
		# Set generated description as local.
		rtc_connection.set_local_description(type, sdp)

func _on_data_channel_received(_channel:WebRTCDataChannel):
	_logS("on_data_channel_received")
	

func _on_track_data_received(ssrc:int, data:PackedVector2Array, channels:int):
	#audio_frames_received += data.size()
	received_frame_counter.add(data.size())
	audio_frames_received = received_frame_counter.frames_per_second
	_update_stats("audio_frames_received", received_frame_counter.frames_per_second)
	_update_stats("received channels", channels)
	_update_stats("received ssrc", ssrc)

	# notify listeners (to visualize in waveform_control)
	audio_received.emit(data)

	audio_ring_buffer.write_vector2_array(data)


static func obj_to_dict(obj: Variant) -> Dictionary:
	var prop_map = {}
	if obj is Object:		
		var prop_list = obj.get_property_list()
		for p in prop_list:
			if p is Object:
				prop_map[p.name] = obj_to_json(p)
			else: 
				prop_map[p.name] = obj.get(p.name)
	elif obj is Transform3D:
		return {
			"basis" : obj_to_dict(obj.basis),
			"origin" : obj_to_dict(obj.origin)
		}
	elif obj is Basis:
		return {
			'x' : obj_to_dict(obj.x),
			'y' : obj_to_dict(obj.y),
			'z' : obj_to_dict(obj.z)
		}
	elif obj is Vector3:
		return {
			"x" : obj.x,
			"y" : obj.y,
			"z" : obj.z
		}
			
	return prop_map

static func obj_to_json(obj: Variant) -> String:
	return JSON.stringify(obj_to_dict(obj))

func send_game_message(type: String, params: Variant):
	if not rtc_channel or last_connection_state != WebRTCPeerConnection.STATE_CONNECTED:
		return

	var params_str = obj_to_dict(params)

	var data = {
		"type" : type,
		"params" : params_str
	}
	var message = JSON.stringify(data)
	var packet = message.to_utf8_buffer()
	if rtc_channel:
		rtc_channel.put_packet(packet)
		#_logS("send_game_message: " + message)
	else:
		_logS("rtc channel is null")
		pass

	pass

func update_listener(listener_transform: Transform3D):
	if rtc_channel and last_connection_state == WebRTCPeerConnection.STATE_CONNECTED:
		send_game_message("listener_transform", listener_transform)

func update_position(position: Vector3):
	if rtc_channel and last_connection_state == WebRTCPeerConnection.STATE_CONNECTED:
		send_game_message("object_position", position)
	

#endregion

func http_error_handler(error:Error, message:String):
	_logS("Error %s %s"%[error, message])

func hand_shake_complete(response: HmcApi.GetSingleItemResponse):
	_logS("handshake message: " + str(response.item))

	state = ConnectionState.HAND_SHAKE
	
#region Events
func list_events(cb: Callable):
	var response = func response_callback(r: HmcApi.GetItemsResponse):
		_logS("get_events response")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		cb.call(r.items)
		pass
	$HmcApi.get_events(response)

func create_event(event_name: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		_logS("create_event response result: " + str(r.result))
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		var event:HmcApi.Event = r.item
		_logS("event %s (%s)"%[event.name, event.id])
		cb.call(event)
		pass
	$HmcApi.create_event(event_name, response)
	pass

func delete_event(event_id: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		_logS("event " + event_id + " removed")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return

		cb.call(r.item)
		pass
	$HmcApi.delete_event(event_id, response)	
	pass
#endregion

#region rooms
func list_rooms(event_id: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetItemsResponse):
		_logS("list_rooms response")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		cb.call(r.items)
	$HmcApi.list_rooms(event_id, response)
	pass

func delete_room(event_id: String, room_id: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("room " +room_id + " removed")
		cb.call(room_id)
		pass
	$HmcApi.delete_room(event_id, room_id, response)	

func create_room(event_id: String, room_name: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		_logS("create_room response")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		var room:HmcApi.Room = r.item
		_logS("room %s (%s)"%[room.name, room.id])
		# rooms[room.id] = room
		cb.call(room)
		pass
	$HmcApi.create_room(event_id, room_name, response)
	pass

#region participants
func get_participants(event_id: String, cb:Callable):
	var response = func response_callback(r: HmcApi.GetItemsResponse):
		_logS("get_paricipants response")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return		
		_logS("participants: " + str(r.items.size()))
		#for participant:HmcApi.Participant in r.items:
			#print("participant %s (%s)"%[participant.name, participant.id])
			#events[event.id] = event
		cb.call(r.items)
		pass
	$HmcApi.get_participants(event_id, response)
	
func create_participant(event_id: String, part_name: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		_logS("create_participant response")
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return		
		var participant:HmcApi.Participant = r.item
		_logS("participant %s (%s)"%[participant.name, participant.id])
		cb.call(participant)
		pass
	$HmcApi.create_participant(event_id, part_name, response)

func update_participant(event_id: String, participant: HmcApi.Participant, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("participant" + participant.id + " updated")
		cb.call(r.item)
		pass
	
	$HmcApi.update_participant(event_id, participant, response)	

func update_participant_rooms(event_id: String, participant: HmcApi.Participant, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("participant" + participant.id + " updated")
		cb.call(r.item)
		pass
	
	$HmcApi.update_participant_rooms(event_id, participant, response)	

func delete_participant(event_id: String, part_id: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("participant" + part_id + " removed")
		cb.call(part_id)
		pass
	$HmcApi.delete_participant(event_id, part_id, response)	

func join_room(event_id: String, part_id: String, room_id: String, cb: Callable):
	var response = func response_callback(r: HmcApi.GetSingleItemResponse):
		if r.result:
			cb.call($HmcApi.get_error_from_result(r.result, r.response_code))
			return
		_logS("participant" + part_id + " joined room " + room_id)
		cb.call(room_id)
		pass
	$HmcApi.join_room(event_id, part_id, room_id, response)	
#endregion

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):		
	if rtc_connection:
		#print("delta: " + str(_delta))
		rtc_connection.poll()
		var con_state = rtc_connection.get_connection_state()
		if con_state != last_connection_state:
			_logS("connection state: %d"%[con_state])
			last_connection_state = con_state
			connection_state_changed.emit(con_state)
		var sig_state = rtc_connection.get_signaling_state()
		if sig_state != last_signaling_state:
			_logS("signaling state: %d"%[sig_state])
			last_signaling_state = sig_state
		var gat_state = rtc_connection.get_gathering_state()
		if gat_state != last_gathering_state:
			_logS("gathering state: %d"%[gat_state])
			last_gathering_state = gat_state
			
		if $Player.playing:
			_fill_buffer()
		if $Recorder.playing or $SpeechPlayer.playing:
			_get_captured_samples()
	pass

func _on_hmc_api_http_error_signal(error, message):
	_logS("Error %s Message %s" % [str(error), message])
