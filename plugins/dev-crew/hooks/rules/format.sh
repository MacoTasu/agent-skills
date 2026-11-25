#!/bin/bash
# rules/format.sh — 規則 format。guard-broad-op.sh が読み込む部品（単体では実行しない）。自己検査は self-test/format.sh。

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

LOADED="$LOADED rules/format.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
