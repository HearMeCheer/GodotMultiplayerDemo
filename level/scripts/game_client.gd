extends GameCommon

class_name GameClient

## WARNING: all RPC functions have to be the same as in game_common.gd. Otherwise they will not be called by the network manager.

@onready var skin_input: OptionButton = $/root/Level/Menu/MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $/root/Level/Menu/MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $/root/Level/Menu/MainContainer/MainMenu/Option3/AddressInput
@onready var address_label: Label = $/root/Level/Menu/MainContainer/MainMenu/OptionPublicIp/AddressLabel
@onready var event_option: OptionButton = $/root/Level/Menu/MainContainer/MainMenu/OptionEvents/EventOptionButton
@onready var audio_input_option: OptionButton = $/root/Level/Menu/MainContainer/MainMenu/OptionAudioInput/AudioInputOptionButton
@onready var host_button: Button = $/root/Level/Menu/MainContainer/MainMenu/Buttons/Host
@onready var join_button: Button = $/root/Level/Menu/MainContainer/MainMenu/Buttons/Join
@onready var quit_button: Button = $/root/Level/Menu/MainContainer/MainMenu/Option4/Quit
@onready var menu: Control = $/root/Level/Menu
@onready var game_menu: CanvasLayer = $/root/Level/InGameMenu
@onready var game_options: Control = $/root/Level/InGameMenu/Control/GameOptions
@onready var mute_button: CheckButton = $/root/Level/InGameMenu/Control/GameOptions/MuteCheckButton
@onready var speaker_button: CheckButton = $/root/Level/InGameMenu/Control/GameOptions/SpeakerCheckButton
@onready var debug_button: CheckButton = $/root/Level/InGameMenu/Control/GameOptions/DebugCheckButton
@onready var env_floor: Node3D = $/root/Level/Environment/Floor

@onready var dev_console_root = $/root/Level/InGameMenu/Control/DevConsoleContainer
@onready var recorded_audio_control: DataPlotControl = $/root/Level/InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/RecordingWaveform
@onready var played_audio_control: DataPlotControl = $/root/Level/InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/PlaybackWaveform
@onready var received_audio_control: DataPlotControl = $/root/Level/InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/ReceivedWaveform
@onready var build_version_label: Label = $/root/Level/InGameMenu/Control/BottomBar/BuildVersion/Value
@onready var build_ext_version_label: Label = $/root/Level/InGameMenu/Control/BottomBar/BuildVersionExt/Value
@onready var voicefile_label: Label = $/root/Level/InGameMenu/Control/BottomBar/VoiceFile/Value
@onready var event_name_label: Label = $/root/Level/InGameMenu/Control/BottomBar/EventName/Value
@onready var voice_stats_control: StatsControl = $/root/Level/InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Stats
@onready var hmc_tab: HmcPanel = $"/root/Level/InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/HMC"

@onready var api_requests: HttpApiRequest = $/root/Level/HttpApiRequest

var local_participant: Dictionary
var current_event: HmcApi.Event
var public_ip := ""
var enable_debug3d = false
var headless_mode = false # bot mode
var server_address = Network.SERVER_ADDRESS

func _initialized():
	self.TAG = "GameClient"
	hmc_tab.set_voice_controller(voice_instance)
	
	if DisplayServer.get_name() == "headless":
		_logS("headless mode")
		headless_mode = true
				
	if self.localhost:
		self.server_address = "127.0.0.1"

	voice_instance.connection_state_changed.connect(func(state: int):
		_on_connection_state_changed(state)
		)

	if headless_mode:
		if Error.OK == self.join_game("bot", "red", self.server_address):
			_logS("joining " + self.server_address)
		else:
			push_error(TAG + ": Failed to join game!")
	else:
		_init_ui()
		_init_info_bar()

	pass

func _init_info_bar():
	var app_version = ProjectSettings.get_setting("application/config/version", "1.0.0")
	build_version_label.text = app_version
	build_ext_version_label.text = "0.1." + str(build_version)
	if options.voice_file.is_empty():
		voicefile_label.text = "None"
	else:
		voicefile_label.text = options.voice_file.get_file()

func _init_ui():
	hmc_tab.set_voice_controller(voice_instance)
	address_input.text = self.server_address
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	mute_button.toggled.connect(func(active: bool):
		_logS("mute toggled: " + str(active))
		voice_instance.mute(active)
		)
	
	speaker_button.button_pressed = true
	speaker_button.toggled.connect(func(active: bool):
		_logS("speaker toggled: " + str(active))
		var speaker_gain = 1.0 if active else 0.0
		voice_instance.speaker(speaker_gain)
		)

	debug_button.toggled.connect(func(active: bool):
		_logS("debug toggled: " + str(active))
		enable_debug3d = active
		)
	
	var input_devices = AudioServer.get_input_device_list()
	for i in range(0, input_devices.size()):
		audio_input_option.add_item(input_devices[i])
		if AudioServer.input_device == input_devices[i]:
			audio_input_option.selected = i

