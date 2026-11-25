#!/bin/bash
# guard-broad-op.sh — PreToolUse hook（Bash）。範囲の広い操作・取り返しのつきにくい操作を、実行の前に確認へ回す。
# 失敗の基準 `unguarded-broad-op`（reference/failure-criteria.md）の手当ての置き場。
#
# なぜ「確認（ask）」で、「拒否（deny）」ではないか:
#   このプラグインを入れた全リポジトリ・全セッションで効くので、誤検出で作業を止めると被害が大きい。
#   人が見ている場では人が選べるようにする。誰も答えられない実行（`claude -p`）では、Claude Code が
#   呼び出しを拒否し、理由を Claude に返す（理由の文面に、代わりにすることを書いてある）。
# なぜ分からない入力を通すか:
#   この hook は最後の砦ではなく、取りこぼしを減らす仕組み。壊れた JSON・jq が無い・長すぎるコマンド・
#   変数や置換で中身が決まる引数は、検査せずに通す（通した理由は標準エラーに 1 行。debug ログに残る）。
#
# 状態を見る git は読むだけにする（--no-optional-locks。利用者の index を書き換えない）。回数と時間に上限を置き、
#   上限で判定できなかったときは「実害が無い」と言えないので、確認に回す。
#
# 無効にする: 環境変数 DEV_CREW_GUARD_BROAD_OP=off（小文字の off だけ。settings.json の `env` でもよい）。
# 確かめる:   bash guard-broad-op.sh --self-test（jq と git が要る）
#
# ファイルの構成（入口はこのファイルだけ。部品はこのファイルの場所から読み込む）:
#   guard-broad-op.sh       共通の変数と小関数、部品の読み込み、命令の振り分け（check_segment）、入口（main）
#   lib/scan.sh             語の切り出し（scan）
#   rules/<規則>.sh         規則（rule_*）と、その規則だけが使う補助
#   self-test/run.sh        自己検査の共通部分（使い捨てのリポジトリの準備、t・quick・raw）
#   self-test/hook.sh       規則によらない場面 ／ self-test/<規則>.sh  規則ごとの場面
#   部品が 1 つでも欠けているとき（ファイルが無い・最後まで読めない・規則の関数が定義されない・このスクリプトの場所が
#   分からない）は、規則が欠けたまま検査を続けない。検査の対象になりうるコマンド（main の、語の切り出しを省く case に
#   当たるもの）を、中身を見ずに全部確認へ回す（理由に欠けている部品を書く。標準エラーにも 1 行）。それ以外のコマンドは通す。
#   jq が無い・壊れた入力・長すぎるコマンドは、部品が揃っているときと同じく通す。--self-test は赤（exit 1）にする。
#   シンボリックリンク経由で呼ぶと、リンクの置き場所から部品を探すので見つからない（リンクはたどらない）。
#
# 規則を足すとき:
#   1. 実際に起きた形だけを狭く書く（出典の課題番号をコメントに残す）。迷う形は通す。
#   2. rules/<規則>.sh に rule_* を書き、止める理由と「代わりにすること」を 1〜2 行で hit に渡す。
#      関数の名前は rule_<規則>（ファイルの名前と揃える）。ファイルの最後に、ほかの部品と同じ LOADED の行を置く。
#   3. このファイルに登録する: RULES に名前を足し、check_segment の case から rule_<規則> を呼ぶ
#      （見る命令の名前が増えるなら、main の、語の切り出しを省く case にも足す）。
#      RULES と、check_segment が呼ぶ rule_* が食い違うと、--self-test が赤になる。
#   4. self-test/<規則>.sh の self_test_<規則> に「止まる入力」と「紛らわしいが止まらない入力」を書く（無いと --self-test が赤になる）。
#      場面を足したり減らしたりしたら、self-test/run.sh の SCENARIOS（場面の総数）を、--self-test が出す数に書き換える。
#   5. README の「作業中の操作を確認に回す hook」の表に 1 行足す。
#   語の切り出し（scan）は、引用符・$(...)・ヒアドキュメントの中を命令として読まない。
#   命令の位置にある語だけを見るので、echo の引数やコミットメッセージの中の文字列は拾わない。

