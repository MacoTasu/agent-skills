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
| `.githooks/{pre-commit,pre-push,public-guard.sh}`・`.gitleaks.toml` | 公開物ガード。git の hook が commit / push の直前に gitleaks で差分を検査する（既定ルール＋端末依存・個人情報のパターン）。`core.hooksPath` は**未設定で、`.git/hooks/` に自前の hook（`.sample` 以外）も無いときだけ** `.githooks` に設定する。別の値が設定済み、または既存の hook があるときは触らず、統合の手順を案内する（既存の hook を黙って無効にしない）。linked worktree（`git worktree add` の先）で実行したときも設定せず、`.githooks/` をコミットしてからメインの作業ツリーで設定するよう案内する。gitleaks が無ければ導入を案内する（無い間は commit / push が止まる） |
| `.claude/hooks/guard.sh` | Claude Code の PreToolUse。`git commit` / `push` の前に、上の公開物ガードが有効か（`core.hooksPath` と gitleaks）だけを確かめる。走査はしない |
| `.claude/settings.json` | hooks 配線（PreToolUse=guard / PostToolUse=validate / Stop=gate）＋**プラグイン宣言**。既存 hooks があるときは書き換えず、guard の配線が無ければ todo を出す。jq があるとき、JSON として読めなければ何も変えずに止まる |

実行後、出力の言語検出結果に従って `.claude/hooks/` の中身を埋める。**ハーネスはコマンドを
持たない＝ここが唯一の拡張点。**

`.githooks/` と `.gitleaks.toml` と `.claude/settings.json`（`.claude/hooks/` も）は一緒にコミットする。
public リポジトリなら `.githooks/public-guard.sh` の `REQUIRE_NOREPLY=1` にする。`core.hooksPath` は clone ごとの設定なので、
別の clone では `git config core.hooksPath .githooks` を 1 回実行する（`/loop-engine:init` を再実行してもよい）。

spec-kit の設定で案内が出たら、人間が直してコミットする:

- 未初期化 → `specify init --here --force --non-interactive --integration claude --script sh`（ブランチの上で）
- `.specify/init-options.json` の `feature_numbering` を `"timestamp"` に
- constitution に「各 FR と受け入れシナリオは自動テストで検証する（MUST）」を追加

`.specify/` と `.claude/skills/speckit-*` はコミットすること。cloud の routine にプラグインは届かないが、
リポジトリにコミットされたスキルは届く。

次に最初の仕様を書く。`/conductor:dev <作りたいもの>`（main 上の親が spec-kit で起草して仕様の PR を作る）か、
`/spec-intake:spec-draft <issue番号>`。詳細は `${CLAUDE_PLUGIN_ROOT}/skills/loop-engine/reference/SETUP.md`。
