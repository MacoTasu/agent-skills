#!/bin/bash
# guard.sh — PreToolUse hook（Bash）。公開物ガードが有効になっているかだけを確かめる配線確認。
#
# 検査の本体は git の pre-commit / pre-push（.githooks/public-guard.sh ＋ gitleaks）で、ここは走査しない。
# コマンドに git と commit / push の語があるときだけ、hook の cwd のリポジトリで
#   - core.hooksPath が pre-commit を持つディレクトリを指しているか
#   - gitleaks があるか
# を見て、欠けていれば exit 2 ＋ stderr に設定コマンドを返す（Claude が受け取って設定する）。
# コマンド文字列からパスは読まない（対象は git が自分のリポジトリで hook を実行するので推定しない）。
# jq が無い・cwd が git リポジトリでないときは何もしない（本体は git hook）。
set -uo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
printf '%s' "$CMD" | grep -qw git || exit 0
printf '%s' "$CMD" | grep -qwE 'commit|push' || exit 0

DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TOP=$(git -C "${DIR:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
HP=$(git -C "$TOP" config --type=path core.hooksPath 2>/dev/null)
case $HP in /*|"") ;; *) HP="$TOP/$HP" ;; esac   # 相対パスは worktree の root から解決される

TODO=""
if [ -z "$HP" ]; then
  TODO="${TODO}  git -C \"$TOP\" config core.hooksPath .githooks\n"
elif [ ! -f "$HP/pre-commit" ]; then   # 設定はあるが hook の実体が無い（この作業ツリーに .githooks/ が無い など）
  TODO="${TODO}  core.hooksPath は設定済みですが ${HP}/pre-commit がありません。.githooks/ を用意する（それを含むブランチをチェックアウトする / /loop-engine:init を実行する）\n"
fi
command -v gitleaks >/dev/null 2>&1 || TODO="${TODO}  brew install gitleaks（ほかの方法: https://github.com/gitleaks/gitleaks#installing）\n"
[ -z "$TODO" ] && exit 0
printf 'guard: 公開物ガード（git hook ＋ gitleaks）が有効ではありません。次を実行してから再試行してください:\n%b' "$TODO" >&2
exit 2
