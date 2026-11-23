extends CanvasLayer
## Release Store update checker (autoload as "UpdateChecker").
##
## At startup it asks your Release Store whether a newer release exists. It tries the
## store's home-network address first, then its Tailscale address (works anywhere when
## Tailscale is on). If neither answers it asks GitHub directly. If there
## is a newer version it shows a popup with "Update" / "Later". On Android "Update" downloads the
## APK inside the game (with a progress bar) and opens Android's installer, which installs it over
## the old version (the first time Android asks to allow installing apps from this game). If the
## download fails it falls back to opening the link in the browser. On PC it opens the store page.
##
## Android export preset: permissions/internet=true and permissions/custom_permissions containing
## "android.permission.REQUEST_INSTALL_PACKAGES" (godot_release.py --wire sets both).
##
## Project settings:
##   application/config/version   this build's version, e.g. "1.2.0".
##                                Keep it the same as Android "version/name" in the export preset.
##   update_checker/repo          "owner/repo" on GitHub
##   update_checker/store_url     e.g. "http://192.168.0.97:8787"; several, comma-separated,
##                                are tried in order (default: DEFAULT_STORES)
##   update_checker/language      "sv" or "en" (default: the device's language)
##   update_checker/key           the store's access key; needed for private repos
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
var _dl: HTTPRequest
var _bar: ProgressBar
var _status: Label
var _was_paused := false
var _sv := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sv = str(ProjectSettings.get_setting("update_checker/language", OS.get_locale_language())) == "sv"
	if OS.has_feature("web"):
		return  # the web version is always the latest
	if FileAccess.file_exists(_apk_path()):
		DirAccess.remove_absolute(_apk_path())  # left over from the last update
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
	var key := str(ProjectSettings.get_setting("update_checker/key", ""))
	var q := "&key=" + key.uri_encode() if key != "" else ""
	var d = await _get_json("%s/api/update/%s?platform=%s%s" % [store, repo, platform(), q])
	if not d is Dictionary or not d.has("version"):
		return {}
	var url := ""
	var apk := false
	if platform() == "android" and d.get("download_url"):
		url = str(d.download_url)
		if url.begins_with("/"):
			url = store + url + ("?" + q.substr(1) if q != "" else "")
		apk = true
	else:
		url = store + str(d.store_page)  # on PC the store page has Install / Download
	return {"version": str(d.version), "name": str(d.name), "notes": str(d.notes), "url": url, "source": "store", "apk": apk}


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
		"notes": str(d.get("body", "")), "url": url, "source": "github", "apk": url.to_lower().ends_with(".apk")}


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
		if platform() == "android" and u.get("apk", false):
			_download(u, box, row, fs)
		else:
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


# ------------------------------------------------------------------ in-app download + install (Android)

func _apk_path() -> String:
	return OS.get_user_data_dir().path_join("update.apk")


## Swap the popup's buttons for a progress bar, download the APK into the game's own files
## and hand it to Android's package installer (Godot opens local files through its FileProvider).
func _download(u: Dictionary, box: VBoxContainer, row: HBoxContainer, fs: int) -> void:
	for c in row.get_children():
		c.queue_free()
	_status = _label("Laddar ner…" if _sv else "Downloading…", int(fs * 0.85))
	box.add_child(_status)
	box.move_child(_status, row.get_index())
	_bar = ProgressBar.new()
	_bar.custom_minimum_size.y = fs * 0.9
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.42, 0.56, 1.0)
	fill.set_corner_radius_all(int(fs * 0.45))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(int(fs * 0.45))
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_bar)
	box.move_child(_bar, row.get_index())
	var cancel := _button("Avbryt" if _sv else "Cancel", fs, false)
	cancel.pressed.connect(func():
		if _dl:
			_dl.cancel_request()
			_dl.queue_free()
			_dl = null
		_close())
	row.add_child(cancel)

	_dl = HTTPRequest.new()
	_dl.use_threads = true
	_dl.download_file = _apk_path()
	_dl.timeout = 300.0
	add_child(_dl)
	_dl.request_completed.connect(func(result: int, code: int, _h, _b):
		_finish_download(result, code, u, row, fs))
	if _dl.request(u.url) != OK:
		_finish_download(HTTPRequest.RESULT_CANT_CONNECT, 0, u, row, fs)


func _process(_delta: float) -> void:
	if _dl and _bar and is_instance_valid(_bar):
		var total := _dl.get_body_size()
		var got := _dl.get_downloaded_bytes()
		if total > 0:
			_bar.value = 100.0 * got / total
			_status.text = ("Laddar ner… %d av %d MB" if _sv else "Downloading… %d of %d MB") % [got / 1048576, max(1, total / 1048576)]


func _finish_download(result: int, code: int, u: Dictionary, row: HBoxContainer, fs: int) -> void:
	if _dl:
		_dl.queue_free()
		_dl = null
	if not _ui or not is_instance_valid(row):
		return  # cancelled
	for c in row.get_children():
		c.queue_free()
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(_apk_path()) \
		and FileAccess.get_file_as_bytes(_apk_path()).slice(0, 2) == PackedByteArray([0x50, 0x4B])  # an APK is a zip
	if not ok:
		print("[UpdateChecker] download failed: result %d, HTTP %d" % [result, code])
		_status.text = "Nedladdningen misslyckades. Öppnar i webbläsaren i stället." if _sv else "Download failed. Opening it in the browser instead."
		var later := _button("Stäng" if _sv else "Close", fs, false)
		later.pressed.connect(_close)
		row.add_child(later)
		OS.shell_open(u.url)
		return
	_bar.value = 100
	_status.text = "Klar! Tryck Installera i rutan som kommer upp." if _sv else "Done! Tap Install in the dialog that opens."
	var close := _button("Stäng" if _sv else "Close", fs, false)
	close.pressed.connect(_close)
	row.add_child(close)
	var inst := _button("Installera" if _sv else "Install", fs, true)
	inst.pressed.connect(_install)
	row.add_child(inst)
	inst.grab_focus()
	_install()


func _install() -> void:
	var err := OS.shell_open(_apk_path())
	if err != OK:
		print("[UpdateChecker] could not open the installer: %d" % err)


func _close() -> void:
	_bar = null
	_status = null
	if _ui:
		_ui.queue_free()
		_ui = null
	get_tree().paused = _was_paused
