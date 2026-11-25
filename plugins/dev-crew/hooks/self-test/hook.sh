#!/bin/bash
# self-test/hook.sh — 規則によらない場面（hook 自身が害にならない・検査せずに通す入力）。
# self-test/run.sh の self_test から呼ばれる部品（単体では実行しない）。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

self_test_harmless() {
  echo "# hook 自身が害にならない"
  # index を書き換えない: 内容は同じで時刻だけ違うファイルがあると、ふつうの git status は index を書き直す
  touch -t 202201010000 "$d/a.txt"
  touch -t 202001010000 "$d/.git/index"
  touch -t 202101010000 "$tmp/marker"
  t ask  "$d" 'git add -A'
  count=$((count + 1))
  if [ "$d/.git/index" -nt "$tmp/marker" ]; then echo "NG   hook が .git/index を書き換えた"; fail=1
  else echo "ok         .git/index を書き換えていない"; fi
  # 同じ判定は 1 回だけ（1600 回並べても git を 1600 回は起動しない）
  many=$(printf 'git add -A;%.0s' $(seq 1 1600))
  quick 5 pass "$c" "$many"
  # 状態を見る git が返ってこないとき: 上限で打ち切り、実害が無いとは言えないので確認に回す
  T_PATH="$tmp/slow:$PATH"
  quick 6 ask  "$c" 'git add -A'
  quick 6 ask  "$c" 'git reset --soft origin/behind'
  T_PATH=""
  # 深い入れ子: 落ちずに通す
  deep=$(printf '"$(%.0s' $(seq 1 4500))
  raw "深い入れ子（4500 段）" "$(jq -n --arg c "git status $deep" '{tool_name:"Bash",tool_input:{command:$c}}')" "$BASH" "$self"
  t ask  "$d" 'echo "$(echo "$(echo "$(date)")")"; git add -A'
  # 利用者の設定で未追跡が status に出なくても、add は巻き込む
  t ask  "$h" 'git add -A'
  # 算術の << はヒアドキュメントではない。後ろの行を読み飛ばさない
  t ask  "$d" 'echo $((1<<2))
git add -A'
  t ask  "$d" 'x=$(echo $((1 << 3)))
git add -A'
  t ask  "$d" 'echo $((1<<2))
git add -A
2'
  t ask  "$d" '(( n = 1 << 2 ))
git add -A'
  t ask  "$d" 'cat <<NEVER_CLOSED
memo
git add -A'
}

self_test_unchecked() {
  echo "# 通す入力（検査しない・できない）"
  raw "壊れた JSON" '{"tool_name": "Bash", "tool_input": {"command": "pkill' "$BASH" "$self"
  raw "空の標準入力" '' "$BASH" "$self"
  raw "コマンドが空" '{"tool_name":"Bash","tool_input":{"command":""}}' "$BASH" "$self"
  raw "コマンドが文字列でない" '{"tool_name":"Bash","tool_input":{"command":{"x":"pkill"}}}' "$BASH" "$self"
  raw "Bash 以外の道具" '{"tool_name":"Write","tool_input":{"command":"pkill -f x","file_path":"/x"}}' "$BASH" "$self"
  raw "無効にする環境変数" '{"tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' env DEV_CREW_GUARD_BROAD_OP=off "$BASH" "$self"
  mkdir -p "$tmp/bin"
  ln -s "$(command -v cat)" "$tmp/bin/cat"
  raw "jq が PATH に無い" '{"tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' env PATH="$tmp/bin" "$BASH" "$self"
  local long
  long=$(printf 'x%.0s' $(seq 1 20001))
  raw "長すぎるコマンド" "$(jq -n --arg c "pkill -f x; echo $long" '{tool_name:"Bash",tool_input:{command:$c}}')" "$BASH" "$self"
  # 20000 バイトちょうどは検査し、1 バイト超えたら通す（数は直に書く。上限の値を変えたら、ここが赤になる）
  pad=$(printf 'x%.0s' $(seq 1 19983))
  t ask  "$p" "pkill -f x; echo $pad"
  t pass "$p" "pkill -f x; echo x$pad"
}

