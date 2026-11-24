#!/bin/sh
# lint.sh — 指示文（markdown）とスクリプトの、決まった形で見つかる誤りの検査。
#
# 使い方:
#   .githooks/lint.sh              追跡ファイル全体を、作業ツリーの中身で検査する
#   .githooks/lint.sh --staged     コミットに入る中身（index）全体を検査する。pre-commit が呼ぶ
#   .githooks/lint.sh --self-test  規則ごとに、内蔵の例で空振りと誤検出を確かめる
# 違反は「ファイル:行: [規則] 説明」で標準出力に出し、1 件でもあれば exit 1。検査そのものができなかったときは exit 2。
# 依存は sh・awk・git・tar（macOS 標準の awk で動く形にしてある）。
# 一覧を作る途中で何かが失敗しても、検査対象が減ったまま通さない: git が言う追跡ファイルの件数と、
# awk が実際に受け取った件数を突き合わせ、合わなければ exit 2（追跡ファイルが本当に 0 件なら、その旨を出して exit 0）。
#
# 規則:
#   heading-ref        `<ファイル>.md`「<見出し>」（ファイル名の直後にかぎ括弧が続く形）が、そのファイルに無い見出しを指している。
#                      見出しの一部でもよい。バッククォートと ** は無視し、『』は「」と同じに扱う。
#                      ファイルは、書いた場所から上へたどっていちばん近いもの → 同じプラグインの中 → リポジトリ全体、の順に名前で探す
#                      （同じ名前が複数あれば、どれかに見出しがあればよい）。
#                      見つからないファイル（対象プロジェクトの側のファイルなど）は確かめず、件数だけを標準エラーに出す。
#                      <…> や $ を含む名前は見ない
#   fence-plugin-root  plugins/ の下の reference/ にある markdown のコードブロックで CLAUDE_PLUGIN_ROOT を使っている
#                      （Read して読む手順書の中では、この変数がシェルに渡らないことがある）
#   quote-blank        引用（> の行）の直後に、空行なしで地の文が続く（その行が引用に巻き込まれる）。
#                      見出し・箇条書き・コードブロックの開き・区切り線・HTML コメントは巻き込まれないので止めない。コードブロックの中は見ない
#   jq-bool-default    「<式> // true」の形（jq の // は左が false のときも右に置き換えるので、false が true になる）。
#                      markdown と、1 行目が #! のシェルスクリプトを見る。「// false」は真偽値の意味を変えないので見ない。
#                      代入の形（//= true）も同じことが起きるが、まだ見ていない
#   unreadable         検査の対象なのに読めなかったファイル（権限が無い、宛先の無いシンボリックリンク、改行を含む名前）
#   allow-format / allow-unused  下の除外の印の書き方の誤りと、規則が当たっていない行に付いた印
#   （unreadable・allow-format・allow-unused は除外できない）
#
# 作業ツリーの検査で見ないもの（件数を標準エラーに出す）: 作業ツリーから消してある追跡ファイル、sparse checkout で外してあるファイル。
# どちらも --staged では見る（index に在るものは全部見る）。
#
# 除外の印（1 種類だけ）:
#   違反の形を意図して書く行（規則の説明、例示）には、同じ行に「lint:allow <規則>: <理由>」を書く。
#   markdown なら <!-- lint:allow <規則>: <理由> -->、スクリプトならコメントにする。理由の無い印は allow-format で止まる。
#
# 規則の足し方（この 1 ファイルで完結する）:
#   1. 上の「規則」に、識別子と、何を止めるかを 1 行で足す
#   2. 下の RULES と、awk の BEGIN の一覧に識別子を足し、判定を awk に書く。1 行で決まるものは check_md / check_script
#      （両方で見るものは check_jq のように関数にして両方から呼ぶ）、ファイルをまたぐものは END。
#      違反は report(ファイル, 行, 規則, 説明) で出す
#   3. 下の write_fixtures に例を足す。検出されるべき行には「NG:<規則>」、形は似ているが検出されてはいけない行には
#      「OK:<規則>」と書く。--self-test は、NG の行がちょうど検出され、ほかの行が 1 つも検出されないことを、
#      作業ツリーの検査と index の検査の両方で見る。NG と OK のどちらかが無い規則は赤になる
#   4. .githooks/lint.sh --self-test と .githooks/lint.sh を実行する。いまのファイルが当たったら、同じ変更で直す
set -u

RULES="heading-ref fence-plugin-root quote-blank jq-bool-default unreadable allow-format allow-unused"

usage() { sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//' >&2; }
die() { echo "lint: $* 検査できていないので、通したことにはしません" >&2; exit 2; }

for tool in awk git tar tr wc sort sed; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool が見つかりません（$tool を使えるようにしてから、もう一度実行する）。"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lint.XXXXXX") || die "一時ディレクトリを作れません（TMPDIR の指す先に書けるかを確かめる）。"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 2' HUP INT TERM
SOH=$(printf '\001')

