#!/bin/bash
# public-guard.sh — git の pre-commit / pre-push から呼ぶ公開物ガード。
#
# 走査は gitleaks に任せる（既定ルール＋リポジトリ直下の .gitleaks.toml。gitleaks が自動で読む）。
# 未追跡の .gitleaks.local.toml があればそれを -c で渡す（公開できない NG ワード用。.gitleaks.toml を extend する。
# linked worktree ではメインの作業ツリーのものを使う）。
#   commit: staged の追加行だけ。作者メールが noreply か（REQUIRE_NOREPLY=1 のとき）
#   push:   push する各 ref の「まだリモートに無いコミット」だけ。同じ範囲の作者メールも見る（REQUIRE_NOREPLY=1 のとき）
#           範囲は必ず明示する（--log-opts を省くと gitleaks は全履歴を見る）
# 違反は exit 1 で git が止める。gitleaks が無いときも止める（検査せずに通さない）。
# 有効化: git config core.hooksPath .githooks（clone ごとに 1 回）。
# 一時的に外す --no-verify は人間の判断でのみ使う。
set -uo pipefail

# 1 なら作者メールを GitHub の noreply（<id>+<user>@users.noreply.github.com）に限る。public リポジトリ向け
REQUIRE_NOREPLY=1

NOREPLY_RE='@users\.noreply\.github\.com$'

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "public-guard: gitleaks が見つからないため止めました（検査せずには通しません）" >&2
  echo "  導入: brew install gitleaks（ほかの方法: https://github.com/gitleaks/gitleaks#installing）" >&2
  echo "  一時的に外すなら人間の判断で --no-verify" >&2
  exit 1
fi

# git は hook を worktree の root で実行するので、相対パスはリポジトリ直下を指す。
# NG ワードの設定はこの作業ツリーの直下、無ければメインの作業ツリーの直下を使う
# （未追跡なので git worktree add の先には無い。そこで黙って外れないように）
LOCAL=""
if [ -f .gitleaks.local.toml ]; then
  LOCAL=.gitleaks.local.toml
else
  COMMON=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$COMMON" ] && COMMON=$(cd "$COMMON" && pwd -P) || COMMON=""
  case $COMMON in
    */.git) [ -f "${COMMON%/.git}/.gitleaks.local.toml" ] && LOCAL="${COMMON%/.git}/.gitleaks.local.toml" ;;
  esac
fi
CONFIG=()
[ -n "$LOCAL" ] && CONFIG=(-c "$LOCAL")
# stdin は pre-push の ref 一覧なので gitleaks に読ませない
scan() { gitleaks git -v --no-banner ${CONFIG[@]+"${CONFIG[@]}"} "$@" </dev/null; }

FAIL=0
check_emails() {  # $1 = 説明, $2 = メールの一覧（改行区切り）
  [ "$REQUIRE_NOREPLY" = 1 ] || return 0
  local bad
  bad=$(printf '%s\n' "$2" | grep -vE "$NOREPLY_RE" | sort -u)
  [ -z "$bad" ] && return 0
  echo "public-guard: $1 の作者メールが noreply ではありません: $(echo $bad)" >&2
  echo "  設定: git config user.email <id>+<user>@users.noreply.github.com" >&2
  FAIL=1
}

case "${1:-}" in
  commit)
    scan --staged || FAIL=1
    # --author で渡した作者はここからは見えない（REQUIRE_NOREPLY=1 なら pre-push の範囲検査で止まる）
    EMAIL=$(git var GIT_AUTHOR_IDENT 2>/dev/null | sed -n 's/.*<\(.*\)>.*/\1/p')
    check_emails "コミット" "${EMAIL:-（不明）}"
    ;;
  push)
    REMOTE=${2:-}
    while read -r LREF LSHA RREF RSHA; do
      [ -n "${LSHA:-}" ] || continue
      case $LSHA in *[!0]*) ;; *) continue ;; esac   # 削除の push は送るコミットが無い
      case $RSHA in
        *[!0]*) RANGE=("$RSHA..$LSHA") ;;
        *)      RANGE=("$LSHA" --not "--remotes=$REMOTE") ;;   # 新規 ref: どのリモート追跡 ref にも無いコミット
      esac
      scan --log-opts="${RANGE[*]}" || FAIL=1
      if EMAILS=$(git log --format=%ae "${RANGE[@]}" </dev/null); then
        [ -z "$EMAILS" ] || check_emails "$LREF → $RREF" "$EMAILS"
      else
        echo "public-guard: $LREF の範囲を読めませんでした" >&2; FAIL=1
      fi
    done
    ;;
  *)
    echo "usage: public-guard.sh commit | push <remote> <url>" >&2
    exit 1
    ;;
esac

if [ "$FAIL" != 0 ]; then
  echo "public-guard: 公開物の検査で止めました。誤検知の行は行末に gitleaks:allow を書くと許可されます" >&2
  exit 1
fi
exit 0
