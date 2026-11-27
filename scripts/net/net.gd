extends Node
## Realm networking: connection, accounts, the party lobby and the in-raid data flow. Autoloaded as "Net".
##
## A realm is a dedicated server (./run.sh server). Players type the realm address, connect, then log in
## or register. The link is encrypted with DTLS (the realm makes a self-signed certificate on first start).
## The party has 5 open slots: anyone can take a slot and pick any class; the leader can add bots of any
## class, and empty slots are filled with bots (missing tank / healer first) when the raid starts.
## In the raid the realm runs the only simulation; clients send movement / target / skill presses and get
## snapshots (~20/s) plus visual events back.

signal lobby_changed
signal chat_received(from: String, text: String, color: Color)
signal status_changed(text: String)
signal connected
signal auth_result(ok: bool, message: String)
signal raid_started(roster: Array)
signal back_in_lobby
signal disconnected(reason: String)
signal ability_failed(text: String)
signal rejoin_offered(info: Dictionary)
signal vote_changed(state: Dictionary)

const DEFAULT_PORT := 24565
const SNAPSHOT_RATE := 0.05
const PARTY_SIZE := 5
const AUTH_TIMEOUT := 120.0
const MAX_FAILED_LOGINS := 5
const VOTE_TIME := 30.0
const VOTE_COOLDOWN := 20.0
const EMPTY_RAID_GRACE := 180.0  # a raid with nobody connected waits this long for someone to rejoin

var mode := "offline"  # offline | host | client | dedicated
var my_name := ""
var logged_in := false
var realm_address := ""
## slots: [{peer (0 = none), bot (bool), class ("" = not chosen), away (account that dropped out mid-raid)}]
## names: {peer_id: account name}
var lobby := {"slots": [], "names": {}, "leader": 0, "in_raid": false}
var main  # main.gd, set by main
var accounts: Accounts
var _authed := {}      # server: peer -> account name
var _joined_at := {}   # server: peer -> seconds since start when they connected
var _failed := {}      # server: peer -> failed login count
var _clock := 0.0
var _snap_t := 0.0
var _input_t := 0.0
var _vote := {}         # server: {by, yes: [peers], no: [peers], t}
var _vote_cd := 0.0
var _empty_t := 0.0
var _snap_max := 0     # server: biggest snapshot (bytes, compressed) since the last log line
var _snap_log_t := 0.0
var vote_state := {}    # client: last vote state from the realm


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach that realm."))
	multiplayer.server_disconnected.connect(func(): _fail("The realm closed the connection."))


func is_net() -> bool:
	return mode != "offline"


func is_server() -> bool:
	return mode == "host" or mode == "dedicated"


func is_client() -> bool:
	return mode == "client"


func my_id() -> int:
	return multiplayer.get_unique_id() if is_net() else 1


func is_leader() -> bool:
	return is_net() and int(lobby["leader"]) == my_id()


func my_slot() -> int:
	var slots: Array = lobby["slots"]
	for i in slots.size():
		if int(slots[i]["peer"]) == my_id():
			return i
	return -1


## Round-trip time to the realm in milliseconds (-1 when not connected as a client).
func latency_ms() -> int:
	if not is_client():
		return -1
	var p := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if p == null or p.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return -1
	var server := p.get_peer(1)
	if server == null:
		return -1
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## "● 42 ms" text and a traffic-light colour for UI.
func latency_text() -> Array:
	var ms := latency_ms()
	if ms < 0:
		return ["", Color.WHITE]
	var c := Color(0.35, 0.95, 0.4)
	if ms >= 150:
		c = Color(1, 0.35, 0.3)
	elif ms >= 80:
		c = Color(1, 0.85, 0.3)
	return ["● %d ms" % ms, c]


static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


static func empty_slots() -> Array:
	var slots: Array = []
	for i in PARTY_SIZE:
		slots.append({"peer": 0, "bot": false, "class": "", "away": ""})
	return slots


# ------------------------------------------------------------------ session