# awk の本体。$( ) の中に置かずファイルに書くのは、bash 3.2 が $( ) の中のヒアドキュメントの括弧を数え損ねるため
write_awk() { cat > "$TMP/lint.awk"; }
write_awk <<'AWK' || die "検査の本体を一時ディレクトリに書けません。"
BEGIN {
  n = split("heading-ref fence-plugin-root quote-blank jq-bool-default", r, " ")
  for (i = 1; i <= n; i++) RULES[r[i]] = 1
  root = ENVIRON["LINT_ROOT"]      # -v で渡すと、パスの中の \ がエスケープとして解釈される
  MARK = "lint:" "allow "          # 分けて書く（このファイル自身が印として読まれないように）
  QO = "\343\200\214"; QC = "\343\200\215"   # 「 と 」
  DQO = "\343\200\216"; DQC = "\343\200\217" # 『 と 』
  nv = 0; nf = 0; nr = 0; nm = 0; nu = 0
}

function report(file, line, rule, msg,   key) {
  key = file SUBSEP line SUBSEP rule
  if (key in marker) { used[key] = 1; return }
  out[++nv] = file ":" line ": [" rule "] " msg
}

function unreadable(file) {
  out[++nv] = file ":0: [unreadable] 読めないので検査できなかった（権限、宛先の無いシンボリックリンク、改行を含む名前を確かめる）"
}

# 除外の印を読む。書き方の誤りはここで出す（除外できない）
function read_markers(file, line, text,   rest, p, id, c, reason) {
  rest = text
  while ((p = index(rest, MARK)) > 0) {
    rest = substr(rest, p + length(MARK))
    if (substr(rest, 1, 1) == "<") continue            # 「<規則>」と書いた説明の文
    id = rest; sub(/[^a-z-].*$/, "", id)
    c = substr(rest, length(id) + 1, 1)
    reason = substr(rest, length(id) + 2)
    sub(/-->.*$/, "", reason); gsub(/[ \t]/, "", reason)
    if (!(id in RULES)) {
      out[++nv] = file ":" line ": [allow-format] 除外の印の規則「" id "」は無い"
    } else if (c != ":" || reason == "") {
      out[++nv] = file ":" line ": [allow-format] 除外の印に理由が無い（規則のあとに、コロンと理由を書く）"
    } else {
      marker[file SUBSEP line SUBSEP id] = 1
      mfile[++nm] = file; mline[nm] = line; mrule[nm] = id
    }
  }
}

function check_jq(file, line, text) {
  if (text ~ /[]A-Za-z0-9_)"?.][ \t]*\/\/[ \t]*true([^A-Za-z0-9_]|$)/)
    report(file, line, "jq-bool-default", "「// true」は左が false のときも true になる（「if . == null then … end」か「== true」に書き直す）")
}

# `<ファイル>.md`「<見出し>」の形を集める（突き合わせは、全ファイルの見出しを読み終えた END でする）
function collect_refs(file, line, text,   rest, p, head, i, k, ref, x, q) {
  rest = text
  while ((p = index(rest, ".md`")) > 0) {
    head = substr(rest, 1, p + 2)
    rest = substr(rest, p + 4)
    k = 0
    for (i = length(head); i > 0; i--) if (substr(head, i, 1) == "`") { k = i; break }
    if (k == 0) continue
    ref = substr(head, k + 1)
    if (ref ~ /[<>${}* \t]/) continue                  # 置き換えて読む名前・コマンドの一部
    x = rest
    if (index(x, QO) != 1) continue                    # 直後に続く形だけ（間に語を挟む形は、見出しでない語句も指す）
    x = substr(x, length(QO) + 1)
    q = index(x, QC)
    if (q == 0) continue
    x = substr(x, 1, q - 1)
    rfile[++nr] = file; rline[nr] = line; rref[nr] = ref; rhead[nr] = x
  }
}

function plain(s) {
  gsub(/`/, "", s); gsub(/\*\*/, "", s)
  while (sub(DQO, QO, s)) ; while (sub(DQC, QC, s)) ;
  return s
}

# 地の文を中断できる行か（引用の直後に空行なしで続いても、引用に巻き込まれない）。t は行頭の空白を除いた行
function interrupts(t) {
  if (t ~ /^#+([ \t]|$)/) return 1                     # 見出し
  if (t ~ /^```/ || t ~ /^~~~/) return 1               # コードブロックの開き
  if (t ~ /^-[ \t]*-[ \t]*-[- \t]*$/ || t ~ /^\*[ \t]*\*[ \t]*\*[* \t]*$/ || t ~ /^_[ \t]*_[ \t]*_[_ \t]*$/) return 1   # 区切り線
  if (t ~ /^[-*+][ \t]+[^ \t]/) return 1               # 箇条書き
  if (t ~ /^1[.)][ \t]+[^ \t]/) return 1               # 番号つきの箇条書き（1 で始まるものだけが中断できる）
  if (t ~ /^<!--/) return 1                            # HTML コメント
  return 0
}

