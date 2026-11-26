#!/bin/bash
# guard-agent-launch.sh — PreToolUse hook（Agent・Task）。1 つの会話がサブエージェントを起動し続けるのを、回数と時間で確認へ回す。
#
# 出典（2026-11-26）: 終わりの条件が無い依頼を受けた指揮（開発の流れを進める役）が、1 件終わるたびに次の仕事を自分で探して始め、
#   サブエージェントを起動し続けて、数時間、走り続けた。手順書には「契約に予算を書く」「一覧が尽きたら止まる」を足したが、
#   数えるのは指揮で、機械的に止める仕組みが無かった。
#
# すること: 会話（入力の session_id）ごとに、起動の回数と、最初の起動の時刻を数える。回数が上限を超える起動、または最初の起動から
#   上限の時間を過ぎたあとの起動を、確認（ask）に回す。session_id ごとに数える（agent_id は見ない）。
#   サブエージェントの中からの起動は、その session_id が親の会話と同じなら、同じ会話に数わる（同じかどうかは、確かめていない）。
# 防がないこと: すでに走っている役を止めること（hook からは止められない）。サブエージェントを使わずに、指揮が自分で走り続けること。
#   トークンや費用を数えること。会話をまたいだ合計。環境変数や状態のファイルを書き換えて、わざと歯止めを外すこと（事故を防ぐ仕組み）。
#
# なぜ「確認（ask）」で、「拒否（deny）」ではないか: guard-broad-op.sh と同じ。人が見ている場では人が選ぶ。誰も答えられない実行
#   （`claude -p`）では、Claude Code が呼び出しを拒否し、理由を Claude に返す（理由の文面に、止めて報告することを書いてある）。
#
# 確認のあと（弱さが在る）:
#   上限を超えたあと、起動のたびに確認するのではなく、確認に回した時点で「次に確認するところ」を進めて、状態に書く。
#   区切りは上限ごとに持つ: 回数の上限で確認に回したときは、回数の側だけ（いまの回数＋STEP_COUNT 回）、時間の上限で確認に
#   回したときは、時間の側だけ（いまの時刻＋STEP_SECONDS 秒）を進める。両方を同時に超えていたら、両方を進める。
#   片方の確認が、もう片方の上限を超えた起動を、知らせないまま通すことは無い（理由の文面にも、超えた上限だけを書く）。
#   hook は、人間が承認したか断ったかを知らない。だから:
#   - 断られた起動も 1 回に数える（実際には行われていない起動が、回数に入る）。
#   - 断られたあとも、進めたところまでは確認なしで通る。断られた指揮がすぐに打ち直すと、通る。
#     誰も答えられない実行でも同じで、拒否は区切りごとに 1 回だけ返り、その間の起動は通る。
#   行われた起動だけを数える作り（PostToolUse で数える）は、起動が終わるまで承認が分からず、並べて起動した分の突き合わせが要るので、採っていない。
#
# なぜ分からないときに通すか: この hook が原因で、起動そのものを失敗させない。jq が無い・壊れた JSON・session_id が無い、形が
#   おかしい・CLAUDE_PLUGIN_DATA が無い、書けない・状態のファイルが壊れている（数字でない）ときは、数えずに通す（理由は標準エラーに 1 行）。
#   壊れた状態のファイルは直さない（その会話は、ファイルが消えるまで数えないまま通る）。
#
# 状態: ${CLAUDE_PLUGIN_DATA}/agent-launch/<session_id>（1 行: 起動の回数 最初の起動の時刻 確認なしで通す回数 確認なしで通す時刻。時刻はエポック秒）。
#   CLAUDE_PLUGIN_ROOT には書かない（プラグインの更新で消える）。session_id は、英数字・-・_ だけ（128 文字まで）のものに限る
#   （ファイルの名前に使うので、置き場の外を指す形を受けない）。
#   書き込みは、同じフォルダの一時ファイルに書いてから mv する（途中で切れても、半分だけのファイルにならない）。鍵は掛けない:
#   同時に 2 つ発火すると、回数が 1 つ落ちることがある（許している。並列の hook が同じファイルを書くときの決まりは、公式の文書に無い）。
#   STALE_DAYS 日以上、書き換えられていない状態のファイルは、発火のついでに消す（消せなくても通す）。
#
# 変える: 環境変数 DEV_CREW_AGENT_LAUNCH_MAX（回数。既定 30）・DEV_CREW_AGENT_LAUNCH_MAX_SECONDS（秒。既定 10800 = 3 時間）。
#   0 以上の整数（9 桁まで）だけ。それ以外は既定に戻し、標準エラーに 1 行。0 は「その上限を使わない」ではない
#   （回数の 0 は最初の起動から、時間の 0 は 2 回目の起動から確認に回る）。区切り（STEP_COUNT・STEP_SECONDS）は、このファイルの定数。
# 無効にする: 環境変数 DEV_CREW_AGENT_LAUNCH_GUARD=off（小文字の off だけ。settings.json の `env` でもよい）。
# 確かめる:   bash guard-agent-launch.sh --self-test（jq が要る。使い捨てのフォルダを CLAUDE_PLUGIN_DATA にして流す）
#
# 確かめていないこと: 道具の名前が古い版で Task だったか（matcher は Agent|Task にしてある）。サブエージェントの中で発火したときの
#   session_id が、親の会話のものと同じか（同じなら、同じ会話として数える）。権限を全部許可するモード（permission mode）のとき、
#   hook の ask が確認として働くか。実際のセッションに組み込んでの発火。
#
# guard-broad-op.sh と違い、部品に分けていない（1 ファイル。読み込めない部品が在る、という壊れ方を持たない）。

