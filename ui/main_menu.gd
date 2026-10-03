extends Control

# 🛠️ Points directly to your root gameplay scene file location
const GAMEPLAY_SCENE_PATH = "res://game_world.tscn"

# Main Menu Container (the standard title buttons)
@onready var main_menu_container = $VBoxContainer

# Main Menu Buttons
@onready var start_btn = $VBoxContainer/StartGameBtn
@onready var settings_btn = $VBoxContainer/SettingsBtn
@onready var overview_btn = $VBoxContainer/OverviewBtn
@onready var about_btn = $VBoxContainer/AboutBtn
@onready var exit_btn = $VBoxContainer/ExitBtn

# Region Selection Panel
@onready var region_panel = $RegionSelectionPanel
@onready var japanese_btn = $RegionSelectionPanel/JapaneseBtn
@onready var mughal_btn = $RegionSelectionPanel/MughalBtn
@onready var mongol_btn = $RegionSelectionPanel/MongolBtn
@onready var region_back_btn = $RegionSelectionPanel/BackBtn

# Difficulty Panel
@onready var difficulty_panel = $DifficultyPanel
@onready var vs_two_btn = $DifficultyPanel/VsTwoBtn
@onready var vs_first_btn = $DifficultyPanel/VsFirstBtn
@onready var vs_second_btn = $DifficultyPanel/VsSecondBtn
@onready var difficulty_back_btn = $DifficultyPanel/BackBtn

# Settings Panel
@onready var settings_panel = $SettingsPanel
@onready var sound_btn = $SettingsPanel/SoundBtn
@onready var controls_btn = $SettingsPanel/ControlsBtn
@onready var tips_btn = $SettingsPanel/TipsBtn
@onready var settings_back_btn = $SettingsPanel/BackBtn

# Controls Panel
@onready var controls_panel = $ControlsPanel
@onready var controls_back_btn = $ControlsPanel/BackBtn
@onready var controls_text = $ControlsPanel/ControlsText

# Tips Panel
@onready var tips_panel = $TipsPanel
@onready var tips_back_btn = $TipsPanel/BackBtn
@onready var tips_text = $TipsPanel/TipsText

# Overview Panel
@onready var overview_panel = $OverviewPanel
@onready var overview_back_btn = $OverviewPanel/BackBtn
@onready var overview_text = $OverviewPanel/OverviewText

# About Panel
@onready var about_panel = $AboutPanel
@onready var about_back_btn = $AboutPanel/BackBtn
@onready var about_text = $AboutPanel/AboutText

# Exit Confirm Panel
@onready var exit_panel = $ExitConfirmPanel
@onready var confirm_exit_btn = $ExitConfirmPanel/ConfirmBtn
@onready var cancel_exit_btn = $ExitConfirmPanel/CancelBtn

# 📥 Pause Panel Node Overlay References
@onready var pause_panel = $PausePanel
@onready var resume_btn = $PausePanel/ResumeBtn
@onready var restart_btn = $PausePanel/RestartBtn
@onready var main_menu_exit_btn = $PausePanel/MainMenuExitBtn

# State Tracking Variables
var is_acting_as_pause_overlay: bool = false
var selected_region = 0
var selected_difficulty = ""
var enemy_regions = []
var sound_enabled = true

func _ready():
	# Allows this UI scene to process input events even while the engine tree is paused mid-match!
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_hide_all_panels()
	
	# Determine context representation state
	if is_acting_as_pause_overlay or (GameManager and GameManager.is_game_active):
		_show_pause_panel()
	else:
		_show_main_menu()
	
	# Connect main menu buttons safely
	start_btn.pressed.connect(_show_region_selection)
	settings_btn.pressed.connect(_show_settings)
	overview_btn.pressed.connect(_show_overview)
	about_btn.pressed.connect(_show_about)
	exit_btn.pressed.connect(_show_exit_confirm)
	
	# Connect region buttons
	japanese_btn.pressed.connect(_on_japanese_selected)
	mughal_btn.pressed.connect(_on_mughal_selected)
	mongol_btn.pressed.connect(_on_mongol_selected)
	region_back_btn.pressed.connect(_hide_region_selection)
	
	# Connect difficulty buttons
	vs_two_btn.pressed.connect(_on_vs_two_selected)
	vs_first_btn.pressed.connect(_on_vs_first_selected)
	vs_second_btn.pressed.connect(_on_vs_second_selected)
	difficulty_back_btn.pressed.connect(_hide_difficulty)
	
	# Connect settings buttons
	sound_btn.pressed.connect(_toggle_sound)
	controls_btn.pressed.connect(_show_controls)
	tips_btn.pressed.connect(_show_tips)
	settings_back_btn.pressed.connect(_hide_settings)
	
	# Connect sub panel back buttons
	controls_back_btn.pressed.connect(_hide_controls)
	tips_back_btn.pressed.connect(_hide_tips)
	overview_back_btn.pressed.connect(_hide_overview)
	about_back_btn.pressed.connect(_hide_about)
	
	# Connect exit buttons
	confirm_exit_btn.pressed.connect(_exit_game)
	cancel_exit_btn.pressed.connect(_hide_exit_confirm)
	
	# Connect Pause Overlay Actions safely
	if pause_panel:
		resume_btn.focus_mode = Control.FOCUS_NONE
		restart_btn.focus_mode = Control.FOCUS_NONE
		main_menu_exit_btn.focus_mode = Control.FOCUS_NONE
		
		resume_btn.pressed.connect(_on_resume_match_pressed)
		restart_btn.pressed.connect(_on_restart_match_pressed)
		main_menu_exit_btn.pressed.connect(_on_pause_exit_to_menu_pressed)
	
	# Set up text content
	_setup_controls_text()
	_setup_tips_text()
	_setup_overview_text()
	_setup_about_text()
	
	_update_sound_button()
	_style_ui()
	_make_panels_transparent()

