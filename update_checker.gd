extends CanvasLayer
## Release Store update checker (autoload as "UpdateChecker").
##
## At startup it asks your Release Store whether a newer release exists. It tries the
## store's home-network address first, then its Tailscale address (works anywhere when
## Tailscale is on). If neither answers it asks GitHub directly. If there
## is a newer version it shows a popup with "Update" / "Later". "Update" opens the
## download in the phone's browser; when it finishes, tap it to install over the old version.
##
## Project settings:
##   application/config/version   this build's version, e.g. "1.2.0".
##                                Keep it the same as Android "version/name" in the export preset.
##   update_checker/repo          "owner/repo" on GitHub
##   update_checker/store_url     e.g. "http://192.168.0.97:8787"; several, comma-separated,
##                                are tried in order (default: DEFAULT_STORES)
##   update_checker/language      "sv" or "en" (default: the device's language)
##
## It only runs in exported builds. To test from the editor/command line:
##   godot --path . -- --update-check            (use real version)
##   godot --path . -- --update-check-as=0.0.1   (pretend to be an old version)
##
## Manual check from a menu button:  UpdateChecker.check(true, true)
## (shows "you have the latest version" / "couldn't check" too). While it runs, `busy` is true
## and button_text() returns "Checking…", so a menu can show that.

signal check_finished(update: Dictionary)  ## empty Dictionary = up to date / unreachable

const DEFAULT_STORES := "http://192.168.0.97:8787,http://100.85.197.108:8787"  # home Wi-Fi, Tailscale
const TIMEOUT := 5.0

var busy := false
var _ui: Control
var _was_paused := false
var _sv := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sv = str(ProjectSettings.get_setting("update_checker/language", OS.get_locale_language())) == "sv"
	if OS.has_feature("web"):
		return  # the web version is always the latest
	if not OS.has_feature("template") and not _forced():
		return  # don't nag while developing in the editor
	await get_tree().create_timer(1.5).timeout
	check()


func _forced() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-check"):
			return true
	return false


func current_version() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-check-as="):
			return a.get_slice("=", 1)
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("macos"):
		return "mac"
	return "linux"


## Text for a menu button: "Check for updates" or "Checking…" (Swedish if the device is).
func button_text() -> String:
	if busy:
		return "Söker..." if _sv else "Checking..."
	return "Sök efter uppdatering" if _sv else "Check for updates"


## Checks for an update and shows the popup if one is found. With manual = true it also
## tells you when you're up to date or the check failed.
## Returns {version, name, notes, url, source} or {} if up to date / offline.
func check(show_popup := true, manual := false) -> Dictionary:
	var repo := str(ProjectSettings.get_setting("update_checker/repo", ""))
	if repo == "" or busy:
		if repo == "":
			push_warning("UpdateChecker: set update_checker/repo in Project Settings")
		return {}
	busy = true
	var latest := {}
	for store in str(ProjectSettings.get_setting("update_checker/store_url", DEFAULT_STORES)).split(",", false):
		latest = await _from_store(store.strip_edges().trim_suffix("/"), repo)
		if not latest.is_empty():
			break
	if latest.is_empty():
		latest = await _from_github(repo)
	busy = false
	var result := {}
	if latest.is_empty():
		print("[UpdateChecker] could not reach store or GitHub")
		if manual and show_popup:
			_dialog("Kunde inte söka" if _sv else "Couldn't check for updates",
				"Är du ansluten till internet?" if _sv else "Are you connected to the internet?", "", {})
	elif is_newer(latest.version, current_version()):
		result = latest
		print("[UpdateChecker] update available: %s -> %s via %s (%s)" % [current_version(), latest.version, latest.source, latest.url])
		if show_popup and latest.url != "":
			_show(latest)
	else:
		print("[UpdateChecker] up to date (%s, latest %s)" % [current_version(), latest.version])
		if manual and show_popup:
			_dialog("Du har senaste versionen" if _sv else "You're up to date",
				"Version %s" % current_version(), "", {})
	check_finished.emit(result)
	return result


func _from_store(store: String, repo: String) -> Dictionary:
	var d = await _get_json("%s/api/update/%s?platform=%s" % [store, repo, platform()])
	if not d is Dictionary or not d.has("version"):
		return {}
	var url := ""
	if platform() == "android" and d.get("download_url"):
		url = str(d.download_url)
		if url.begins_with("/"):
			url = store + url
	else:
		url = store + str(d.store_page)  # on PC the store page has Install / Download
	return {"version": str(d.version), "name": str(d.name), "notes": str(d.notes), "url": url, "source": "store"}


