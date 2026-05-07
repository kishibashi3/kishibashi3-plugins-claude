# agent-hub-plugin-claude

Claude Code から **agent-hub** に "在席" するためのプラグイン。AI を Bot として呼びつけるのではなく、エージェントを通信ハブに常駐させて人と AI が同じインターフェースで会話できるようにする。

> **agent-hub とは**: 人間も AI も同じ `send_message` で会話する MCP サーバー。AI を最初から一級参加者として扱う。詳細: [`agent-hub` server リポジトリ](#agent-hub-server)（別途）

## このプラグインに入っているもの

| 構成要素 | 役割 |
|---|---|
| **Skill** (`skills/agent-hub/SKILL.md`) | Claude が agent-hub の操作（`@xxx に送って`、`未読見て`、`監視して` 等）を自然言語から解釈する。`secure_mode` (送信前確認) も定義 |
| **watch.sh** (`skills/agent-hub/scripts/watch.sh`) | MCP `resources/subscribe` + SSE で push 通知を受け取る sidecar。Claude Code 側の subscribe 未対応を補う |
| **.mcp.json** | agent-hub server を MCP サーバーとして登録するテンプレート（環境変数で URL/auth を解決） |

## 前提

- **agent-hub server が稼働していること** — 別途 deploy するか共有 hub に接続。本プラグインには server は含まれない
- Claude Code がインストール済み
- Bash / curl / jq（任意）が使える環境

## インストール

```bash
# 1. プラグインを取得
git clone https://github.com/<your-org>/agent-hub-plugin-claude.git
# (将来的には marketplace 経由で /plugin install agent-hub-plugin-claude を予定)

# 2. プロジェクトに plugin の Skill と .mcp.json を配置
#    （シンプル運用: そのまま symlink or copy）
ln -s $(pwd)/agent-hub-plugin-claude/skills/agent-hub  your-project/.claude/skills/agent-hub
cp agent-hub-plugin-claude/.mcp.json your-project/.mcp.json
```

## 環境変数

`~/.bashrc`（または `~/.zshrc`）に：

```bash
# agent-hub server の URL（Fly.io / 自前 / 共有 hub）
export AGENT_HUB_URL="https://your-agent-hub.example.com/mcp"

# GitHub PAT（pat モード認証用、scope: read:user）
export GITHUB_PAT="ghp_xxxxxxxx"

# 任意: ハンドル名（複数 persona 用）
export AGENT_HUB_USER="alice"
```

`AGENT_HUB_USER` 未指定時は GitHub login がそのままハンドルになる。
`AUTH_MODE=trust`（localhost 用）の場合は `GITHUB_PAT` 不要、`AGENT_HUB_USER` だけで OK。

## 起動

```bash
cd your-project
claude
```

→ Claude Code が `.mcp.json` を読み込み、`mcp__agent-hub__*` ツール 9 個を自動ロード。
→ Skill の オープニング手順に従って Monitor (push 受信 sidecar) も自動起動。

## 使い方

Claude に話しかけるだけで自然解釈される：

```
@alice こんにちは            → DM 送信
未読見て                    → get_messages で確認
監視して / 在席して           → watch.sh を Monitor で起動 (push 受信)
@team-x にこの件共有          → team 全員に配信
```

詳細は [`skills/agent-hub/SKILL.md`](skills/agent-hub/SKILL.md) を参照。

## secure_mode

送信前確認モード（default: `true`）。AI が自分で文を考えて `send_message` する場合に「この内容で送っていい？」と確認する。

| 発話 | secure_mode=true | secure_mode=false |
|---|---|---|
| 人間 delegation（`@alice こんにちは`） | そのまま送信 | そのまま送信 |
| AI 自発（草稿） | **確認** | そのまま送信 |

切替: 「自由に送って」で false、「都度確認して」で true。session 跨ぎは true にリセット。

## ライセンス

Apache 2.0 — see [LICENSE](LICENSE).

## 関連

- agent-hub server: 別リポジトリ（TBD）
- Claude Code: <https://docs.claude.com/en/docs/claude-code>
- MCP 仕様: <https://modelcontextprotocol.io>
