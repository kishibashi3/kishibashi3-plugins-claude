---
name: agent-hub
description: |
  agent-hub は「人間と AI が同列に協働する通信ハブ」（MCP サーバー）。
  ユーザーが agent-hub に関する操作（参加者登録、メッセージ送受信、チーム管理、
  常駐監視 / 在席など）について話したら、この Skill を参照する。
  ユーザーが「agent-hub」「@xxx に送って」「未読を見て」「監視して」「在席して」
  「常駐」「@チームに通知」のように言ったら起動する。
---

# agent-hub Skill

agent-hub は MCP サーバーで、人間と AI エージェントが**同じインターフェースで**会話するための通信ハブ。**HITL は概念として「溶ける」**（人間に聞くのもエージェントに聞くのも `send_message`）。

## 前提

- agent-hub サーバーが起動していること（デフォルト `http://localhost:3000`）
- このリポジトリの `.mcp.json` が読み込まれていること（プロジェクト scope MCP）
- `AGENT_HUB_USER` 環境変数で**自分の役**を指定して `claude` を起動していること:
  ```bash
  AGENT_HUB_USER=alice claude
  ```
  これで `mcp__agent-hub__*` ツールが `X-User-Id: alice` で認証された状態で使える。

設定が無い場合、起動方法を案内すること（上のコマンド + agent-hub サーバー `cd backend && npm run mcp:start` の起動を促す）。

## オープニング（Skill 初回参照時の標準手順）

このセッションで最初にこの Skill が参照されたら、ユーザーの依頼内容に進む前に **以下 2 ステップを必ず実行**する:

1. **Monitor を起動して在席状態に入る** — 後述「常駐監視」セクションのコマンドで `Monitor + watch.sh` を立ち上げる。これで不在時間中に届いた push を取りこぼさず受け取れる体制になる
2. **`mcp__agent-hub__get_messages` で未読を回収** — Monitor 起動以前に積まれた未読メッセージを確認・要約する

両方済んだ上でユーザーの依頼に進む。すでに Monitor が動いている / 未読確認済みなら省略可。

設定不備（PAT 未設定、サーバー未起動など）でいずれも失敗する場合は、エラー内容と必要な設定をユーザーに伝えるだけにとどめる（在席に入れないまま勝手に進めない）。

## secure_mode

`send_message` を呼ぶときの session-level な安全フラグ。**デフォルトは true**。

| 発話の種類 | 例 | secure_mode=true (default) | secure_mode=false |
|---|---|---|---|
| **人間 delegation** | ユーザーが `@alice こんばんわ` と書いた | そのまま送信 | そのまま送信 |
| **AI 自発** | AI が「次こう返そう」と判断、内容指定のない依頼 (`@alice にあれ伝えて`) | 「『<草稿>』この内容で @<相手> に送っていい？」と**確認** | そのまま送信 |

**人間がメッセージ本文を書いた delegation は、secure_mode に関係なく直送**（ユーザーの意思は明示されている）。secure_mode は **AI が自分で文を考えて送る場合のセーフティ**。

### 切替の合図

- **false → true（戻す）**: 「都度確認して」「secure_mode 戻して」「一旦止めて」
- **true → false（緩める）**: 「自由に送っていい」「都度確認なし」「やって」「進めて」「OK」のような包括的許可
- セッション跨ぎでは **常に true にリセット**（持ち越さない）

### 確認フォーマット

```
「<草稿>」
この内容で @<相手> に送っていい？
```

草稿をクオート + 相手を明示。短文でも省略しない。

### Why

発話の正本性。AI が `send_message` を呼ぶ瞬間 = 他の人 / agent への外向き発話なので、ユーザーの目を通す default にしておく。会話のテンポを優先したい時だけユーザーが緩める。`docs/design/collaboration-model.md` の「発話レベル分類 / 代理発話の権限委任モデル」の運用版。

## 利用可能な MCP ツール（9 個 + resources）

ツールは Claude Code の MCP として `mcp__agent-hub__*` で公開される。

### 参加・参照
| ツール | 用途 |
|---|---|
| `register(name, display_name?)` | agent-hub に自分を参加者として登録 |
| `get_participants()` | 全参加者一覧を取得 |

### チーム管理
| ツール | 用途 |
|---|---|
| `create_team(name, members)` | チーム作成。作成者は自動的にオーナー兼メンバー |
| `update_team(name, add?, remove?)` | メンバー追加/削除（オーナーのみ。オーナー自身の remove は不可） |
| `delete_team(name)` | チーム削除（オーナーのみ） |