## Start a realm. dedicated = headless server with accounts; otherwise a listen host (dev only).
func host(port: int, player_name: String, dedicated := false) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 16)
	if err != OK:
		return "Could not open port %d (error %d)." % [port, err]
	var tls := _server_tls()
	if tls != null:
		peer.host.dtls_server_setup(tls)
	multiplayer.multiplayer_peer = peer
	mode = "dedicated" if dedicated else "host"
	my_name = player_name
	accounts = Accounts.new()
	lobby = {"slots": empty_slots(), "names": {}, "leader": 0, "in_raid": false}
	if not dedicated:
		lobby["names"][1] = player_name
		lobby["leader"] = 1
		_authed[1] = player_name
		logged_in = true
	_lobby_updated()
	return ""


## Connect to a realm (encrypted). The login screen follows once `connected` fires.
func connect_realm(address: String, port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Could not connect (error %d)." % err
	peer.host.dtls_client_setup(address, TLSOptions.client_unsafe())
	multiplayer.multiplayer_peer = peer
	mode = "client"
	realm_address = "%s:%d" % [address, port]
	status_changed.emit("Connecting to %s ..." % realm_address)
	return ""


func login(user: String, password: String) -> void:
	if is_client():
		req_login.rpc_id(1, user, password)


func register_account(user: String, password: String) -> void:
	if is_client():
		req_create_account.rpc_id(1, user, password)


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	logged_in = false
	_authed.clear()
	_joined_at.clear()
	_failed.clear()
	_vote.clear()
	vote_state = {}
	lobby = {"slots": [], "names": {}, "leader": 0, "in_raid": false}


func _fail(reason: String) -> void:
	leave()
	disconnected.emit(reason)


func _on_connected() -> void:
	status_changed.emit("Connected to %s" % realm_address)
	connected.emit()


func _on_peer_connected(id: int) -> void:
	if is_server():
		_joined_at[id] = _clock


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	_joined_at.erase(id)
	_failed.erase(id)
	var was_authed := _authed.has(id)
	_authed.erase(id)
	if not was_authed:
		return
	var nm: String = lobby["names"].get(id, "Someone")
	lobby["names"].erase(id)
	var in_raid := false
	for s in lobby["slots"]:
		if int(s["peer"]) == id:
			s["peer"] = 0
			s["bot"] = lobby["in_raid"]  # mid-raid a bot plays their hero until they come back
			if s["bot"]:
				s["away"] = nm
				in_raid = true
			else:
				s["class"] = ""
	if int(lobby["leader"]) == id:
		lobby["leader"] = _next_leader()
	if main and main.world and lobby["in_raid"]:
		main.world_peer_left(id)
	_server_chat("%s left the realm.%s" % [nm, "  A bot covers for them until they rejoin." if in_raid else ""])
	_lobby_updated()
	_vote_check()


func _next_leader() -> int:
	for s in lobby["slots"]:
		if int(s["peer"]) != 0:
			return int(s["peer"])
	var ids: Array = lobby["names"].keys()
	return int(ids[0]) if not ids.is_empty() else 0


## Self-signed certificate for DTLS, created once and kept in the server's user data.
func _server_tls() -> TLSOptions:
	var key_path := "user://realm.key"
	var cert_path := "user://realm.crt"
	var crypto := Crypto.new()
	var key: CryptoKey = null
	var cert: X509Certificate = null
	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path):
		key = CryptoKey.new()
		cert = X509Certificate.new()
		if key.load(key_path) != OK or cert.load(cert_path) != OK:
			key = null
	if key == null:
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=emberfall-realm,O=Emberfall,C=TH",
			"20260101000000", "20360101000000")
		key.save(key_path)
		cert.save(cert_path)
	return TLSOptions.server(key, cert)


# ------------------------------------------------------------------ accounts (client -> realm)

