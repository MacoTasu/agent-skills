#!/bin/bash
# self-test/run.sh — 自己検査の共通部分。guard-broad-op.sh --self-test が読み込む部品（単体では実行しない）。
# 使い捨てのリポジトリの準備と、検査の道具（t・quick・raw）はここ 1 か所。場面は self-test/hook.sh（規則によらないもの）と
# self-test/<規則>.sh（入口の RULES の順に呼ぶ）に分けてある。場面の関数は、ここの local（tmp・fail・d・c・p・h など）を使う。

# 場面（t・raw の実行。quick は t を呼ぶ。t・raw を通らない確認は、その場で count を足している）の総数。場面が黙って減ったら赤にするために、数を直に書く。
# 場面を足したり減らしたりしたら、--self-test が出す「場面の数」に書き換える
SCENARIOS=170

self_test() {
  local self=$1 tmp fail=0 T_PATH="" many deep pad
  local count=0 rule called="" want=""
  command -v jq >/dev/null 2>&1 || { echo "self-test: jq が要ります" >&2; return 1; }
  command -v git >/dev/null 2>&1 || { echo "self-test: git が要ります" >&2; return 1; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/guard-broad-op.XXXXXX") || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  g() { git -c user.name=self-test -c user.email=self-test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1; }

  # dirty: 未追跡のファイルがある／clean: 未追跡が無い（追跡済みの変更だけ）
  mkdir -p "$tmp/dirty/pkg" "$tmp/clean" "$tmp/plain"
  g -C "$tmp/dirty" init -q
  echo a >"$tmp/dirty/a.txt"; echo 'package pkg' >"$tmp/dirty/pkg/main.go"
  g -C "$tmp/dirty" add a.txt pkg/main.go; g -C "$tmp/dirty" commit -q -m c1
  echo stray >"$tmp/dirty/stray.txt"
  g -C "$tmp/clean" init -q
  echo a >"$tmp/clean/a.txt"
  g -C "$tmp/clean" add a.txt; g -C "$tmp/clean" commit -q -m c1
  echo b >>"$tmp/clean/a.txt"
  # reset 用: origin/behind は HEAD の祖先、origin/ahead は HEAD に無いコミットを持つ
  g -C "$tmp/clean" update-ref refs/remotes/origin/behind HEAD
  g -C "$tmp/clean" checkout -q -b side
  g -C "$tmp/clean" commit -q --allow-empty -m side
  g -C "$tmp/clean" update-ref refs/remotes/origin/ahead HEAD
  g -C "$tmp/clean" checkout -q -
  g -C "$tmp/clean" commit -q -am c2
  # @{u} を origin/ahead に向ける
  g -C "$tmp/clean" config remote.origin.url ../nowhere
  g -C "$tmp/clean" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  g -C "$tmp/clean" config "branch.$(git -C "$tmp/clean" symbolic-ref --short HEAD).remote" origin
  g -C "$tmp/clean" config "branch.$(git -C "$tmp/clean" symbolic-ref --short HEAD).merge" refs/heads/ahead
  # hidden: 未追跡のファイルがあるが、利用者の設定で status には出ない
  mkdir -p "$tmp/hidden"
  g -C "$tmp/hidden" init -q
  echo a >"$tmp/hidden/a.txt"
  g -C "$tmp/hidden" add a.txt; g -C "$tmp/hidden" commit -q -m c1
  g -C "$tmp/hidden" config status.showUntrackedFiles no
  echo stray >"$tmp/hidden/stray.txt"
  # 止まったままの git（時間の上限を確かめる）
  mkdir -p "$tmp/slow"
  printf '#!/bin/sh\nexec sleep 30\n' >"$tmp/slow/git"
  chmod +x "$tmp/slow/git"
  git -C "$tmp/clean" merge-base --is-ancestor origin/behind HEAD 2>/dev/null || { echo "self-test: 準備に失敗（origin/behind）" >&2; return 1; }
  git -C "$tmp/clean" merge-base --is-ancestor origin/ahead HEAD 2>/dev/null && { echo "self-test: 準備に失敗（origin/ahead）" >&2; return 1; }

  # 検査の本体。$1 = 期待（ask / pass） $2 = cwd $3 = コマンド
  t() {
    local want=$1 dir=$2 command=$3 out rc got
    count=$((count + 1))
    out=$(jq -n --arg cwd "$dir" --arg command "$command" \
      '{session_id: "self-test", cwd: $cwd, permission_mode: "default", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $command, description: "self-test"}, tool_use_id: "toolu_self_test"}' |
      PATH=${T_PATH:-$PATH} "$BASH" "$self" 2>/dev/null)
    rc=$?
    [ "${#command}" -le 160 ] || command="${command:0:60} ...（${#command} バイト）"
    if [ -z "$out" ]; then got=pass
    else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "invalid"' 2>/dev/null) || got=invalid; fi
    [ "$rc" = 0 ] || got="exit$rc"
    if [ "$got" = "$want" ]; then printf 'ok   %-4s  %s\n' "$want" "$command" | tr '\n' ' '; echo
    else printf 'NG   want=%s got=%s  %s\n' "$want" "$got" "$command"; fail=1; fi
  }
  # t と同じ。加えて、$1 秒以内に終わることを確かめる
  quick() {
    local limit=$1 began=$SECONDS
    shift
    t "$@"
    if [ $((SECONDS - began)) -gt "$limit" ]; then printf 'NG   %s 秒を超えた（%s 秒）\n' "$limit" $((SECONDS - began)); fail=1; fi
  }
  # 生の入力をそのまま渡す。$1 = 説明 $2 = 入力（常に、出力なし・終了コード 0 を期待）
  raw() {
    local label=$1 input=$2 out rc
    count=$((count + 1))
    shift 2
    out=$(printf '%s' "$input" | "$@" 2>/dev/null); rc=$?
    if [ "$rc" = 0 ] && [ -z "$out" ]; then printf 'ok   pass  [%s]\n' "$label"
    else printf 'NG   want=pass got=exit%s out=%s  [%s]\n' "$rc" "$out" "$label"; fail=1; fi
  }

  local d=$tmp/dirty c=$tmp/clean p=$tmp/plain h=$tmp/hidden

  # 場面の関数を呼ぶ。1 件も場面を実行しなければ赤（中身が空になった・途中で抜けた、を緑にしない）
  section() {
    local began=$count
    "$1"
    if [ "$count" -le "$began" ]; then echo "NG   $1 が場面を 1 件も実行していない"; fail=1; fi
  }

  section self_test_harmless
  for rule in $RULES; do section "self_test_$rule"; done
  section self_test_unchecked
  section self_test_parts

  echo "# 登録と場面の数"
  # 入口の RULES と、check_segment が呼ぶ rule_* が食い違っていないか（declare -f の出力にコメントは入らない）
  called=$(declare -f check_segment | grep -o 'rule_[a-z_]*' | sort -u | tr '\n' ' ')
  want=$(for rule in $RULES; do echo "rule_$rule"; done | sort -u | tr '\n' ' ')
  if [ -n "$called" ] && [ "$called" = "$want" ]; then echo "ok         RULES と check_segment が呼ぶ規則が同じ（${called% }）"
  else echo "NG   RULES（${want% }）と、check_segment が呼ぶ規則（${called% }）が違う"; fail=1; fi
  if [ "$count" = "$SCENARIOS" ]; then echo "ok         場面の数 ${count} 件"
  else echo "NG   場面の数 ${count} 件（期待 ${SCENARIOS} 件）。足した・減らしたのが意図どおりなら、self-test/run.sh の SCENARIOS を書き換える"; fail=1; fi

  if [ "$fail" = 0 ]; then echo "self-test: すべて期待どおり"; else echo "self-test: 期待と違う結果があります" >&2; fi
  return "$fail"
}

LOADED="$LOADED self-test/run.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