function check_md(file, path,   line, n, t, o, run, infence, fch, flen, prevq, isq, inref, st) {
  n = 0; infence = 0; prevq = 0
  inref = (file ~ /^plugins\/.*\/reference\//)
  mdfile[++nf] = file
  while ((st = (getline line < path)) > 0) {
    n++
    sub(/\r$/, "", line)                               # CRLF（残すと、コードブロックの閉じを見落とす）
    read_markers(file, n, line)
    check_jq(file, n, line)
    collect_refs(file, n, line)
    t = line; sub(/^[ \t]+/, "", t)
    if (infence) {
      run = t
      if (fch == "`") sub(/[^`].*$/, "", run); else sub(/[^~].*$/, "", run)
      if (length(run) >= flen && substr(t, length(run) + 1) ~ /^[ \t]*$/) { infence = 0; continue }
      if (inref && index(line, "CLAUDE_PLUGIN_ROOT") > 0)
        report(file, n, "fence-plugin-root", "コードブロックの中の CLAUDE_PLUGIN_ROOT はシェルに渡らないことがある（このファイルを Read した場所から解決する形にする）")
      continue
    }
    isq = (t ~ /^>/)
    if (prevq && !isq && t != "" && !interrupts(t))
      report(file, n, "quote-blank", "引用の直後に空行が無い（この行が引用に巻き込まれる）")
    prevq = isq
    o = t                                              # 箇条書きの行で開くコードブロック（「- 」のあとに ```）
    while (sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", o)) ;
    if (o ~ /^```/ || o ~ /^~~~/) {
      fch = substr(o, 1, 1); run = o
      if (fch == "`") sub(/[^`].*$/, "", run); else sub(/[^~].*$/, "", run)
      if (!(fch == "`" && index(substr(o, length(run) + 1), "`") > 0)) { infence = 1; flen = length(run); prevq = 0 }
      continue
    }
    if (line ~ /^#+[ \t]/) { hcount[file]++; heading[file, hcount[file]] = plain(line) }
  }
  close(path)
  if (st < 0) unreadable(file)
}

function check_script(file, path,   line, n, st) {
  n = 0
  st = (getline line < path)
  if (st > 0 && line ~ /^#!.*sh/) {                    # シェルスクリプトだけを見る
    do {
      n++
      sub(/\r$/, "", line)
      read_markers(file, n, line)
      check_jq(file, n, line)
    } while ((st = (getline line < path)) > 0)
  }
  close(path)
  if (st < 0) unreadable(file)
}

function has_heading(file, x,   i) {
  for (i = 1; i <= hcount[file]; i++) if (index(heading[file, i], x) > 0) return 1
  return 0
}

function ends_with(s, suffix) {
  return s == suffix || (length(s) > length(suffix) && substr(s, length(s) - length(suffix)) == "/" suffix)
}

{
  if ($0 ~ /\.md$/) check_md($0, root $0); else check_script($0, root $0)
}

END {
  for (i = 1; i <= nf; i++) ismd[mdfile[i]] = 1
  for (i = 1; i <= nr; i++) {
    ref = rref[i]; src = rfile[i]
    while (ref ~ /^\.\.?\//) sub(/^\.\.?\//, "", ref)
    dir = src; if (!sub(/\/[^\/]*$/, "", dir)) dir = ""
    plugin = ""
    if (src ~ /^plugins\/[^\/]+\//) { plugin = src; sub(/^plugins\//, "", plugin); sub(/\/.*$/, "", plugin); plugin = "plugins/" plugin "/" }
    nc = 0
    for (d = dir; nc == 0; ) {                         # 書いた場所から上へ、いちばん近いものを 1 つ
      rel = (d == "" ? ref : d "/" ref)
      if (rel in ismd) cand[++nc] = rel
      if (d == "" || !sub(/\/[^\/]*$/, "", d)) break
    }
    if (nc == 0 && plugin != "")
      for (j = 1; j <= nf; j++) if (index(mdfile[j], plugin) == 1 && ends_with(mdfile[j], ref)) cand[++nc] = mdfile[j]
    if (nc == 0)
      for (j = 1; j <= nf; j++) if (ends_with(mdfile[j], ref)) cand[++nc] = mdfile[j]
    if (nc == 0) { nu++; continue }                    # リポジトリに無いファイルは確かめられない
    x = plain(rhead[i]); found = 0; names = ""
    for (j = 1; j <= nc; j++) { if (has_heading(cand[j], x)) found = 1; names = names (j > 1 ? ", " : "") cand[j] }
    if (!found)
      report(src, rline[i], "heading-ref", "`" rref[i] "`" QO rhead[i] QC " に当たる見出しが無い（探した先: " names "）")
  }
  for (i = 1; i <= nm; i++)
    if (!((mfile[i] SUBSEP mline[i] SUBSEP mrule[i]) in used))
      out[++nv] = mfile[i] ":" mline[i] ": [allow-unused] 除外の印の規則 " mrule[i] " は、この行に当たっていない（印を消す）"
  for (i = 1; i <= nv; i++) print out[i]
  print NR > ENVIRON["LINT_COUNT"]                     # 受け取ったファイルの数（呼び出し側が git の件数と突き合わせる）
  if (nu > 0)
    print "lint: heading-ref は、参照先のファイルがリポジトリに見つからない " nu " 件を確かめていません" > "/dev/stderr"
}
AWK

# run_lint <root> — 標準入力のファイル名（root からの相対。1 行に 1 つ）を検査して、違反を標準出力に出す。
# LC_ALL=C: awk の実装やロケールで文字の数え方が変わらないように、バイトで扱う
run_lint() {
  LINT_ROOT="$1/" LINT_COUNT="$TMP/count" LC_ALL=C awk -f "$TMP/lint.awk"
}

# 以下、一覧を作る段階は、パイプでつながない（sh には pipefail が無く、左側の失敗が落ちる）。
# 1 つずつ一時ファイルに書き、失敗したらその場で return 1 する。
# ファイル名の一覧は -z で受ける（-z なしだと、タブや " を含む名前が引用符つきで返り、開けずに検査から落ちる）。
# 改行を含む名前は \001 に置き換わって開けなくなり、unreadable で止まる。
# 件数は -z なしの出力の行数で数える（引用符つきになるので、どんな名前でも 1 エントリが 1 行）

# count_lines <file> — 行数を標準出力に出す
count_lines() {
  n=$(wc -l < "$1") || return 1
  case $n in *[0-9]*) ;; *) return 1 ;; esac
  echo $((n + 0))
}

# list_worktree <top> — 作業ツリーで検査する追跡ファイルの一覧を標準出力に、検査するはずの件数を $TMP/expect に出す。
# 消してあるものと sparse checkout で外してあるものは、見ないことを標準エラーに出して除く
# （消すつもりの作業を止めない。コミットに入る中身は --staged が見る）
list_worktree() {
  (cd "$1" && git ls-files -t) > "$TMP/tracked.q" || return 1
  total=$(count_lines "$TMP/tracked.q") || return 1
  (cd "$1" && git ls-files -t -z) > "$TMP/tracked.z" || return 1
  tr '\n\0' '\001\n' < "$TMP/tracked.z" > "$TMP/tracked" || return 1
  gone=0; sparse=0; dirs=0
  while IFS= read -r ent; do
    f=${ent#? }
    case $ent in S\ *) sparse=$((sparse + 1)); continue ;; esac
    case $f in
      *"$SOH"*) ;;
      *) if [ ! -e "$1/$f" ] && [ ! -L "$1/$f" ]; then gone=$((gone + 1)); continue; fi
         if [ -d "$1/$f" ] && [ ! -L "$1/$f" ]; then dirs=$((dirs + 1)); continue; fi ;;   # サブモジュール
    esac
    printf '%s\n' "$f" || return 1
  done < "$TMP/tracked"
  echo $((total - gone - sparse - dirs)) > "$TMP/expect" || return 1
  [ "$gone" -eq 0 ] || echo "lint: 作業ツリーに無い追跡ファイル $gone 件は見ていません（--staged は index の中身を見ます）" >&2
  [ "$sparse" -eq 0 ] || echo "lint: sparse checkout で外してある追跡ファイル $sparse 件は見ていません（--staged は index の中身を見ます）" >&2
}

# export_index <top> <dest> — index の中身を dest に書き出し、その一覧を標準出力に、検査するはずの件数を $TMP/expect に出す。
# tree にしてから取り出す（checkout-index は sparse checkout で外したファイルを書き出さない）
export_index() {
  tree=$(cd "$1" && git write-tree) || return 1
  (cd "$1" && git archive --format=tar "$tree") > "$TMP/index.tar" || return 1
  mkdir -p "$2" || return 1
  tar -xf "$TMP/index.tar" -C "$2" || return 1
  (cd "$1" && git ls-tree -r "$tree") > "$TMP/tree.q" || return 1
  total=$(count_lines "$TMP/tree.q") || return 1
  (cd "$1" && git ls-tree -r -z --name-only "$tree") > "$TMP/tree.z" || return 1
  tr '\n\0' '\001\n' < "$TMP/tree.z" > "$TMP/tree" || return 1
  dirs=0
  while IFS= read -r f; do
    if [ -d "$2/$f" ] && [ ! -L "$2/$f" ]; then dirs=$((dirs + 1)); continue; fi   # サブモジュール
    printf '%s\n' "$f" || return 1
  done < "$TMP/tree"
  echo $((total - dirs)) > "$TMP/expect" || return 1
}

# lint_tree <root> <一覧> <違反の出力先> — 検査して、受け取った件数を、一覧を作った側が出した件数（$TMP/expect）と突き合わせる。
# 一覧が途中で失われていたら（件数が合わなければ）return 2
lint_tree() {
  rm -f "$TMP/count"
  run_lint "$1" < "$2" > "$3" || { echo "lint: awk が失敗しました（上のメッセージを確かめる）。" >&2; return 2; }
  expect=""; got=""
  read -r expect < "$TMP/expect" || :
  read -r got < "$TMP/count" || :
  if [ -z "$expect" ] || [ "$expect" != "$got" ]; then
    echo "lint: 検査するはずのファイルは ${expect:-?} 件ですが、実際に検査に渡ったのは ${got:-?} 件です（一覧を作る途中で失われた）。" >&2
    return 2
  fi
  [ "$expect" -ne 0 ] || echo "lint: 追跡ファイルが 0 件なので、検査するものがありません" >&2
  return 0
}

# 違反の一覧（$1）を出して、件数で終了コードを決める
finish() {
  if [ -s "$1" ]; then
    sort -t: -k1,1 -k2,2n "$1" || cat "$1"             # 並べ替えられなくても、違反は見せる
    echo "lint: $(($(wc -l < "$1") + 0)) 件の違反で止めました。意図して書く行には、同じ行に除外の印（.githooks/lint.sh の先頭の説明）を理由つきで書きます" >&2
    return 1
  fi
  return 0
}

write_fixtures() {  # $1 = 例を置くディレクトリ。@ALT@ → //、@ALLOW@ → 除外の印（このファイル自身が当たらないように置き換えて書く）
  mkdir -p "$1/plugins/demo/reference" "$1/plugins/demo/skills/demo" "$1/plugins/demo/scripts" "$1/plugins/other/skills/other"
  cat > "$1/plugins/demo/reference/target.md" <<'EOF'
# 対象

## 在る節

### 3. `code` を含む節

## 中に「かぎ括弧」がある節

```text
## コードブロックの中の見出し
```
EOF
  cat > "$1/plugins/demo/reference/refs.md" <<'EOF'
# 参照

- `target.md`「在る節」 OK:heading-ref
- `target.md` の「見出しでない語句」 OK:heading-ref（間に語を挟む形は見ない）
- `target.md`「中に『かぎ括弧』がある節」 OK:heading-ref（入れ子のかぎ括弧は『』で書ける）
- `target.md`「3. code を含む節」 OK:heading-ref（見出しの側のバッククォートは無視する）
- `./target.md`「在る節」と `target.md`「在る」 OK:heading-ref（見出しの一部でもよい）
- `target.md`「無い節」 NG:heading-ref
- **`target.md`「無い『かぎ括弧』の節」** NG:heading-ref
- `target.md`「コードブロックの中の見出し」 NG:heading-ref
- `elsewhere.md`「リポジトリに無いファイル」 OK:heading-ref
- `<dir>/target.md`「置き換えて読む名前」 OK:heading-ref
- `target.md` を読み、「地の文のかぎ括弧」と続く OK:heading-ref
- `target.md`「無い節」 OK:heading-ref <!-- @ALLOW@heading-ref: 例として書いている -->
- `SKILL.md`「demo の見出し」 OK:heading-ref（同じプラグインの中から探す）
- `SKILL.md`「near の見出し」 OK:heading-ref（同じプラグインに 2 つあれば、どちらかにあればよい）
- `SKILL.md`「other の見出し」 NG:heading-ref（同じプラグインにあれば、ほかのプラグインは見ない）
EOF
  cat > "$1/plugins/demo/skills/demo/SKILL.md" <<'EOF'
# demo

## demo の見出し

```bash
ls "${CLAUDE_PLUGIN_ROOT}/reference"   # OK:fence-plugin-root（reference/ の外は見ない）
```
EOF
  mkdir -p "$1/plugins/demo/skills/near/reference"
  cat > "$1/plugins/demo/skills/near/SKILL.md" <<'EOF'
# near

## near の見出し
EOF
  cat > "$1/plugins/demo/skills/near/reference/steps.md" <<'EOF'
# 手順

`SKILL.md`「near の見出し」 OK:heading-ref（上へたどって、いちばん近い SKILL.md を見る）
`SKILL.md`「demo の見出し」 NG:heading-ref（近いものが在れば、同じプラグインのほかの SKILL.md は見ない）
EOF
  cat > "$1/plugins/other/skills/other/SKILL.md" <<'EOF'
# other

## other の見出し

`target.md`「在る節」 OK:heading-ref（ほかのプラグインのファイルは、リポジトリ全体から探す）
`target.md`「無い節」 NG:heading-ref
EOF
  cat > "$1/plugins/demo/reference/fence.md" <<'EOF'
# コードブロック

文中の `${CLAUDE_PLUGIN_ROOT}` は読み替える。 OK:fence-plugin-root

```bash
cat "${CLAUDE_PLUGIN_ROOT}/reference/a.md"   # NG:fence-plugin-root
cat "<reference>/a.md"                       # OK:fence-plugin-root
```

コードブロックを閉じたあとの CLAUDE_PLUGIN_ROOT。 OK:fence-plugin-root

````markdown
```bash
echo "$CLAUDE_PLUGIN_ROOT"   # NG:fence-plugin-root（4 つで開いた中の 3 つは閉じない）
```
echo "$CLAUDE_PLUGIN_ROOT"   # NG:fence-plugin-root
````

1. 字下げしたコードブロック:

   ```
   echo "$CLAUDE_PLUGIN_ROOT"   # NG:fence-plugin-root
   ```

   echo CLAUDE_PLUGIN_ROOT OK:fence-plugin-root

- ```bash
  echo "$CLAUDE_PLUGIN_ROOT"   # NG:fence-plugin-root（箇条書きの行で開くコードブロック）
  ```
  箇条書きの行で開いたコードブロックを閉じたあとの CLAUDE_PLUGIN_ROOT。 OK:fence-plugin-root

```bash
echo "$CLAUDE_PLUGIN_ROOT"   # OK:fence-plugin-root @ALLOW@fence-plugin-root: 例として書いている
```
EOF
  # CRLF のファイル（閉じを見落とすと、閉じたあとの行が検出される）
  awk '{ printf "%s\r\n", $0 }' > "$1/plugins/demo/reference/crlf.md" <<'EOF'
# CRLF

```bash
echo "$CLAUDE_PLUGIN_ROOT"   # NG:fence-plugin-root
```

閉じたあとの CLAUDE_PLUGIN_ROOT。 OK:fence-plugin-root

> 引用

空行のあとの本文。 OK:quote-blank
EOF
  cat > "$1/plugins/demo/reference/quote.md" <<'EOF'
# 引用

> 引用の 1 行目
> 引用の 2 行目 OK:quote-blank

空行のあとの本文。 OK:quote-blank

> 引用
空行なしで続く本文。 NG:quote-blank
その次の行。 OK:quote-blank

- 箇条書きの中
  > 字下げした引用
  空行なしで続く。 NG:quote-blank

> 引用
- 空行なしで続く箇条書きは、引用に巻き込まれない。 OK:quote-blank

> 引用
1. 1 で始まる番号つきの箇条書きも巻き込まれない。 OK:quote-blank

> 引用
2. 1 以外で始まる番号は地の文として巻き込まれる。 NG:quote-blank

> 引用
## 空行なしで続く見出し OK:quote-blank

> 引用
<!-- 空行なしで続く HTML コメント OK:quote-blank -->

> 引用
---

> 引用
```text
空行なしで開くコードブロック。 OK:quote-blank
```

> 引用
#見出しではない（# のあとに空白が無い）。 NG:quote-blank

> 引用
-箇条書きではない（- のあとに空白が無い）。 NG:quote-blank

```text
> コードブロックの中の引用
コードブロックの中は見ない。 OK:quote-blank
```

> 引用
空行なしで続く。 OK:quote-blank <!-- @ALLOW@quote-blank: 例として書いている -->

> 最後の行が引用 OK:quote-blank
EOF
  cat > "$1/plugins/demo/reference/jq.md" <<'EOF'
# jq

```bash
jq -r '.is_error @ALT@ true' r.json    # NG:jq-bool-default
jq -r '.ok@ALT@true' r.json            # NG:jq-bool-default
jq -r '(.a.b) @ALT@ true | not' r.json # NG:jq-bool-default
jq -r '.is_error @ALT@ false' r.json   # OK:jq-bool-default（false と null が false になるだけ）
jq -r '.name @ALT@ empty' r.json       # OK:jq-bool-default
jq -r '.name @ALT@ "trueish"' r.json   # OK:jq-bool-default
jq -r '.flag @ALT@ truename' r.json    # OK:jq-bool-default
jq -e '.is_error == true' r.json       # OK:jq-bool-default
curl https:@ALT@true.example/          # OK:jq-bool-default
```

文中の `.x @ALT@ true` も見る。 NG:jq-bool-default

文中の `.x @ALT@ true` の説明。 OK:jq-bool-default <!-- @ALLOW@jq-bool-default: 規則の説明 -->
EOF
  cat > "$1/plugins/demo/scripts/tick" <<'EOF'
#!/bin/bash
err=$(jq -r '.is_error @ALT@ true' "$1")    # NG:jq-bool-default
err=$(jq -r '.is_error @ALT@ false' "$1")   # OK:jq-bool-default
err=$(jq -r '.is_error @ALT@ true' "$1")    # OK:jq-bool-default @ALLOW@jq-bool-default: 例として書いている
EOF
  cat > "$1/plugins/demo/scripts/data.txt" <<'EOF'
.is_error @ALT@ true   OK:jq-bool-default（シェルスクリプトでも markdown でもないファイルは見ない）
EOF
  cat > "$1/plugins/demo/reference/allow.md" <<'EOF'
# 除外の印

印の書き方の説明: @ALLOW@<規則>: <理由> OK:allow-format OK:allow-unused

理由が無い。 NG:allow-format <!-- @ALLOW@quote-blank -->
理由が空。 NG:allow-format <!-- @ALLOW@quote-blank:  -->
無い規則。 NG:allow-format <!-- @ALLOW@no-such-rule: 理由 -->
当たっていない行の印。 NG:allow-unused <!-- @ALLOW@quote-blank: 当たっていない -->
規則が違う印。 `.x @ALT@ true` NG:jq-bool-default NG:allow-unused <!-- @ALLOW@quote-blank: 別の規則 -->
EOF
  # 名前にタブと " を含むファイル（一覧を -z で受けないと、検査から落ちる）
  cat > "$1/plugins/demo/reference/odd	\"name\".md" <<'EOF'
> 引用
空行なしで続く本文。 NG:quote-blank
EOF
  # 作業ツリーから消すファイルと、sparse checkout で外すファイル（作業ツリーの検査は見ない。index の検査は見る）
  cat > "$1/plugins/demo/reference/gone.md" <<'EOF'
`.x @ALT@ true` NG:jq-bool-default
EOF
  cp "$1/plugins/demo/reference/gone.md" "$1/plugins/demo/reference/sparse.md"
  mark="lint:"; mark="${mark}allow "   # 分けて書く（このファイル自身が印として読まれないように）
  find "$1" -type f > "$TMP/fx-all" || return 1
  while IFS= read -r f; do
    sed -e 's|@ALT@|//|g' -e "s|@ALLOW@|$mark|g" "$f" > "$f.new" || return 1
    mv "$f.new" "$f" || return 1
  done < "$TMP/fx-all"
  # 読めないファイル（宛先の無いシンボリックリンク）と、読めるが空のファイル
  ln -s nowhere.md "$1/plugins/demo/reference/dangling.md" || return 1
  : > "$1/plugins/demo/reference/empty.md" || return 1
}

# compare <名前> <root> <一覧> <実際の出力> — 例の NG／OK の印と、実際の出力を規則ごとに突き合わせる
compare() {
  sed 's/\] .*$/]/' "$4" | sort > "$TMP/fx-actual"
  for rule in $RULES; do
    if [ "$rule" = unreadable ]; then
      echo "plugins/demo/reference/dangling.md:0: [unreadable]" > "$TMP/fx-want"
      ok_lines=$(grep -c '/empty\.md$' "$3")
    else
      (cd "$2" && while IFS= read -r f; do
         grep -n "NG:$rule\([^a-z-]\|\$\)" "$f" 2>/dev/null | sed "s|^\([0-9]*\):.*|$f:\1: [$rule]|"
       done < "$3") | sort > "$TMP/fx-want"
      ok_lines=$(cd "$2" && while IFS= read -r f; do grep -h "OK:$rule\([^a-z-]\|\$\)" "$f" 2>/dev/null; done < "$3" | wc -l | tr -d ' ')
    fi
    grep -F "[$rule]" "$TMP/fx-actual" > "$TMP/fx-got"
    want=$(wc -l < "$TMP/fx-want" | tr -d ' ')
    if [ "$want" -eq 0 ] || [ "$ok_lines" -eq 0 ]; then
      echo "NG  $1 $rule: 例が足りない（検出される例 $want 行、検出されない例 $ok_lines 行）"; bad=1
    elif cmp -s "$TMP/fx-want" "$TMP/fx-got"; then
      echo "ok  $1 $rule: 検出される例 $want 行を検出、検出されない例 $ok_lines 行は検出なし"
    else
      echo "NG  $1 $rule:"; bad=1
      comm -23 "$TMP/fx-want" "$TMP/fx-got" | sed 's/^/      空振り（検出されるはず）: /'
      comm -13 "$TMP/fx-want" "$TMP/fx-got" | sed 's/^/      誤検出（検出されないはず）: /'
    fi
  done
  # 規則の一覧に無い識別子で出た違反が無いこと
  known=$(echo "$RULES" | sed 's/ /|/g')
  if grep -vE "\[($known)\]\$" "$TMP/fx-actual"; then echo "NG  $1: 一覧に無い規則の違反が出た"; bad=1; fi
}

# expect_note <名前> <標準エラーの控え> <含まれるはずの文字列>
expect_note() {
  if grep -qF -- "$3" "$2"; then echo "ok  $1 見ていないものの知らせ: $3"
  else echo "NG  $1 見ていないものの知らせが出ていない: $3"; bad=1; fi
}

self_test() {
  # pre-commit から呼ばれると GIT_INDEX_FILE などが付いている。例のリポジトリの操作が、呼び出し元の index に届かないように外す
  # shellcheck disable=SC2046
  unset $(git rev-parse --local-env-vars 2>/dev/null)
  fx="$TMP/fix\\tures"                 # 名前に \ を含める（パスの \ が解釈されると、全ファイルが読めなくなる）
  write_fixtures "$fx" || die "例を書けません。"
  (cd "$fx" && git init -q . && git add .) || die "例のリポジトリを作れません。"
  # 作業ツリーにだけ無い状態を作る（index には残す）
  (cd "$fx" && git update-index --skip-worktree plugins/demo/reference/sparse.md) || die "例のリポジトリを作れません。"
  rm "$fx/plugins/demo/reference/gone.md" "$fx/plugins/demo/reference/sparse.md" || die "例のリポジトリを作れません。"
  bad=0

  list_worktree "$fx" > "$TMP/fx-files" 2> "$TMP/fx-err" || die "例の一覧を取れません。"
  lint_tree "$fx" "$TMP/fx-files" "$TMP/fx-out" 2>> "$TMP/fx-err" || { cat "$TMP/fx-err" >&2; die "例を検査できません。"; }
  compare "作業ツリー" "$fx" "$TMP/fx-files" "$TMP/fx-out"
  expect_note "作業ツリー" "$TMP/fx-err" "作業ツリーに無い追跡ファイル 1 件"
  expect_note "作業ツリー" "$TMP/fx-err" "sparse checkout で外してある追跡ファイル 1 件"
  expect_note "作業ツリー" "$TMP/fx-err" "見つからない 1 件"

  export_index "$fx" "$TMP/fx-index" > "$TMP/fx-files" || die "例の index を書き出せません。"
  lint_tree "$TMP/fx-index" "$TMP/fx-files" "$TMP/fx-out" 2> "$TMP/fx-err" || { cat "$TMP/fx-err" >&2; die "例を検査できません。"; }
  compare "index" "$TMP/fx-index" "$TMP/fx-files" "$TMP/fx-out"
  for f in gone.md sparse.md; do
    if grep -q "/$f:1: \[jq-bool-default\]" "$TMP/fx-out"; then echo "ok  index 作業ツリーに無い $f も見ている"
    else echo "NG  index 作業ツリーに無い $f を見ていない"; bad=1; fi
  done

  # 途中のコマンドが失敗したら、通さない。違反のある例のリポジトリで、常に失敗する偽物を PATH の先頭に置いて確かめる
  # （偽物なしなら違反で 1。偽物があっても 0 にならないこと）
  self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  expect_rc "偽物なし" 1 1 ""
  for tool in tr wc awk git; do
    make_fake "$TMP/fake-$tool" "$tool" 1
    expect_rc "$tool が失敗" 2 2 "$TMP/fake-$tool"
  done
  make_fake "$TMP/fake-tar" tar 1      # tar を使うのは index の書き出しだけ
  expect_rc "tar が失敗" 1 2 "$TMP/fake-tar"
  # 一覧が黙って空になる場合（失敗を返さず、何も出さない tr）。件数の突き合わせで止まること
  make_fake "$TMP/fake-silent" tr 0
  expect_rc "tr が何も出さない" 2 2 "$TMP/fake-silent"
  # 追跡ファイルが本当に 0 件のリポジトリは通す
  mkdir "$TMP/fx-empty" || die "空のリポジトリを作れません。"
  (cd "$TMP/fx-empty" && git init -q .) || die "空のリポジトリを作れません。"
  fx="$TMP/fx-empty"
  expect_rc "追跡ファイルが 0 件" 0 0 ""
  return $bad
}

# make_fake <dir> <コマンド名> <終了コード> — 何も出さずに、その終了コードで終わる偽のコマンドを置く
make_fake() {
  mkdir -p "$1" || die "偽のコマンドを作れません。"
  printf '#!/bin/sh\nexit %s\n' "$3" > "$1/$2" || die "偽のコマンドを作れません。"
  chmod +x "$1/$2" || die "偽のコマンドを作れません。"
}

# expect_rc <名前> <引数なしの終了コード> <--staged の終了コード> <PATH の先頭に足すディレクトリ> — $fx の中で自分を実行する
expect_rc() {
  for mode in "" --staged; do
    if [ -z "$mode" ]; then want=$2; else want=$3; fi
    # shellcheck disable=SC2086
    (cd "$fx" && PATH="${4:+$4:}$PATH" sh "$self" $mode) > /dev/null 2>&1; rc=$?
    if [ "$rc" -eq "$want" ]; then echo "ok  $1: ${mode:-引数なし} は exit $rc"
    else echo "NG  $1: ${mode:-引数なし} は exit ${rc}（期待 ${want}）"; bad=1; fi
  done
}

case "${1:-}" in
  "")
    top=$(git rev-parse --show-toplevel) || die "git のリポジトリの中で実行してください。"
    list_worktree "$top" > "$TMP/files" || die "追跡ファイルの一覧を作れません（上のメッセージを確かめる）。"
    lint_tree "$top" "$TMP/files" "$TMP/out" || die "検査が最後まで走っていません。"
    finish "$TMP/out"
    ;;
  --staged)
    top=$(git rev-parse --show-toplevel) || die "git のリポジトリの中で実行してください。"
    # index の中身を書き出して見る（作業ツリーだけ直しても、コミットに入る中身が違反なら止まるように）
    export_index "$top" "$TMP/index" > "$TMP/files" || die "index の中身を書き出せません（衝突が残っていないか、上のメッセージを確かめる）。"
    lint_tree "$TMP/index" "$TMP/files" "$TMP/out" || die "検査が最後まで走っていません。"
    finish "$TMP/out"
    ;;
  --self-test)
    self_test
    ;;
  *)
    usage; exit 2
    ;;
esac