@rpc("any_peer", "reliable")
func req_login(user: String, password: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _authed.has(id):
		return
	var nm := accounts.verify(user.strip_edges(), password)
	if nm == "":
		_failed[id] = int(_failed.get(id, 0)) + 1
		auth_reply.rpc_id(id, false, "Wrong name or password.", "")
		if int(_failed[id]) >= MAX_FAILED_LOGINS:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# Same account still connected (e.g. the game crashed and the old link has not timed out yet):
	# the new, password-checked login takes over and the old connection is dropped.
	for old in _authed.keys():
		if String(_authed[old]).to_lower() == nm.to_lower():
			if old == 1:
				auth_reply.rpc_id(id, false, "That account is already logged in.", "")
				return
			_on_peer_disconnected(old)
			multiplayer.multiplayer_peer.disconnect_peer(old)
	_welcome(id, nm)


@rpc("any_peer", "reliable")
func req_create_account(user: String, password: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _authed.has(id):
		return
	var nm := user.strip_edges()
	var err := accounts.register(nm, password)
	if err != "":
		auth_reply.rpc_id(id, false, err, "")
		return
	print("[realm] new account: %s (%d total)" % [nm, accounts.count()])
	_welcome(id, nm)


func _welcome(id: int, nm: String) -> void:
	_authed[id] = nm
	_failed.erase(id)
	lobby["names"][id] = nm
	if int(lobby["leader"]) == 0:
		lobby["leader"] = id
	auth_reply.rpc_id(id, true, "Welcome, %s!" % nm, nm)
	_server_chat("%s entered the realm." % nm)
	_lobby_updated()
	var info := rejoin_info(nm)
	if not info.is_empty():
		rejoin_offer.rpc_id(id, info)


@rpc("authority", "reliable")
func auth_reply(ok: bool, message: String, account_name: String) -> void:
	logged_in = ok
	if ok:
		my_name = account_name
	auth_result.emit(ok, message)


# ------------------------------------------------------------------ party requests (client -> realm)

## The host calls the handler directly; clients send an RPC to the realm.
func request(method: String, args: Array = []) -> void:
	if is_server():
		callv("_do_" + method, [my_id()] + args)
	elif is_client():
		match method:
			"take_slot":
				req_take_slot.rpc_id(1, args[0])
			"leave_slot":
				req_leave_slot.rpc_id(1)
			"set_class":
				req_set_class.rpc_id(1, args[0], args[1])
			"set_bot":
				req_set_bot.rpc_id(1, args[0], args[1])
			"start":
				req_start.rpc_id(1)
			"chat":
				req_chat.rpc_id(1, args[0])
			"retry":
				req_retry.rpc_id(1)
			"to_lobby":
				req_to_lobby.rpc_id(1)
			"rejoin":
				req_rejoin.rpc_id(1)
			"surrender":
				req_surrender.rpc_id(1)
			"vote":
				req_vote.rpc_id(1, args[0])


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if _authed.has(id) else -1


@rpc("any_peer", "reliable")
func req_take_slot(i: int) -> void:
	var id := _sender()
	if id > 0:
		_do_take_slot(id, i)


@rpc("any_peer", "reliable")
func req_leave_slot() -> void:
	var id := _sender()
	if id > 0:
		_do_leave_slot(id)


@rpc("any_peer", "reliable")
func req_set_class(i: int, cid: String) -> void:
	var id := _sender()
	if id > 0:
		_do_set_class(id, i, cid)


@rpc("any_peer", "reliable")
func req_set_bot(i: int, on: bool) -> void:
	var id := _sender()
	if id > 0:
		_do_set_bot(id, i, on)


@rpc("any_peer", "reliable")
func req_start() -> void:
	var id := _sender()
	if id > 0:
		_do_start(id)


@rpc("any_peer", "reliable")
func req_chat(text: String) -> void:
	var id := _sender()
	if id > 0:
		_do_chat(id, text)


@rpc("any_peer", "reliable")
func req_retry() -> void:
	var id := _sender()
	if id > 0:
		_do_retry(id)


@rpc("any_peer", "reliable")
func req_to_lobby() -> void:
	var id := _sender()
	if id > 0:
		_do_to_lobby(id)


@rpc("any_peer", "reliable")
func req_rejoin() -> void:
	var id := _sender()
	if id > 0:
		_do_rejoin(id)


@rpc("any_peer", "reliable")
func req_surrender() -> void:
	var id := _sender()
	if id > 0:
		_do_surrender(id)


@rpc("any_peer", "reliable")
func req_vote(yes: bool) -> void:
	var id := _sender()
	if id > 0:
		_do_vote(id, yes)


## Class that fills the party's biggest gap (tank, then healer, then damage).
func _suggest_class(exclude_slot := -1) -> String:
	var roles := {"tank": 0, "healer": 0}
	var slots: Array = lobby["slots"]
	for i in slots.size():
		var cid: String = slots[i]["class"]
		if i != exclude_slot and cid != "" and (int(slots[i]["peer"]) != 0 or slots[i]["bot"]):
			var r: String = GameData.CLASSES[cid]["role"]
			roles[r] = int(roles.get(r, 0)) + 1
	if roles["tank"] == 0:
		return "warden"
	if roles["healer"] == 0:
		return "oracle"
	return "blademaster" if randi() % 2 == 0 else "arcanist"


func _do_take_slot(id: int, i: int) -> void:
	if lobby["in_raid"] or i < 0 or i >= lobby["slots"].size():
		return
	var s: Dictionary = lobby["slots"][i]
	if int(s["peer"]) != 0:
		return
	var keep := ""
	for o in lobby["slots"]:
		if int(o["peer"]) == id:
			keep = o["class"]
			o["peer"] = 0
			o["class"] = ""
	s["peer"] = id
	s["bot"] = false
	s["class"] = keep if keep != "" else _suggest_class(i)
	_lobby_updated()


func _do_leave_slot(id: int) -> void:
	if lobby["in_raid"]:
		return
	for o in lobby["slots"]:
		if int(o["peer"]) == id:
			o["peer"] = 0
			o["class"] = ""
	_lobby_updated()


## Players change their own class; the leader changes a bot's class.
func _do_set_class(id: int, i: int, cid: String) -> void:
	if lobby["in_raid"] or i < 0 or i >= lobby["slots"].size() or not GameData.CLASSES.has(cid):
		return
	var s: Dictionary = lobby["slots"][i]
	var mine := int(s["peer"]) == id
	var leader_bot: bool = s["bot"] and int(s["peer"]) == 0 and id == int(lobby["leader"])
	if mine or leader_bot:
		s["class"] = cid
		_lobby_updated()


func _do_set_bot(id: int, i: int, on: bool) -> void:
	if lobby["in_raid"] or id != int(lobby["leader"]) or i < 0 or i >= lobby["slots"].size():
		return
	var s: Dictionary = lobby["slots"][i]
	if int(s["peer"]) == 0:
		s["bot"] = on
		s["class"] = _suggest_class(i) if on else ""
		_lobby_updated()


func _do_chat(id: int, text: String) -> void:
	var t := text.strip_edges().substr(0, 200)
	if t == "":
		return
	var nm: String = lobby["names"].get(id, "Realm")
	for p in _authed:
		if p != 1:
			recv_chat.rpc_id(p, nm, t, Color(1, 0.92, 0.75))
	chat_received.emit(nm, t, Color(1, 0.92, 0.75))


func _do_start(id: int) -> void:
	if id != int(lobby["leader"]) or lobby["in_raid"]:
		return
	var players := 0
	for s in lobby["slots"]:
		if int(s["peer"]) != 0:
			players += 1
	if players == 0:
		_server_chat("Join a slot before starting the raid.")
		return
	var roster := _build_roster()
	lobby["in_raid"] = true
	_lobby_updated()
	_server_chat("The raid begins!")
	_start_for_party(roster)


func _do_retry(id: int) -> void:
	if id != int(lobby["leader"]) or not lobby["in_raid"]:
		return
	_start_for_party(_build_roster())


func _start_for_party(roster: Array) -> void:
	if not _vote.is_empty():
		_vote.clear()
		_send_vote_state({"active": false, "result": ""})
	for p in _raid_peers():
		start_raid.rpc_id(p, roster)
	if main:
		main.server_start_raid(roster)


func _do_to_lobby(id: int) -> void:
	if id != int(lobby["leader"]):
		return
	_end_raid()


## Everyone goes back to the lobby; seats of players who never came back are freed.
func _end_raid() -> void:
	lobby["in_raid"] = false
	for s in lobby["slots"]:
		if s.get("away", "") != "":
			s["away"] = ""
			s["bot"] = false
			s["class"] = ""
	_vote.clear()
	_empty_t = 0.0
	_lobby_updated()
	for p in _authed:
		if p != 1:
			go_lobby.rpc_id(p)
	if main:
		main.return_to_lobby()


# ------------------------------------------------------------------ rejoin

func _away_slot(nm: String) -> int:
	var slots: Array = lobby["slots"]
	for i in slots.size():
		if String(slots[i].get("away", "")).to_lower() == nm.to_lower() and nm != "":
			return i
	return -1


## Server: what the rejoin screen shows, or {} when this account has no raid to go back to.
func rejoin_info(nm: String) -> Dictionary:
	if not lobby["in_raid"] or main == null or main.world == null:
		return {}
	var i := _away_slot(nm)
	if i < 0:
		return {}
	var w = main.world
	var u: Unit = w.unit_by_id(i)
	if u == null:
		return {}
	return {"slot": i, "class": u.class_id, "boss_pct": w.boss.hp_pct(), "time": w.fight_time,
		"alive": w.party_alive().size(), "party": w.party_all().size(), "hero_alive": u.alive,
		"finished": w.finished, "started": w.started}


## Client: the raid I dropped out of is still running (from the lobby state).
func can_rejoin() -> bool:
	return lobby.get("in_raid", false) and _away_slot(my_name) >= 0


func _do_rejoin(id: int) -> void:
	var nm: String = _authed.get(id, "")
	var i := _away_slot(nm)
	if i < 0 or not lobby["in_raid"] or main == null or main.world == null or unit_slot_taken(id):
		return
	var s: Dictionary = lobby["slots"][i]
	s["peer"] = id
	s["bot"] = false
	s["away"] = ""
	var roster: Array = main.world_peer_rejoined(id, i, nm)
	_empty_t = 0.0
	start_raid.rpc_id(id, roster)
	for ev in main.world.catchup_events():
		fx.rpc_id(id, ev[0], ev[1])
	_server_chat("%s rejoined the raid." % nm)
	_lobby_updated()
	_vote_check()


func unit_slot_taken(id: int) -> bool:
	for s in lobby["slots"]:
		if int(s["peer"]) == id:
			return true
	return false


# ------------------------------------------------------------------ surrender vote

## Connected players who are in the running raid (the listen host counts too).
func _raid_voters() -> Array:
	var out: Array = []
	for s in lobby["slots"]:
		var p := int(s["peer"])
		if p != 0 and _authed.has(p):
			out.append(p)
	return out


func _do_surrender(id: int) -> void:
	if not lobby["in_raid"] or not (id in _raid_voters()) or main == null or main.world == null:
		return
	if main.world.finished:
		_server_chat("The fight is already over.")
		return
	if not _vote.is_empty():
		_do_vote(id, true)
		return
	if _vote_cd > 0.0:
		_send_vote_state({"active": false, "result": "Wait %d s before calling another vote." % ceili(_vote_cd)}, [id])
		return
	_vote = {"by": String(_authed.get(id, "Someone")), "yes": [id], "no": [], "t": VOTE_TIME}
	_server_chat("%s wants to surrender. Press Esc or use the vote buttons to answer." % _vote["by"])
	_vote_check()


func _do_vote(id: int, yes: bool) -> void:
	if _vote.is_empty() or not (id in _raid_voters()):
		return
	if id in _vote["yes"] or id in _vote["no"]:
		return
	_vote["yes" if yes else "no"].append(id)
	_vote_check()


## Majority of connected raiders passes; once that is out of reach (or time runs out) the vote fails.
func _vote_check() -> void:
	if _vote.is_empty() or not is_server():
		return
	var voters := _raid_voters()
	_vote["yes"] = _vote["yes"].filter(func(p): return p in voters)
	_vote["no"] = _vote["no"].filter(func(p): return p in voters)
	var n := voters.size()
	var needed := n / 2 + 1
	var yes: int = _vote["yes"].size()
	var no: int = _vote["no"].size()
	if n == 0:
		_vote.clear()
		return
	if main == null or main.world == null or main.world.finished:
		_vote.clear()
		_send_vote_state({"active": false, "result": ""})
		return
	if yes >= needed:
		_vote.clear()
		_send_vote_state({"active": false, "result": "Surrender passed (%d of %d)." % [yes, n]})
		_server_chat("The party surrendered. Returning to the lobby.")
		_end_raid()
		return
	if no > n - needed or float(_vote["t"]) <= 0.0:
		_vote.clear()
		_vote_cd = VOTE_COOLDOWN
		_send_vote_state({"active": false, "result": "Surrender vote failed (%d yes, %d no)." % [yes, no]})
		_server_chat("The surrender vote failed. Fight on!")
		return
	_send_vote_state({"active": true, "by": _vote["by"], "yes": yes, "no": no, "needed": needed, "total": n,
		"time": float(_vote["t"]), "voted": _vote["yes"] + _vote["no"]})


func _send_vote_state(state: Dictionary, to: Array = []) -> void:
	var targets := to if not to.is_empty() else _raid_voters()
	for p in targets:
		if p == 1:
			vote_state = state
			vote_changed.emit(state)
		else:
			vote_update.rpc_id(p, state)


## Have I already answered the running vote?
func i_voted() -> bool:
	return my_id() in vote_state.get("voted", [])


## Players and chosen bots keep their classes; empty slots get bots that fill missing roles first.
func _build_roster() -> Array:
	var slots: Array = lobby["slots"]
	for i in slots.size():
		var s: Dictionary = slots[i]
		if int(s["peer"]) == 0 and not s["bot"]:
			s["bot"] = true
			s["class"] = _suggest_class(i)
	var roster: Array = []
	var name_idx := {}
	for s in slots:
		var peer := int(s["peer"])
		var cid: String = s["class"] if s["class"] != "" else "blademaster"
		var nm: String
		if peer != 0:
			nm = lobby["names"].get(peer, "Adventurer")
		else:
			nm = RaidWorld.bot_name(cid, name_idx) + " (bot)"
		roster.append({"class": cid, "peer": peer, "name": nm})
	return roster


func _server_chat(text: String) -> void:
	for p in _authed:
		if p != 1:
			recv_chat.rpc_id(p, "", text, Color(0.75, 0.85, 1))
	chat_received.emit("", text, Color(0.75, 0.85, 1))


## Lobby state only goes to logged-in players.
func _lobby_updated() -> void:
	if is_server():
		for id in _authed:
			if id != 1:
				sync_lobby.rpc_id(id, lobby)
	lobby_changed.emit()


# ------------------------------------------------------------------ realm -> clients

@rpc("authority", "reliable")
func sync_lobby(data: Dictionary) -> void:
	lobby = data
	lobby_changed.emit()


@rpc("authority", "reliable")
func recv_chat(from: String, text: String, c: Color) -> void:
	chat_received.emit(from, text, c)


@rpc("authority", "reliable")
func start_raid(roster: Array) -> void:
	raid_started.emit(roster)


@rpc("authority", "reliable")
func go_lobby() -> void:
	vote_state = {}
	back_in_lobby.emit()


@rpc("authority", "reliable")
func rejoin_offer(info: Dictionary) -> void:
	rejoin_offered.emit(info)


@rpc("authority", "reliable")
func vote_update(state: Dictionary) -> void:
	vote_state = state
	vote_changed.emit(state)


@rpc("authority", "unreliable_ordered")
func snapshot(buf: PackedByteArray, raw_size: int) -> void:
	if main and main.world and main.world.net_role == "client":
		var data = bytes_to_var(buf.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE))
		if data is Array:
			main.world.apply_snapshot(data)


@rpc("authority", "reliable")
func fx(ev: String, args: Array) -> void:
	if main and main.world and main.world.net_role == "client":
		main.world.net_in(ev, args)


@rpc("authority", "reliable")
func force_pos(pos: Vector3) -> void:
	if main and main.world and main.world.player:
		main.world.player.position = pos


@rpc("authority", "reliable")
func ability_error(text: String) -> void:
	ability_failed.emit(text)


func _raid_peers() -> Array:
	var out: Array = []
	for s in lobby["slots"]:
		var p := int(s["peer"])
		if p > 1 and _authed.has(p):
			out.append(p)
	return out


func send_fx(ev: String, args: Array) -> void:
	if not is_server():
		return
	for p in _raid_peers():
		fx.rpc_id(p, ev, args)


func send_force_position(peer: int, pos: Vector3) -> void:
	if is_server():
		force_pos.rpc_id(peer, pos)


# ------------------------------------------------------------------ player input (client -> realm)

@rpc("any_peer", "unreliable_ordered")
func in_state(pos: Vector3, rot: float) -> void:
	var u := _sender_unit()
	if u == null or not u.alive or u.is_dashing():
		return
	var p: Vector3 = main.world.clamp_to_arena(pos)
	if p.distance_to(u.position) > 0.02:
		u.moved_this_tick = true
	u.position = p
	u.rotation.y = rot


@rpc("any_peer", "reliable")
func in_ability(aid: String, target_id: int, point) -> void:
	var u := _sender_unit()
	if u == null or not GameData.ABILITIES.has(aid) or not (aid in u.ability_ids):
		return
	if point != null and not (point is Vector3):
		return
	var err := u.use_ability(aid, main.world.unit_by_id(target_id), point)
	if err != "" and err != "GCD":
		ability_error.rpc_id(multiplayer.get_remote_sender_id(), err)


@rpc("any_peer", "reliable")
func in_target(target_id: int) -> void:
	var u := _sender_unit()
	if u != null:
		u.target = main.world.unit_by_id(target_id)


func _sender_unit() -> Unit:
	if not is_server() or main == null or main.world == null:
		return null
	var id := multiplayer.get_remote_sender_id()
	if not _authed.has(id):
		return null
	return main.world.unit_of_peer(id)


func send_ability(aid: String, target: Unit, point) -> void:
	in_ability.rpc_id(1, aid, target.net_id if target else -1, point)


func send_target(target: Unit) -> void:
	in_target.rpc_id(1, target.net_id if target else -1)


# ------------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	_clock += delta
	if is_server():
		# Drop connections that never log in
		for id in _joined_at.keys():
			if not _authed.has(id) and _clock - float(_joined_at[id]) > AUTH_TIMEOUT:
				_joined_at.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id)
		_vote_cd = maxf(0.0, _vote_cd - delta)
		if not _vote.is_empty():
			var before := ceili(float(_vote["t"]))
			_vote["t"] = float(_vote["t"]) - delta
			if ceili(float(_vote["t"])) != before:
				_vote_check()  # once a second: refresh the countdown, fail on timeout
		_snap_log_t += delta
		if _snap_log_t >= 60.0:
			_snap_log_t = 0.0
			if _snap_max > 0:
				print("[realm] largest snapshot in the last minute: %d bytes" % _snap_max)
			_snap_max = 0
		if lobby["in_raid"] and _raid_voters().is_empty():
			_empty_t += delta
			if _empty_t >= EMPTY_RAID_GRACE:
				print("[realm] nobody came back to the raid; closing it")
				_end_raid()
		else:
			_empty_t = 0.0
	if main == null or main.world == null:
		return
	var w = main.world
	if is_server() and lobby["in_raid"]:
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = SNAPSHOT_RATE
			var peers := _raid_peers()
			if not peers.is_empty():
				# Shared state plus each player's own cooldowns, deflated: well under one packet even
				# with adds up, so nothing needs IP fragmentation (WARP drops fragmented UDP).
				var snap: Array = w.make_snapshot()
				for p in peers:
					var u: Unit = w.unit_of_peer(p)
					snap[9] = w.own_state(u) if u != null else null
					var raw := var_to_bytes(snap)
					var buf := raw.compress(FileAccess.COMPRESSION_DEFLATE)
					_snap_max = maxi(_snap_max, buf.size())
					snapshot.rpc_id(p, buf, raw.size())
	elif is_client() and w.net_role == "client" and w.player != null:
		_input_t -= delta
		if _input_t <= 0.0:
			_input_t = SNAPSHOT_RATE
			if w.synced and w.player.alive and not w.player.net_dashing:
				in_state.rpc_id(1, w.player.position, w.player.rotation.y)
