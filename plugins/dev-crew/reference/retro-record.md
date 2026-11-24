# retro の記録の形（版 1）

PR ごとの振り返り（`dev-crew:retro`）が、PR のコメントに残す記録の形。
書く側（`agents/retro.md`）と、あとでまとめて読む側の両方が、このファイルを読む。課題（issue）は作らない。記録はこのコメントだけ。

- 形を変えるときは版を上げ（先頭の印の `v1`）、下の「集め方」「読み戻し」を同じ変更で直す。
- 基準の識別子は `failure-criteria.md` の見出しにあるものだけを使う。

## 形

1 回の招集で、PR にコメントを 1 つ足す（先にあるコメントは編集しない）。`{{…}}` は書く側が埋める場所で、投稿する本文に 1 つも残さない。

````markdown
<!-- retro-record v1 -->
## 🔁 retro の記録（{{trigger}}）

```retro
pr: {{PR 番号}}
trigger: {{trigger}}
rounds: {{数か unknown}}
rejects: {{数か unknown}}
interventions: {{数か unknown}}
```

| # | 基準 | 何が起きたか | 何が止めたか | 被害 |
|---|---|---|---|---|
| 1 | `{{基準の識別子}}` | {{何が起きたかを 1 行で}} | {{止めたもの}} | {{severe か -}} |

- 不足していた入力: {{無かった入力の名前。無ければ「なし」}}
````

- **1 行目は必ず `<!-- retro-record v1 -->`。** 記録のコメントであることと、形の版を、この印 1 つで表す。
- **出来事が 0 件なら、表の見出しの 2 行だけを残し**、表の下に `- 出来事: なし` を足す。
- 表のセルに `|` と改行と `{{` を書かない（言い換える）。出来事 1 件が 1 行。
- `post-merge` の記録には、PR 作成より後に分かった出来事だけを書く（先の記録に書いた出来事を繰り返さない。回数が二重になる）。

### ブロックの値

| キー | 意味 | 値 |
|---|---|---|
| `pr` | 対象の PR 番号 | 数 |
| `trigger` | いつの記録か | `pr-created`（PR 作成時）か `post-merge`（マージ後） |
| `rounds` | 司法を招集した回数 | 数（1 = 一発で通った）か `unknown` |
| `rejects` | 司法の `REJECT` と `RETRY` の回数 | 数か `unknown` |
| `interventions` | 人間の介入の回数 | 数か `unknown`。許可プロンプトの承認は数えない |

**`unknown` と 0 は別の事実。** 0 は「無かったと分かっている」、`unknown` は「分からない」。渡されなかった・取れなかった値を 0 と書かない。

### 表の列

| 列 | 書くもの |
|---|---|
| 基準 | 当てはまる基準の識別子を、すべて、1 つずつバッククォートで囲んで並べる（`claim-mismatch` `verification-swapped` のように）。どれにも当てはまらなければ `other` |
| 何が起きたか | 事実を 1 行で。提案・評価は書かない |
| 何が止めたか | 次の 5 語のどれか 1 つ |
| 被害 | `severe` か `-` |

「何が止めたか」の 5 語:

| 語 | 使うとき |
|---|---|
| `hook` | 機械的な検査（hook・lint・CI）が止めた |
| `書記` | 書記の所見で見つかった |
| `司法` | 司法の判定（`REJECT` / `RETRY` / `ESCALATE`）か、止めない指摘で見つかった |
| `人間` | 人間の発言・レビューで見つかった |
| `止まらなかった` | 誰も止めないまま進んだ（マージされた、または後から事実として分かった） |

### `severe`（1 回の被害が大きい出来事）

回数を待たずに人間へ伝える出来事に付ける印。**実際に起きたか、人間が止めなければ起きていたもの**のうち、次に当たるものに付ける:
データの破壊・消失、秘匿情報や私的な情報の露出、契約に無い全体の状態（マシン全体の設定・共有の環境・公開済みの履歴）の変更。
印を付けても課題は作らない。書く側は呼び出し元への返答に `severe` の行を載せ、呼び出し元は人間へのサマリで必ず伝える。

## 読み戻し

