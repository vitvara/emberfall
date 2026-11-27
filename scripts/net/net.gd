extends Node
## Realm networking: connection, accounts, the Outpost, war parties and the in-raid data flow.
## Autoloaded as "Net".
##
## A realm is a dedicated server (./run.sh server). Players type the realm address, connect (DTLS, the
## realm makes a self-signed certificate on first start), log in or register, choose a hero and walk the
## Outpost together with everyone else on the realm. Walking through the raid portal opens the war-party
## window: create a party or join one (5 seats). Only the party's leader starts the raid; empty seats are
## filled with bots (missing tank / healer first). Every party fights in its own raid on the realm, so
## several raids can run at once.
## In a raid the realm runs the only simulation; clients send movement / target / skill presses and get
## snapshots (30/s) plus visual events back.

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
signal hub_snapshot_received(ids: PackedInt32Array, data: PackedFloat32Array)
signal notice_received(text: String)

const DEFAULT_PORT := 24565
const SNAPSHOT_RATE := 1.0 / 30.0  # raid: realm snapshots and client input, 30/s
const PARTY_SIZE := 5
const MAX_PARTIES := 12
const AUTH_TIMEOUT := 120.0
const MAX_FAILED_LOGINS := 5
const VOTE_TIME := 30.0
const VOTE_COOLDOWN := 20.0
const EMPTY_RAID_GRACE := 180.0  # a raid with nobody connected waits this long for someone to rejoin
const HUB_RATE := 0.05          # Outpost position sync (both directions), 20/s
const HUB_VIEW_RADIUS := 90.0   # area of interest: you only hear about walkers this close...
const HUB_MAX_VISIBLE := 24     # ...and at most this many (nearest first), so packets stay < 1 KB on any map size
const CHAT_HISTORY := 40

var mode := "offline"  # offline | client | dedicated
var my_name := ""
var logged_in := false
var realm_address := ""
## What a client knows (each player gets their own copy):
##   roster:  {peer: [account name, hero class ("" until chosen)]}: everyone logged in to the realm
##   parties: [[id, leader name, players, seats filled, in_raid, [classes]]]: every war party, for the list
##   party:   my party, or {}: {id, leader (peer), in_raid, slots: [{peer, bot, class, away}]}
var lobby := {"roster": {}, "parties": [], "party": {}}
var main  # main.gd, set by main
var accounts: Accounts
var vote_state := {}    # client: last vote state from the realm
var chat_history: Array = []  # [from, text, color], newest last, so a freshly built chat box can catch up

# Server state
var _players := {}     # peer -> {name, class, party (0 = none)}; logged-in players only
var _parties := {}     # id -> {id, leader, slots, in_raid, world, vote, vote_cd, empty_t}
var _next_party := 1
var _joined_at := {}   # peer -> seconds since start when they connected
var _failed := {}      # peer -> failed login count
var _hub_pos := {}     # peer -> [Vector3 pos, float rot] for players walking the Outpost
var _clock := 0.0
var _snap_t := 0.0
var _input_t := 0.0
var _hub_t := 0.0
var _snap_max := 0     # biggest snapshot (bytes, compressed) since the last log line
var _lobby_max := 0    # biggest lobby sync (bytes, compressed) since the last log line
var _log_t := 0.0
var _dirty := false    # lobby changed this frame: sync once at the end of the frame


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach that realm."))
	multiplayer.server_disconnected.connect(func(): _fail("The realm closed the connection."))
	chat_received.connect(func(f: String, t: String, c: Color):
		chat_history.append([f, t, c])
		if chat_history.size() > CHAT_HISTORY:
			chat_history.pop_front())


func is_net() -> bool:
	return mode != "offline"


func is_server() -> bool:
	return mode == "dedicated"


func is_client() -> bool:
	return mode == "client"


func my_id() -> int:
	return multiplayer.get_unique_id() if is_net() else 1


# ------------------------------------------------------------------ client view helpers

func my_party() -> Dictionary:
	return lobby.get("party", {})


func in_party() -> bool:
	return not my_party().is_empty()


