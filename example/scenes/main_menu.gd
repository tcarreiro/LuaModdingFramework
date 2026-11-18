extends Control

@onready var main_options: VBoxContainer = %MainOptions
@onready var play_options: VBoxContainer = %PlayOptions
@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var new_game_button: Button = %NewGameButton
@onready var load_game_button: Button = %LoadGameButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	GameMods.stop_runtime()
	play_button.pressed.connect(_show_play_options)
	settings_button.disabled = true
	quit_button.pressed.connect(_on_quit_pressed)
	new_game_button.pressed.connect(_start_new_game)
	load_game_button.disabled = true
	back_button.pressed.connect(_show_main_options)
	_show_main_options()


func _show_play_options() -> void:
	main_options.hide()
	play_options.show()
	new_game_button.grab_focus()


func _show_main_options() -> void:
	play_options.hide()
	main_options.show()
	play_button.grab_focus()


func _start_new_game() -> void:
	get_tree().change_scene_to_file("res://example/scenes/mod_selection.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
