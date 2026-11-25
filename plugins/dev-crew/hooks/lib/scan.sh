#!/bin/bash
# lib/scan.sh — 語の切り出し。guard-broad-op.sh が読み込む部品（単体では実行しない）。
# コマンドの文字列（CMD・N）を命令ごとの語（WORDS）に分け、命令の区切りごとに check_segment（入口の側）を呼ぶ。
# 引用符・$(...)・ヒアドキュメントの中は命令として読まない。変数は入口で宣言したものを使う。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

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

LOADED="$LOADED lib/scan.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
