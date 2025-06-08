extends Node3D

@onready var skin_input: OptionButton = $Menu/MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $Menu/MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $Menu/MainContainer/MainMenu/Option3/AddressInput
@onready var address_label: Label = $Menu/MainContainer/MainMenu/OptionPublicIp/AddressLabel
@onready var event_option: OptionButton = $Menu/MainContainer/MainMenu/OptionEvents/EventOptionButton
@onready var audio_input_option: OptionButton = $Menu/MainContainer/MainMenu/OptionAudioInput/AudioInputOptionButton
@onready var host_button: Button = $Menu/MainContainer/MainMenu/Buttons/Host
@onready var join_button: Button = $Menu/MainContainer/MainMenu/Buttons/Join
@onready var players_container: Node3D = $PlayersContainer
@onready var menu: Control = $Menu

@onready var dev_console_root = $InGameMenu/Control/DevConsoleContainer
@onready var recorded_audio_control: DataPlotControl = $InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/RecordingWaveform
@onready var played_audio_control: DataPlotControl = $InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/PlaybackWaveform
@onready var received_audio_control: DataPlotControl = $InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Waveforms/ReceivedWaveform
@onready var build_version_label: Label = $InGameMenu/Control/BottomBar/BuildVersion/Value
@onready var voice_stats_control: StatsControl = $InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/Stats
@onready var hmc_tab: HmcPanel = $InGameMenu/Control/DevConsoleContainer/DevConsolePanel/TabContainer/HMC
@export var player_scene: PackedScene

@onready var api_requests: HttpApiRequest = $HttpApiRequest

var voice_packed = preload("res://HMC/voice.tscn")
var dedicated_server: bool
var public_ip := ""
var local_participant: Dictionary
var is_closing: bool = false
var current_event: HmcApi.Event
var build_version: int

var game_state: GameCommon

func _is_headless() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	return false	

func _is_dedicated_server() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	if "--server" in OS.get_cmdline_user_args():
		return true
	return false

func _read_build_version() -> int:
	if FileAccess.file_exists("res://version.txt"):
		var version_file = FileAccess.open("res://version.txt", FileAccess.READ)
		var version = version_file.get_as_text().strip_edges().to_int()
		version_file.close()
		return version
	else:
		push_error("version.txt not found!")
		return -1
		
func _voice_stats_changed(key: String, value: Variant):
	voice_stats_control.update_stats(key, value)
	pass

func _ready():			
	build_version = _read_build_version()

	var cmd_line = OS.get_cmdline_args()
	var localhost = true if "--localhost" in cmd_line else false
	
	var voice_file = ""
	var voice_file_idx = cmd_line.find("--voicefile")
	if voice_file_idx >= 0:
		if voice_file_idx + 1 < cmd_line.size():
			voice_file = cmd_line[voice_file_idx + 1]
		else:
			voice_file = "obama_mono.ogg"
	
	dedicated_server = _is_dedicated_server()
	if dedicated_server:
		print("starting dedicated server...")
		game_state = GameServer.new()
		add_child(game_state)
		#initialize_server()
	else:
		print("initializing client...")
		game_state = GameClient.new()
		add_child(game_state)
		#initialize_client()

	game_state.initialize({ 
		"version" : build_version,
		"localhost": localhost,
		"voice_file": voice_file
		})
			
func _process(_delta):

	pass

func quit_game():
	#_leave_event()
	get_tree().quit()
	
func _on_audio_input_option_button_item_selected(index):
	var item = audio_input_option.get_item_text(index)
	AudioServer.input_device = item
	pass # Replace with function body.

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		is_closing = true
		print("Close request...")
		quit_game()
		#close_connection()
		print("Connection closed")