LC_ALL=C
export LC_ALL

MAX_COMMAND_BYTES=20000
MAX_DEPTH=40          # 引用符と $(...) の入れ子。深い再帰で bash が落ちる前にやめる
MAX_GIT_CALLS=6       # 1 回の実行で状態を見る git の回数
GIT_LIMIT_SECONDS=2   # 状態を見る git 1 回の上限

CMD=""; N=0; I=0
WORD=""; HAVE=0
WORDS=(); HEREDOCS=()
CWD=""; CWD_OK=0
REASONS=""; SEEN=""
DEPTH=0; TOO_DEEP=0
PIPELINE=""           # いまのパイプラインで、ここまでに出た命令の名前
FETCHED=0             # 同じコマンドの中で、先に origin を更新する命令があったか
GIT_CALLS=0; GIT_OUT=""
U_ALL="-"; U_DOT="-"  # 未追跡の件数の控え（"-" = まだ見ていない、"" = 判定できなかった）
RESET_SEEN=""

note() { printf 'guard-broad-op: %s\n' "$1" >&2; }

seen() { case " $SEEN " in *" $1 "*) return 0 ;; esac; return 1; }

hit() {  # $1 = 規則の名前（同じ規則は 1 回だけ載せる） $2 = 理由と代わりにすること
  case " $SEEN " in *" $1 "*) return ;; esac
  SEEN="$SEEN $1"
  REASONS="${REASONS}${REASONS:+
}$2"
}

# ---- 部品の読み込み -------------------------------------------------------

# 規則の名前。rules/<名前>.sh を読み込み、自己検査では self-test/<名前>.sh の self_test_<名前> をこの順に呼ぶ
RULES="kill format git"