func _from_github(repo: String) -> Dictionary:
	var d = await _get_json("https://api.github.com/repos/%s/releases/latest" % repo)
	if not d is Dictionary or not d.has("tag_name"):
		return {}
	var url := str(d.html_url)
	var want: Array = {"android": [".apk"], "windows": ["windows", ".exe"], "linux": ["linux", ".appimage"], "mac": ["mac", ".dmg"]}[platform()]
	if platform() == "android":
		for a in d.get("assets", []):
			var n := str(a.name).to_lower()
			for w in want:
				if w in n:
					url = str(a.browser_download_url)
	var tag := str(d.tag_name)
	return {"version": tag.trim_prefix("v").trim_prefix("V"), "name": str(d.get("name", tag)),
		"notes": str(d.get("body", "")), "url": url, "source": "github"}


func _get_json(url: String):
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	var err := req.request(url, ["Accept: application/json"])
	if err != OK:
		req.queue_free()
		return null
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


## True if version a is newer than b ("1.10.0" > "1.9.2", "v2.0" > "1.9").
static func is_newer(a: String, b: String) -> bool:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in max(pa.size(), pb.size()):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return x > y
	return false


static func _parts(v: String) -> Array[int]:
	var out: Array[int] = []
	for p in v.strip_edges().trim_prefix("v").trim_prefix("V").get_slice("-", 0).split("."):
		out.append(p.to_int())
	return out


# ------------------------------------------------------------------ popup

## The first section of the release notes ("What's new"), without markdown, max 6 lines.
func _clean_notes(md: String) -> String:
	var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")  # [text](link) -> text
	var bullet := RegEx.create_from_string("^[-*+]\\s+")
	var marks := RegEx.create_from_string("[#*`_>]+")
	var lines := PackedStringArray()
	for raw in md.split("\n"):
		var l := raw.strip_edges()
		if l.begins_with("#"):  # a heading: skip the first, stop at the next
			if lines.size() > 0:
				break
			continue
		l = marks.sub(bullet.sub(link.sub(l, "$1", true), "• "), "", true).strip_edges()
		if l != "":
			lines.append(l)
		if lines.size() >= 6:
			break
	var text := "\n".join(lines)
	return text.left(320) + ("…" if text.length() > 320 else "")


func _show(u: Dictionary) -> void:
	var notes := _clean_notes(u.notes)
	if notes == "":
		notes = u.name
	_dialog("Ny version finns!" if _sv else "Update available", "%s  →  %s" % [current_version(), u.version], notes, u)


## A popup. With an update (u not empty): "Later" / "Update"; otherwise just "OK".
func _dialog(title_text: String, sub_text: String, body_text: String, u: Dictionary) -> void:
	if _ui:
		_ui.queue_free()
	_was_paused = get_tree().paused
	get_tree().paused = true

	var vp := get_viewport().get_visible_rect().size
	var fs := int(clamp(min(vp.x, vp.y) / 24.0, 14.0, 48.0))

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16)
	sb.set_corner_radius_all(fs)
	sb.set_content_margin_all(fs * 1.2)
	sb.border_color = Color(0.42, 0.56, 1.0, 0.5)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = min(vp.x * 0.88, fs * 22.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(fs * 0.6))
	panel.add_child(box)

	box.add_child(_label(title_text, int(fs * 1.35)))
	var sub := _label(sub_text, fs)
	sub.modulate = Color(0.65, 0.75, 1.0)
	box.add_child(sub)
	if body_text != "":
		var body := _label(body_text, int(fs * 0.8))
		body.modulate = Color(0.85, 0.87, 0.92)
		box.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(fs * 0.6))
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	if u.is_empty():
		var ok := _button("OK", fs, true)
		ok.pressed.connect(_close)
		row.add_child(ok)
		ok.grab_focus()
		return
	var later := _button("Senare" if _sv else "Later", fs, false)
	later.pressed.connect(_close)
	row.add_child(later)
	var go := _button("Uppdatera" if _sv else "Update", fs, true)
	go.pressed.connect(func():
		OS.shell_open(u.url)
		_close())
	row.add_child(go)
	go.grab_focus()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, size: int, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(size * 5.5, size * 2.2)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(size * 2)
		if primary:
			sb.bg_color = Color(0.42, 0.56, 1.0) if state != "pressed" else Color(0.34, 0.46, 0.85)
		else:
			sb.bg_color = Color(1, 1, 1, 0.08 if state != "pressed" else 0.16)
		if state == "focus":
			sb.draw_center = false
			sb.border_color = Color(1, 1, 1, 0.5)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	if primary:
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color(0.04, 0.05, 0.08))
	return b


func _close() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
	get_tree().paused = _was_paused
