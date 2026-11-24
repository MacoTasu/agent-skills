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
# 規則を足すとき:
#   1. 実際に起きた形だけを狭く書く（出典の課題番号をコメントに残す）。迷う形は通す。
#   2. rule_* を足して check_segment の case から呼び、止める理由と「代わりにすること」を 1〜2 行で hit に渡す。
#   3. self_test に「止まる入力」と「紛らわしいが止まらない入力」を足す。
#   4. README の「作業中の操作を確認に回す hook」の表に 1 行足す。
#   語の切り出し（scan）は、引用符・$(...)・ヒアドキュメントの中を命令として読まない。
#   命令の位置にある語だけを見るので、echo の引数やコミットメッセージの中の文字列は拾わない。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

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

# ---- 語の切り出し ---------------------------------------------------------

read_heredoc_delim() {  # I は "<<" の先頭。区切りの語を HEREDOCS に積み、I をその直後へ進める
  local j=$((I + 2)) c d=""
  [ "${CMD:$j:1}" = "-" ] && j=$((j + 1))
  while [ "${CMD:$j:1}" = " " ] || [ "${CMD:$j:1}" = "	" ]; do j=$((j + 1)); done
  while [ "$j" -lt "$N" ]; do
    c=${CMD:$j:1}
    case $c in
      "'" | '"' | \\) ;;
      [A-Za-z0-9_.-]) d="$d$c" ;;
      *) break ;;
    esac
    j=$((j + 1))
  done
  [ -n "$d" ] && HEREDOCS[${#HEREDOCS[@]}]=$d
  I=$j
}

skip_heredocs() {  # I は改行。積んである区切りの行まで本文を読み飛ばす（I は区切りの行の末尾の改行か N）
  local k=0 delim rest line start found
  while [ "$k" -lt "${#HEREDOCS[@]}" ]; do
    delim=${HEREDOCS[$k]}
    start=$I; found=0
    while [ "$I" -lt "$N" ]; do
      rest=${CMD:$((I + 1))}
      line=${rest%%$'\n'*}
      I=$((I + 1 + ${#line}))
      while [ "${line#	}" != "$line" ]; do line=${line#	}; done
      if [ "$line" = "$delim" ]; then found=1; break; fi
    done
    if [ "$found" = 0 ]; then
      # 区切りの行が無い（<< がヒアドキュメントでなかった、など）。読み飛ばすと後ろを丸ごと見逃すので、戻って検査する
      I=$start
      note "ヒアドキュメントの区切り（${delim}）が見つからないので、読み飛ばさずに検査します"
    fi
    k=$((k + 1))
  done
  HEREDOCS=()
}

skip_squote() {  # I は開きの '。I を閉じの直後へ進める
  local rest seg
  rest=${CMD:$((I + 1))}
  seg=${rest%%\'*}
  I=$((I + ${#seg} + 2))
}

skip_backtick() {  # I は開きの `。I を閉じの直後へ進める
  local rest seg
  rest=${CMD:$((I + 1))}
  seg=${rest%%\`*}
  I=$((I + ${#seg} + 2))
}

enter() {  # 入れ子を 1 段深くする。上限を超えたら、残りを読まずに終わらせる（main が検査せずに通す）
  DEPTH=$((DEPTH + 1))
  [ "$DEPTH" -le "$MAX_DEPTH" ] && return 0
  TOO_DEEP=1; I=$N
  return 1
}

skip_dollar() {  # I は $。"$((" か "$(" なら読み飛ばして 0、どちらでもなければ何もせず 1
  if [ "${CMD:$I:3}" = '$((' ]; then skip_subst 2 1; return 0; fi
  if [ "${CMD:$I:2}" = '$(' ]; then skip_subst 2 0; return 0; fi
  return 1
}

skip_dquote() {  # I は開きの "。I を閉じの直後へ進める
  local c
  enter || return 0
  I=$((I + 1))
  while [ "$I" -lt "$N" ]; do
    c=${CMD:$I:1}
    case $c in
      \\) I=$((I + 2)); continue ;;
      '"') I=$((I + 1)); break ;;
      '$') skip_dollar && continue ;;
      '`') skip_backtick; continue ;;
    esac
    I=$((I + 1))
  done
  DEPTH=$((DEPTH - 1))
}

skip_subst() {  # I は開きの先頭。$1 = 開きのうち数えずに進める長さ（"$(" は 2、"((" は 1） $2 = 1 なら算術。対応する ) の直後へ進める
  local depth=1 c arith=$2
  enter || return 0
  I=$((I + $1))
  while [ "$I" -lt "$N" ] && [ "$depth" -gt 0 ]; do
    c=${CMD:$I:1}
    case $c in
      \\) I=$((I + 2)); continue ;;
      "'") skip_squote; continue ;;
      '"') skip_dquote; continue ;;
      '`') skip_backtick; continue ;;
      '$') skip_dollar && continue ;;
      '(') depth=$((depth + 1)) ;;
      ')') depth=$((depth - 1)) ;;
      '<')
        # 算術の中の << はシフト。ヒアドキュメントとして読むと、後ろの行を丸ごと読み飛ばす
        if [ "$arith" = 0 ]; then
          if [ "${CMD:$I:3}" = "<<<" ]; then I=$((I + 3)); continue; fi
          if [ "${CMD:$I:2}" = "<<" ]; then read_heredoc_delim; continue; fi
        fi
        ;;
      $'\n') [ "${#HEREDOCS[@]}" -gt 0 ] && skip_heredocs ;;
    esac
    I=$((I + 1))
  done
  DEPTH=$((DEPTH - 1))
}

end_word() {
  if [ "$HAVE" = 1 ]; then
    WORDS[${#WORDS[@]}]=$WORD
    WORD=""; HAVE=0
  fi
}

end_segment() {  # $1 = "|" なら、パイプで次の命令へ続く
  end_word
  [ "${#WORDS[@]}" -gt 0 ] && check_segment
  [ "${1:-}" = "|" ] || PIPELINE=""
  WORDS=()
}

scan() {
  local c start len rest seg
  I=0; WORD=""; HAVE=0; WORDS=(); HEREDOCS=()
  while [ "$I" -lt "$N" ]; do
    c=${CMD:$I:1}
    case $c in
      ' ' | '	') end_word ;;
      $'\n')
        end_segment
        [ "${#HEREDOCS[@]}" -gt 0 ] && skip_heredocs
        ;;
      '&')
        # 2>&1 や &> はリダイレクトの一部。命令の区切りにしない
        if [ "$I" -gt 0 ] && [ "${CMD:$((I - 1)):1}" = ">" ]; then WORD="$WORD$c"; HAVE=1
        elif [ "${CMD:$((I + 1)):1}" = ">" ]; then WORD="$WORD$c"; HAVE=1
        else end_segment; fi
        ;;
      '|')
        case ${CMD:$((I + 1)):1} in
          '|') end_segment; I=$((I + 2)); continue ;;
          '&') end_segment "|"; I=$((I + 2)); continue ;;
        esac
        end_segment "|"
        ;;
      '(')
        end_segment
        # (( ... )) は算術。中の << をヒアドキュメントとして読まない
        if [ "${CMD:$I:2}" = "((" ]; then skip_subst 1 1; continue; fi
        ;;
      ';' | ')') end_segment ;;
      \\)
        if [ "${CMD:$((I + 1)):1}" != $'\n' ]; then WORD="$WORD${CMD:$((I + 1)):1}"; HAVE=1; fi
        I=$((I + 2)); continue
        ;;
      "'")
        start=$I; skip_squote
        len=$((I - start - 2)); [ "$len" -lt 0 ] && len=0
        WORD="$WORD${CMD:$((start + 1)):$len}"; HAVE=1; continue
        ;;
      '"')
        start=$I; skip_dquote
        len=$((I - start - 2)); [ "$len" -lt 0 ] && len=0
        WORD="$WORD${CMD:$((start + 1)):$len}"; HAVE=1; continue
        ;;
      '$')
        start=$I
        if skip_dollar; then WORD="$WORD${CMD:$start:$((I - start))}"; HAVE=1; continue; fi
        WORD="$WORD$c"; HAVE=1
        ;;
      '`')
        start=$I; skip_backtick
        WORD="$WORD${CMD:$start:$((I - start))}"; HAVE=1; continue
        ;;
      '#')
        if [ "$HAVE" = 0 ]; then
          rest=${CMD:$I}; seg=${rest%%$'\n'*}
          I=$((I + ${#seg})); continue
        fi
        WORD="$WORD$c"
        ;;
      '<')
        if [ "${CMD:$I:3}" = "<<<" ]; then WORD="$WORD<<<"; HAVE=1; I=$((I + 3)); continue; fi
        if [ "${CMD:$I:2}" = "<<" ]; then end_word; read_heredoc_delim; continue; fi
        WORD="$WORD$c"; HAVE=1
        ;;
      *) WORD="$WORD$c"; HAVE=1 ;;
    esac
    I=$((I + 1))
  done
  end_segment
}

