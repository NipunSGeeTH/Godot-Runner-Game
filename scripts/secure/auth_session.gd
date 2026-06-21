extends Node

## Stores JWT from register/login. Required before online play.

var token: String = ""
var user_id: int = 0
var index_number: String = ""
var username: String = ""
var best_coins: int = 0


func is_logged_in() -> bool:
	return token != ""


func set_auth(body: Dictionary) -> void:
	token = str(body.get("token", ""))
	user_id = int(body.get("user_id", 0))
	index_number = str(body.get("index_number", ""))
	username = str(body.get("username", body.get("name", "")))
	best_coins = int(body.get("best_coins", 0))


func clear() -> void:
	token = ""
	user_id = 0
	index_number = ""
	username = ""
	best_coins = 0