func _update_input_devices():
	var input_devices = AudioServer.get_input_device_list()
	# if size differs, update the list
	if input_devices.size() != audio_input_option.item_count:
		audio_input_option.clear()
		for i in range(0, input_devices.size()):
			audio_input_option.add_item(input_devices[i])

	for i in range(0, input_devices.size()):
		if AudioServer.input_device == audio_input_option.get_item_text(i):
			if audio_input_option.selected != i:
				audio_input_option.selected = i
		
func _on_quit_pressed() -> void:
	_quit_game()
		
func _on_host_pressed():
	if Error.OK == self.start_host(nick_input.text.strip_edges(), skin_input.text.strip_edges()):
		menu.hide()
		#_join_event()
	else:
		push_error(TAG + ": Failed to host game!")

func _on_join_pressed():
	var ip = address_input.text.strip_edges()
	if not ip.is_valid_ip_address() and not Network.is_valid_url(ip):
		push_error(TAG + ": Invalid ip address: " + ip)
		
	if Error.OK == self.join_game(nick_input.text.strip_edges(), skin_input.text.strip_edges(), ip):
		menu.hide()
		game_options.show()
		_logS("joining " + ip)
		# uncomment only if connection to game server fails:
		#_join_event()
	else:
		push_error(TAG + ": Failed to join game!")
		
#region Network handlers
func join_game(nickname: String, skin_color: String, address: String) -> int:
	var err = Network.create_client(address, Network.SERVER_PORT)
	if err != Error.OK:
		push_error(TAG + ": failed to create client!")
		return err

	if !nickname:
		nickname = "Player_" + str(multiplayer.get_unique_id())
	if !skin_color:
		skin_color = "blue"
	
	local_player_info["nick"] = nickname
	local_player_info["skin"] = skin_color

	return Error.OK

func _connection_succeeded(peer_id: int):
	_logS("Connected to server!")
	self.TAG = "GameClient(" + local_player_info["nick"] + ")"
	all_players[peer_id] = local_player_info
	local_player_info["peer_id"] = peer_id
	#player_connected.emit(peer_id, player_info)
	_on_player_connected(peer_id, local_player_info)
	# connected to server so we can join voice
	#_join_event()
	pass
	
func _server_disconnected():
	_logS("server disconnected!")
	var peer_id = local_player_info["peer_id"]
	local_player_info.erase("peer_id")
	all_players.erase(peer_id)
#endregion

#region Voice handlers
func _sync_voice_data(server_player_info):
	_logS("sync_voice_data: " + str(server_player_info))
	local_voice_data.merge(server_player_info, true)
	var ice_url = local_voice_data.get("iceUrl")
	var connection_url = local_voice_data.get("connectionUrl")
	
	voice_stats_control.update_stats("ice_url", ice_url)
	voice_stats_control.update_stats("connection_url", connection_url)
	voice_stats_control.update_stats("event_id", local_voice_data.get("event_id"))
	voice_stats_control.update_stats("participant_id", local_voice_data.get("participant_id"))
	event_name_label.text = local_voice_data.get("event_id")

	if ice_url and connection_url:
		voice_instance.initialize_audio(options.voice_file)
		_logS("init connection with ice: " + ice_url + " connection: " + connection_url)
		voice_instance.init_connection_with_url(ice_url, connection_url, func(result: Variant):
			if result is HmcApi.HmcApiError:
				push_error("failed to create connection: " + result.message)
			else:
				_logS("rtc connection created")
			)
	pass
#endregion
		
#region HMC event
func _voice_stats_changed(key: String, value: Variant):
	voice_stats_control.update_stats(key, value)
	pass

func _on_voice_event_list_changed():
	event_option.clear()

	for e in $Voice.events.values():
		var idx = event_option.get_item_count()
		event_option.add_item(e.name)
		event_option.set_item_metadata(idx, e)
	
	host_button.disabled = event_option.get_item_count() == 0
	join_button.disabled = event_option.get_item_count() == 0
	
func _on_audio_recorded(buffer: PackedVector2Array):
	recorded_audio_control.append_audio_data(buffer)
	pass

func _on_audio_played(buffer: PackedVector2Array):
	played_audio_control.append_audio_data(buffer)
	pass

func _on_audio_received(buffer: PackedVector2Array):
	received_audio_control.append_audio_data(buffer)
	pass
	
func _join_event():
	var event = event_option.get_item_metadata(event_option.selected)
	if local_participant.get(event.id):
		return
	
	var callback = func participant_created(p: HmcApi.Participant):
		_logS("participant created %s id: %s" % [p.name, p.id])
		local_participant[event.id] = p
		$Voice.initialize_audio()
		$Voice.init_connection(p)
		pass
	
	var nick = Network.player_info["nick"]
	$Voice.create_participant(event.id, nick, callback)
	current_event = event
	_logS("joined event " + event.id)
	pass
	
func _leave_event():
	var event = current_event
	if event == null:
		return
		
	var participant: HmcApi.Participant = local_participant.get(event.id)
	if participant == null:
		return
		
	var callback = func():
		local_participant.erase(event.id)
		#refresh_participants()
		
	$Voice.delete_participant(event.id, participant.id, callback)
	$Voice.close_connection()
	current_event = null
	_logS("left event " + event.id)
	pass