func is_leader() -> bool:
	return in_party() and int(my_party()["leader"]) == my_id()


func my_slot() -> int:
	var slots: Array = my_party().get("slots", [])
	for i in slots.size():
		if int(slots[i]["peer"]) == my_id():
			return i
	return -1


func peer_name(peer: int) -> String:
	var r: Array = lobby.get("roster", {}).get(peer, [])
	return String(r[0]) if not r.is_empty() else "Adventurer"


## The hero this peer walks the Outpost as ("" until they have chosen one).
func avatar_class(peer: int) -> String:
	var r: Array = lobby.get("roster", {}).get(peer, [])
	return String(r[1]) if r.size() > 1 else ""


## Client: my party's raid is still going and a bot holds my hero.
func can_rejoin() -> bool:
	var p := my_party()
	if p.is_empty() or not p.get("in_raid", false) or my_name == "":
		return false
	for s in p["slots"]:
		if String(s.get("away", "")).to_lower() == my_name.to_lower():
			return true
	return false


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

## Start a realm (headless dedicated server with accounts).
func host(port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 32)
	if err != OK:
		return "Could not open port %d (error %d)." % [port, err]
	var tls := _server_tls()
	if tls != null:
		peer.host.dtls_server_setup(tls)
	multiplayer.multiplayer_peer = peer
	mode = "dedicated"
	accounts = Accounts.new()
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
	my_name = ""
	_players.clear()
	_parties.clear()
	_joined_at.clear()
	_failed.clear()
	_hub_pos.clear()
	vote_state = {}
	chat_history.clear()
	lobby = {"roster": {}, "parties": [], "party": {}}


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
	_hub_pos.erase(id)
	if not _players.has(id):
		return
	var nm: String = _players[id]["name"]
	var pid := int(_players[id]["party"])
	var covered := false
	if _parties.has(pid):
		var party: Dictionary = _parties[pid]
		for s in party["slots"]:
			if int(s["peer"]) == id:
				s["peer"] = 0
				if party["in_raid"]:
					s["bot"] = true  # mid-raid a bot plays their hero until they come back
					s["away"] = nm
					covered = true
					if party["world"] != null:
						main.world_peer_left(party["world"], id)
				else:
					s["class"] = ""
	_players.erase(id)
	if _parties.has(pid):
		_after_member_left(pid)
	_server_chat("%s left the realm.%s" % [nm, "  A bot covers for them until they rejoin." if covered else ""])
	_lobby_updated()


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
	if _players.has(id):
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
	for old in _players.keys():
		if String(_players[old]["name"]).to_lower() == nm.to_lower():
			_on_peer_disconnected(old)
			multiplayer.multiplayer_peer.disconnect_peer(old)
	_welcome(id, nm)


