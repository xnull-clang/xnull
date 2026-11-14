#!/usr/bin/env bash
# XDK 源码层 E2E（B5 过渡）：text / sys / resources / net。
# 前置：bootstrap/bin/{xparser,xn-s4} 已构建（无 Go 亦可）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
export XNULL_XDK_SOURCE=1
pass=0; fail=0
run_case() {
  local name=$1; shift
  local out rc want
  out=$(cd "$ROOT" && bin/xnull --bootstrap run "$HERE/$name.x" -- "$@" 2>&1); rc=$?
  want=$(cat "$HERE/$name.expect")
  if [ $rc -eq 0 ] && [ "$out" = "$want" ]; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL $name rc=$rc"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") | head -20
    fail=$((fail+1))
  fi
}

rm -f /tmp/xdk-src-file.txt /tmp/xdk-src-none.txt /tmp/xdk-io.bin /tmp/xdk-io-copy.bin /tmp/xdk-io-moved.bin; rmdir /tmp/xdk-io-dir 2>/dev/null
run_case text
run_case core_bytes
run_case core_text
run_case core_builder
run_case core_containers
run_case sync_atomic_ref
run_case tasks_group
run_case errors_report
run_case sys_file
run_case io_binary

export XNULL_RESOURCES="$HERE/resources"
run_case resources
run_case resources_cancel
unset XNULL_RESOURCES

# net_http：动态端口 + 本地 http.server。
http_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
(cd "$HERE" && python3 -m http.server "$http_port" >/dev/null 2>&1) &
srv=$!
sleep 1
run_case net_http "$http_port"
kill $srv 2>/dev/null

# net_socket：动态端口 + 本地 echo 服务。
socket_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
XDK_SOCKET_PORT=$socket_port python3 - <<'PY2' &
import os, socket
port = int(os.environ["XDK_SOCKET_PORT"])
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port))
s.listen(1)
c, _ = s.accept()
data = c.recv(16)
c.sendall(data)
c.close()
s.close()
PY2
srv=$!
sleep 1
run_case net_socket "$socket_port"
kill $srv 2>/dev/null

# net_listener：动态端口，需真实客户端并发连接。
listener_out=$(mktemp "${TMPDIR:-/tmp}/xdk-listener.XXXXXX")
listener_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
(cd "$ROOT" && perl -e 'alarm 120; exec @ARGV' bin/xnull --bootstrap run "$HERE/net_listener.x" -- "$listener_port" > "$listener_out" 2>&1) &
srv=$!
XDK_LISTENER_PORT=$listener_port python3 - <<'PY3'
import os, socket, time
port = int(os.environ["XDK_LISTENER_PORT"])
s = socket.socket()
last = None
for _ in range(100):
    try:
        s.connect(("127.0.0.1", port))
        break
    except OSError as exc:
        last = exc
        time.sleep(0.1)
else:
    raise last
s.sendall(b"ping")
assert s.recv(4) == b"pong"
s.close()
PY3
client_rc=$?
if [ $client_rc -ne 0 ]; then kill $srv 2>/dev/null; fi
if wait $srv; then server_rc=0; else server_rc=$?; fi
want=$(cat "$HERE/net_listener.expect")
out=$(cat "$listener_out")
if [ $client_rc -eq 0 ] && [ $server_rc -eq 0 ] && [ "$out" = "$want" ]; then
  echo "PASS net_listener"; pass=$((pass+1))
else
  echo "FAIL net_listener client=$client_rc server=$server_rc"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") | head -20
  fail=$((fail+1))
fi
rm -f "$listener_out"

echo "XDK 源码层：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