# 部品は、このスクリプト自身の場所から探す（作業ディレクトリにも CLAUDE_PLUGIN_ROOT にも頼らない）。
# 場所が分からないとき（標準入力や -c で渡された、など）は空にして、部品が欠けているときと同じ扱いにする
case ${BASH_SOURCE[0]:-} in
  */*) HOOK_DIR=${BASH_SOURCE[0]%/*} ;;
  "") HOOK_DIR="" ;;
  *) if [ -f "./${BASH_SOURCE[0]}" ]; then HOOK_DIR=.; else HOOK_DIR=""; fi ;;  # 名前だけで呼ばれた。作業ディレクトリに在るときだけ
esac
LOADED=""   # 最後まで読めた部品（各部品の最後の行が、自分のパスを足す）
MISSING=""  # 欠けている部品（理由の文面に使う）

# $@ = HOOK_DIR からの相対パス。欠けているものがあれば MISSING に入れ、1 を返す。
# 読めたかどうかは、部品の最後の行まで実行されたか（LOADED）で見る。部品の最後の命令の終了コードでは見ない
# （構文エラーなら bash はそこで読むのをやめるので、最後の行に届かない）。
# 先にサブシェルで試し読みをする: bash 4 以降は、引用符や $( が閉じないまま終わる部品を読むと、シェルごと終わる。
# このプロセスで読むと、何も出力せずに終わって、確認に回せない。試し読みは、いま読んでいる部品の名前を 1 行ずつ出し、
# 全部読めたら最後に ok を出す（途中で終わっても、最後の行が欠けている部品の名前になる）
# 試し読みの本体。load_parts が $( ) の中（サブシェル）で呼ぶ。関数に分けてあるのは、bash 3.2 が $( ) の中に直に書いた
# case の閉じ括弧を数え損ねるため
probe_parts() {
  local part
  exec 2>/dev/null </dev/null
  for part in "$@"; do
    printf '%s\n' "$part"
    [ -r "$HOOK_DIR/$part" ] || exit 1
    # shellcheck source=/dev/null
    . "$HOOK_DIR/$part" >/dev/null
    case " $LOADED " in *" $part "*) ;; *) exit 1 ;; esac
  done
  echo ok
}

load_parts() {
  local part probe
  MISSING=${1:-}
  [ -n "$HOOK_DIR" ] || return 1
  probe=$(probe_parts "$@")
  if [ "${probe##*$'\n'}" != ok ]; then
    [ -n "$probe" ] && MISSING=${probe##*$'\n'}
    return 1
  fi
  for part in "$@"; do
    MISSING=$part
    # shellcheck source=/dev/null
    . "$HOOK_DIR/$part"
    case " $LOADED " in *" $part "*) ;; *) return 1 ;; esac
  done
  MISSING=""
}

have_functions() {  # $@ = 関数の名前。定義されていないものがあれば、MISSING に入れて 1 を返す
  local fn
  for fn in "$@"; do
    declare -F "$fn" >/dev/null && continue
    MISSING="関数 $fn"
    return 1
  done
}

# ---- 命令の振り分け -------------------------------------------------------

check_segment() {
  local n=${#WORDS[@]} i=0 j w name cmd located=0
  local A=()
  # リダイレクトは引数に数えない
  while [ "$i" -lt "$n" ]; do
    w=${WORDS[$i]}
    case $w in
      '>' | '>>' | '<' | '&>' | '&>>' | [0-9]'>' | [0-9]'>>' | [0-9]'<') i=$((i + 2)); continue ;;
      '>'* | '<'* | '&>'* | [0-9]'>'* | [0-9]'<'*) i=$((i + 1)); continue ;;
    esac
    A[${#A[@]}]=$w
    i=$((i + 1))
  done
  n=${#A[@]}; i=0
  # 命令の前に付く語（代入・予約語・包む命令とそのオプション）を飛ばして、命令の位置を取る
  while [ "$i" -lt "$n" ]; do
    w=${A[$i]}
    case $w in
      [A-Za-z_]*=*)
        name=${w%%=*}
        case $name in
          *[!A-Za-z0-9_]*) ;;
          *)
            case $name in GIT_DIR | GIT_WORK_TREE) located=1 ;; esac
            i=$((i + 1)); continue
            ;;
        esac
        ;;
    esac
    case ${w##*/} in
      '{' | '}' | '!' | if | then | else | elif | fi | do | done | while | until | nohup) i=$((i + 1)) ;;
      time | command) i=$((i + 1)); skip_flags "" "" ;;
      exec) i=$((i + 1)); skip_flags "a" "" ;;
      nice) i=$((i + 1)); skip_flags "n" "" ;;
      sudo) i=$((i + 1)); skip_flags "ughpCDRTUrt" "-D" ;;
      env) i=$((i + 1)); skip_flags "uCS" "-C" ;;
      timeout) i=$((i + 1)); skip_flags "sk" ""; i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  cmd=${A[$i]##*/}
  case $cmd in
    npx | bunx | pnpm | yarn | npm)
      j=$((i + 1))
      while [ "$j" -lt "$n" ] && [ "$j" -le $((i + 3)) ]; do
        case ${A[$j]##*/} in prettier | prettier@*) i=$j; cmd=prettier; break ;; esac
        j=$((j + 1))
      done
      ;;
  esac
  i=$((i + 1))
  case $cmd in
    cd | pushd | popd) CWD_OK=0 ;;
    export)
      for w in "${A[@]:$i}"; do
        case $w in GIT_DIR=* | GIT_WORK_TREE=*) CWD_OK=0 ;; esac
      done
      ;;
    pkill | killall | kill | xargs) rule_kill "$cmd" "${A[@]:$i}" ;;
    gofmt | go | prettier) rule_format "$cmd" "${A[@]:$i}" ;;
    git) rule_git "$located" "${A[@]:$i}" ;;
  esac
  PIPELINE="$PIPELINE $cmd"
  return 0
}

