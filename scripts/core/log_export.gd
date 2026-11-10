class_name LogExport
extends RefCounted
## Builds a shareable plain-text diagnostics file (recent engine log lines plus build and device info)
## so a tester can send it without a computer. Pure helpers are static and unit-tested.

const LOG_PATH := "user://logs/godot.log"
const OUT_DIR := "user://export"
const MAX_LINES := 400


## Last `max_lines` lines of `text` (whole text when shorter). CRLF is normalised.
static func tail_lines(text: String, max_lines: int = MAX_LINES) -> String:
	var lines := text.replace("\r\n", "\n").split("\n")
	while not lines.is_empty() and lines[lines.size() - 1] == "":
		lines.remove_at(lines.size() - 1)
	if max_lines > 0 and lines.size() > max_lines:
		lines = lines.slice(lines.size() - max_lines)
	return "\n".join(lines)


static func build_report(header: String, log_text: String, max_lines: int = MAX_LINES) -> String:
	var body := tail_lines(log_text, max_lines)
	if body == "":
		body = "(no log lines available on this device)"
	return "%s\n\n--- recent log ---\n%s\n" % [header.strip_edges(), body]


static func read_log(path: String = LOG_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


## Writes the report to <dir>/football-golf-log.txt. Returns {ok, path, error}.
static func export_to(dir: String, header: String, log_text: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("football-golf-log.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": path, "error": "cannot write file"}
	f.store_string(build_report(header, log_text))
	f.close()
	return {"ok": true, "path": ProjectSettings.globalize_path(path), "error": ""}
