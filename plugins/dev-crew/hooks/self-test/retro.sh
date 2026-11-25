#!/bin/bash
# self-test/retro.sh — rules/retro.sh の場面。self-test/run.sh の self_test から呼ばれる部品（単体では実行しない）。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

self_test_retro() {
  local self=$self copy=$tmp/copy-retro big writer many began
  # t と同じ入力で、通すこと（出力なし・終了コード 0）に加えて、標準エラーも確かめる。$1 = 標準エラーに含まれるはずの文字（空なら、何も出ないこと） $2 = コマンド
  quiet() {
    local want=$1 command=$2 out err rc
    count=$((count + 1))
    out=$(jq -n --arg cwd "$p" --arg command "$command" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' |
      "$BASH" "$self" 2>"$tmp/retro.err")
    rc=$?
    err=$(cat "$tmp/retro.err")
    [ "${#command}" -le 160 ] || command="${command:0:60} ...（${#command} バイト）"
    if [ "$rc" = 0 ] && [ -z "$out" ] && { if [ -n "$want" ]; then case $err in *"$want"*) true ;; *) false ;; esac; else [ -z "$err" ]; fi; }; then
      printf 'ok   pass  %s（標準エラー: %s）\n' "$command" "${want:-なし}"
    else printf 'NG   want=pass 標準エラー=%s got=exit%s out=%s err=%s  %s\n' "${want:-なし}" "$rc" "$out" "$err" "$command"; fail=1; fi
  }
  echo "# retro（#41）"
  printf '%s\n' '<!-- retro-record v1 -->' 'pr: {{PR 番号}}' >"$p/unfilled.md"
  printf '%s\n' '<!-- retro-record v1 -->' 'pr: 12' >"$p/filled.md"
  printf '%s\n' 'テンプレートの {{name}} を埋める' >"$p/template.md"
  mkdir -p "$p/sub" "$p/a-dir.md"
  # 本文を引数で渡す形
  t ask  "$p" 'gh pr comment 12 --body "<!-- retro-record v1 -->
pr: {{PR 番号}}"'
  t ask  "$p" "gh pr comment 12 -b '<!-- retro-record v1 --> {{trigger}}'"
  t ask  "$p" 'gh pr comment 12 --body="<!-- retro-record v1 --> {{trigger}}"'
  t ask  "$p" "gh issue comment 34 --body '<!-- retro-record v1 --> {{trigger}}'"
  t ask  "$p" "gh pr comment --edit-last --body '<!-- retro-record v1 --> {{trigger}}'"
  t ask  "$p" 'gh pr comment 12 --body "$(cat <<'\''EOF'\''
<!-- retro-record v1 -->
pr: {{PR 番号}}
EOF
)"'
  # 本文をファイルで渡す形
  t ask  "$p" 'gh pr comment 12 --body-file unfilled.md'
  t ask  "$p" 'gh pr comment 12 -F unfilled.md'
  t ask  "$p" 'gh pr comment 12 --body-file=unfilled.md'
  t ask  "$p" "gh pr comment 12 --body-file '$p/unfilled.md'"
  t ask  "$p" 'gh issue comment 34 -F ./unfilled.md 2>&1'
  # 前置き・リポジトリの指定・連結
  t ask  "$p" 'env gh pr comment 12 -F unfilled.md'
  t ask  "$p" 'GH_TOKEN=x gh pr comment 12 -F unfilled.md'
  t ask  "$p" 'gh pr comment 12 --repo owner/name -F unfilled.md'
  t ask  "$p" 'gh pr -R owner/name comment 12 -F unfilled.md'
  t ask  "$p" 'gh issue --repo owner/name comment 34 --body-file unfilled.md'
  t ask  "$p" 'ls && gh pr comment 12 -F unfilled.md'
  t ask  "$p" '/opt/homebrew/bin/gh pr comment 12 -F unfilled.md; echo done'
  # 片方だけなら通す
  t pass "$p" "gh pr comment 12 --body '<!-- retro-record v1 --> pr: 12'"
  t pass "$p" "gh pr comment 12 --body 'テンプレートの {{name}} を埋める'"
  t pass "$p" 'gh pr comment 12 -F filled.md'
  t pass "$p" 'gh pr comment 12 --body-file template.md'
  t pass "$p" "gh issue comment 34 --body 'x'"
  # 判定できない本文は通す
  t pass "$p" 'gh pr comment 12 -F no-such-file.md'
  t pass "$p" 'gh pr comment 12 -F a-dir.md'
  # ふつうのファイルでないものは開かない。FIFO は、開いたら印と {{ が読める書き手を置いておく（読めば確認に回って赤になる。
  # 書き手が無いと、読んだときに固まるだけで赤にならない）。mkfifo が無い環境では、飛ばさずに赤にする（確かめていないのに緑にしない）
  mkfifo "$p/fifo.md" 2>/dev/null || { echo "NG   mkfifo で FIFO を作れない（この場面を確かめられない）"; fail=1; }
  (while [ -p "$p/fifo.md" ]; do printf '%s\n' '<!-- retro-record v1 --> {{' >"$p/fifo.md"; sleep 0.2; done) 2>/dev/null &
  writer=$!
  quick 5 pass "$p" 'gh pr comment 12 -F fifo.md'
  kill "$writer" 2>/dev/null; wait "$writer" 2>/dev/null
  # 終わりの無いデバイス: 読めば上限を超えて標準エラーに 1 行出るので、何も出ないことで「開いていない」を確かめる
  quiet "" 'gh pr comment 12 -F /dev/zero'
  t pass "$p" 'gh pr comment 12 -F -'
  t pass "$p" 'gh pr comment 12 --body-file - <<EOF
