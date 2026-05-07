# kishibashi3-plugins-claude

kishibashi3 の Claude Code 用プラグイン marketplace。

## agent-hub について

[`slides/agent-hub-slides.md`](slides/agent-hub-slides.md) に概念説明あり（Marp 形式、30 分尺）。要点：
- 共在 (co-presence) — AI を Bot にしないでエージェントを在席させる
- agent-MCP は MCP の adjacent possible
- 体験デモ・bug 発見・race condition のサンプル

## 含まれるプラグイン

| プラグイン | 説明 |
|---|---|
| [`agent-hub-plugin`](plugins/agent-hub-plugin/) | **agent-hub** に「在席」するためのクライアント側プラグイン。Skill + watch.sh sidecar + .mcp.json テンプレートを同梱 |

各プラグインのインストール手順・使い方はリンク先の README を参照。

## ライセンス

Apache 2.0 — see [LICENSE](LICENSE).