# ---- 規則 -----------------------------------------------------------------

# #46: 名前やポートの条件で探したプロセスの停止。同じ条件に一致する、別の作業のプロセスも止まる。
rule_kill() {  # $1 = 命令の名前、残り = 引数
  local cmd=$1 a found=0 skip=0
  shift
  case $cmd in
    pkill | killall) found=1 ;;
    xargs)
      # pgrep ... | xargs kill の形。探す命令がパイプの前にあるときだけ（控えた PID の一覧を渡す形は通す）
      case " $PIPELINE " in
        *" pgrep "* | *" pidof "* | *" lsof "* | *" ps "*)
          # xargs が実行する命令（オプションの後ろの最初の語）だけを見る
          for a in "$@"; do
            if [ "$skip" = 1 ]; then skip=0; continue; fi
            case $a in
              -[nIPLsEda]) skip=1; continue ;;
              -*) continue ;;
            esac
            case ${a##*/} in kill | pkill | killall) found=1 ;; esac
            break
          done
          ;;
      esac
      ;;
    kill)
      for a in "$@"; do
        case $a in
          *'$('* | *'`'*)
            case $a in *pgrep* | *pidof* | *lsof* | *"ps "*) found=1 ;; esac
            ;;
        esac
      done
      ;;
  esac
  [ "$found" = 1 ] || return 0
  hit kill "名前やポートの条件で探したプロセスをまとめて止めようとしています（pkill / killall / kill \$(pgrep ...) / pgrep ... | xargs kill の形）。同じ条件に一致する、別の作業のプロセスも止まります。自分で起動して控えた PID だけを kill <pid> で止めてください。"
}

