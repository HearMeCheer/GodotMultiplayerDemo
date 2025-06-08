extends Node

class_name GameCommon

@onready var players_container: Node3D = $/root/Level/PlayersContainer
var player_scene: PackedScene = preload("res://level/scenes/player.tscn")

var build_version: int = 0
var localhost = false
var voice_packed = preload("res://HMC/voice.tscn")
var voice_instance: Voice

var TAG = "GameCommon"

class Options:
	var enable_voice: bool = true
	var enable_position_update: bool = false
	var enable_player_rooms: bool = false
	var delete_empty_event: bool = false
	var voice_file: String = ""
	#var dev_event_name: String = "dev_event"
	#var dev_event_name: String = "testevent"
	#var dev_event_name: String = "devevent"
	var dev_event_name: String = "temp"
	var use_random_event_name = false

var options: Options = Options.new()

var all_players = {}
var local_player_info = {
	"nick" : "host",
	"skin" : "blue",
	"position" : Vector3(0, 0, 0),
	#"camera_position" : Vector3(0, 0, 0),
	#"camera_position_changed" : false,
	#"player_room" : "room123456",
	#"camera_transform" : Transform3D(),
	#"participant_id" : "",
	"ready" : false,
	"connection_state" : WebRTCPeerConnection.STATE_NEW,
	"version" : 0
}

var local_voice_data = {
	"iceUrl" : "",
	"connectionUrl" : "",
	"participant_id" : ""
}

func initialize(params: Dictionary):
	self.name = "GameState"
	build_version = params.version
	localhost = params.localhost
	local_player_info["version"] = build_version

	if params.voice_file:
		var file_name : String = params.voice_file
		if file_name.get_extension().is_empty():
			file_name = file_name + "*"
		var voice_file = find_file("res://assets/audio", file_name)
		options.voice_file = voice_file
	
	Network.player_connected.connect(_on_peer_connected)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.connection_succeeded.connect(_connection_succeeded)
	Network.connection_failed.connect(_connection_failed)
	Network.server_disconnected.connect(_server_disconnected)
	
	_initialize_voice()
	_initialized()

func start_host(_nickname: String, _skin_color: String) -> int:
	return Error.OK

func join_game(_nickname: String, _skin_color: String, _address: String) -> int:
	return Error.OK

func find_file(path: String, file_name: String) -> String:
	var files = list_files(path)
	for file in files:
		if file.match(file_name):
			return path + "/" + file
	return ""

func list_files(path: String) -> Array:
	var dir = DirAccess.open(path)
	if dir:
		var files = []
		dir.list_dir_begin()
		while true:
			var file_name = dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			files.append(file_name)
		dir.list_dir_end()
		return files
	return []

func _logS(msg: String):
	print(TAG + ": " + msg)

func _logA(msg: Array[String]):
	var line: String = TAG + ": "
	for i in msg:
		line += i + " "

	print(line)

func get_spawn_point() -> Vector3:
	var spawn_point = Vector2.from_angle(randf() * 2 * PI) * 10 # spawn radius
	return Vector3(spawn_point.x, 0, spawn_point.y)

func _quit_game():
	#_leave_event()
	get_tree().quit()

func get_position_in_camera_space(position: Vector3, camera_transform: Transform3D) -> Vector3:
	return camera_transform.affine_inverse() * position

func calculate_distance_attenuation(position: Vector3, listener_position: Vector3, min_distance: float = 5.0, max_distance: float = 50.0) -> float:
	var distance = position.distance_to(listener_position)
	if distance > max_distance:
		return 0.0
	if distance < min_distance:
		return 1.0

	return 1.0 - (distance - min_distance) / (max_distance - min_distance)

func _initialized():
	pass

func _initialize_voice():
	voice_instance = voice_packed.instantiate()
	add_child(voice_instance)
	#voice_instance.event_list_changed.connect(self._on_voice_event_list_changed)
	voice_instance.audio_recorded.connect(self._on_audio_recorded)
	voice_instance.audio_played.connect(self._on_audio_played)
	voice_instance.audio_received.connect(self._on_audio_received)
	voice_instance.stats_changed.connect(self._voice_stats_changed)		
	voice_instance.initialize()
	#voice_instance.initialize_audio()
	pass

func _check_remote_version(remote_ver: int):
	if remote_ver != build_version:
		push_error("remote version: " + str(remote_ver) + " > local version: " + str(build_version))
		return false
	return true

#region Network handlers
# local player connected to server
func _connection_succeeded(_peer_id: int):
	pass

# local player failed to connect to server (only for client)
func _connection_failed():
	pass
	
# server disconnected (only for client)
func _server_disconnected():
	pass	
	
func _on_peer_connected(peer_id):
	# send player info to new player
	_register_player.rpc_id(peer_id, local_player_info)

# called from multiplayer.peer_disconnected for all
func _on_player_disconnected(peer_id):	
	var info = all_players.get(peer_id)
	if info:
		_logS("player " + str(peer_id) + " removed from all_players")
		_remove_player(peer_id, info)
		all_players.erase(peer_id)
	pass
#endregion

func _on_connection_state_changed(state):
	#var peer_id = Network.multiplayer.get_unique_id()
	#_logS(str(peer_id) + " connection state changed: " + str(state))
	local_player_info["connection_state"] = state
	sync_player_connection_state.rpc(state)
	pass

