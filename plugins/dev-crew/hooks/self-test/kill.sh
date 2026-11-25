#!/bin/bash
# self-test/kill.sh — rules/kill.sh の場面。self-test/run.sh の self_test から呼ばれる部品（単体では実行しない）。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

self_test_kill() {
  echo "# kill（#46）"
  t ask  "$p" 'pkill -f "node .*dev-server"'
  t ask  "$p" 'killall node'
  t ask  "$p" 'npm test; pkill -f vite'
  t ask  "$p" 'sudo /usr/bin/pkill -9 -f worker'
  t ask  "$p" 'kill $(pgrep -f vite)'
  t ask  "$p" 'kill -9 `lsof -ti:3000`'
  t pass "$p" 'kill 12345'
  t pass "$p" 'kill -TERM "$SERVER_PID"'
  t pass "$p" 'kill $(cat .server.pid)'
  t pass "$p" 'echo "pkill -f vite で止めない"'
  t pass "$p" 'git commit -m "pkill を hook で確認に回す"'
  t pass "$p" 'grep -rn "killall" docs/'
  t pass "$p" 'pgrep -fl vite'
  t pass "$p" 'npm run skill-lint'
  t ask  "$p" 'lsof -ti:3000 | xargs kill -9'
  t ask  "$p" 'pgrep -f vite | xargs kill'
  t ask  "$p" 'ps aux | grep vite | awk "{print \$2}" | xargs -n 1 kill'
  t pass "$p" 'cat .pids | xargs kill'
  t pass "$p" 'pgrep -f vite || xargs kill < .pids'
  t pass "$p" 'pgrep -f vite | xargs echo kill'
  t ask  "$p" 'timeout 5 pkill -f vite'
  t ask  "$p" 'timeout -s KILL 5 pkill -f vite'
  t ask  "$p" 'nice -n 10 killall node'
  t ask  "$p" 'nohup pkill -f vite'
  t ask  "$p" 'time -p pkill -f vite'
  t ask  "$p" 'sudo -u app pkill -f worker'
  t ask  "$p" 'env -u NODE_ENV pkill -f vite'
  t ask  "$p" 'NODE_ENV=test env FOO=1 pkill -f vite'
  t pass "$p" 'timeout 5 npm test'
  t pass "$p" 'sudo -u pkill ls'
  t pass "$p" 'ls # x; pkill -f vite'
}

LOADED="$LOADED self-test/kill.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
