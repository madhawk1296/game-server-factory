#!/usr/bin/env bash
# v1 acceptance tests. Run from local/.
#   ./test.sh          non-destructive checks only
#   ./test.sh --full   also replaces a container and cycles a world's lifecycle
set -uo pipefail
cd "$(dirname "$0")"

PASS=0; FAIL=0
ok()   { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
head_() { printf "\n\033[1m%s\033[0m\n" "$1"; }

ping_motd() { python3 -c "
import sys; sys.path.insert(0,'test')
from slp import ping
try:
    r = ping('127.0.0.1', int('$2'), '$1')
    d = r.get('description')
    print(d.get('text') if isinstance(d, dict) else d)
except Exception:
    print('REFUSED')
"; }

head_ "Config matches reality"
if terraform plan -detailed-exitcode -no-color >/dev/null 2>&1; then
  ok "no drift between config and running infrastructure"
else
  [ $? -eq 2 ] && bad "terraform plan shows pending changes" || bad "terraform plan errored"
fi

head_ "Worlds are up"
for w in smp creative; do
  st=$(docker inspect -f '{{.State.Status}}' "mc-$w" 2>/dev/null || echo missing)
  check "mc-$w running" "$st" "running"
done

head_ "Resource limits enforced (v1.1)"
for w in smp creative; do
  m=$(docker inspect -f '{{.HostConfig.Memory}}' "mc-$w")
  s=$(docker inspect -f '{{.HostConfig.MemorySwap}}' "mc-$w")
  [ "$m" -gt 0 ] && ok "mc-$w has a hard memory cap ($((m/1048576))MB)" || bad "mc-$w is unlimited"
  check "mc-$w swap disabled" "$m" "$s"
done

head_ "Worlds are isolated (v1.2)"
docker exec -i mc-smp      rcon-cli forceload add 0 0 >/dev/null 2>&1
docker exec -i mc-creative rcon-cli forceload add 0 0 >/dev/null 2>&1
a=$(docker exec -i mc-smp      rcon-cli execute if block 0 100 0 minecraft:gold_block 2>/dev/null)
b=$(docker exec -i mc-creative rcon-cli execute if block 0 100 0 minecraft:gold_block 2>/dev/null)
check "gold block present in smp"     "$a" "Test passed"
check "gold block absent in creative" "$b" "Test failed"
check "smp is survival"     "$(docker exec mc-smp      sh -c 'grep -h ^gamemode= /data/server.properties')" "gamemode=survival"
check "creative is creative" "$(docker exec mc-creative sh -c 'grep -h ^gamemode= /data/server.properties')" "gamemode=creative"

head_ "One port, many worlds (v1.3)"
check "smp.mc.localhost      -> Survival"              "$(ping_motd smp.mc.localhost 25565)"      "Survival"
check "creative.mc.localhost -> Creative build server" "$(ping_motd creative.mc.localhost 25565)" "Creative build server"
check "unmapped hostname refused"                      "$(ping_motd nope.mc.localhost 25565)"     "REFUSED"
check "no default route"                               "$(ping_motd localhost 25565)"             "REFUSED"

head_ "Exposed surface (v1.4)"
check "smp published on 25566"    "$(ping_motd localhost 25566)" "Survival"
check "creative not published"    "$(ping_motd localhost 25567)" "REFUSED"

head_ "Backups exist and restore (v1.6)"
for w in smp creative; do
  n=$(docker exec "mc-$w-backup" restic snapshots 2>/dev/null | grep -cE '^[0-9a-f]{8} ')
  [ "${n:-0}" -ge 1 ] && ok "$w has $n restic snapshot(s)" || bad "$w has no snapshots"
done
if docker exec mc-minio sh -c 'grep -rql "level.dat" /data/mc-backups 2>/dev/null | head -1' | grep -q .; then
  bad "plaintext found in bucket"
else
  ok "bucket contents are encrypted"
fi
if docker exec mc-smp-backup sh -c 'rm -rf /tmp/t && restic restore latest --target /tmp/t >/dev/null 2>&1 && test -f /tmp/t/data/world/level.dat'; then
  ok "restore produces a usable world (level.dat present)"
else
  bad "restore failed"
fi

if [ "${1:-}" = "--full" ]; then
  head_ "Server is disposable (v0)"
  docker exec -i mc-smp rcon-cli setblock 0 101 0 minecraft:emerald_block >/dev/null
  old=$(docker inspect -f '{{.Id}}' mc-smp)
  terraform apply -replace='docker_container.mc["smp"]' -auto-approve -no-color >/dev/null 2>&1
  for _ in $(seq 1 60); do docker logs mc-smp 2>&1 | grep -q 'Done (' && break; sleep 3; done
  new=$(docker inspect -f '{{.Id}}' mc-smp)
  [ "$old" != "$new" ] && ok "container was genuinely replaced" || bad "container not replaced"
  docker exec -i mc-smp rcon-cli forceload add 0 0 >/dev/null 2>&1
  check "unsaved block survived replacement" \
    "$(docker exec -i mc-smp rcon-cli execute if block 0 101 0 minecraft:emerald_block)" "Test passed"

  head_ "Lifecycle stop/start keeps data (v1.5)"
  cp variables.tf .variables.tf.bak
  trap 'cp .variables.tf.bak variables.tf 2>/dev/null; rm -f .variables.tf.bak' EXIT
  docker exec -i mc-creative rcon-cli setblock 0 101 0 minecraft:diamond_block >/dev/null

  sed -i '' 's/^    creative = {$/    creative = {\
      state      = "stopped"/' variables.tf
  terraform apply -auto-approve -no-color >/dev/null 2>&1

  gone=$(docker ps -q --filter "name=^mc-creative$" | wc -l | tr -d ' ')
  vol=$(docker volume ls -q --filter name=mc-creative-data | wc -l | tr -d ' ')
  check "stopped: container removed" "$gone" "0"
  check "stopped: volume retained"   "$vol"  "1"
  check "stopped: route withdrawn"   "$(ping_motd creative.mc.localhost 25565)" "REFUSED"
  check "stopped: smp unaffected"    "$(ping_motd smp.mc.localhost 25565)"      "Survival"

  cp .variables.tf.bak variables.tf; rm -f .variables.tf.bak; trap - EXIT
  terraform apply -auto-approve -no-color >/dev/null 2>&1
  for _ in $(seq 1 60); do docker logs mc-creative 2>&1 | grep -q 'Done (' && break; sleep 3; done
  docker exec -i mc-creative rcon-cli forceload add 0 0 >/dev/null 2>&1
  check "restarted: world data survived" \
    "$(docker exec -i mc-creative rcon-cli execute if block 0 101 0 minecraft:diamond_block)" "Test passed"

fi

head_ "Result"
printf "  %d passed, %d failed\n\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