@rpc("any_peer", "reliable")
func req_create_account(user: String, password: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _players.has(id):
		return
	var nm := user.strip_edges()
	var err := accounts.register(nm, password)
	if err != "":
		auth_reply.rpc_id(id, false, err, "")
		return
	print("[realm] new account: %s (%d total)" % [nm, accounts.count()])
	_welcome(id, nm)


func _welcome(id: int, nm: String) -> void:
	_failed.erase(id)
	_players[id] = {"name": nm, "class": "", "party": 0}
	# Back from a crash / dropped link while their party fights: they are still a member.
	for pid in _parties:
		if _away_slot(_parties[pid], nm) >= 0:
			_players[id]["party"] = pid
	auth_reply.rpc_id(id, true, "Welcome, %s!" % nm, nm)
	_server_chat("%s entered the realm." % nm)
	_lobby_updated()
	var info := rejoin_info(id)
	if not info.is_empty():
		rejoin_offer.rpc_id(id, info)


@rpc("authority", "reliable")
func auth_reply(ok: bool, message: String, account_name: String) -> void:
	logged_in = ok
	if ok:
		my_name = account_name
	auth_result.emit(ok, message)


# ------------------------------------------------------------------ requests (client -> realm)

## request name -> number of arguments
const _REQUESTS := {"set_hero": 1, "create_party": 0, "join_party": 1, "leave_party": 0, "set_bot": 2,
	"set_bot_class": 2, "start": 0, "chat": 1, "retry": 0, "to_lobby": 0, "rejoin": 0, "surrender": 0, "vote": 1}


## Everything a player asks of the realm goes through one RPC: request("join_party", [3]).
func request(method: String, args: Array = []) -> void:
	if is_client() and _REQUESTS.get(method, -1) == args.size():
		req.rpc_id(1, method, args)


@rpc("any_peer", "reliable")
func req(method: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_server() or not _players.has(id) or _REQUESTS.get(method, -1) != args.size():
		return
	callv("_do_" + method, [id] + args)


func _do_set_hero(id: int, cid) -> void:
	if not (cid is String) or not GameData.CLASSES.has(cid):
		return
	var pl: Dictionary = _players[id]
	var party := _party_of(id)
	if not party.is_empty() and party["in_raid"] and _slot_of(party, id) >= 0:
		return  # your hero is fighting
	pl["class"] = cid
	if not party.is_empty():
		var i := _slot_of(party, id)
		if i >= 0:
			party["slots"][i]["class"] = cid
	_lobby_updated()


func _do_create_party(id: int) -> void:
	var pl: Dictionary = _players[id]
	if int(pl["party"]) != 0 or pl["class"] == "":
		return
	if _parties.size() >= MAX_PARTIES:
		_notice(id, "The realm has too many war parties right now. Join one instead.")
		return
	var pid := _next_party
	_next_party += 1
	var slots := empty_slots()
	slots[0] = {"peer": id, "bot": false, "class": pl["class"], "away": ""}
	_parties[pid] = {"id": pid, "leader": id, "slots": slots, "in_raid": false, "world": null,
		"vote": {}, "vote_cd": 0.0, "empty_t": 0.0}
	pl["party"] = pid
	_server_chat("%s formed a war party." % pl["name"])
	_lobby_updated()


func _do_join_party(id: int, pid) -> void:
	var pl: Dictionary = _players[id]
	if not (pid is int) or int(pl["party"]) != 0 or pl["class"] == "" or not _parties.has(pid):
		return
	var party: Dictionary = _parties[pid]
	if party["in_raid"]:
		_notice(id, "That party is already fighting. Wait for them to return.")
		return
	var seat := -1
	for want_bot in [false, true]:  # an open seat first, then one a bot holds
		for i in PARTY_SIZE:
			var s: Dictionary = party["slots"][i]
			if seat < 0 and int(s["peer"]) == 0 and bool(s["bot"]) == want_bot:
				seat = i
	if seat < 0:
		_notice(id, "That party is full.")
		return
	party["slots"][seat] = {"peer": id, "bot": false, "class": pl["class"], "away": ""}
	pl["party"] = pid
	_party_chat(party, "%s joined the party." % pl["name"])
	_lobby_updated()


func _do_leave_party(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty():
		return
	var nm: String = _players[id]["name"]
	var i := _slot_of(party, id)
	if i >= 0:
		var s: Dictionary = party["slots"][i]
		s["peer"] = 0
		s["away"] = ""
		if party["in_raid"]:
			s["bot"] = true  # the raid goes on; a bot takes the hero for good
			if party["world"] != null:
				main.world_peer_left(party["world"], id)
			go_lobby.rpc_id(id)
		else:
			s["bot"] = false
			s["class"] = ""
	_players[id]["party"] = 0
	_party_chat(party, "%s left the party." % nm)
	_after_member_left(int(party["id"]))
	_lobby_updated()


## A member left or dropped: hand over leadership, or disband a party nobody is in any more.
func _after_member_left(pid: int) -> void:
	var party: Dictionary = _parties[pid]
	var members := _members(party)
	if members.is_empty():
		if not party["in_raid"]:
			_parties.erase(pid)
		return  # mid-raid the bots fight on for EMPTY_RAID_GRACE in case someone comes back
	if not (int(party["leader"]) in members):
		party["leader"] = members[0]
		_party_chat(party, "%s now leads the party." % _players[members[0]]["name"])
	_vote_check(party)


func _do_set_bot(id: int, i, on) -> void:
	var party := _party_of(id)
	if party.is_empty() or party["in_raid"] or id != int(party["leader"]) or not (i is int) or i < 0 or i >= PARTY_SIZE:
		return
	var s: Dictionary = party["slots"][i]
	if int(s["peer"]) == 0:
		s["bot"] = bool(on)
		s["class"] = _suggest_class(party, i) if s["bot"] else ""
		_lobby_updated()


func _do_set_bot_class(id: int, i, cid) -> void:
	var party := _party_of(id)
	if party.is_empty() or party["in_raid"] or id != int(party["leader"]) or not (i is int) or i < 0 or i >= PARTY_SIZE:
		return
	var s: Dictionary = party["slots"][i]
	if int(s["peer"]) == 0 and s["bot"] and cid is String and GameData.CLASSES.has(cid):
		s["class"] = cid
		_lobby_updated()


func _do_chat(id: int, text) -> void:
	var t := String(text).strip_edges().substr(0, 200)
	if t == "":
		return
	var nm: String = _players[id]["name"]
	for p in _players:
		recv_chat.rpc_id(p, nm, t, Color(1, 0.92, 0.75))
	chat_received.emit(nm, t, Color(1, 0.92, 0.75))


func _do_start(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty() or id != int(party["leader"]) or party["in_raid"]:
		return
	var roster := _build_roster(party)
	party["in_raid"] = true
	party["empty_t"] = 0.0
	for p in _members(party):
		_hub_pos.erase(p)  # raiders leave the Outpost
	_lobby_updated()
	_party_chat(party, "The raid begins!")
	print("[realm] party %d (%s) starts a raid with %d players" % [party["id"], _players[id]["name"], _members(party).size()])
	_start_for_party(party, roster)


func _do_retry(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty() or id != int(party["leader"]) or not party["in_raid"]:
		return
	_start_for_party(party, _build_roster(party))


func _start_for_party(party: Dictionary, roster: Array) -> void:
	if not party["vote"].is_empty():
		party["vote"] = {}
		_send_vote_state(party, {"active": false, "result": ""})
	if party["world"] != null:
		main.server_end_raid(party["world"])
	party["world"] = main.server_start_raid(int(party["id"]), roster)
	for p in _raid_peers(party):
		start_raid.rpc_id(p, roster)


func _do_to_lobby(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty() or id != int(party["leader"]) or not party["in_raid"]:
		return
	_end_raid(party)


## The party walks back into the Outpost. Seats of players who never came back are freed;
## members who were away but are online again take their seats back.
func _end_raid(party: Dictionary) -> void:
	party["in_raid"] = false
	for s in party["slots"]:
		var away := String(s.get("away", ""))
		if away != "":
			s["away"] = ""
			s["bot"] = false
			var back := _peer_by_name(away)
			if back > 0 and int(_players[back]["party"]) == int(party["id"]):
				s["peer"] = back
				s["class"] = _players[back]["class"] if _players[back]["class"] != "" else s["class"]
			else:
				s["class"] = ""
	party["vote"] = {}
	party["empty_t"] = 0.0
	if party["world"] != null:
		main.server_end_raid(party["world"])
		party["world"] = null
	for p in _members(party):
		go_lobby.rpc_id(p)
	if _members(party).is_empty():
		_parties.erase(party["id"])
	_lobby_updated()


# ------------------------------------------------------------------ rejoin

func _away_slot(party: Dictionary, nm: String) -> int:
	for i in PARTY_SIZE:
		if nm != "" and String(party["slots"][i].get("away", "")).to_lower() == nm.to_lower():
			return i
	return -1


## What the rejoin screen shows, or {} when this player has no raid to go back to.
func rejoin_info(id: int) -> Dictionary:
	var party := _party_of(id)
	if party.is_empty() or not party["in_raid"] or party["world"] == null:
		return {}
	var i := _away_slot(party, _players[id]["name"])
	if i < 0:
		return {}
	var w = party["world"]
	var u: Unit = w.unit_by_id(i)
	if u == null:
		return {}
	return {"slot": i, "class": u.class_id, "boss_pct": w.boss.hp_pct(), "time": w.fight_time,
		"alive": w.party_alive().size(), "party": w.party_all().size(), "hero_alive": u.alive,
		"finished": w.finished, "started": w.started}


func _do_rejoin(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty() or not party["in_raid"] or party["world"] == null or _slot_of(party, id) >= 0:
		return
	var nm: String = _players[id]["name"]
	var i := _away_slot(party, nm)
	if i < 0:
		return
	var s: Dictionary = party["slots"][i]
	s["peer"] = id
	s["bot"] = false
	s["away"] = ""
	_hub_pos.erase(id)
	var roster: Array = main.world_peer_rejoined(party["world"], id, i, nm)
	party["empty_t"] = 0.0
	start_raid.rpc_id(id, roster)
	for ev in party["world"].catchup_events():
		fx.rpc_id(id, ev[0], ev[1])
	_party_chat(party, "%s rejoined the raid." % nm)
	_lobby_updated()
	_vote_check(party)


# ------------------------------------------------------------------ surrender vote (per party)

func _do_surrender(id: int) -> void:
	var party := _party_of(id)
	if party.is_empty() or not party["in_raid"] or not (id in _raid_peers(party)) or party["world"] == null:
		return
	if party["world"].finished:
		_notice(id, "The fight is already over.")
		return
	if not party["vote"].is_empty():
		_do_vote(id, true)
		return
	if float(party["vote_cd"]) > 0.0:
		_send_vote_state(party, {"active": false, "result": "Wait %d s before calling another vote." % ceili(party["vote_cd"])}, [id])
		return
	party["vote"] = {"by": String(_players[id]["name"]), "yes": [id], "no": [], "t": VOTE_TIME}
	_party_chat(party, "%s wants to surrender. Press Esc or use the vote buttons to answer." % party["vote"]["by"])
	_vote_check(party)


func _do_vote(id: int, yes) -> void:
	var party := _party_of(id)
	if party.is_empty() or party["vote"].is_empty() or not (id in _raid_peers(party)):
		return
	var v: Dictionary = party["vote"]
	if id in v["yes"] or id in v["no"]:
		return
	v["yes" if bool(yes) else "no"].append(id)
	_vote_check(party)


## Majority of connected raiders passes; once that is out of reach (or time runs out) the vote fails.
func _vote_check(party: Dictionary) -> void:
	var v: Dictionary = party["vote"]
	if v.is_empty():
		return
	var voters := _raid_peers(party)
	v["yes"] = v["yes"].filter(func(p): return p in voters)
	v["no"] = v["no"].filter(func(p): return p in voters)
	var n := voters.size()
	var needed := n / 2 + 1
	var yes: int = v["yes"].size()
	var no: int = v["no"].size()
	if n == 0:
		party["vote"] = {}
		return
	if party["world"] == null or party["world"].finished:
		party["vote"] = {}
		_send_vote_state(party, {"active": false, "result": ""})
		return
	if yes >= needed:
		party["vote"] = {}
		_send_vote_state(party, {"active": false, "result": "Surrender passed (%d of %d)." % [yes, n]})
		_party_chat(party, "The party surrendered. Returning to the Outpost.")
		_end_raid(party)
		return
	if no > n - needed or float(v["t"]) <= 0.0:
		party["vote"] = {}
		party["vote_cd"] = VOTE_COOLDOWN
		_send_vote_state(party, {"active": false, "result": "Surrender vote failed (%d yes, %d no)." % [yes, no]})
		_party_chat(party, "The surrender vote failed. Fight on!")
		return
	_send_vote_state(party, {"active": true, "by": v["by"], "yes": yes, "no": no, "needed": needed, "total": n,
		"time": float(v["t"]), "voted": v["yes"] + v["no"]})


func _send_vote_state(party: Dictionary, state: Dictionary, to: Array = []) -> void:
	for p in (to if not to.is_empty() else _raid_peers(party)):
		vote_update.rpc_id(p, state)


## Have I already answered the running vote?
func i_voted() -> bool:
	return my_id() in vote_state.get("voted", [])


# ------------------------------------------------------------------ party helpers (server)

func _party_of(id: int) -> Dictionary:
	if not _players.has(id):
		return {}
	return _parties.get(int(_players[id]["party"]), {})


func _slot_of(party: Dictionary, id: int) -> int:
	for i in PARTY_SIZE:
		if int(party["slots"][i]["peer"]) == id:
			return i
	return -1


## Connected players who belong to the party (seated, or away from a raid and back online).
func _members(party: Dictionary) -> Array:
	var out: Array = []
	for p in _players:
		if int(_players[p]["party"]) == int(party["id"]):
			out.append(p)
	return out


## Connected players fighting in the party's raid.
func _raid_peers(party: Dictionary) -> Array:
	var out: Array = []
	for s in party["slots"]:
		var p := int(s["peer"])
		if p != 0 and _players.has(p):
			out.append(p)
	return out


func _raiding(id: int) -> bool:
	var party := _party_of(id)
	return not party.is_empty() and party["in_raid"] and _slot_of(party, id) >= 0


func _peer_by_name(nm: String) -> int:
	for p in _players:
		if String(_players[p]["name"]).to_lower() == nm.to_lower():
			return p
	return -1


## Class that fills the party's biggest gap (tank, then healer, then damage).
func _suggest_class(party: Dictionary, exclude_slot := -1) -> String:
	var roles := {"tank": 0, "healer": 0}
	for i in PARTY_SIZE:
		var s: Dictionary = party["slots"][i]
		var cid: String = s["class"]
		if i != exclude_slot and cid != "" and (int(s["peer"]) != 0 or s["bot"]):
			var r: String = GameData.CLASSES[cid]["role"]
			roles[r] = int(roles.get(r, 0)) + 1
	if roles["tank"] == 0:
		return "warden"
	if roles["healer"] == 0:
		return "oracle"
	return ["blademaster", "arcanist", "arms"][randi() % 3]


## Players and chosen bots keep their classes; empty seats get bots that fill missing roles first.
func _build_roster(party: Dictionary) -> Array:
	var slots: Array = party["slots"]
	for i in PARTY_SIZE:
		var s: Dictionary = slots[i]
		if int(s["peer"]) == 0 and not s["bot"]:
			s["bot"] = true
			s["class"] = _suggest_class(party, i)
	var roster: Array = []
	var name_idx := {}
	for s in slots:
		var peer := int(s["peer"])
		var cid: String = s["class"] if s["class"] != "" else "blademaster"
		var nm: String
		if peer != 0:
			nm = _players[peer]["name"] if _players.has(peer) else "Adventurer"
		else:
			nm = RaidWorld.bot_name(cid, name_idx) + " (bot)"
		roster.append({"class": cid, "peer": peer, "name": nm})
	return roster


func _server_chat(text: String) -> void:
	for p in _players:
		recv_chat.rpc_id(p, "", text, Color(0.75, 0.85, 1))
	chat_received.emit("", text, Color(0.75, 0.85, 1))


func _party_chat(party: Dictionary, text: String) -> void:
	for p in _members(party):
		recv_chat.rpc_id(p, "", text, Color(0.6, 1.0, 0.7))


func _notice(id: int, text: String) -> void:
	if _players.has(id):
		notice.rpc_id(id, text)


func _lobby_updated() -> void:
	if is_server():
		_dirty = true  # sent once at the end of this frame
	lobby_changed.emit()


## Each player's view: the realm roster, the party list and their own party, deflated.
func _sync_lobbies() -> void:
	_dirty = false
	var roster := {}
	for p in _players:
		roster[p] = [_players[p]["name"], _players[p]["class"]]
	var list: Array = []
	for pid in _parties:
		var party: Dictionary = _parties[pid]
		var classes: Array = []
		var filled := 0
		for s in party["slots"]:
			if int(s["peer"]) != 0 or s["bot"]:
				filled += 1
				classes.append(s["class"])
		var lead := int(party["leader"])
		list.append([pid, _players[lead]["name"] if _players.has(lead) else "?", _raid_peers(party).size(),
			filled, party["in_raid"], classes])
	for p in _players:
		var mine: Dictionary = {}
		var party := _party_of(p)
		if not party.is_empty():
			mine = {"id": party["id"], "leader": party["leader"], "in_raid": party["in_raid"], "slots": party["slots"]}
		var raw := var_to_bytes({"roster": roster, "parties": list, "party": mine})
		var buf := raw.compress(FileAccess.COMPRESSION_DEFLATE)
		_lobby_max = maxi(_lobby_max, buf.size())
		sync_lobby.rpc_id(p, buf, raw.size())
	if main and main.dedicated:
		main.log_realm(_players, _parties)


# ------------------------------------------------------------------ realm -> clients

@rpc("authority", "reliable")
func sync_lobby(buf: PackedByteArray, raw_size: int) -> void:
	var data = bytes_to_var(buf.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE))
	if data is Dictionary:
		lobby = data
		lobby_changed.emit()


@rpc("authority", "reliable")
func recv_chat(from: String, text: String, c: Color) -> void:
	chat_received.emit(from, text, c)


@rpc("authority", "reliable")
func notice(text: String) -> void:
	notice_received.emit(text)


@rpc("authority", "reliable")
func start_raid(roster: Array) -> void:
	vote_state = {}
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


## A raid world's visual event goes to the players of the party fighting in it.
func send_fx(w, ev: String, args: Array) -> void:
	if not is_server() or not _parties.has(int(w.party_id)):
		return
	for p in _raid_peers(_parties[int(w.party_id)]):
		fx.rpc_id(p, ev, args)


func send_force_position(peer: int, pos: Vector3) -> void:
	if is_server() and _players.has(peer):
		force_pos.rpc_id(peer, pos)


# ------------------------------------------------------------------ the Outpost (hub)

## Client -> realm, 20/s while walking the Outpost.
func send_hub_pos(pos: Vector3, rot: float) -> void:
	if is_client() and logged_in:
		in_hub.rpc_id(1, pos, rot)


@rpc("any_peer", "unreliable_ordered")
func in_hub(pos: Vector3, rot: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id]["class"] == "" or _raiding(id):
		return  # not in the Outpost yet, or a late packet from someone who just left for the raid
	_hub_pos[id] = [HubWorld.walk_bounds(pos), wrapf(rot, -PI, PI)]


## Realm -> each walker: [peer ids] and [x, y, z, yaw] for the nearest walkers in view (themselves included).
## 24 walkers ≈ 600 bytes.
@rpc("authority", "unreliable_ordered")
func hub_snap(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	hub_snapshot_received.emit(ids, data)


func _send_hub_snapshot() -> void:
	for p in _hub_pos.keys():
		if not _players.has(p) or _raiding(p):
			_hub_pos.erase(p)
	var walkers: Array = _hub_pos.keys()
	for to in walkers:
		var here: Vector3 = _hub_pos[to][0]
		var near: Array = []
		for p in walkers:
			var d := here.distance_to(_hub_pos[p][0])
			if d <= HUB_VIEW_RADIUS:
				near.append([d, p])
		near.sort_custom(func(a, b): return a[0] < b[0])
		var ids := PackedInt32Array()
		var data := PackedFloat32Array()
		for n in near.slice(0, HUB_MAX_VISIBLE + 1):  # +1: the recipient is always nearest
			var e: Array = _hub_pos[n[1]]
			var v: Vector3 = e[0]
			ids.append(n[1])
			data.append_array([v.x, v.y, v.z, float(e[1])])
		hub_snap.rpc_id(to, ids, data)


# ------------------------------------------------------------------ player input (client -> realm)

@rpc("any_peer", "unreliable_ordered")
func in_state(pos: Vector3, rot: float) -> void:
	var w = _sender_world()
	var u := _sender_unit(w)
	if u == null or not u.alive or u.is_dashing():
		return
	var p: Vector3 = w.clamp_to_arena(pos)
	if p.distance_to(u.position) > 0.02:
		u.moved_this_tick = true
	u.position = p
	u.rotation.y = rot


@rpc("any_peer", "reliable")
func in_ability(aid: String, target_id: int, point) -> void:
	var w = _sender_world()
	var u := _sender_unit(w)
	if u == null or not GameData.ABILITIES.has(aid) or not (aid in u.ability_ids):
		return
	if point != null and not (point is Vector3):
		return
	var err := u.use_ability(aid, w.unit_by_id(target_id), point)
	if err != "" and err != "GCD":
		ability_error.rpc_id(multiplayer.get_remote_sender_id(), err)


@rpc("any_peer", "reliable")
func in_target(target_id: int) -> void:
	var w = _sender_world()
	var u := _sender_unit(w)
	if u != null:
		u.target = w.unit_by_id(target_id)


func _sender_world():
	if not is_server():
		return null
	var id := multiplayer.get_remote_sender_id()
	if not _raiding(id):
		return null
	return _party_of(id)["world"]


func _sender_unit(w) -> Unit:
	if w == null:
		return null
	return w.unit_of_peer(multiplayer.get_remote_sender_id())


func send_ability(aid: String, target: Unit, point) -> void:
	in_ability.rpc_id(1, aid, target.net_id if target else -1, point)


func send_target(target: Unit) -> void:
	in_target.rpc_id(1, target.net_id if target else -1)


# ------------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	_clock += delta
	if is_server():
		_server_tick(delta)
		return
	if main == null or main.world == null:
		return
	var w = main.world
	if is_client() and w.net_role == "client" and w.player != null:
		_input_t -= delta
		if _input_t <= 0.0:
			_input_t = maxf(_input_t + SNAPSHOT_RATE, 0.0)
			if w.synced and w.player.alive and not w.player.net_dashing:
				in_state.rpc_id(1, w.player.position, w.player.rotation.y)


func _server_tick(delta: float) -> void:
	# Drop connections that never log in
	for id in _joined_at.keys():
		if not _players.has(id) and _clock - float(_joined_at[id]) > AUTH_TIMEOUT:
			_joined_at.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for pid in _parties.keys():
		if not _parties.has(pid):
			continue
		var party: Dictionary = _parties[pid]
		party["vote_cd"] = maxf(0.0, float(party["vote_cd"]) - delta)
		var v: Dictionary = party["vote"]
		if not v.is_empty():
			var before := ceili(float(v["t"]))
			v["t"] = float(v["t"]) - delta
			if ceili(float(v["t"])) != before:
				_vote_check(party)  # once a second: refresh the countdown, fail on timeout
		if party["in_raid"] and _raid_peers(party).is_empty():
			party["empty_t"] = float(party["empty_t"]) + delta
			if float(party["empty_t"]) >= EMPTY_RAID_GRACE:
				print("[realm] nobody came back to party %d's raid; closing it" % pid)
				_end_raid(party)
		else:
			party["empty_t"] = 0.0
	_log_t += delta
	if _log_t >= 60.0:
		_log_t = 0.0
		if _snap_max > 0 or _lobby_max > 0:
			print("[realm] largest packets in the last minute: snapshot %d B, lobby %d B" % [_snap_max, _lobby_max])
		_snap_max = 0
		_lobby_max = 0
	_hub_t -= delta
	if _hub_t <= 0.0:
		_hub_t = maxf(_hub_t + HUB_RATE, 0.0)  # accumulate so frame timing does not round the rate down
		_send_hub_snapshot()
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = maxf(_snap_t + SNAPSHOT_RATE, 0.0)
		for pid in _parties:
			var party: Dictionary = _parties[pid]
			var w = party["world"]
			if not party["in_raid"] or w == null:
				continue
			var peers := _raid_peers(party)
			if peers.is_empty():
				continue
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
	if _dirty:
		_sync_lobbies()