# 部品が欠けた写しを使い捨てで作り、規則が欠けたまま検査を続けないことを確かめる。
# kill 12345 は、部品が揃っていれば通る。確認に回れば、中身を見ずに回したことが分かる
self_test_parts() {
  local copy=$tmp/copy self
  echo "# 部品が欠けているとき"
  fresh() { rm -rf "$copy"; cp -R "$HOOK_DIR" "$copy"; }
  fresh; self=$copy/guard-broad-op.sh
  # 写しは、そのままなら元と同じに動く
  t pass "$p" 'kill 12345'
  t ask  "$p" 'pkill -f x'
  # 規則のファイルが無い: 検査の対象になりうるコマンドは確認に回し、それ以外は通す
  rm "$copy/rules/kill.sh"
  t ask  "$p" 'kill 12345'
  t ask  "$c" 'git status'
  t pass "$p" 'ls -la'
  raw "部品が欠けていて、壊れた JSON" '{"tool_name": "Bash", "tool_input": {"command": "pkill' "$BASH" "$self"
  raw "部品が欠けていて、Bash 以外の道具" '{"tool_name":"Write","tool_input":{"command":"pkill -f x","file_path":"/x"}}' "$BASH" "$self"
  raw "部品が欠けていて、無効にする環境変数" '{"tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' env DEV_CREW_GUARD_BROAD_OP=off "$BASH" "$self"
  mkdir -p "$tmp/bin"
  [ -e "$tmp/bin/cat" ] || ln -s "$(command -v cat)" "$tmp/bin/cat"
  raw "部品が欠けていて、jq が PATH に無い" '{"tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' env PATH="$tmp/bin" "$BASH" "$self"
  count=$((count + 1))
  if "$BASH" "$self" --self-test >/dev/null 2>&1; then echo "NG   部品が欠けているのに --self-test が緑"; fail=1
  else echo "ok         部品が欠けていると --self-test が赤"; fi
  # 語の切り出しが無い
  fresh; rm "$copy/lib/scan.sh"
  t ask  "$p" 'kill 12345'
  t pass "$p" 'ls -la'
  # ファイルは在るが、規則の関数が定義されない
  fresh; echo true >"$copy/rules/format.sh"
  t ask  "$p" 'kill 12345'
  # 構文エラーで最後まで読めない（規則の関数は定義されている）。閉じていない関数を、最後の行の前に入れる
  fresh
  { sed '$d' "$HOOK_DIR/rules/git.sh"; echo 'broken() {'; tail -n 1 "$HOOK_DIR/rules/git.sh"; } >"$copy/rules/git.sh"
  t ask  "$p" 'kill 12345'
  # 途中で切れた部品・閉じていない引用符（bash 4 以降は、読んだシェルごと終わる形。hook のプロセスは終わらせない）
  fresh; head -c 900 "$HOOK_DIR/rules/git.sh" >"$copy/rules/git.sh"
  t ask  "$p" 'kill 12345'
  t pass "$p" 'ls -la'
  fresh
  { head -n 29 "$HOOK_DIR/lib/scan.sh"; echo 'x="abc'; tail -n +30 "$HOOK_DIR/lib/scan.sh"; } >"$copy/lib/scan.sh"
  t ask  "$p" 'kill 12345'
  t pass "$p" 'ls -la'
  fresh; : >"$copy/rules/kill.sh"
  t ask  "$p" 'kill 12345'
  # 部品の最後の命令が 1 を返すだけなら、欠けている扱いにしない
  fresh; echo false >>"$copy/rules/git.sh"
  t pass "$p" 'kill 12345'
  t ask  "$p" 'pkill -f x'
  t pass "$c" 'git add -A'
}

LOADED="$LOADED self-test/hook.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