# Call this immediately after instantiating to force pause overlay configuration layouts
func setup_as_pause_overlay():
	is_acting_as_pause_overlay = true
	_show_pause_panel()

func _make_panels_transparent():
	var panels = [
		region_panel, difficulty_panel, settings_panel, 
		controls_panel, tips_panel, overview_panel, 
		about_panel, exit_panel, pause_panel
	]
	for panel in panels:
		if panel:
			panel.self_modulate.a = 0.0

# 🛠️ FIXED CRASH: Uses get_node_or_null to safely check for GameTitle presence
func _style_ui():
	var title_node = get_node_or_null("GameTitle")
	if title_node:
		title_node.add_theme_font_size_override("font_size", 48)
		title_node.add_theme_color_override("font_color", Color.GOLD)
		title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		print("⚠️ Note: 'GameTitle' node structure not found relative to this scene root. Skipping style step.")

func _show_main_menu():
	if main_menu_container:
		main_menu_container.visible = true
	if pause_panel:
		pause_panel.visible = false

func _hide_main_menu():
	if main_menu_container:
		main_menu_container.visible = false

func _hide_all_panels():
	if region_panel: region_panel.visible = false
	if difficulty_panel: difficulty_panel.visible = false
	if settings_panel: settings_panel.visible = false
	if controls_panel: controls_panel.visible = false
	if tips_panel: tips_panel.visible = false
	if overview_panel: overview_panel.visible = false
	if about_panel: about_panel.visible = false
	if exit_panel: exit_panel.visible = false
	if pause_panel: pause_panel.visible = false

# ===== 📥 PAUSE OVERLAY ROUTINES =====
func _show_pause_panel():
	_hide_main_menu()
	_hide_all_panels()
	if pause_panel:
		pause_panel.visible = true

func _on_resume_match_pressed():
	print("⚔️ Returning to active battlefield match...")
	get_tree().paused = false  # Unpause the game simulation loop
	queue_free()               # Safely remove this overlay menu instance from memory, resuming the live game

func _on_restart_match_pressed():
	print("🔄 Re-instantiating fresh game session instance...")
	get_tree().paused = false
	if GameManager:
		GameManager.is_game_active = false
	
	var error = get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)
	if error != OK:
		print("❌ ERROR: Failed to restart game! Code: ", error)

func _on_pause_exit_to_menu_pressed():
	print("🏰 Closing pause configurations. Re-routing back to standalone Title Scene loop.")
	get_tree().paused = false
	if GameManager:
		GameManager.is_game_active = false
		
	# Force clean collection unloads by changing contexts back to a standalone instance of this scene file
	var error = get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		# Fail-safe local visibility fallback code
		_hide_all_panels()
		_show_main_menu()

# ===== REGION SELECTION =====
func _show_region_selection():
	_hide_main_menu()
	_hide_all_panels()
	region_panel.visible = true

func _hide_region_selection():
	region_panel.visible = false
	_show_main_menu()

func _on_japanese_selected():
	selected_region = 0
	_show_difficulty_for_region("Japanese")

func _on_mughal_selected():
	selected_region = 1
	_show_difficulty_for_region("Mughal")

func _on_mongol_selected():
	selected_region = 2
	_show_difficulty_for_region("Mongol")

# ===== DIFFICULTY SELECTION =====
func _show_difficulty_for_region(region: String):
	region_panel.visible = false
	difficulty_panel.visible = true
	var vt = "⚔️ "
	match region:
		"Japanese":
			vs_two_btn.text = vt + "VS Mughal + Mongol (2 Empires - Hard)"
			vs_first_btn.text = vt + "VS Mughal Empire"
			vs_second_btn.text = vt + "VS Mongol Empire"
		"Mughal":
			vs_two_btn.text = vt + "VS Japanese + Mongol (2 Empires - Hard)"
			vs_first_btn.text = vt + "VS Japanese Empire"
			vs_second_btn.text = vt + "VS Mongol Empire"
		"Mongol":
			vs_two_btn.text = vt + "VS Japanese + Mughal (2 Empires - Hard)"
			vs_first_btn.text = vt + "VS Japanese Empire"
			vs_second_btn.text = vt + "VS Mughal Empire"

