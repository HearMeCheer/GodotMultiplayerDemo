extends Node

const SERVER_ADDRESS: String = "s2.mydevil.net" #"91.185.190.103" #"142.214.185.204" #127.0.0.1"
#const SERVER_ADDRESS: String = "127.0.0.1"
const SERVER_PORT: int = 1370
const MAX_PLAYERS : int = 10

@export var DEFAULT_HTTP_REQUEST_SITE: String = ""
@export var DEFAULT_HTTP_HEADERS: Array[String] = []

signal player_list_changed()
# emitter for individual peer
signal connection_failed()
signal connection_succeeded(peer_id)
# emittet for every peer connected
signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal server_disconnected()

var players = {}
var player_info = {
	"nick" : "host",
	"skin" : "blue"
}

var hosting: bool = false

func is_valid_url(url: String) -> bool:
	# Regular expression for basic URL validation
	var url_regex = RegEx.new()
	url_regex.compile(r"^(https?|ftp)://[^\s/$.?#].[^\s]*$")
	
	# Check if the URL matches the pattern
	return url_regex.search(url) != null

func _ready() -> void:
	# server events:
	# Emitted when this MultiplayerAPI's multiplayer_peer disconnects from a peer. 
	# Clients get notified when other clients disconnect from the same server.
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	# Emitted when this MultiplayerAPI's multiplayer_peer connects with a new peer. ID is the peer ID of the new peer. 
	# Clients get notified when other clients connect to the same server. Upon connecting to a server, 
	# a client also receives this signal for the server (with ID being 1).
	multiplayer.peer_connected.connect(_on_player_connected)
	# client events:
	# Emitted when this MultiplayerAPI's multiplayer_peer successfully connected to a server. Only emitted on clients.
	multiplayer.connected_to_server.connect(_on_connected_ok)
	# Emitted when this MultiplayerAPI's multiplayer_peer disconnects from server. Only emitted on clients.
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Emitted when this MultiplayerAPI's multiplayer_peer fails to establish a connection to a server. Only emitted on clients.
	multiplayer.connection_failed.connect(_on_connection_failed)

func close_multiplayer():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

func create_server(port: int, max_players: int) -> int:
	var peer = ENetMultiplayerPeer.new()
	#peer.set_bind_ip(SERVER_ADDRESS)
	var error = peer.create_server(port, max_players)
	if error:
		return error
		
	multiplayer.multiplayer_peer = peer
	self.hosting = true
	return Error.OK

func create_client(address: String, port: int) -> int:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error:
		return error
		
	multiplayer.multiplayer_peer = peer
	return Error.OK

func start_host(nickname: String, skin_color: String) -> int:
	var peer = ENetMultiplayerPeer.new()
	#peer.set_bind_ip(SERVER_ADDRESS)
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	if error:
		return error
		
	multiplayer.multiplayer_peer = peer
	
	if !nickname:
		nickname = "Player_" + str(multiplayer.get_unique_id())
	if !skin_color:
		skin_color = "blue"
	player_info["nick"] = nickname
	player_info["skin"] = skin_color
	
	players[1] = player_info
	player_connected.emit(1, player_info)
	print("hosting at " + SERVER_ADDRESS + ":" + str(SERVER_PORT))
	self.hosting = true
	return Error.OK
	
func join_game(nickname: String, skin_color: String, address: String = SERVER_ADDRESS) -> int:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, SERVER_PORT)
	if error:
		return error
		
	multiplayer.multiplayer_peer = peer
	
	if !nickname:
		nickname = "Player_" + str(multiplayer.get_unique_id())
	if !skin_color:
		skin_color = "blue"
	player_info["nick"] = nickname
	player_info["skin"] = skin_color
	
	return Error.OK
	
func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	connection_succeeded.emit(peer_id)
	#print("_on_connected_ok: " + str(peer_id))
	# players[peer_id] = player_info
	# player_connected.emit(peer_id, player_info)
	
# server event	
# This signal is emitted with the newly connected peer's ID on each other peer, and on the new peer multiple times, once with each other peer's ID.
func _on_player_connected(id):
	# When a peer connects, send them my player info.
	# This allows transfer of all desired data for each player, not only the unique ID.
	#_register_player.rpc_id(id, player_info)
	player_connected.emit(id)

# server event
# This signal is emitted on every remaining peer when one disconnects.
func _on_player_disconnected(id):
	# var info = players[id]
	# players.erase(id)
	#_unregister_player.rpc_id(id, info)
	player_disconnected.emit(id)
	player_list_changed.emit()
	
@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	#print("_register_player: " + str(new_player_id))
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)
	player_list_changed.emit()
	#print("debug _register_player ", players)	

# @rpc("any_peer", "reliable")
# func _unregister_player(id, info):
# 	print("_unregister_player: " + str(id))
# 	player_disconnected.emit(id, info)
# 	player_list_changed.emit()
# 	print("debug _unregister_player ", players)	
	
func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	