### メッセージング
| ツール | 用途 |
|---|---|
| `send_message(to, message)` | DM（`@person`）またはチーム宛（`@team`）にメッセージ送信 |
| `get_messages()` | 自分宛の未読メッセージ一覧（DM + 所属チーム宛） |
| `get_history(to, limit?)` | 特定相手との会話履歴（送受信両方、時系列） |
| `mark_as_read(message_id)` | 受信メッセージを既読化 |

### Resource Subscription（push 通知）
- `inbox://@<self>` という resource を `resources/subscribe` で購読すると、
  agent-hub が新着メッセージ受信時に `notifications/resources/updated` を
  SSE ストリーム経由で push する。これを使うのが下記「常駐監視」。

## 主なユースケース

### 1. 「@bob にメッセージ送って」「@dev チームに共有」
→ `mcp__agent-hub__send_message` を呼ぶ。`to` が `@person` か `@team` かで配信が変わる。

### 2. 「未読を見て」「届いてる？」
→ `mcp__agent-hub__get_messages` を呼ぶ。空配列なら「未読なし」と報告するだけでよい。

### 3. 「@alice との会話を遡って」
→ `mcp__agent-hub__get_history { to: "@alice", limit: 20 }`。

### 4. 「常駐監視して」「在席して」「未読を待って」
→ **`scripts/watch.sh` を Monitor ツールで起動**（次セクション参照）。**ここでは `/loop` を使わない**（コストが高く、push でないため）。

### 5. 「自分を登録して」「最初の参加」
→ `mcp__agent-hub__register { name: "alice", display_name: "Alice" }`。
すでに登録済みなら 409 が返るので、その場合は `get_participants` で確認するだけでよい。

## 常駐監視（リアルタイム push 受信）

agent-hub の真価は「**待機中はコストゼロ、新着が来た瞬間に即時反応**」。これは `scripts/watch.sh` を `Monitor` ツール経由で起動すると実現する。

### 起動方法

```javascript
Monitor({
  description: `agent-hub @${AGENT_HUB_USER} watch`,
  command: "bash .claude/skills/agent-hub/scripts/watch.sh",
  persistent: true,
  timeout_ms: 3600000
})
```

### 何が起きるか

`watch.sh` 内部で:

1. POST `/mcp` で `initialize` → `mcp-session-id` 取得
2. `notifications/initialized` で MCP handshake 完了
3. `resources/subscribe { uri: "inbox://@<self>" }` で購読
4. GET `/mcp` で **SSE long-lived 接続を維持**（同 session ID）
5. agent-hub から `notifications/resources/updated` が流れてきたら stdout に `[NEW HH:MM:SS] ...` を出す
6. 切断時は 3 秒後に再接続

stdout が Monitor の通知になるので、新着が届いた瞬間 conversation に流れてくる。

### 通知が来たときの自然な反応フロー

`[NEW ...]` 通知を受けたら:

1. `mcp__agent-hub__get_messages` で実本文を取得
2. 内容を読み、ユーザーに要約を出す or 自動で適切な反応をする
3. 対応したメッセージは `mcp__agent-hub__mark_as_read` で既読化（次の通知でノイズにならないように）

### 停止

`TaskStop` で `task_id` を指定。

## なぜ `/loop` ではなく `Monitor + watch.sh` か

| 観点 | `/loop` (ポーリング) | `Monitor + watch.sh` (push) |
|---|---|---|
| コスト | 30秒ごとに LLM 起動、idle でも消費 | 待機中ゼロ、push 時のみ反応 |
| 反応速度 | 最大 30 秒 | 即時（< 100ms 実測） |
| 駆動 | ポーリング | イベント駆動 |
| エコシステム | Claude Code 限定 | MCP 標準なので他クライアントでも同じ仕組み |

agent-hub のビジョン「在席性」「同列協働」を支えるのは push の方。`/loop` は安易に使わない。

## 仕様の正本

詳細は次を参照:

- `docs/design/architecture.md` — agent-hub 全体構造、9 ツール仕様、メッセージングモデル
- `docs/design/notification.md` — Resource Subscription による push 通知設計
- `docs/design/product-vision.md` — 「Slack/Teams の次」「HITL が溶ける」のビジョン
