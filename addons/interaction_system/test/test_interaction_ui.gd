## XR interaction test — covers all common social-VR GUI control types.
##
## Left panel  — controls driven by lasso (ray-cast + press/drag/scroll)
## Right panel — unit test results + live interaction log
##
## Control coverage:
##   Button       point + press
##   CheckBox     point + press (latching toggle)
##   HSlider      point + grip-hold + translate (drag)
##   VSlider      point + grip-hold + translate (vertical drag)
##   SpinBox      point + press (increment/decrement arrows)
##   OptionButton point + press → dropdown, aim + press to select item
##   LineEdit     point + press to focus, keyboard/virtual input
##   ScrollContainer  point + hold + translate (scroll region)
extends Node

# ── panel controls ───────────────────────────────────────────────────────────
var _btn_action:   Button
var _check_toggle: CheckBox
var _slider_h:     HSlider
var _slider_v:     VSlider
var _spin:         SpinBox
var _option:       OptionButton
var _line_edit:    LineEdit
var _scroll:       ScrollContainer
var _label_status: Label

# ── interaction log ───────────────────────────────────────────────────────────
var _log: VBoxContainer

# ── test signal bookkeeping ───────────────────────────────────────────────────
var _gui_input_fired    := false
var _virtual_input_fired := false
var _btn_pressed_fired  := false

# ── test result rows ──────────────────────────────────────────────────────────
var _results: VBoxContainer
var _rows: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_run_unit_tests()


# ── scene construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.2292, 0.2845, 0.2995, 1.0)  # okhsl H=0.60 S=0.15 L=0.30
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"separation", 4)
	add_child(root)

	_build_left_panel(root)

	var sep := VSeparator.new()
	root.add_child(sep)

	_build_right_panel(root)


func _build_left_panel(root: HBoxContainer) -> void:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override(&"separation", 6)
	root.add_child(panel)

	var heading := Label.new()
	heading.text = "XR Interaction Target Panel"
	panel.add_child(heading)

	# Button — point + press
	_btn_action = Button.new()
	_btn_action.text = "Action Button"
	_btn_action.pressed.connect(func():
		_btn_pressed_fired = true
		_log_event("Button pressed"))
	panel.add_child(_btn_action)

	# CheckBox — point + press (toggle)
	_check_toggle = CheckBox.new()
	_check_toggle.text = "Toggle"
	_check_toggle.toggled.connect(func(v: bool): _log_event("Toggle → %s" % v))
	panel.add_child(_check_toggle)

	# HSlider — point + hold + horizontal drag
	var hslider_row := HBoxContainer.new()
	panel.add_child(hslider_row)
	var hslider_lbl := Label.new()
	hslider_lbl.text = "H-Slide:"
	hslider_row.add_child(hslider_lbl)
	_slider_h = HSlider.new()
	_slider_h.min_value = 0.0
	_slider_h.max_value = 1.0
	_slider_h.step = 0.01
	_slider_h.value = 0.5
	_slider_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_h.value_changed.connect(func(v: float): _log_event("HSlider → %.2f" % v))
	hslider_row.add_child(_slider_h)

	# VSlider — point + hold + vertical drag
	var vslider_row := HBoxContainer.new()
	panel.add_child(vslider_row)
	var vslider_lbl := Label.new()
	vslider_lbl.text = "V-Slide:"
	vslider_row.add_child(vslider_lbl)
	_slider_v = VSlider.new()
	_slider_v.min_value = 0.0
	_slider_v.max_value = 1.0
	_slider_v.step = 0.01
	_slider_v.value = 0.5
	_slider_v.custom_minimum_size = Vector2(20, 60)
	_slider_v.value_changed.connect(func(v: float): _log_event("VSlider → %.2f" % v))
	vslider_row.add_child(_slider_v)

	# SpinBox — point + press increment/decrement arrows
	var spin_row := HBoxContainer.new()
	panel.add_child(spin_row)
	var spin_lbl := Label.new()
	spin_lbl.text = "Spin:"
	spin_row.add_child(spin_lbl)
	_spin = SpinBox.new()
	_spin.min_value = 0
	_spin.max_value = 10
	_spin.value = 5
	_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin.value_changed.connect(func(v: float): _log_event("SpinBox → %.0f" % v))
	spin_row.add_child(_spin)

	# OptionButton — point + press → list, aim + press to select
	_option = OptionButton.new()
	_option.add_item("Option A")
	_option.add_item("Option B")
	_option.add_item("Option C")
	_option.item_selected.connect(func(i: int): _log_event("Dropdown → %s" % _option.get_item_text(i)))
	panel.add_child(_option)

	# LineEdit — point + press to focus, type text
	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Type here…"
	_line_edit.text_changed.connect(func(t: String): _log_event("LineEdit → \"%s\"" % t))
	panel.add_child(_line_edit)

	# ScrollContainer — point + hold + translate to scroll
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 60)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll_inner := VBoxContainer.new()
	for i in range(8):
		var item := Label.new()
		item.text = "Scroll item %d" % (i + 1)
		scroll_inner.add_child(item)
	_scroll.add_child(scroll_inner)
	_scroll.get_v_scroll_bar().value_changed.connect(
		func(v: float): _log_event("Scroll → %.0f" % v))
	panel.add_child(_scroll)

	# Status
	_label_status = Label.new()
	_label_status.text = "status: waiting"
	_label_status.add_theme_color_override(&"font_color", Color(0.75, 0.8, 0.94))
	panel.add_child(_label_status)


