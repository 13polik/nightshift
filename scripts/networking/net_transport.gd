class_name NetTransport
extends RefCounted
## Transport abstraction. The game only talks to Godot's high-level MultiplayerAPI, so a
## relay / dedicated-server / platform (Game Center, Play Games, Steam) transport only has
## to produce a MultiplayerPeer here.

var last_error: String = ""


func create_host(_port: int, _max_clients: int) -> MultiplayerPeer:
	return null


func create_client(_address: String, _port: int) -> MultiplayerPeer:
	return null


func kick(_peer: MultiplayerPeer, _peer_id: int) -> void:
	pass


func describe() -> String:
	return "abstract"