is_broad_path() {  # 引数が、ディレクトリ全体（やその配下すべて）を指すか。分からない形は「指さない」にする
  case $1 in
    -*) return 1 ;;
    *'$'* | *'`'* | *'*'*) return 1 ;;
    . | ./ | .. | ../ | */ | */. | ... | */...) return 0 ;;
    /*) [ -d "$1" ]; return ;;
  esac
  [ "$CWD_OK" = 1 ] && [ -d "$CWD/$1" ]
}

# #52: ディレクトリ全体への書き込みの整形。無関係なファイルが差分に入る。
rule_format() {  # $1 = gofmt | go | prettier、残り = 引数
  local cmd=$1 a write=0 broad=0 skip=0 isfmt=0
  shift
  case $cmd in
    gofmt)
      for a in "$@"; do
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case $a in
          -w | --w | -w=true | --w=true) write=1 ;;
          -r | --r | -cpuprofile | --cpuprofile) skip=1 ;;
          *) is_broad_path "$a" && broad=1 ;;
        esac
      done
      ;;
    go)
      # go fmt は常に書き込む。対象が広いのは、配下すべてを指す ... の形だけ
      for a in "$@"; do
        if [ "$isfmt" = 0 ]; then
          case $a in -*) continue ;; fmt) isfmt=1; write=1; continue ;; *) return 0 ;; esac
        fi
        case $a in -*) ;; *...*) broad=1 ;; esac
      done
      ;;
    prettier)
      for a in "$@"; do
        case $a in
          --write | -w) write=1 ;;
          *) is_broad_path "$a" && broad=1 ;;
        esac
      done
      ;;
  esac
  [ "$write" = 1 ] && [ "$broad" = 1 ] || return 0
  hit format "書き込みの整形（gofmt -w / go fmt / prettier --write）が、ディレクトリ全体を対象にしています。無関係なファイルまで書き換わり、差分に入ります。変更したファイルだけを名指しで渡してください（例: gofmt -w \$(git diff --name-only -- '*.go')）。"
}

git_look() {  # 状態を読むだけの git。出力は GIT_OUT。戻り値が 0 と 1 以外なら「判定できなかった」
  GIT_OUT=""
  [ "$GIT_CALLS" -lt "$MAX_GIT_CALLS" ] || return 125
  GIT_CALLS=$((GIT_CALLS + 1))
  # macOS 標準には timeout が無いので、見張りを自前で置く。--no-optional-locks: 読むだけにして index を書き換えない
  GIT_OUT=$(
    git --no-optional-locks -C "$CWD" "$@" 2>/dev/null &
    pid=$!
    (
      trap 'kill "$nap" 2>/dev/null; exit 0' TERM
      sleep "$GIT_LIMIT_SECONDS" &
      nap=$!
      wait "$nap" && kill "$pid"
    ) >/dev/null 2>&1 &
    watch=$!
    wait "$pid"
    rc=$?
    kill "$watch" 2>/dev/null
    exit "$rc"
  )
}

count_untracked() {  # $1 = all | dot。結果は UNTRACKED（件数。判定できなければ空）。同じ実行の中では 1 回だけ見る
  local line n=0
  if [ "$1" = all ]; then UNTRACKED=$U_ALL; else UNTRACKED=$U_DOT; fi
  [ "$UNTRACKED" = "-" ] || return 0
  UNTRACKED=""
  # --untracked-files を明示する: status.showUntrackedFiles=no の利用者でも、add が巻き込むものを数える
  if [ "$1" = all ]; then set -- all status --porcelain --untracked-files=normal
  else set -- dot status --porcelain --untracked-files=normal -- .; fi
  if git_look "${@:2}"; then
    while IFS= read -r line; do
      case $line in '??'*) n=$((n + 1)) ;; esac
    done <<EOF
$GIT_OUT
EOF
    UNTRACKED=$n
  fi
  if [ "$1" = all ]; then U_ALL=$UNTRACKED; else U_DOT=$UNTRACKED; fi
}

rule_git() {  # $1 = 1 なら、前置きで git の対象が変えられている。残り = git より後ろの語
  local sub="" located=$1 a
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      -C | --git-dir | --work-tree) located=1; shift; [ $# -gt 0 ] && shift ;;
      --git-dir=* | --work-tree=*) located=1; shift ;;
      -c | --namespace | --exec-path | --super-prefix | --config-env) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) sub=$1; shift; break ;;
    esac
  done
  # 状態を見て「実害が無い」と分かったときだけ通す。hook の cwd と git の対象がずれうるとき（cd の後・-C 指定）は見ない
  local can_look=0
  [ "$CWD_OK" = 1 ] && [ "$located" = 0 ] && command -v git >/dev/null 2>&1 && can_look=1

  case $sub in
    add)
      # #75: 未追跡のファイルを巻き込む一括のステージ
      local all=0 dot=0 npath=0 skip=0 dd=0 count=""
      seen add && return 0
      for a in "$@"; do
        if [ "$dd" = 0 ]; then
          case $a in
            --) dd=1; continue ;;
            --all | --no-ignore-removal) all=1; continue ;;
            # 何もステージしない（--dry-run）、追跡済みだけ（-u・--renormalize・--refresh）、人が 1 つずつ選ぶ（-p・-i・-e）
            --dry-run | --update | --renormalize | --refresh | --patch | --interactive | --edit) skip=1; continue ;;
            --*) continue ;;
            -*)
              case $a in *A*) all=1 ;; esac
              case $a in *[nupie]*) skip=1 ;; esac
              continue
              ;;
          esac
        fi
        npath=$((npath + 1))
        case $a in . | ./) dot=1 ;; esac
      done
      [ "$skip" = 0 ] || return 0
      { [ "$all" = 1 ] && [ "$npath" = 0 ]; } || [ "$dot" = 1 ] || return 0
      if [ "$can_look" = 1 ]; then
        if [ "$npath" = 0 ]; then count_untracked all; else count_untracked dot; fi
        [ "$UNTRACKED" = 0 ] && return 0
        [ -n "$UNTRACKED" ] && count="（いま ${UNTRACKED} 件）"
      fi
      hit add "git add -A / --all / . は、未追跡のファイル${count}もまとめてステージします。並行する作業のファイルが紛れ込みます。git status --short で確かめ、入れるファイルを名指しで git add してください。"
      ;;
    fetch | pull) FETCHED=1 ;;
    remote)
      for a in "$@"; do [ "$a" = update ] && FETCHED=1; done
      ;;
    reset)
      # #66: 基点を巻き戻すリセット（squash のつもりの git reset --soft origin/<ブランチ>）
      local soft=0 ref=""
      seen reset && return 0
      for a in "$@"; do
        case $a in --soft) soft=1 ;; origin/* | '@{u}'* | '@{upstream}'*) ref=$a ;; esac
      done
      [ "$soft" = 1 ] && [ -n "$ref" ] || return 0
      # 上流の先頭がすでに HEAD の祖先なら、何も巻き戻らない。ただし同じコマンドの中で先に fetch / pull していたら、
      # いま手元にある上流は「実行するときの上流」ではないので、見ても判定にならない
      if [ "$can_look" = 1 ] && [ "$FETCHED" = 0 ]; then
        case " $RESET_SEEN " in *" $ref "*) return 0 ;; esac
        if git_look merge-base --is-ancestor "$ref" HEAD; then RESET_SEEN="$RESET_SEEN $ref"; return 0; fi
      fi
      hit reset "git reset --soft ${ref} は、上流が先に進んでいると、基点の側で入った変更を巻き戻すコミットになります。まとめ直すなら、分岐点へ戻してください: git reset --soft \"\$(git merge-base ${ref} HEAD)\""
      ;;
  esac
}

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

# ---- 自己検査 -------------------------------------------------------------

self_test() {
  local self=$1 tmp fail=0 T_PATH="" many deep pad
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
    shift 2
    out=$(printf '%s' "$input" | "$@" 2>/dev/null); rc=$?
    if [ "$rc" = 0 ] && [ -z "$out" ]; then printf 'ok   pass  [%s]\n' "$label"
    else printf 'NG   want=pass got=exit%s out=%s  [%s]\n' "$rc" "$out" "$label"; fail=1; fi
  }

  local d=$tmp/dirty c=$tmp/clean p=$tmp/plain h=$tmp/hidden

  echo "# hook 自身が害にならない"
  # index を書き換えない: 内容は同じで時刻だけ違うファイルがあると、ふつうの git status は index を書き直す
  touch -t 202201010000 "$d/a.txt"
  touch -t 202001010000 "$d/.git/index"
  touch -t 202101010000 "$tmp/marker"
  t ask  "$d" 'git add -A'
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

  echo "# format（#52）"
  t ask  "$d" 'gofmt -w .'
  t ask  "$d" 'gofmt -l -w ./pkg/'
  t ask  "$d" 'gofmt -w pkg'
  t ask  "$d" 'go fmt ./...'
  t ask  "$d" 'cd pkg && go fmt ./...'
  t ask  "$d" 'prettier --write .'
  t ask  "$d" 'npx prettier --write pkg/'
  t ask  "$d" 'pnpm exec prettier -w .'
  t pass "$d" 'gofmt -w pkg/main.go'
  t pass "$d" 'gofmt -l .'
  t pass "$d" 'gofmt -d ./pkg/'
  t pass "$d" 'gofmt -w $(git diff --name-only -- "*.go")'
  t pass "$d" 'go fmt ./pkg'
  t pass "$d" 'go vet ./...'
  t pass "$d" 'go test ./... -run fmt'
  t pass "$d" 'prettier --check .'
  t pass "$d" 'prettier --write a.txt'
  t pass "$d" 'echo "gofmt -w ." >> NOTES.md'

  echo "# git reset（#66）"
  t ask  "$c" 'git reset --soft origin/ahead'
  t ask  "$c" 'git fetch && git reset --soft origin/ahead && git commit -m squash'
  t ask  "$p" 'git -C ../other reset --soft origin/main'
  t ask  "$c" 'cd sub && git reset --soft origin/behind'
  t pass "$c" 'git reset --soft origin/behind'
  t pass "$c" 'git status && git reset --soft origin/behind'
  t ask  "$c" 'git fetch && git reset --soft origin/behind'
  t ask  "$c" 'git fetch origin; git reset --soft origin/behind'
  t ask  "$c" 'git pull --rebase && git reset --soft origin/behind'
  t ask  "$c" 'git remote update && git reset --soft origin/behind'
  t pass "$c" 'git remote -v && git reset --soft origin/behind'
  t ask  "$c" 'git reset --soft @{u}'
  t ask  "$c" 'git reset --soft "@{upstream}"'
  t pass "$c" 'git reset --soft HEAD@{1}'
  t pass "$c" 'git reset --soft "$(git merge-base origin/ahead HEAD)"'
  t pass "$c" 'git reset --soft HEAD~1'
  t pass "$c" 'git reset --hard origin/ahead'
  t pass "$c" 'git reset a.txt'
  t pass "$c" 'git log origin/ahead --soft'
  t pass "$c" 'echo "git reset --soft origin/ahead"'

  echo "# git add（#75）"
  t ask  "$d" 'git add -A'
  t ask  "$d" 'git add --all'
  t ask  "$d" 'git add .'
  t ask  "$d" 'git add -A && git commit -m wip'
  t ask  "$d" 'git -c core.quotepath=off add -Av'
  t ask  "$d" 'git add -A 2>&1'
  t ask  "$p" 'git -C ../other add -A'
  # 未追跡の無いリポジトリにいても、対象が別の場所なら状態を見ずに確認に回す
  t ask  "$c" 'git -C ../dirty add -A'
  t ask  "$c" 'git --git-dir=../dirty/.git --work-tree=../dirty add -A'
  t ask  "$c" 'GIT_DIR=../dirty/.git GIT_WORK_TREE=../dirty git add -A'
  t ask  "$c" 'export GIT_DIR=../dirty/.git; git add -A'
  t ask  "$c" 'env -C ../dirty git add -A'
  t ask  "$c" 'cd ../dirty && git add -A'
  t pass "$c" 'FOO=1 git add -A'
  t pass "$d" 'git add -u .'
  t pass "$d" 'git add -p .'
  t pass "$d" 'git add --patch .'
  t pass "$d" 'git add --renormalize .'
  t pass "$d" 'git add -i'
  t ask  "$d" 'git add -v .'
  t pass "$d" 'ls # x; git add -A'
  t pass "$d" 'ls   # git add -A && git add .'
  t pass "$c" 'git add -A'
  t pass "$c" 'git add .'
  t pass "$d" 'git add a.txt'
  t pass "$d" 'git add -A pkg/main.go'
  t pass "$d" 'git add -u'
  t pass "$d" 'git add -A --dry-run'
  t pass "$d" 'git add -p'
  t pass "$d" 'git commit -am "git add -A をやめる"'
  t pass "$d" 'git commit -m "$(cat <<'"'"'EOF'"'"'
1) git add -A を使わない
2) pkill も使わない :)
EOF
)"'
  t pass "$d" 'cat > NOTES.md <<EOF
git add -A
pkill -f vite
EOF'
  t ask  "$d" 'cat > NOTES.md <<EOF
memo
EOF
git add -A'
  t pass "$d" '# git add -A はしない
git status --short'

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

  if [ "$fail" = 0 ]; then echo "self-test: すべて期待どおり"; else echo "self-test: 期待と違う結果があります" >&2; fi
  return "$fail"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test "$0"
  exit $?
fi
main
