extends Node

var sound_enabled: bool = true


func apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_enabled)


func toggle_sound() -> void:
	sound_enabled = not sound_enabled
	apply_sound()