func _hide_difficulty():
	difficulty_panel.visible = false
	_show_region_selection()

func _on_vs_two_selected():
	selected_difficulty = "2v1"
	_set_enemy_regions_for_difficulty()
	_start_game()

func _on_vs_first_selected():
	selected_difficulty = "vs_first"
	_set_enemy_regions_for_difficulty()
	_start_game()

func _on_vs_second_selected():
	selected_difficulty = "vs_second"
	_set_enemy_regions_for_difficulty()
	_start_game()

func _set_enemy_regions_for_difficulty():
	enemy_regions = []
	match selected_region:
		0:
			match selected_difficulty:
				"2v1": enemy_regions = [1, 2]
				"vs_first": enemy_regions = [1]
				"vs_second": enemy_regions = [2]
		1:
			match selected_difficulty:
				"2v1": enemy_regions = [0, 2]
				"vs_first": enemy_regions = [0]
				"vs_second": enemy_regions = [2]
		2:
			match selected_difficulty:
				"2v1": enemy_regions = [0, 1]
				"vs_first": enemy_regions = [0]
				"vs_second": enemy_regions = [1]

func _start_game():
	if GameData:
		GameData.set_user_region(selected_region)
		GameData.set_data({
			"user_region": selected_region,
			"enemy_regions": enemy_regions,
			"difficulty": selected_difficulty
		})
	if GameManager:
		GameManager.is_game_active = false
	
	var error = get_tree().change_scene_to_file(GAMEPLAY_SCENE_PATH)
	if error != OK:
		print("❌ ERROR: Failed to start match! Code: ", error)

# ===== SETTINGS =====
func _show_settings():
	_hide_main_menu()
	_hide_all_panels()
	settings_panel.visible = true

func _hide_settings():
	settings_panel.visible = false
	_show_main_menu()

func _toggle_sound():
	sound_enabled = !sound_enabled
	_update_sound_button()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not sound_enabled)

func _update_sound_button():
	sound_btn.text = "🔊 Sound: ON" if sound_enabled else "🔇 Sound: OFF"

func _show_controls():
	settings_panel.visible = false
	controls_panel.visible = true

func _hide_controls():
	controls_panel.visible = false
	settings_panel.visible = true

func _show_tips():
	settings_panel.visible = false
	tips_panel.visible = true

func _hide_tips():
	tips_panel.visible = false
	settings_panel.visible = true

# ===== OVERVIEW =====
func _show_overview():
	_hide_main_menu()
	_hide_all_panels()
	overview_panel.visible = true

func _hide_overview():
	overview_panel.visible = false
	_show_main_menu()

# ===== ABOUT =====
func _show_about():
	_hide_main_menu()
	_hide_all_panels()
	about_panel.visible = true

func _hide_about():
	about_panel.visible = false
	_show_main_menu()

# ===== EXIT =====
func _show_exit_confirm():
	_hide_main_menu()
	_hide_all_panels()
	exit_panel.visible = true

func _hide_exit_confirm():
	exit_panel.visible = false
	_show_main_menu()

func _exit_game():
	get_tree().quit()

# ===== TEXT CONTENT SETUP =====
func _setup_controls_text():
	if controls_text:
		controls_text.bbcode_enabled = true
		controls_text.text = "[center][b]🎮 CONTROLS GUIDE[/b][/center]\n\n"
		controls_text.text += "[color=yellow]Camera Controls:[/color]\n• Arrow Keys / WASD - Move\n• Mouse Wheel - Zoom\n\n[color=yellow]Unit Controls:[/color]\n• Left Click - Select\n• Right Click - Move/Attack"

func _setup_tips_text():
	if tips_text:
		tips_text.bbcode_enabled = true
		tips_text.text = "[center][b]💡 GAME TIPS[/b][/center]\n\n[color=yellow]Resource Management:[/color]\n• Wood -> Trees\n• Food -> Bushes\n• Coin -> Stones"

func _setup_overview_text():
	if overview_text:
		overview_text.bbcode_enabled = true
		overview_text.text = "[center][b]🏛️ GENERATIONAL BUILDINGS[/b][/center]\n\nProgress through historical ages by constructing unique monuments."

func _setup_about_text():
	if about_text:
		about_text.bbcode_enabled = true
		about_text.text = "[center][b]🏯 AGE OF EMPIRES[/b][/center]\n[center]Godot Engine Strategy Remaster[/center]\n\n© 2026 - All Rights Reserved"
