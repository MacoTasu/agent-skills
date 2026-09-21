# 公開前チェックリスト

**読んで想像せず、実行する。** 構造検査だけで通してしまうと、配信環境で初めて出る欠陥を逃す。

---

## 1. ドキュメントの土台

- [ ] **`<meta charset="utf-8">` がある**

  無いと、`charset` を付けずに配信するサーバでブラウザが推測に失敗し、**非ラテン文字が全て化ける**。
  ファイル自体が UTF-8 でも関係ない。プレビュー環境が `<head>` を被せる作りだと**そこでは露見せず**、
  素のファイルを配信する GitHub Pages やローカルサーバで初めて出る。

  ```bash
  grep -c 'meta charset' <file>     # 1 であること
  ```

- [ ] **`<meta name="viewport" content="width=device-width, initial-scale=1">` がある**

  無いとモバイルで縮小表示になり、本文が読めない。

- [ ] タグの開閉が揃っている

  ```bash
  python3 -c "
  import re,sys,pathlib
  from collections import Counter
  s=pathlib.Path(sys.argv[1]).read_text()
  t='div|section|dl|dt|dd|p|svg|g|header|footer|pre|code|span|h1|h2|h3|table|tr|td|th'
  o=Counter(re.findall(rf'<({t})\b[^>]*?(?<!/)>',s)); c=Counter(re.findall(rf'</({t})>',s))
  bad={k:(o[k],c[k]) for k in set(o)|set(c) if o[k]!=c[k]}
  print('不整合:', bad or 'なし')" <file>
  ```

## 2. テーマ

- [ ] **`body` に token 由来の背景色が明示されている**

  透明のままだと、埋め込み先の地の色を借りてしまい、片方のテーマで文字が読めなくなる。

- [ ] **色の定義が `:root` に揃っている** — `@media (prefers-color-scheme)` や `[data-theme]` の
      **中でしか定義されていない色が無い**こと。そこにしか無い色は、テーマ指定が無い既定状態で適用されない

  ```bash
  grep -n '#[0-9A-Fa-f]\{3,8\}' <file> | grep -v ':root'   # 出力が無いか、意図したものだけ
  ```

- [ ] **ライト・ダーク両方で実際にレンダリングして見る**（下の「実レンダリング確認」）

## 3. 実レンダリング確認

`file:` プロトコルはブラウザ自動化から塞がれていることがあるので、ローカル配信する。

```bash
cd <ディレクトリ> && python3 -m http.server 8931 &
```

その上で、ブラウザ自動化で以下を確認する。

- [ ] **ライトテーマ** — 開いて文字化けが無いか、階層が読めるか
- [ ] **ダークテーマ** — `document.documentElement.setAttribute('data-theme','dark')` を評価してから見る。
      図版（SVG）の色が CSS 変数で解決されているかも確認する
- [ ] **フォントが読み込まれている** — `document.fonts.status === 'loaded'`。
      指定した書体が落ちて既定書体で出ていないか
- [ ] **コンソールエラーが無い**（`favicon.ico` の 404 は無視してよい）

確認後はサーバを止める。

## 4. レスポンシブ

- [ ] **狭い幅（390px 相当）でページ本体が横スクロールしない**

  ```js
  // ビューポートを 390x844 にしてから評価
  () => { const d=document.documentElement;
          return {scrollWidth:d.scrollWidth, clientWidth:d.clientWidth,
                  overflow: d.scrollWidth > d.clientWidth}; }
  ```

- [ ] **広い要素は自分のコンテナの中でスクロールする** — 表・コード・図版は
      `overflow-x: auto` を持つ親に入れる。ページ本体を横に伸ばさない

## 5. 内容

- [ ] **実データ・実名で書かれている** — プレースホルダや仮の数値が残っていない
- [ ] **数値が実物と一致する** — 「5軸24項目」のような具体値は、書いた後に対象が変わると必ずズレる。
      公開前に数え直す
- [ ] **「決定の記録」がある** — 結論だけでなく理由が書かれている
- [ ] **外部に出してよい内容か** — 固有名詞・内部の数値・秘匿情報が混ざっていない。
      公開リポジトリの `docs/` に置くなら、その時点で公開される

## 6. 配信（GitHub Pages に載せる場合）

- [ ] `docs/.nojekyll` がある
- [ ] README の冒頭からリンクされている
- [ ] Pages の配信元が `main` の `/docs` になっている

  ```bash
  gh api repos/<owner>/<repo>/pages --jq '{status, source: .source}'
  ```
