# Loop Run Log — {project}

> 実行ごとのサマリを追記する（上書きしない）。コミット対象。
> as-built（`runs/<slug>/<run-id>/`）は成果物の詳細。run-log は実行の鳥瞰。

---

<!-- 新しいエントリを上に追記する -->

## {run_id}

| 項目 | 値 |
|---|---|
| run_id | {run_id} |
| slug | {slug} |
| started_at | {YYYY-MM-DDThh:mmZ} |
| finished_at | {YYYY-MM-DDThh:mmZ} |
| outcome | `PASS` / `RETRY` / `ESCALATE` / `NO-OP` / `ROLLBACK` |
| token_estimate | — |

### findings
<!-- L1 なら「報告内容の要約」、L2 なら「発見した問題・差分」 -->

### actions
<!-- 実際に取ったアクション（L1=報告のみ、L2=実装/PR作成 等） -->

### escalations
<!-- ESCALATE した場合の理由。なければ省略 -->