<!-- retro-record v1 -->
pr: {{PR 番号}}
EOF'
  t pass "$p" 'gh pr comment 12 --body "$BODY"'
  t pass "$p" 'gh pr comment 12 --body "$(cat unfilled.md)"'
  t pass "$p" 'gh pr comment 12 -F "$DIR/unfilled.md"'
  t pass "$p" 'cd sub && gh pr comment 12 -F unfilled.md'
  t ask  "$p" "cd sub && gh pr comment 12 -F '$p/unfilled.md'"
  # 上限（20000 バイト）ちょうどは読み、1 バイト超えたら通して、標準エラーに 1 行出す。無いファイルでは何も出さない
  big=$(printf 'x%.0s' $(seq 1 19971))
  printf '%s\n' '<!-- retro-record v1 -->' '{{' "$big" >"$p/at-limit.md"
  printf '%s\n' '<!-- retro-record v1 -->' '{{' "x$big" >"$p/over-limit.md"
  t ask  "$p" 'gh pr comment 12 -F at-limit.md'
  quiet "本文のファイルが 20000 バイトを超えるので、検査せずに通します" 'gh pr comment 12 -F over-limit.md'
  quiet "" 'gh pr comment 12 -F no-such-file.md'
  # 読むファイルは 1 回の実行で 4 つまで（数は直に書く。上限の値を変えたら、ここが赤になる）。超えた分は読まずに通し、標準エラーに 1 行出す
  t ask  "$p" 'gh pr comment 12 -F filled.md -F filled.md -F filled.md -F unfilled.md'
  quiet "本文のファイルが 4 個を超えるので、残りは検査せずに通します" 'gh pr comment 12 -F filled.md -F filled.md -F filled.md -F filled.md -F unfilled.md'
  cp "$p/filled.md" "$p/f"
  many=$(printf -- '-F f %.0s' $(seq 1 3900))
  began=$SECONDS
  quiet "本文のファイルが 4 個を超えるので、残りは検査せずに通します" "gh pr comment 12 $many-F unfilled.md"
  count=$((count + 1))
  if [ $((SECONDS - began)) -gt 8 ]; then printf 'NG   -F を 3900 個並べたコマンドが 8 秒を超えた（%s 秒）\n' $((SECONDS - began)); fail=1
  else echo "ok         -F を 3900 個並べたコマンドが 8 秒以内に終わる（hook の時間の上限は 10 秒）"; fi
  # 連結した投稿は、最初に確認に回すと決まったら、後ろのファイルを読まない
  many=$(printf 'gh issue comment 1 -F unfilled.md;%.0s' $(seq 1 300))
  quick 5 ask "$p" "$many"
  # 見ていない形（README の「見ていない形」）: 短いフラグに = や値を直につなげた形、~ で始まるパス、pushd の後、xargs・bash -c 経由、印の表記ゆれ
  mkdir -p "$p/~"; cp "$p/unfilled.md" "$p/~/unfilled.md"
  t pass "$p" "gh pr comment 12 -b='<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" "gh pr comment 12 -b'<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" 'gh pr comment 12 -F=unfilled.md'
  t pass "$p" 'gh pr comment 12 -Funfilled.md'
  t pass "$p" 'gh pr comment 12 -F ~/unfilled.md'
  t pass "$p" 'gh pr comment 12 --body-file=~/unfilled.md'
  t pass "$p" 'pushd sub && gh pr comment 12 -F unfilled.md'
  t pass "$p" 'echo unfilled.md | xargs gh pr comment 12 -F'
  t pass "$p" 'bash -c "gh pr comment 12 -F unfilled.md"'
  t pass "$p" "gh pr comment 12 --body '<!--retro-record v1--> {{trigger}}'"
  # 別の下位命令・別の命令
  t pass "$p" 'gh pr view 12'
  t pass "$p" "gh pr create --title t --body '<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" "gh pr edit 12 --body-file unfilled.md"
  t pass "$p" "gh pr review 12 --comment --body '<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" "gh api repos/owner/name/issues/12/comments -f body='<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" "echo gh pr comment 12 --body '<!-- retro-record v1 --> {{trigger}}'"
  t pass "$p" 'git commit -m "gh pr comment -F unfilled.md を確認に回す"'
  t pass "$p" 'cat unfilled.md # gh pr comment 12 -F unfilled.md'
  # 規則のファイルが無い写し: gh のコメントの投稿は中身を見ずに確認に回し、別の下位命令は通す
  rm -rf "$copy"; cp -R "$HOOK_DIR" "$copy"; rm "$copy/rules/retro.sh"
  self=$copy/guard-broad-op.sh
  t ask  "$p" 'gh pr comment 12 --body x'
  t pass "$p" 'gh pr view 12'
}

LOADED="$LOADED self-test/retro.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
