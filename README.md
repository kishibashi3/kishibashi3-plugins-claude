# claude-plugins-kishibashi3

kishibashi3 の Claude Code 用プラグイン marketplace。

## 含まれるプラグイン

| プラグイン | 説明 |
|---|---|
| [`agent-hub-plugin`](plugins/agent-hub-plugin/) | **agent-hub** に「在席」するためのクライアント側プラグイン。Skill + watch.sh sidecar + .mcp.json テンプレートを同梱 |

## 使い方

Claude Code 内で：

```
/plugin marketplace add https://github.com/kishibashi3/claude-plugins-kishibashi3
/plugin install agent-hub-plugin
```

各プラグインの詳細はそれぞれのディレクトリの README を参照。

## ライセンス

Apache 2.0 — see [LICENSE](LICENSE).