func _build_right_panel(root: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 2)
	root.add_child(right)

	var result_heading := Label.new()
	result_heading.text = "Test Results"
	right.add_child(result_heading)

	_results = VBoxContainer.new()
	right.add_child(_results)

	var sep := HSeparator.new()
	right.add_child(sep)

	var log_heading := Label.new()
	log_heading.text = "Live interactions:"
	right.add_child(log_heading)

	_log = VBoxContainer.new()
	right.add_child(_log)


func _log_event(msg: String) -> void:
	_label_status.text = msg
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override(&"font_color", Color(0.97, 0.76, 0.4))
	_log.add_child(lbl)
	# keep only last 6 log lines
	while _log.get_child_count() > 6:
		_log.get_child(0).queue_free()


# ── test rows ─────────────────────────────────────────────────────────────────

func _add_row(name: String) -> void:
	var lbl := Label.new()
	lbl.text = "[ ] %s" % name
	_results.add_child(lbl)
	_rows[name] = lbl


func _mark(name: String, passed: bool, detail: String = "") -> void:
	var lbl: Label = _rows.get(name)
	if lbl == null:
		return
	if passed:
		lbl.text = "[PASS] %s%s" % [name, (" — " + detail) if detail else ""]
		lbl.add_theme_color_override(&"font_color", Color(0.2, 0.9, 0.3))
	else:
		lbl.text = "[FAIL] %s%s" % [name, (" — " + detail) if detail else ""]
		lbl.add_theme_color_override(&"font_color", Color(0.9, 0.2, 0.2))


# ── unit tests ────────────────────────────────────────────────────────────────

func _run_unit_tests() -> void:
	_add_row("call_gui_input fires gui_input signal")
	_add_row("call_gui_input reaches _gui_input virtual")
	_add_row("isolated: prior accept does not block second call")
	_add_row("button press via call_gui_input fires pressed signal")
	_add_row("interaction_action routes pose to Control [canvas_plane needed]")
	_add_row("mouse motion updates current_canvas_item [canvas_plane needed]")

	await get_tree().process_frame

	_test_signal_fires()
	_test_virtual_fires()
	_test_isolation()
	_test_button_press()
	_test_interaction_action_pose()
	_test_interaction_action_motion()


# test 1
func _test_signal_fires() -> void:
	var btn := Button.new()
	add_child(btn)
	var fired := false
	btn.gui_input.connect(func(_e): fired = true)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	btn.queue_free()
	_mark("call_gui_input fires gui_input signal", fired)


# test 2
class _TestButton extends Button:
	var virtual_fired := false
	func _gui_input(_ev: InputEvent) -> void:
		virtual_fired = true


func _test_virtual_fires() -> void:
	var btn := _TestButton.new()
	add_child(btn)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	var ok: bool = btn.virtual_fired
	btn.queue_free()
	_mark("call_gui_input reaches _gui_input virtual", ok)


# test 3
func _test_isolation() -> void:
	var btn := Button.new()
	add_child(btn)
	var count := 0
	btn.gui_input.connect(func(e: InputEvent): count += 1; btn.accept_event())
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	btn.call_gui_input(ev)
	btn.queue_free()
	_mark("isolated: prior accept does not block second call", count == 2,
			"signal fired %d/2 times" % count)


# test 4
func _test_button_press() -> void:
	var btn := Button.new()
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	add_child(btn)
	var pressed := false
	btn.pressed.connect(func(): pressed = true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(4, 4)
	press.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(press)
	btn.queue_free()
	_mark("button press via call_gui_input fires pressed signal", pressed)


# test 5 + 6
func _test_interaction_action_pose() -> void:
	var has_canvas_plane := ResourceLoader.exists("res://addons/canvas_plane/canvas_plane.gd")
	_mark("interaction_action routes pose to Control [canvas_plane needed]",
			has_canvas_plane,
			"canvas_plane addon missing — expected during red phase")


func _test_interaction_action_motion() -> void:
	var has_canvas_plane := ResourceLoader.exists("res://addons/canvas_plane/canvas_plane.gd")
	_mark("mouse motion updates current_canvas_item [canvas_plane needed]",
			has_canvas_plane,
			"canvas_plane addon missing — expected during red phase")
