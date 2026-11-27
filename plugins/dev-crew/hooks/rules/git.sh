#!/bin/bash
# rules/git.sh — 規則 add・reset・stash（git の下位命令ごと）。guard-broad-op.sh が読み込む部品（単体では実行しない）。
# 自己検査は self-test/git.sh。状態を見る git の上限（MAX_GIT_CALLS・GIT_LIMIT_SECONDS）は入口で決めている。

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
    stash)
      # 2026-11-26（課題番号は無い）: 差分を読むだけの役が、前の版と比べるために git stash を打ち、同じ worktree で別の役が
      # 書いている途中の変更が一度消えた。退避する形（引数なし・push・save・オプションから始まる形）と、pop・apply・drop・clear だけを見る。
      # 読むだけの形（list・show）、ヘルプ、ほかの下位命令（branch・create・store）は通す
      case ${1:-} in
        "" | push | save | pop | apply | drop | clear) ;;
        -h | --help) return 0 ;;
        -*) ;;
        *) return 0 ;;
      esac
      hit stash "git stash（退避・pop・apply・drop・clear）は、作業ツリーか stash の置き場を書き換えます。stash の置き場は worktree をまたいで共有で、ほかの役の作業中の変更を巻き込むことがあります。前の版と比べるなら git show <rev>:<path> の出力を作業フォルダの外に写し、作業を退けるなら一時的なコミットにしてください。"
      ;;
  esac
}

LOADED="$LOADED rules/git.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
