#!/usr/bin/env bash
# Online co-op smoke test: real Godot processes (1 host + 1..3 clients).
#   tools/mp_smoke.sh client_leaves   # LAN/direct (ENet): clients disconnect mid-mission
#   tools/mp_smoke.sh host_leaves     # LAN/direct (ENet): host disappears, clients return to menu
#   tools/mp_smoke.sh relay           # internet path: everyone connects through a local relay server
#   tools/mp_smoke.sh public          # internet path through the deployed public relay (needs internet)
# Options (env): MISSION=<mission id> (default: lobby default), PLAYERS=2..4 (default 2), RELEASE=<s> hunter release time,
#                HUNTERS=<n> expected hunters replicated to clients.
# Logs: $TMPDIR/ns_host.log, ns_client.log, ns_client2.log... (+ ns_relay.log). Exit 0 = all checks passed.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="${TMPDIR:-/tmp}"
SCENARIO="${1:-client_leaves}"
PORT="${PORT:-24577}"
PLAYERS="${PLAYERS:-2}"
MISSION="${MISSION:-}"
HUNTERS="${HUNTERS:-}"
ROOM="SMK$((RANDOM % 900 + 100))"

if [ "$SCENARIO" = "host_leaves" ]; then HOST_T=45; CLIENT_T=70; else HOST_T=75; CLIENT_T=45; fi
# extra players share one machine here: give everyone more time
EXTRA=$(( (PLAYERS - 2) * 30 )); HOST_T=$((HOST_T + EXTRA)); CLIENT_T=$((CLIENT_T + EXTRA))

RELAY_PID=""
case "$SCENARIO" in
	relay)
		RELAY_PORT="${RELAY_PORT:-9091}"
		RELAY="ws://127.0.0.1:$RELAY_PORT"
		"$DIR/godot.sh" --headless --path "$DIR/../server/relay" -- --port=$RELAY_PORT > "$TMP/ns_relay.log" 2>&1 &
		RELAY_PID=$!
		sleep 3
		HOST_ARGS="--ns-host-online --ns-room=$ROOM --ns-relay=$RELAY"
		CLIENT_ARGS="--ns-join-online=$ROOM --ns-relay=$RELAY"
		;;
	public)
		# default relay from project settings (wss://...onrender.com); may need ~1 min to wake up
		HOST_ARGS="--ns-host-online --ns-room=$ROOM"
		CLIENT_ARGS="--ns-join-online=$ROOM"
		HOST_T=$((HOST_T + 40)); CLIENT_T=$((CLIENT_T + 40))
		;;
	*)
		HOST_ARGS="--ns-port=$PORT --ns-host"
		CLIENT_ARGS="--ns-port=$PORT --ns-join=127.0.0.1"
		;;
esac
MISSION_ARG=""
[ -n "$MISSION" ] && MISSION_ARG="--ns-mission=$MISSION"

"$DIR/godot.sh" --headless -- --ns-profile=mp_host $HOST_ARGS $MISSION_ARG ${RELEASE:+--ns-release=$RELEASE} --ns-autostart=$PLAYERS --ns-bot --ns-quit-after=$HOST_T > "$TMP/ns_host.log" 2>&1 &
HOST_PID=$!
# wait until the host's lobby really exists (slow machines take a while with several instances)
for i in $(seq 1 120); do
	if grep -qE "online lobby ready|net] hosting on" "$TMP/ns_host.log" 2>/dev/null; then break; fi
	sleep 1
done
sleep 2
CLIENT_PIDS=""
for i in $(seq 1 $((PLAYERS - 1))); do
	SUFFIX=""; [ "$i" -gt 1 ] && SUFFIX="$i"
	"$DIR/godot.sh" --headless -- --ns-profile=mp_client$SUFFIX $CLIENT_ARGS --ns-bot --ns-quit-after=$CLIENT_T > "$TMP/ns_client$SUFFIX.log" 2>&1 &
	CLIENT_PIDS="$CLIENT_PIDS $!"
	sleep 1
done
for p in $CLIENT_PIDS; do wait $p; done
wait $HOST_PID
if [ -n "$RELAY_PID" ]; then kill $RELAY_PID 2>/dev/null; fi

fail=0
check() { if grep -q "$2" "$TMP/$1"; then echo "PASS  $1: $3"; else echo "FAIL  $1: $3"; fail=1; fi; }
check_not() { if grep -q "$2" "$TMP/$1"; then echo "FAIL  $1: $3"; grep -m3 -A3 "$2" "$TMP/$1"; fail=1; else echo "PASS  $1: $3"; fi; }

M="${MISSION:-[a-z_]*}"
check ns_host.log "registered as" "client registered with the authoritative host"
check ns_host.log "MISSION_STARTED $M .* players=$PLAYERS" "host started the $PLAYERS-player mission ${MISSION:-}"
check_not ns_host.log "SCRIPT ERROR" "no script errors on host"
for i in $(seq 1 $((PLAYERS - 1))); do
	SUFFIX=""; [ "$i" -gt 1 ] && SUFFIX="$i"
	L="ns_client$SUFFIX.log"
	check $L "MISSION_STARTED $M .* players=$PLAYERS" "client $i loaded the same mission"
	check $L "netstat.*players=\[1@" "client $i sees replicated players"
	check $L "netstat.*players=\[1@[^|]*held=battery" "client $i sees the item in the host's hand"
	check_not $L "SCRIPT ERROR" "no script errors on client $i"
	if [ -n "$HUNTERS" ]; then
		last=$(grep "netstat" "$TMP/$L" | tail -1)
		n=$(echo "$last" | grep -o "Enemy_" | wc -l)
		if [ "$n" -eq "$HUNTERS" ]; then echo "PASS  $L: $HUNTERS hunters replicated"; else echo "FAIL  $L: expected $HUNTERS hunters, saw $n"; fail=1; fi
		if echo "$last" | grep -q "Enemy_[0-9]*@([^)]*)\(PATROL\|CHASE\|INVESTIGATE\|SEARCH\|ALERT\|ATTACK\|IDLE\|LOST_TARGET\|RETURN_TO_PATROL\)"; then
			echo "PASS  $L: hunter AI state replicated"
		else
			echo "WARN  $L: hunters not active yet in last snapshot"
		fi
	fi
done
case "$SCENARIO" in
	relay)
		check ns_relay.log "room $ROOM opened" "relay opened the host's room"
		check ns_relay.log "joined $ROOM ($PLAYERS players)" "all clients joined through the relay"
		check ns_client.log "joining online lobby $ROOM" "client used the online path"
		check ns_host.log "disconnected - dropping their items" "host handles client disconnect over the relay"
		;;
	public)
		check ns_host.log "online lobby ready, code $ROOM" "public relay opened the room"
		check ns_client.log "joining online lobby $ROOM via wss://" "client connected over TLS"
		check ns_host.log "disconnected - dropping their items" "host handles client disconnect over the internet"
		;;
	host_leaves)
		check ns_client.log "lost connection to host" "client detects host loss"
		;;
	*)
		check ns_host.log "disconnected - dropping their items" "host handles client disconnect"
		if awk '/disconnected - dropping/{d=1} d && /netstat/{n++} END{exit !(n>=1)}' "$TMP/ns_host.log"; then
			echo "PASS  ns_host.log: mission keeps running after the disconnect"
		else
			echo "FAIL  ns_host.log: mission keeps running after the disconnect"; fail=1
		fi
		;;
esac
exit $fail