LC_ALL=C
export LC_ALL

DEFAULT_MAX=30             # 起動の回数の上限
DEFAULT_MAX_SECONDS=10800  # 最初の起動からの時間の上限（3 時間）
STEP_COUNT=10              # 回数の上限で確認に回したあと、次に確認するまでの回数
STEP_SECONDS=1800          # 時間の上限で確認に回したあと、次に確認するまでの時間（30 分）
STALE_DAYS=7               # これ以上、書き換えられていない状態のファイルを消す

# 自己検査の場面（fire・state・check の実行）の総数。場面が黙って減ったら赤にするために、数を直に書く。
# 場面を足したり減らしたりしたら、--self-test が出す「場面の数」に書き換える
SCENARIOS=150

LIMIT=0

note() { printf 'guard-agent-launch: %s\n' "$1" >&2; }

pass() { note "$1ので、数えずに通します"; exit 0; }  # 数えずに通す（理由を標準エラーに 1 行）

is_number() {  # 0 以上の整数（12 桁まで。算術であふれない長さ）
  case $1 in '' | *[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 12 ]
}

read_limit() {  # $1 = 環境変数の名前 $2 = 既定。結果は LIMIT
  local value=${!1-}
  LIMIT=$2
  [ -n "$value" ] || return 0
  if is_number "$value" && [ "${#value}" -le 9 ]; then
    LIMIT=$((10#$value))
  else
    note "$1 が 0 以上の整数（9 桁まで）でないので、既定（$2）を使います"
  fi
}

duration() {  # $1 = 秒。「H 時間 M 分」
  printf '%s 時間 %s 分' $(($1 / 3600)) $(($1 % 3600 / 60))
}

main() {
  local input parsed tool sid dir file tmp now max max_seconds elapsed over_count=0 over_time=0 detail="" reason
  local count="" first="" ack_count="" ack_time="" extra=""
  [ "${DEV_CREW_AGENT_LAUNCH_GUARD:-}" = "off" ] && exit 0
  input=$(cat)
  [ -n "$input" ] || exit 0
  command -v jq >/dev/null 2>&1 || pass "jq が無い"
  parsed=$(printf '%s' "$input" | jq -r '(.tool_name | if type == "string" then . else "" end), (.session_id | if type == "string" then . else "" end)' 2>/dev/null) ||
    pass "入力を JSON として読めない"
  # 1 行目が道具の名前、残りが session_id（改行を含む session_id は、下の形の検査で落ちる）
  tool=${parsed%%$'\n'*}
  case $parsed in *$'\n'*) sid=${parsed#*$'\n'} ;; *) sid="" ;; esac
  case $tool in Agent | Task) ;; *) exit 0 ;; esac

  read_limit DEV_CREW_AGENT_LAUNCH_MAX "$DEFAULT_MAX"; max=$LIMIT
  read_limit DEV_CREW_AGENT_LAUNCH_MAX_SECONDS "$DEFAULT_MAX_SECONDS"; max_seconds=$LIMIT

  case $sid in
    '') pass "session_id が無い" ;;
    *[!A-Za-z0-9_-]*) pass "session_id が英数字・-・_ だけの形でない" ;;
  esac
  [ "${#sid}" -le 128 ] || pass "session_id が 128 文字を超える"
  case ${CLAUDE_PLUGIN_DATA:-} in
    /*) ;;
    *) pass "CLAUDE_PLUGIN_DATA が無い（または絶対パスでない）" ;;
  esac
  dir=$CLAUDE_PLUGIN_DATA/agent-launch
  mkdir -p "$dir" 2>/dev/null || pass "状態の置き場（CLAUDE_PLUGIN_DATA の下）を作れない"
  find "$dir" -maxdepth 1 -type f -mtime +$((STALE_DAYS - 1)) -exec rm -f {} + >/dev/null 2>&1

  now=${DEV_CREW_AGENT_LAUNCH_NOW:-}  # 自己検査が時刻を差し替える（ふだんは使わない）
  is_number "$now" || now=$(date +%s 2>/dev/null)
  is_number "$now" || pass "いまの時刻が分からない"

  file=$dir/$sid
  if [ -e "$file" ]; then
    # shellcheck disable=SC2162  # 数字だけを受けるので、-r は要らない（下で確かめる）
    read count first ack_count ack_time extra <"$file" 2>/dev/null
    if ! is_number "$count" || ! is_number "$first" || ! is_number "$ack_count" || ! is_number "$ack_time" || [ -n "$extra" ]; then
      pass "状態のファイルが壊れている（数字 4 つの形でない）"
    fi
    count=$((10#$count)); first=$((10#$first)); ack_count=$((10#$ack_count)); ack_time=$((10#$ack_time))
  else
    count=0; first=$now; ack_count=0; ack_time=0
  fi

  count=$((count + 1))
  elapsed=$((now - first))
  [ "$elapsed" -ge 0 ] || elapsed=0  # 時計が戻った
  # 上限を超えていて、かつ、その上限についての前の確認で進めたところも過ぎている。上限ごとに別々に見て、超えた側の区切りだけを進める
  if [ "$count" -gt "$max" ] && [ "$count" -gt "$ack_count" ]; then
    over_count=1
    ack_count=$((count + STEP_COUNT))
    detail="回数: いま ${count} 回目・上限 ${max} 回。次の確認は ${ack_count} 回目を超える起動"
  fi
  if [ "$elapsed" -gt "$max_seconds" ] && [ "$now" -gt "$ack_time" ]; then
    over_time=1
    ack_time=$((now + STEP_SECONDS))
    detail="${detail}${detail:+／}時間: 最初の起動から $(duration "$elapsed")・上限 $(duration "$max_seconds")。次の確認は $(duration "$STEP_SECONDS")を過ぎたあとの起動"
  fi

  tmp=$dir/.$sid.$$.tmp
  if ! printf '%s %s %s %s\n' "$count" "$first" "$ack_count" "$ack_time" 2>/dev/null >"$tmp" || ! mv -f "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    pass "状態のファイルを書けない"
  fi

  [ "$over_count" = 1 ] || [ "$over_time" = 1 ] || exit 0
  reason="この会話でのサブエージェントの起動が、歯止めの上限を超えました（${detail}）。すでに走っている役は、この確認では止まりません。
続けるなら承認する。止めるなら断って、できたこと・残ったことを人間に報告する（どちらでも、上の「次の確認」までは、その上限については確認なしで通る）。
上限を変える: 環境変数 DEV_CREW_AGENT_LAUNCH_MAX（回数）・DEV_CREW_AGENT_LAUNCH_MAX_SECONDS（秒）。無効にする: DEV_CREW_AGENT_LAUNCH_GUARD=off。"
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# ---- 自己検査 -------------------------------------------------------------

self_test() {
  local self=$1 tmp data dir fail=0 count=0 OUT="" NOW=1000000 T0=1000000 v sid before
  local DATA_ENV=()
  command -v jq >/dev/null 2>&1 || { echo "self-test: jq が要ります" >&2; return 1; }
  case $self in /*) ;; *) self=$PWD/$self ;; esac
  # 利用者の環境に在る設定を持ち込まない
  unset DEV_CREW_AGENT_LAUNCH_GUARD DEV_CREW_AGENT_LAUNCH_MAX DEV_CREW_AGENT_LAUNCH_MAX_SECONDS DEV_CREW_AGENT_LAUNCH_NOW CLAUDE_PLUGIN_DATA
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/guard-agent-launch.XXXXXX") || return 1
  # shellcheck disable=SC2064
  trap "chmod -R u+w '$tmp' 2>/dev/null; rm -rf '$tmp'" EXIT
  # 状態は、使い捨てのフォルダにだけ書く（実際の CLAUDE_PLUGIN_DATA には書かない）。hook は cwd で走らせ、相対パスに書いたら分かるようにする
  data=$tmp/root/data; dir=$data/agent-launch
  mkdir -p "$tmp/root/cwd" "$dir" "$tmp/bin"
  ln -s "$(command -v cat)" "$tmp/bin/cat"
  DATA_ENV=("CLAUDE_PLUGIN_DATA=$data")

  launch() {  # $1 = session_id $2 = 道具の名前（省けば Agent）。hook の入力を出す
    jq -n --arg sid "$1" --arg tool "${2:-Agent}" \
      '{session_id: $sid, cwd: "/", permission_mode: "default", hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {description: "self-test", prompt: "self-test", subagent_type: "general-purpose"}, tool_use_id: "toolu_self_test"}'
  }
  # 検査の本体。$1 = 期待 $2 = 説明 $3 = 入力 $4 以降 = 足す環境変数（名前=値）
  #   pass = 何も出さずに終了コード 0 ／ note = 標準出力は空・標準エラーに 1 行・終了コード 0
  #   ask = 確認の JSON・標準エラーは空・終了コード 0 ／ ask+note = 確認の JSON と、標準エラーに 1 行
  fire() {
    local want=$1 label=$2 input=$3 rc got notes
    shift 3
    count=$((count + 1))
    OUT=$(cd "$tmp/root/cwd" && printf '%s' "$input" | env "${DATA_ENV[@]}" "DEV_CREW_AGENT_LAUNCH_NOW=$NOW" "$@" "$BASH" "$self" 2>"$tmp/err"); rc=$?
    notes=$(wc -l <"$tmp/err" | tr -d ' ')
    if [ -z "$OUT" ]; then got=pass
    elif printf '%s' "$OUT" | jq -e '(keys == ["hookSpecificOutput"]) and (.hookSpecificOutput | (keys == ["hookEventName", "permissionDecision", "permissionDecisionReason"]) and .hookEventName == "PreToolUse" and .permissionDecision == "ask" and (.permissionDecisionReason | type == "string" and length > 0 and (split("\n") | length <= 3)))' >/dev/null 2>&1; then got=ask
    else got=invalid; fi
    case $got:$notes in
      pass:0 | ask:0) ;;
      pass:1) got=note ;;
      ask:1) got=ask+note ;;
      *) got="$got（標準エラー ${notes} 行）" ;;
    esac
    [ "$rc" = 0 ] || got="exit$rc"
    if [ "$got" = "$want" ]; then printf 'ok   %-8s  [%s]\n' "$want" "$label"
    else printf 'NG   want=%s got=%s  [%s]\n' "$want" "$got" "$label"; fail=1; fi
  }
  state() {  # $1 = session_id $2 = 期待する状態のファイルの中身（"-" = ファイルが無い）
    local got=-
    count=$((count + 1))
    [ -f "$dir/$1" ] && got=$(cat "$dir/$1")
    if [ "$got" = "$2" ]; then printf 'ok   state     %s = %s\n' "$1" "$2"
    else printf 'NG   state %s: want=%s got=%s\n' "$1" "$2" "$got"; fail=1; fi
  }
  check() {  # $1 = 説明 $2 以降 = 成り立つはずの命令
    local label=$1
    shift
    count=$((count + 1))
    if "$@" >/dev/null 2>&1; then printf 'ok   check     %s\n' "$label"
    else printf 'NG   check: %s\n' "$label"; fail=1; fi
  }
  # shellcheck disable=SC2329  # check に名前で渡して呼ぶ
  reason_has() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF -- "$1"; }
  # shellcheck disable=SC2329
  reason_lacks() { ! reason_has "$1"; }
  put() { printf '%s\n' "$2" >"$dir/$1"; }  # 状態のファイルを直に置く
  snapshot() { find "$tmp/root" | sort; cat "$dir"/* 2>/dev/null; }
  # shellcheck disable=SC2329
  no_tmp_left() { [ -z "$(find "$dir" -name '*.tmp')" ]; }

  echo "# 上限の内側は通し、超える起動を確認に回す（上限 3 回）"
  for v in 1 2 3; do fire pass "s1 の ${v} 回目" "$(launch s1)" DEV_CREW_AGENT_LAUNCH_MAX=3; done
  state s1 "3 $T0 0 0"
  fire ask "s1 の 4 回目（上限を超える）" "$(launch s1)" DEV_CREW_AGENT_LAUNCH_MAX=3
  check "理由に、いまの回数・上限・次の確認が在る" reason_has "回数: いま 4 回目・上限 3 回。次の確認は 14 回目を超える起動"
  check "理由に、超えていない時間の上限は無い" reason_lacks "時間:"
  check "理由に、断ったあとにすることが在る" reason_has "止めるなら断って、できたこと・残ったことを人間に報告する"
  check "理由に、上限の変え方が在る" reason_has "DEV_CREW_AGENT_LAUNCH_MAX_SECONDS"
  state s1 "4 $T0 14 0"
  echo "# 確認のあと、区切り（10 回）までは通る"
  for v in 5 6 7 8 9 10 11 12 13 14; do fire pass "s1 の ${v} 回目" "$(launch s1)" DEV_CREW_AGENT_LAUNCH_MAX=3; done
  state s1 "14 $T0 14 0"
  fire ask "s1 の 15 回目（区切りを超える）" "$(launch s1)" DEV_CREW_AGENT_LAUNCH_MAX=3
  state s1 "15 $T0 25 0"

  echo "# 時間の上限（既定 3 時間）と、確認のあとの区切り（30 分）"
  fire pass "s2 の最初の起動" "$(launch s2)"
  NOW=$((T0 + 10800)); fire pass "ちょうど 3 時間" "$(launch s2)"
  NOW=$((T0 + 10801)); fire ask "3 時間を 1 秒過ぎた" "$(launch s2)"
  check "理由に、経過時間・上限・次の確認が在る" reason_has "時間: 最初の起動から 3 時間 0 分・上限 3 時間 0 分。次の確認は 0 時間 30 分を過ぎたあとの起動"
  check "理由に、超えていない回数の上限は無い" reason_lacks "回数:"
  state s2 "3 $T0 0 $((T0 + 12601))"
  NOW=$((T0 + 10802)); fire pass "確認の直後" "$(launch s2)"
  NOW=$((T0 + 12601)); fire pass "確認からちょうど 30 分" "$(launch s2)"
  NOW=$((T0 + 12602)); fire ask "確認から 30 分を 1 秒過ぎた" "$(launch s2)"
  NOW=$T0; fire pass "s3 の最初の起動（上限 60 秒）" "$(launch s3)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=60
  NOW=$((T0 + 60)); fire pass "ちょうど 60 秒" "$(launch s3)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=60
  NOW=$((T0 + 61)); fire ask "61 秒" "$(launch s3)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=60
  NOW=$((T0 - 500)); fire pass "時計が戻った" "$(launch s2)"
  NOW=$T0

  echo "# 区切りは上限ごと（片方の確認が、もう片方の上限を超えた起動を通さない）"
  put x1 "24 $T0 0 0"
  NOW=$((T0 + 10801)); fire ask "x1 の 25 回目: 時間の上限だけで確認に回る" "$(launch x1)"
  state x1 "25 $T0 0 $((T0 + 12601))"
  for v in 26 27 28 29 30; do fire pass "x1 の ${v} 回目（時間は確認のあと、回数は上限の内側）" "$(launch x1)"; done
  fire ask "x1 の 31 回目: 時間の確認のあとでも、回数の上限で確認に回る" "$(launch x1)"
  check "理由に、回数の上限が在る" reason_has "回数: いま 31 回目・上限 30 回。次の確認は 41 回目を超える起動"
  check "理由に、確認が済んでいる時間の上限は無い" reason_lacks "時間:"
  state x1 "31 $T0 41 $((T0 + 12601))"
  put x2 "30 $T0 0 0"
  NOW=$((T0 + 100)); fire ask "x2 の 31 回目: 回数の上限だけで確認に回る" "$(launch x2)"
  state x2 "31 $T0 41 0"
  NOW=$((T0 + 10800)); fire pass "x2 の 32 回目（回数は確認のあと、時間は上限ちょうど）" "$(launch x2)"
  NOW=$((T0 + 10801)); fire ask "x2 の 33 回目: 回数の確認のあとでも、時間の上限で確認に回る" "$(launch x2)"
  check "理由に、時間の上限が在る" reason_has "時間: 最初の起動から 3 時間 0 分・上限 3 時間 0 分"
  check "理由に、確認が済んでいる回数の上限は無い" reason_lacks "回数:"
  state x2 "33 $T0 41 $((T0 + 12601))"
  put x3 "30 $T0 0 0"
  fire ask "x3 の 31 回目: 両方を同時に超える" "$(launch x3)"
  check "理由に、回数の上限が在る" reason_has "回数: いま 31 回目・上限 30 回。次の確認は 41 回目を超える起動"
  check "理由に、時間の上限も在る" reason_has "／時間: 最初の起動から 3 時間 0 分・上限 3 時間 0 分。次の確認は 0 時間 30 分を過ぎたあとの起動"
  state x3 "31 $T0 41 $((T0 + 12601))"
  NOW=$T0

  echo "# session_id が違えば別に数える。Task も、agent_id が付いた入力も、session_id が同じなら同じ会話に数える"
  fire pass "s4 の 1 回目（s1 は 15 回）" "$(launch s4)" DEV_CREW_AGENT_LAUNCH_MAX=3
  state s4 "1 $T0 0 0"
  state s1 "15 $T0 25 0"
  fire pass "道具の名前が Task" "$(launch s4 Task)" DEV_CREW_AGENT_LAUNCH_MAX=3
  fire pass "agent_id が付いた入力（session_id は同じ）" "$(launch s4 | jq '. + {agent_id: "agent-1", agent_type: "general-purpose"}')" DEV_CREW_AGENT_LAUNCH_MAX=3
  state s4 "3 $T0 0 0"
  fire ask "s4 の 4 回目" "$(launch s4 Task)" DEV_CREW_AGENT_LAUNCH_MAX=3

  echo "# Agent でも Task でもない道具は数えない"
  put s5 "30 $T0 0 0"
  fire pass "Bash" "$(launch s5 Bash)"
  fire pass "名前が Agent で始まる別の道具" "$(launch s5 AgentX)"
  fire pass "tool_name が無い" "$(launch s5 | jq 'del(.tool_name)')"
  fire pass "tool_name が文字列でない" "$(launch s5 | jq '.tool_name = ["Agent"]')"
  state s5 "30 $T0 0 0"
  fire ask "同じ会話の Agent は、31 回目として確認に回る" "$(launch s5)"

  echo "# 無効にする環境変数"
  put s6 "30 $T0 0 0"
  fire pass "off" "$(launch s6)" DEV_CREW_AGENT_LAUNCH_GUARD=off
  state s6 "30 $T0 0 0"
  fire ask "大文字の OFF は無効にしない" "$(launch s6)" DEV_CREW_AGENT_LAUNCH_GUARD=OFF

  echo "# 上限の環境変数（おかしな値は既定に戻す）"
  for v in abc -1 1.5 "1 0" 1234567890; do
    sid=bad-$count
    put "$sid" "29 $T0 0 0"
    fire note "回数の上限が「${v}」: 既定の 30 回目までは通る" "$(launch "$sid")" "DEV_CREW_AGENT_LAUNCH_MAX=$v"
    fire ask+note "回数の上限が「${v}」: 31 回目は確認に回る" "$(launch "$sid")" "DEV_CREW_AGENT_LAUNCH_MAX=$v"
  done
  put empty "29 $T0 0 0"
  fire pass "回数の上限が空: 既定（何も言わない）" "$(launch empty)" DEV_CREW_AGENT_LAUNCH_MAX=
  fire ask "回数の上限が空: 31 回目は確認に回る" "$(launch empty)" DEV_CREW_AGENT_LAUNCH_MAX=
  fire ask "回数の上限が 0: 最初の起動から確認に回る" "$(launch zero)" DEV_CREW_AGENT_LAUNCH_MAX=0
  put lead "7 $T0 0 0"
  # 0 で始まる数字は 10 進数に読む（008・009 は、8 進数に読むと算術の誤りになり、hook が終了コード 1 で終わる）
  fire pass "回数の上限が 008: 8 回目は通る（8 進数に読まない）" "$(launch lead)" DEV_CREW_AGENT_LAUNCH_MAX=008
  fire ask "回数の上限が 008: 9 回目は確認に回る" "$(launch lead)" DEV_CREW_AGENT_LAUNCH_MAX=008
  put lead9 "8 $T0 0 0"
  fire pass "回数の上限が 009: 9 回目は通る" "$(launch lead9)" DEV_CREW_AGENT_LAUNCH_MAX=009
  fire ask "回数の上限が 009: 10 回目は確認に回る" "$(launch lead9)" DEV_CREW_AGENT_LAUNCH_MAX=009
  NOW=$((T0 + 9)); fire pass "時間の上限が 009: 9 秒は通る" "$(launch lead9)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=009 DEV_CREW_AGENT_LAUNCH_MAX=99
  NOW=$((T0 + 10)); fire ask "時間の上限が 009: 10 秒は確認に回る" "$(launch lead9)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=009 DEV_CREW_AGENT_LAUNCH_MAX=99
  NOW=$T0
  put zeros "008 0$T0 009 08"
  fire pass "状態の数字が 0 で始まる（008）: 9 回目として数える" "$(launch zeros)"
  state zeros "9 $T0 9 8"
  put zeros "0029 0$T0 0 0"
  fire pass "状態の回数が 0029: 30 回目は通る" "$(launch zeros)"
  fire ask "状態の回数が 0029 から: 31 回目は確認に回る" "$(launch zeros)"
  put big "5000 $T0 0 0"
  fire pass "回数の上限が 999999999（9 桁）" "$(launch big)" DEV_CREW_AGENT_LAUNCH_MAX=999999999
  put sec "1 $T0 0 0"
  NOW=$((T0 + 10800)); fire note "時間の上限が「abc」: 既定の 3 時間ちょうどは通る" "$(launch sec)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=abc
  NOW=$((T0 + 10801)); fire ask+note "時間の上限が「abc」: 3 時間を過ぎたら確認に回る" "$(launch sec)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=abc
  NOW=$T0; fire pass "時間の上限が 0: 最初の起動は通る" "$(launch sec0)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=0
  NOW=$((T0 + 1)); fire ask "時間の上限が 0: 1 秒後の起動は確認に回る" "$(launch sec0)" DEV_CREW_AGENT_LAUNCH_MAX_SECONDS=0
  NOW=$T0

  echo "# 通す入力（数えない・数えられない）。状態の置き場にも、その外にも書かない"
  before=$(snapshot)
  fire note "壊れた JSON" '{"tool_name": "Agent", "session_id": "s7'
  fire pass "空の標準入力" ''
  fire note "JSON だが、オブジェクトでない" '["Agent"]'
  fire note "session_id が無い" "$(launch x | jq 'del(.session_id)')"
  fire note "session_id が文字列でない" "$(launch x | jq '.session_id = 7')"
  fire note "session_id が空" "$(launch "")"
  fire note "session_id が ../x" "$(launch ../x)"
  fire note "session_id が ../../cwd/x" "$(launch ../../cwd/x)"
  fire note "session_id が .." "$(launch ..)"
  fire note "session_id が a/b" "$(launch a/b)"
  fire note "session_id に空白" "$(launch "a b")"
  fire note "session_id に改行" "$(launch "a
b")"
  fire note "session_id が 129 文字" "$(launch "$(printf 'a%.0s' $(seq 1 129))")"
  fire note "jq が PATH に無い" "$(launch s7)" "PATH=$tmp/bin"
  DATA_ENV=(-u CLAUDE_PLUGIN_DATA)
  fire note "CLAUDE_PLUGIN_DATA が無い" "$(launch s7)"
  DATA_ENV=("CLAUDE_PLUGIN_DATA=")
  fire note "CLAUDE_PLUGIN_DATA が空" "$(launch s7)"
  DATA_ENV=("CLAUDE_PLUGIN_DATA=data")
  fire note "CLAUDE_PLUGIN_DATA が相対パス" "$(launch s7)"
  echo x >"$tmp/file"
  DATA_ENV=("CLAUDE_PLUGIN_DATA=$tmp/file")
  fire note "CLAUDE_PLUGIN_DATA がファイル（置き場を作れない）" "$(launch s7)"
  DATA_ENV=("CLAUDE_PLUGIN_DATA=$data")
  check "ここまでの「数えない」場面で、何も書いていない" [ "$before" = "$(snapshot)" ]
  echo "# 壊れた状態のファイル・書けない置き場（数えずに通し、ファイルは直さない）"
  for v in "abc" "1 2 3" "1 2 3 4 5" "" "1 x 0 0" "-1 $T0 0 0" "1.5 $T0 0 0" "1234567890123 $T0 0 0"; do
    put broken "$v"
    fire note "壊れた状態のファイル「${v}」" "$(launch broken)"
    state broken "$v"
  done
  rm "$dir/broken"; mkdir "$dir/broken"
  fire note "状態のファイルの場所がフォルダ" "$(launch broken)"
  rmdir "$dir/broken"
  put s8 "30 $T0 0 0"
  if [ "$(id -u)" = 0 ]; then
    count=$((count + 1)); echo "ok   （root なので、書けない置き場の場面は飛ばす）"
  else
    chmod 555 "$dir"
    fire note "状態の置き場に書けない（上限を超える起動でも通す）" "$(launch s8)"
    chmod 755 "$dir"
  fi
  state s8 "30 $T0 0 0"
  check "一時ファイルが残っていない" no_tmp_left
  fire pass "128 文字の session_id は数える" "$(launch "$(printf 'a%.0s' $(seq 1 128))")"
  state "$(printf 'a%.0s' $(seq 1 128))" "1 $T0 0 0"
  fire pass "英数字・-・_ の session_id は数える" "$(launch "0aZ_-9")"
  state "0aZ_-9" "1 $T0 0 0"

  echo "# 古い状態のファイルを消す。一時ファイルを残さない"
  put old "5 1 0 0"; touch -t 202001010000 "$dir/old"
  : >"$dir/.old.1.tmp"; touch -t 202001010000 "$dir/.old.1.tmp"
  fire pass "s9 の 1 回目" "$(launch s9)"
  state old "-"
  check "古い一時ファイルも消えている" no_tmp_left
  state s8 "30 $T0 0 0"
  check "置き場の外（cwd）に何も書いていない" [ -z "$(ls -A "$tmp/root/cwd")" ]

  echo "# 場面の数"
  if [ "$count" = "$SCENARIOS" ]; then echo "ok         場面の数 ${count} 件"
  else echo "NG   場面の数 ${count} 件（期待 ${SCENARIOS} 件）。足した・減らしたのが意図どおりなら、SCENARIOS を書き換える"; fail=1; fi

  if [ "$fail" = 0 ]; then echo "self-test: すべて期待どおり"; else echo "self-test: 期待と違う結果があります" >&2; fi
  return "$fail"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test "$0"
  exit $?
fi
main
