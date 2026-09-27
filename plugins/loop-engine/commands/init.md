---
description: "このリポジトリで loop-engine を回すための初期セットアップ（spec-kit の設定確認・hooks・settings 配線）"
---

現在のリポジトリに loop-engine の実行基盤を用意する。冪等なので何度実行しても安全。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/loop-init"
```

揃うもの・確認されるもの:

| 対象 | 役割 |
|---|---|
| spec-kit の設定（`.specify/`・`feature_numbering`・constitution） | 仕様（SSOT）は spec-kit の `specs/<機能>/`。**確認して足りないものを案内するだけで、書き換えない** |
| `.claude/hooks/{validate,gate}.sh` | プロジェクト固有 validation の雛形（既定 no-op） |
| `.claude/settings.json` | hooks 配線（PostToolUse=validate / Stop=gate）＋**プラグイン宣言**を安全マージ |

実行後、出力の言語検出結果に従って `.claude/hooks/` の中身を埋める。**ハーネスはコマンドを
持たない＝ここが唯一の拡張点。**

spec-kit の設定で案内が出たら、人間が直してコミットする:

- 未初期化 → `specify init --here --force --non-interactive --integration claude --script sh`（ブランチの上で）
- `.specify/init-options.json` の `feature_numbering` を `"timestamp"` に
- constitution に「各 FR と受け入れシナリオは自動テストで検証する（MUST）」を追加

`.specify/` と `.claude/skills/speckit-*` はコミットすること。cloud の routine にプラグインは届かないが、
リポジトリにコミットされたスキルは届く。

次に最初の仕様を書く。`/conductor:dev <作りたいもの>`（main 上の親が spec-kit で起草して仕様の PR を作る）か、
`/spec-intake:spec-draft <issue番号>`。詳細は `${CLAUDE_PLUGIN_ROOT}/skills/loop-engine/reference/SETUP.md`。
