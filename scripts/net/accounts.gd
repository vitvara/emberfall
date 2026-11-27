class_name Accounts
extends RefCounted
## Realm accounts, stored on the server only (user://accounts.json).
## Passwords are never stored: each account keeps a random salt and a PBKDF2-HMAC-SHA256 hash.

const PATH := "user://accounts.json"
const ITERATIONS := 12000

var _db := {}
var _crypto := Crypto.new()


func _init() -> void:
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_db = data


func count() -> int:
	return _db.size()


static func valid_name(n: String) -> String:
	if n.length() < 3 or n.length() > 16:
		return "Name must be 3-16 characters."
	var re := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	if re.search(n) == null:
		return "Name may use letters, numbers and _ only."
	return ""


static func valid_password(p: String) -> String:
	if p.length() < 6:
		return "Password must be at least 6 characters."
	if p.length() > 128:
		return "Password is too long."
	return ""


## Returns "" on success, otherwise the reason.
func register(user: String, password: String) -> String:
	var err := valid_name(user)
	if err == "":
		err = valid_password(password)
	if err != "":
		return err
	var key := user.to_lower()
	if _db.has(key):
		return "That name is already taken."
	var salt := _crypto.generate_random_bytes(16)
	_db[key] = {"name": user, "salt": salt.hex_encode(), "iter": ITERATIONS,
		"hash": _pbkdf2(password, salt, ITERATIONS).hex_encode(), "created": Time.get_datetime_string_from_system(true)}
	_save()
	return ""


## Returns the account's display name on success, or "" if the name/password is wrong.
func verify(user: String, password: String) -> String:
	var rec: Dictionary = _db.get(user.to_lower(), {})
	if rec.is_empty():
		_pbkdf2(password, PackedByteArray([1, 2, 3]), ITERATIONS)  # same work either way
		return ""
	var expect: PackedByteArray = String(rec["hash"]).hex_decode()
	var got := _pbkdf2(password, String(rec["salt"]).hex_decode(), int(rec["iter"]))
	return String(rec["name"]) if _same(expect, got) else ""


func _save() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(_db, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))


func _pbkdf2(password: String, salt: PackedByteArray, iters: int) -> PackedByteArray:
	var key := password.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	var out := u.duplicate()
	for i in range(1, iters):
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		for j in out.size():
			out[j] = out[j] ^ u[j]
	return out


static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0
