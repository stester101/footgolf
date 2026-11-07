class_name TestCase
extends RefCounted
## Minimal dependency-free test base. Methods named test_* are run by tests/run_tests.gd.

var failures: Array[String] = []
var current_test := ""
var notes: Array[String] = []


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func note(msg: String) -> void:
	notes.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(a, b, msg: String = "") -> void:
	if a != b:
		fail("%s expected %s == %s" % [msg, str(a), str(b)])


func assert_near(a: float, b: float, tol: float, msg: String = "") -> void:
	if not (absf(a - b) <= tol):
		fail("%s expected %.6f within %.6f of %.6f (diff %.6f)" % [msg, a, tol, b, a - b])


func assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		fail("%s expected %.6f < %.6f" % [msg, a, b])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	if not (a > b):
		fail("%s expected %.6f > %.6f" % [msg, a, b])