skip_flags() {  # check_segment の i を、包む命令のオプションの後ろへ進める。$1 = 値を取る 1 文字のオプション $2 = 作業ディレクトリを変えるオプション
  local f
  while [ "$i" -lt "$n" ]; do
    f=${A[$i]}
    case $f in
      --) i=$((i + 1)); return ;;
      --chdir=*) located=1 ;;
      --chdir) located=1; i=$((i + 1)) ;;
      --user | --group | --host | --prompt | --unset | --signal | --kill-after | --adjustment | --split-string) i=$((i + 1)) ;;
      --*) ;;
      -?)
        [ -n "$2" ] && [ "$f" = "$2" ] && located=1
        case $1 in *"${f#-}"*) i=$((i + 1)) ;; esac
        ;;
      -*) ;;
      *) return ;;
    esac
    i=$((i + 1))
  done
}

# ---- 入口 -----------------------------------------------------------------

main() {
  local input
  [ "${DEV_CREW_GUARD_BROAD_OP:-}" = "off" ] && exit 0
  input=$(cat)
  [ -n "$input" ] || exit 0
  if ! command -v jq >/dev/null 2>&1; then
    note "jq が無いので、検査せずに通します"
    exit 0
  fi
  CMD=$(printf '%s' "$input" | jq -r 'if .tool_name == "Bash" then (.tool_input.command | if type == "string" then . else "" end) else "" end' 2>/dev/null) || {
    note "入力を JSON として読めないので、検査せずに通します"
    exit 0
  }
  # 規則が見る命令の名前がどこにも無ければ、語の切り出しをしない（ほとんどの呼び出しはここで終わる）
  case $CMD in
    *kill* | *gofmt* | *"go "* | *prettier* | *git*) ;;
    *) exit 0 ;;
  esac
  N=${#CMD}
  if [ "$N" -gt "$MAX_COMMAND_BYTES" ]; then
    note "コマンドが ${MAX_COMMAND_BYTES} バイトを超えるので、検査せずに通します"
    exit 0
  fi
  CWD=$(printf '%s' "$input" | jq -r '.cwd | if type == "string" then . else "" end' 2>/dev/null)
  [ -n "$CWD" ] && [ -d "$CWD" ] && CWD_OK=1

  scan

  if [ "$TOO_DEEP" = 1 ]; then
    note "引用符と \$(...) の入れ子が ${MAX_DEPTH} 段を超えるので、検査せずに通します"
    exit 0
  fi
  [ -n "$REASONS" ] || exit 0
  jq -n --arg reason "$REASONS" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

PARTS="lib/scan.sh"; NEEDED="scan"
for rule in $RULES; do PARTS="$PARTS rules/$rule.sh"; NEEDED="$NEEDED rule_$rule"; done
# shellcheck disable=SC2086  # 空白で区切った一覧を、語に分けて渡す
if ! load_parts $PARTS || ! have_functions $NEEDED; then
  if [ "${1:-}" = "--self-test" ]; then
    echo "self-test: 部品（${MISSING}）を読み込めません" >&2
    exit 1
  fi
  # 規則が欠けたまま検査を続けない。語の切り出しを「必ず確認に回す」に差し替えて、main に進む。
  # こうすると、無効にする環境変数・jq が無い・壊れた入力・検査の対象でないコマンドは、部品が揃っているときと同じ動きになる
  scan() {
    note "部品（${MISSING}）を読み込めないので、中身を見ずに確認に回します"
    REASONS="guard-broad-op の部品（${MISSING}）を読み込めないので、このコマンドが範囲の広い操作・取り返しのつきにくい操作に当たるかを検査できていません。内容を確かめてから実行してください。直すには、dev-crew プラグインを入れ直してください。"
  }
  main
fi

if [ "${1:-}" = "--self-test" ]; then
  PARTS="self-test/run.sh self-test/hook.sh"; NEEDED="self_test self_test_harmless self_test_unchecked self_test_parts"
  for rule in $RULES; do PARTS="$PARTS self-test/$rule.sh"; NEEDED="$NEEDED self_test_$rule"; done
  # shellcheck disable=SC2086
  if ! load_parts $PARTS || ! have_functions $NEEDED; then
    echo "self-test: 部品（${MISSING}）を読み込めません" >&2
    exit 1
  fi
  self_test "$0"
  exit $?
fi
main
