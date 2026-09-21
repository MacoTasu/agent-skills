---
description: "このリポジトリで loop-engine を回すための初期セットアップ（goals/ ・hooks ・settings 配線）"
---

現在のリポジトリに loop-engine の実行基盤を用意する。冪等なので何度実行しても安全。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/loop-init"
```

揃うもの:

| 生成物 | 役割 |
|---|---|
| `goals/` | 変更ユニット（spec）置き場。**人間が所有する SSOT** |
| `.claude/hooks/{validate,gate}.sh` | プロジェクト固有 validation の雛形（既定 no-op） |
| `.claude/settings.json` | hooks 配線（PostToolUse=validate / Stop=gate）＋**プラグイン宣言**を安全マージ |
| `.gitignore` | `.claude/loop/judgments.md` を追記 |

実行後、出力の言語検出結果に従って `.claude/hooks/` の中身を埋める。**ハーネスはコマンドを
持たない＝ここが唯一の拡張点。**

**`.claude/settings.json` のプラグイン宣言（`extraKnownMarketplaces` ＋ `enabledPlugins`）は
コミットすること。** ユーザー設定で有効にしたプラグインは cloud session に届かないため、
これが無いと定期発火（cloud routine）の側にハーネスが存在しない。

次に最初の spec を書く。**仕様の様式と起草の支援は `spec-intake` プラグインが持つ**
（loop-engine は spec を実行するもので、書き方は教えない）。

```
/plugin install spec-intake@macotasu-agent-skills
/spec-intake:spec-draft <issue番号>     # issue から起草して PR にする
```

手で書くなら `spec-intake` 同梱の `SPEC.template.md` を `goals/$(date +%Y%m%d)-<slug>.md` に写す。
`status: active`、`autonomy:` は省略（＝L1＝報告のみ）から始める。詳細は
`${CLAUDE_PLUGIN_ROOT}/skills/loop-engine/reference/SETUP.md`。
