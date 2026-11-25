#!/bin/bash
# self-test/git.sh — rules/git.sh の場面。self-test/run.sh の self_test から呼ばれる部品（単体では実行しない）。

# shellcheck disable=SC2016  # '$(' などは、展開させずに文字として比べる・渡すために単引用符で書いている

self_test_git() {
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
}

LOADED="$LOADED self-test/git.sh"  # 最後まで読めた印（入口の load_parts が見る。この行はファイルの最後に置く）
