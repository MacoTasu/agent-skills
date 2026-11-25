#!/bin/bash
# self-test/format.sh — rules/format.sh の場面。self-test/run.sh の self_test から呼ばれる部品（単体では実行しない）。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

self_test_format() {
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
}

LOADED="$LOADED self-test/format.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
