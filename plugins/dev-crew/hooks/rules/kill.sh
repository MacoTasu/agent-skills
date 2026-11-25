#!/bin/bash
# rules/kill.sh — 規則 kill。guard-broad-op.sh が読み込む部品（単体では実行しない）。自己検査は self-test/kill.sh。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

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

LOADED="$LOADED rules/kill.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
