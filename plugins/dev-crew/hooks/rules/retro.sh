#!/bin/bash
# rules/retro.sh — 規則 retro。guard-broad-op.sh が読み込む部品（単体では実行しない）。自己検査は self-test/retro.sh。
# 本文のファイルを読む大きさの上限は、入口の MAX_COMMAND_BYTES に合わせている。読む数の上限（MAX_BODY_FILES）も入口で決めている。
# どちらも、超えるものは判定できないので通し、標準エラーに 1 行出す。

# shellcheck disable=SC2016  # '$' などは、展開させずに文字として比べるために単引用符で書いている

retro_unfilled() {  # $1 = コメントの本文。振り返りの記録の印と、穴埋めの記号の両方が在れば 0
  # 片方だけでは止めない: テンプレートの説明や CI の設定を書いた普通のコメントにも {{ は出る
  case $1 in *'<!-- retro-record'*) ;; *) return 1 ;; esac
  case $1 in *'{{'*) return 0 ;; esac
  return 1
}

retro_file_unfilled() {  # $1 = --body-file の値。読めて、印と穴埋めの記号の両方が在れば 0。判定できないものは 1（通す）
  local f=$1 size
  case $f in
    '' | - | *'$'* | *'`'* | '~'*) return 1 ;;  # 標準入力と、変数・置換・~ の展開で決まるパス
    /*) ;;
    *) [ "$CWD_OK" = 1 ] || return 1; f=$CWD/$f ;;  # 同じコマンドの中で cd した後は、どこから解決するかが分からない
  esac
  # ふつうのファイルだけを読む（FIFO やデバイスを読むと、返ってこないことがある）
  [ -f "$f" ] && [ -r "$f" ] || return 1
  # 読む数の上限。-F を何千個も並べたコマンドで、hook の時間の上限を超えない
  if [ "$BODY_FILES" -ge "$MAX_BODY_FILES" ]; then
    [ "$BODY_FILES" = "$MAX_BODY_FILES" ] && note "本文のファイルが ${MAX_BODY_FILES} 個を超えるので、残りは検査せずに通します"
    BODY_FILES=$((BODY_FILES + 1))
    return 1
  fi
  BODY_FILES=$((BODY_FILES + 1))
  # 上限の 1 バイト先までしか読まない（大きさを数えるだけのために、大きなファイルを最後まで読まない）
  size=$(head -c $((MAX_COMMAND_BYTES + 1)) "$f" 2>/dev/null | wc -c) || return 1
  size=${size//[!0-9]/}
  [ -n "$size" ] || return 1
  if [ "$size" -gt "$MAX_COMMAND_BYTES" ]; then
    note "本文のファイルが ${MAX_COMMAND_BYTES} バイトを超えるので、検査せずに通します"
    return 1
  fi
  retro_unfilled "$(cat "$f" 2>/dev/null)"
}

# #41: 振り返りの記録（PR・issue へのコメント）を、テンプレートの穴埋めの記号が残ったまま投稿する。
rule_retro() {  # $@ = gh の引数（リダイレクトを除いたもの）
  local a group="" sub="" skip=0 k=0 n=${#WORDS[@]} w found=0
  seen retro && return 0  # もう確認に回すと決まっている。連結した後ろの投稿のファイルは読まない
  # 下位命令を取る（gh pr comment / gh issue comment だけを見る。間に入る -R / --repo とその値は飛ばす）
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case $a in
      -R | --repo) skip=1; continue ;;
      -*) continue ;;
    esac
    if [ -z "$group" ]; then group=$a; continue; fi
    sub=$a
    break
  done
  case "$group $sub" in "pr comment" | "issue comment") ;; *) return 0 ;; esac
  # 本文は、引数ではなく WORDS から取る: check_segment は < で始まる語をリダイレクトとして引数から除くので、
  # 引用符で渡した本文（印の <!-- で始まる）が引数に残らない
  while [ "$k" -lt "$n" ]; do
    w=${WORDS[$k]}
    k=$((k + 1))
    case $w in
      --body | -b)
        [ "$k" -lt "$n" ] && retro_unfilled "${WORDS[$k]}" && found=1
        k=$((k + 1))
        ;;
      --body=*) retro_unfilled "${w#--body=}" && found=1 ;;
      --body-file | -F)
        [ "$k" -lt "$n" ] && retro_file_unfilled "${WORDS[$k]}" && found=1
        k=$((k + 1))
        ;;
      --body-file=*) retro_file_unfilled "${w#--body-file=}" && found=1 ;;
    esac
  done
  [ "$found" = 1 ] || return 0
  hit retro "振り返りの記録（<!-- retro-record の印があるコメント）を、テンプレートの穴埋めの記号 {{ が残ったまま投稿しようとしています（gh pr comment / gh issue comment の --body・--body-file）。埋め残しのある記録が、そのまま PR・issue に残ります。{{ の残っている箇所を埋めてから（本文がファイルなら grep -n '{{' <ファイル> で場所が分かります）、投稿してください。"
}

LOADED="$LOADED rules/retro.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