ある PR に、ある `trigger` の記録があるかを確かめる。出力は記録のコメントの URL（1 行に 1 つ）。**何も出なければ、記録は無い。**
投稿の前（二重に書かない）、投稿の後（投稿されたことを確かめる）、呼び出し元の確認の 3 か所で、同じコマンドを使う。
見るのは ```` ```retro ```` ブロックの `trigger` だけで、先頭の印は見ない（印の無い旧い形の retro のコメントも「既にある」と数える。親の掃き出しと同じ見方）。

````bash
gh pr view <PR番号> --json comments --jq '.comments[] | select(.body | test("```retro[^`]*trigger: <trigger>")) | .url'
````

## 集め方

リポジトリの PR・課題のコメントをすべて取り、記録だけを拾って、基準ごとの回数を出す。読むだけで、書き込みはしない。
`<dir>` は `mktemp -d` が返したディレクトリ。絞るなら、URL の末尾に `&since=<ISO 8601 の時刻>` を足す（その時刻より後に書かれた・直されたコメントだけになる）。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/comments?per_page=100" > <dir>/comments.json
```

````bash
jq -s '
  def events: split("\n")[] | select(test("^\\| *[0-9]+ *\\|")) | split("|") | map(gsub("^ +| +$"; ""))
    | { cols: length, criteria: [ (.[2] // "") | scan("[a-z][a-z-]*") ], what: .[3], stopped_by: .[4], damage: .[5] }
    | . + { severe: (.damage == "severe"),
            ok: (.cols == 7 and (.criteria | length > 0) and (.stopped_by | IN("hook", "書記", "司法", "人間", "止まらなかった")) and (.damage | IN("severe", "-"))) };
  [ (add // [])[]
    | select(.body | startswith("<!-- retro-record v"))
    | (.body | gsub("\r"; "")) as $body
    | (($body | capture("^<!-- retro-record v(?<n>[0-9]+) -->").n | tonumber) // null) as $version
    | ((($body | capture("```retro\n(?<b>[^`]*)```").b) // "") | split("\n") | map(capture("^(?<key>[a-z]+): *(?<value>.*)$")) | from_entries) as $m
    | { url: .html_url, at: .created_at, version: $version, pr: ($m.pr | tonumber? // null), trigger: $m.trigger,
        rounds: $m.rounds, rejects: $m.rejects, interventions: $m.interventions, events: [ $body | events ] }
  ] as $all
  | ($all | map(select(.version == 1 and .pr != null and (.trigger | IN("pr-created", "post-merge")) and all(.events[]; .ok)))) as $readable
  | ($readable | group_by([.pr, .trigger]) | map(sort_by(.at) | last)) as $counted
  | { records: ($all | length), counted: ($counted | length),
      by_criterion: ( [ $counted[] | .pr as $pr | .events[].criteria[] | { c: ., pr: $pr } ]
                      | group_by(.c) | map({ criterion: .[0].c, count: length, prs: (map(.pr) | unique) }) | sort_by(-.count, .criterion) ),
      severe: [ $counted[] | . as $r | .events[] | select(.severe) | { pr: $r.pr, url: $r.url, criteria, what } ],
      unparsed: ($all - $readable | map(.url)),
      duplicates: ($readable - $counted | map(.url)),
      list: $counted }
' <dir>/comments.json
````

| 出力 | 中身 |
|---|---|
| `records` / `counted` | 印の付いたコメントの数 / そのうち数に入れた記録の数 |
| `by_criterion` | 基準ごとの回数（`count`）と、起きた PR の番号（`prs`）。多い順 |
| `severe` | `severe` の付いた出来事 |
| `unparsed` | 読めなかった記録の URL。**数に入れていない**ので、空でなければ回数は足りていない。読めないのは: 版が 1 でない、ブロックの `pr`・`trigger` が無い、出来事の行の列の数が合わない（セルに `\|` がある）、基準が無い、「何が止めたか」「被害」が決まった語でない |
| `duplicates` | 同じ PR・同じ `trigger` の記録が 2 つ以上あるときの、いちばん新しいもの以外の URL。**数に入れていない** |
| `list` | 数に入れた記録ごとの値（`url`・`at`・`version`・ブロックの値・`events`） |

- 印の無い旧いコメント（この形より前の、手で書いた記録や旧い retro のコメント）は拾わない。
- `by_criterion` の識別子が `failure-criteria.md` に無ければ、書き間違い。その記録を直すのではなく、読む側が数から外して人間に伝える。
- `rounds` / `rejects` を合計するなら、`trigger` が `pr-created` の記録の値だけを使う（`post-merge` の記録は同じ値を引き継いで書いているので、足すと二重になる）。