#region Player management
# register players already in the game
@rpc("any_peer", "reliable")
func _register_player(remote_player_info):
	var remote_player_id = multiplayer.get_remote_sender_id()
	_logS("_register_player: " + str(remote_player_id) + str(remote_player_info))

	if _check_remote_version(remote_player_info["version"]) == false:
		_logS("version mismatch")
		if remote_player_id == 1:
			Network.close_multiplayer()
		return

	_logS("player " + remote_player_info["nick"] + " added to all_players")
	all_players[remote_player_id] = remote_player_info
	_on_player_connected(remote_player_id, remote_player_info)
	#print("debug _register_player ", players)	

# called from multiplayer.connected_to_server for client and from multiplayer.peer_connected for all
func _on_player_connected(peer_id, player_info):	
	for id in all_players.keys():
		if id != peer_id:
			var player_data = all_players[id]
			rpc_id(peer_id, "sync_player_skin", id, player_data["skin"])
			
	_add_player(peer_id, player_info)	
	pass

func _set_player_connection_state(id: int, state: int):
	_logS("player " + str(id) + " connection state: " + str(state))
	var color: Color = Color.WHITE
	match state:
		WebRTCPeerConnection.STATE_CONNECTING:
			color = Color.YELLOW
		WebRTCPeerConnection.STATE_CONNECTED:
			color = Color.GREEN
		WebRTCPeerConnection.STATE_DISCONNECTED:
			color = Color.WHITE
		WebRTCPeerConnection.STATE_FAILED:
			color = Color.RED
		WebRTCPeerConnection.STATE_CLOSED:
			color = Color.WHITE

	var player = players_container.get_node(str(id))
	if player:
		player.set_nick_color(color)
	pass

func _add_player(id: int, player_info : Dictionary):
	if id == 1:
		#_logS("server version: " + str(player_info["version"]))
		return

	var con_state = player_info.get("connection_state")
	if con_state:
		_logS("adding player " + str(id) + " connection state: " + str(con_state))
		_set_player_connection_state(id, con_state)
		pass

	if players_container.has_node(str(id)):
		return
		
	_logS("adding player scene for " + str(id))
	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point()
	players_container.add_child(player, true)
	player.set_info_text("")
	
	var nick = all_players[id]["nick"]
	player.rpc("change_nick", nick)
	
	_player_added(id, player_info)
	
	var skin_name = player_info["skin"]
	rpc("sync_player_skin", id, skin_name)
	
	rpc("sync_player_position", id, player.position)	
	pass

func _player_added(_id: int, _player_info : Dictionary):
	pass

func _remove_player(id: int, _player_info : Dictionary):
	if not multiplayer.is_server() or not players_container.has_node(str(id)):
		return
	
	_logS("removing player " + str(id))	
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()

	_player_removed(id, _player_info)
	pass

func get_player(id: int) -> Character:
	if !players_container.has_node(str(id)):
		push_warning(TAG + ": player " + str(id) + "not found!")
		return null

	return players_container.get_node(str(id))

func get_local_player() -> Character:
	return self.get_player(local_player_info["peer_id"]) if local_player_info.get("peer_id") else null

func _player_removed(_id: int, _player_info : Dictionary):
	pass
#endregion

#region RPC

# "call_local": The function can be called on the local peer. Useful when the server is also a player.
@rpc("any_peer", "call_local")
func sync_player_position(id: int, new_position: Vector3):
	if !players_container.has_node(str(id)):
		push_warning(TAG + ": player " + str(id) + "not found!")
		return

	var player = players_container.get_node(str(id))
	if player:
		#print("player " + str(id) + " position: " + str(new_position))
		_logS("player " + str(id) + " position: " + str(new_position))
		player.position = new_position	
	pass
			
# "any_peer": Clients are allowed to call remotely. Useful for transferring user input.
@rpc("any_peer", "call_local")
func sync_player_skin(id: int, skin_name: String):
	if id == 1:
		return
	#if id == 1: return # ignore host
	if !players_container.has_node(str(id)):
		push_warning(TAG + ": player " + str(id) + "not found!")
		return
	
	var player = players_container.get_node(str(id))
	if player:
		player.set_player_skin(skin_name)	
	pass

@rpc("any_peer", "call_local")
func sync_player_connection_state(state: int):
	var id = multiplayer.get_remote_sender_id()
	if !players_container.has_node(str(id)):
		push_warning(TAG + ": player " + str(id) + "not found!")
		return
	
	_set_player_connection_state(id, state)
	pass

# send camera position to server
@rpc("any_peer", "call_remote")
func sync_camera_transform(transform: Transform3D):
	var id = multiplayer.get_remote_sender_id()
	var info = all_players.get(id)
	if info:
		var position_changed = true
		if info.has("camera_position"):
			var position = transform.origin
			var diff = position.distance_to(info["camera_position"])
			if diff < 1:
				position_changed = false
		else:
			_logS("player " + str(id) + " initializing camera position to " + str(transform.origin))

		if position_changed:
			info["camera_position"] = transform.origin
			info["camera_transform"] = transform
			info["camera_position_changed"] = position_changed
			#_logS("player " + str(id) + " camera position: " + str(position))
	pass

# "authority" - Only the multiplayer authority can call remotely
# "call_remote": The function will not be called on the local peer.
@rpc("authority", "call_remote", "reliable")
func _sync_voice_data(_server_player_info):	
	# _logS("sync_voice_data: " + str(server_player_info))
	# local_player_info.merge(server_player_info, false)
	pass
#endregion

#region HMC event
func _voice_stats_changed(_key: String, _value: Variant):
	pass	

func _on_voice_event_list_changed():
	pass
	
func _on_audio_recorded(_buffer: PackedVector2Array):
	pass

func _on_audio_played(_buffer: PackedVector2Array):
	pass

func _on_audio_received(_buffer: PackedVector2Array):
	pass
	
func _join_event():
	pass
	
func _leave_event():
	pass
#endregion		

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
