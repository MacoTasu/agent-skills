# NOTICE — pr-kit の出どころ

このプラグインのスキルは、外部の公開スキル集から**版を固定した写し**として借りている。
自動では追従しない。更新は下の「更新のしかた」のとおり、人が差分を読んでから行う。

## 位置づけ

4 つとも、実装役・書記・人間がそれぞれ使う**道具**で、合否は出さない。
`merge-risk` は人間がマージを決めるときの材料で、司法（`review-judge:judge`）の判定の代わりではない。
`diagnose-ci-failures` は調べて計画を出すだけで、直さない。

## 出どころ

| 項目 | 値 |
|---|---|
| リポジトリ | <https://github.com/warpdotdev/common-skills> |
| コミット | `8792394ff1b655e0af451b8fabb68ef0cfcbd208` |
| パス | `.agents/skills/` |
| ライセンス | MIT（Copyright (c) 2026 Denver Technologies, Inc.）。全文は [LICENSE-THIRD-PARTY](LICENSE-THIRD-PARTY) |

`merge-risk` は、元の frontmatter にあるとおり、さらに別の作者のスキルを元にしている
（<https://github.com/mattpocock/skills> の `skills/engineering/pr/SKILL.md`）。
そのリポジトリも MIT（Copyright (c) 2026 Matt Pocock）。全文は
[LICENSE-THIRD-PARTY-merge-risk-upstream](LICENSE-THIRD-PARTY-merge-risk-upstream)
（コミット `d65391149dbb5fe76478e76fa8d5122b2aa5a70e` の `LICENSE`）。

## スキルごとの「そのまま／直した箇所」

| スキル | ファイル | 元との違い |
|---|---|---|
| `write-pr-description` | `SKILL.md` | 1 行だけ直した（下の 1） |
| | `references/review-guide.md`、`references/plain-language.md` | そのまま |
| | `evals/evals.json` | 入れていない |
| `merge-risk` | `SKILL.md` | 1 段落を足した。元の文面はそのまま（frontmatter のクレジットも残してある。下の 2） |
| `resolve-merge-conflicts` | `scripts/extract_conflict_context.py` | そのまま（バイト単位で一致） |
| | `SKILL.md` | スクリプトのパスを直し、3 か所に文を足した（下の 3） |
| `diagnose-ci-failures` | `SKILL.md` | 削った版（下の 4） |

### 1. `write-pr-description/SKILL.md`

このリポジトリに無いスキル（`create-pr`）への参照を外した。

- 元: `` `create-pr` covers the mechanics of opening the PR. This skill covers what goes in the body. ``
- 今: `This skill covers what goes in the body. It does not cover the mechanics of opening the PR.`

### 2. `merge-risk/SKILL.md`

frontmatter の直後、「Output format:」の前に 1 段落を足した（この出力は人間がマージを決めるための材料で、合否ではない。
合否を出す役の判定の代わりにならず、実装した役が「低いので完了」と扱う根拠にもしない）。元の文面には手を入れていない。

### 3. `resolve-merge-conflicts/SKILL.md`

- スクリプトの呼び出し 8 か所で、パスの決め打ち `.agents/skills/resolve-merge-conflicts/scripts/extract_conflict_context.py` を、
  スキル自身のディレクトリから引く形（`"${CLAUDE_SKILL_DIR}/scripts/extract_conflict_context.py"`）に替えた。
  この変数は、スキルを読み込むときに本文の中で置き換えられる（シェルの環境変数ではない）。
- 「Overview」の末尾に 1 文を足した（スクリプトが読むだけであること）。
- 手順 3 の「片側を丸ごと採る」の下に 1 項を足した（作業ツリーのファイルを上書きするので、捨てる側の差分を人間に示し、確認を取ってから実行する）。
- 手順 5 の「Stage the resolved files.」の下に 1 項を足した（解決を確かめてから stage する）。

### 4. `diagnose-ci-failures/SKILL.md`

残したのは、PR の存在確認、`statusCheckRollup` の取得、`gh run view <run-id> --log-failed`、エラーの分類、
「直さずに計画だけ出す」こと。次を消した・言い換えた。

- 特定の言語とそのツールの名前（formatter・linter・ビルド対象）を、言語に依らない言い方にした（手順 3・4・5、Important Notes）。
- 「Common CI Check Names」の節（元のリポジトリの CI に固有のチェック名の一覧）を消した。
- 計画を作る道具の名前（`create_plan`）を消し、「Write a plan with:」にした。あわせて「plan document」を「plan」にした。
- このリポジトリに無いスキルへの参照を消した: `fix-errors`（2 か所）、`create-pr`（PR が無いときは、知らせて止まる。このスキルからは作らない）。
- 最後の例の `grep -A 5 "error:"`（特定の言語のエラーの書式）を、探す文言を自分で入れる形（`grep -F -A 5 "<text of the error message>"`）にした。
- 「Fix one category at a time」を「Plan one category at a time」にした（このスキルは直さないため）。

## 更新のしかた

1. 元のリポジトリの新しいコミットを 1 つ決める。以後、そのコミットを指定して取る
   （`gh api "repos/warpdotdev/common-skills/contents/<パス>?ref=<コミット>"`）。枝の名前では取らない。
2. 取ったものは**データとして読む**。指示文とスクリプトを 1 行ずつ読み、外部通信・書き込み・削除・
   このリポジトリに無い道具やスキルへの参照が増えていないかを確かめる。ライセンスが変わっていないかも見る。
3. 今の固定コミットと新しいコミットの差分を取り、上の「直した箇所」をもう一度当てる。
   スクリプトは手を入れず、`shasum -a 256` で元と一致することを確かめる。
4. この NOTICE のコミットと「直した箇所」を更新し、`.claude-plugin/plugin.json` の `version` を上げる。