#endregion	

func _gainAndPhase(source: Vector3) -> Vector4:
	const speedOfSound = 343
	const sampleRate = 48000
	const headWidthMeters = 0.15
	var leftEar = Vector3(-headWidthMeters / 2, 0, 0)
	var rightEar = Vector3(headWidthMeters / 2, 0, 0)

	var dLeft = source.distance_to(leftEar) # Distance(source, leftEar)
	var dRight = source.distance_to(rightEar) # Distance(source, rightEar)

	var deltaS = (dLeft - dRight) / speedOfSound
	var delay = int(deltaS * sampleRate)
	var gainL: float
	var gainR: float
	var delayL: int
	var delayR: int
	if delay > 0:
		delayL = delay
		delayR = 0

		#1/r^2
		var ratio = dLeft / dRight
		gainR = 1.0
		gainL = float(1 / (ratio * ratio))
	else:
		delayL = 0
		delayR = - delay

		var ratio = dRight / dLeft
		gainR = float(1 / (ratio * ratio))
		gainL = 1.0
	
	return Vector4(gainL, gainR, delayL, delayR)

func _update_info_text(player: Character):
	var transform : Transform3D = player.get_camera_transform()

	if enable_debug3d:
		var part_id = local_voice_data["participant_id"]
		var local_info = "pid: %s\norigin: %s\nbasis.X: %s\nbasis.Y: %s\nbasis.Z: %s"%[part_id, str(transform.origin), str(transform.basis.x), str(transform.basis.y), str(transform.basis.z)]
		player.set_info_text(local_info)
	else:
		player.set_info_text("")

	for remote_player in players_container.get_children():
		if remote_player != player and remote_player is Character:
			var player_char = remote_player as Character
			if enable_debug3d:
				var cam_pos = transform.affine_inverse() * player_char.position
				var gain = _gainAndPhase(cam_pos)
				var distance = transform.origin.distance_to(player_char.position)
				var attenuation = calculate_distance_attenuation(player_char.position, transform.origin)
				var info = "\ngainL: %.2f gainR: %.2f\ndelayL: %.2f delayR: %.2f\ndistance: %.2f attenuation: %.2f"%[gain.x, gain.y, gain.z, gain.w, distance, attenuation]
				#player_char.set_info_text(str(cam_pos) + "\ngainL: " + str(gain.x) + " gainR: " + str(gain.y) + "\n delayL: " + str(gain.z) + " delayR: " + str(gain.w))
				player_char.set_info_text(str(cam_pos) + info)	

			else:
				player_char.set_info_text("")
	pass

#region Node
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if Input.is_action_just_pressed("dev_console"):
		dev_console_root.visible = !dev_console_root.visible
	
	# var test_transform = env_floor.transform
	# #var json = JSON.stringify(test_transform)
	# var msg = Voice.obj_to_json(test_transform)
	
	if Input.is_action_just_pressed("ingame_menu"):
		if menu.visible:
			return
		
		game_menu.visible = !game_menu.visible
		pass
		
	if Input.is_action_just_pressed("playback_waveform"):
		played_audio_control.visible = !played_audio_control.visible

	if Input.is_action_just_pressed("recording_waveform"):
		recorded_audio_control.visible = !recorded_audio_control.visible

	if Input.is_action_just_pressed("received_waveform"):
		received_audio_control.visible = !received_audio_control.visible

	if menu.visible:
		_update_input_devices()

	if voice_instance.is_playing():
		var buffer_size: float = voice_instance.audio_playback_buffer_size
		var player = $Voice/Player.get_stream_playback() as AudioStreamGeneratorPlayback
		var available = player.get_frames_available()
		var filled: float = (buffer_size - available) * 100 / buffer_size

		voice_stats_control.update_stats("playback_buffer_size", buffer_size)
		voice_stats_control.update_stats("playback_available", available)
		voice_stats_control.update_stats("playback_buffer_filled", "%0.2f"%filled + "%")

		voice_stats_control.update_stats("playback_skips", player.get_skips())
		
	voice_stats_control.update_stats("connection_state", $Voice.get_connnection_state())
	voice_stats_control.update_stats("channel_state", $Voice.get_channel_state())

	if local_player_info.get("peer_id"):
		var player = self.get_player(local_player_info["peer_id"])
		if player == null:
			return

		var transform = player.get_camera_transform()
		var pos = transform.origin
		var player_pos = player.position
		sync_camera_transform.rpc_id(1, transform)
		voice_stats_control.update_stats("camera_pos", pos)
		voice_stats_control.update_stats("participant_pos", player_pos)
		
		voice_instance.update_listener(transform)
		voice_instance.update_position(player_pos)
		
		_update_info_text(player)

	if public_ip.is_empty() and api_requests.has_active_requests() == false:
		var response_handler = func handler(body: Dictionary):
			print("response: " + str(body))
			public_ip = body.data
			address_label.text = public_ip
			pass
		
		api_requests.process_request(response_handler, "https://api.ipify.org")
	
	pass
#endregion
