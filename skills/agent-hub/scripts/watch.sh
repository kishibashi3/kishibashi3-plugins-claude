#!/usr/bin/env bash
# agent-hub-watch: 自分宛て未読メッセージの SSE push を待機する常駐スクリプト
#
# 使い方:
#   # PAT モード（推奨。GitHub PAT で認証、ハンドル=GitHub login）
#   GITHUB_PAT=ghp_xxx... bash .claude/skills/agent-hub/scripts/watch.sh
#
#   # PAT モード + ペルソナ override（同じ owner で別ハンドルを名乗る）
#   GITHUB_PAT=ghp_xxx... AGENT_HUB_USER=alice bash .claude/skills/agent-hub/scripts/watch.sh
#
#   # Trust モード（localhost のみ。サーバー側 AUTH_MODE=trust）
#   AGENT_HUB_USER=alice bash .claude/skills/agent-hub/scripts/watch.sh
#
# 認証モードは agent-hub サーバー側の AUTH_MODE に合わせる:
#   - サーバー pat → GITHUB_PAT を設定（推奨）。AGENT_HUB_USER も併設すれば handle override
#   - サーバー trust（localhost 互換）→ AGENT_HUB_USER のみ
#
# 環境変数:
#   GITHUB_PAT       GitHub Personal Access Token（read:user scope）。pat モード用
#   AGENT_HUB_USER   handle 名 (trust モードでは識別、pat モードでは GitHub login を override)
#   AGENT_HUB_URL    MCP エンドポイント。未設定なら http://localhost:3000/mcp

set -u

HUB="${AGENT_HUB_URL:-http://localhost:3000/mcp}"
PAT="${GITHUB_PAT:-}"
HANDLE_OVERRIDE="${AGENT_HUB_USER:-}"

# 認証モード判定 + USER_ID 解決 + curl 用ヘッダ配列を組み立て
AUTH_HEADERS=()
if [ -n "$PAT" ]; then
  # pat モード: GitHub API /user を叩いて login 取得（owner 確認）
  GITHUB_LOGIN=$(curl -s --max-time 10 \
    -H "Authorization: Bearer $PAT" \
    -H "User-Agent: agent-hub-watch" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user 2>/dev/null \
    | grep -oP '"login":\s*"\K[^"]+' | head -1)
  if [ -z "$GITHUB_LOGIN" ]; then
    echo "[ERR $(date +%H:%M:%S)] could not resolve GitHub login from GITHUB_PAT (revoked or invalid?)"
    exit 1
  fi
  AUTH_HEADERS+=(-H "Authorization: Bearer $PAT")
  if [ -n "$HANDLE_OVERRIDE" ]; then
    # PAT で本人認証 + X-User-Id でハンドル override（マルチペルソナ）
    USER_ID="$HANDLE_OVERRIDE"
    AUTH_HEADERS+=(-H "X-User-Id: $USER_ID")
    AUTH_MODE_LABEL="pat+override(owner=$GITHUB_LOGIN)"
  else
    # 素の pat モード: GitHub login をそのままハンドルにする
    USER_ID="$GITHUB_LOGIN"
    AUTH_MODE_LABEL="pat"
  fi
elif [ -n "$HANDLE_OVERRIDE" ]; then
  # trust モード: X-User-Id を無検証で信じる（localhost 専用）
  USER_ID="$HANDLE_OVERRIDE"
  AUTH_HEADERS+=(-H "X-User-Id: $USER_ID")
  AUTH_MODE_LABEL="trust"
else
  echo "[ERR $(date +%H:%M:%S)] Set GITHUB_PAT (pat mode) or AGENT_HUB_USER (trust mode)"
  exit 1
fi

echo "[boot $(date +%H:%M:%S)] mode=$AUTH_MODE_LABEL user=$USER_ID hub=$HUB"

# 初回接続フラグ。初回 init/subscribed は stdout (通知)、reconnect 後は stderr (静音)
FIRST_CONNECT=1

while true; do
  # 1) initialize で sessionId を取り出す
  INIT=$(curl -s -i --max-time 10 -X POST "$HUB" \
    "${AUTH_HEADERS[@]}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"agent-hub-watch","version":"1.0"}},"id":0}' 2>/dev/null)
  SID=$(echo "$INIT" | grep -i "^mcp-session-id:" | awk '{print $2}' | tr -d '\r\n')
  if [ -z "$SID" ]; then
    echo "[ERR $(date +%H:%M:%S)] initialize failed (is agent-hub running at $HUB ?), retry in 5s"
    sleep 5
    continue
  fi
  if [ -n "$FIRST_CONNECT" ]; then
    echo "[init $(date +%H:%M:%S)] sessionId=${SID:0:8}... user=$USER_ID"
  else
    echo "[init $(date +%H:%M:%S)] sessionId=${SID:0:8}... user=$USER_ID" >&2
  fi

  # 2) initialized notification（MCP プロトコル必須）
  curl -s --max-time 5 -X POST "$HUB" \
    "${AUTH_HEADERS[@]}" \
    -H "mcp-session-id: $SID" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null 2>&1

  # 3) resources/subscribe で自分の inbox を購読
  SUB=$(curl -s --max-time 5 -X POST "$HUB" \
    "${AUTH_HEADERS[@]}" \
    -H "mcp-session-id: $SID" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"resources/subscribe\",\"params\":{\"uri\":\"inbox://@$USER_ID\"},\"id\":1}" 2>/dev/null)
  if echo "$SUB" | grep -q '"error"'; then
    echo "[ERR $(date +%H:%M:%S)] subscribe failed: $SUB"
    sleep 5
    continue
  fi
  if [ -n "$FIRST_CONNECT" ]; then
    echo "[subscribed $(date +%H:%M:%S)] inbox://@$USER_ID — waiting for pushes..."
    FIRST_CONNECT=
  else
    echo "[subscribed $(date +%H:%M:%S)] inbox://@$USER_ID — waiting for pushes..." >&2
  fi

  # 4) GET /mcp で long-lived SSE。notifications/resources/updated だけ拾う。
  curl -sN -X GET "$HUB" \
    "${AUTH_HEADERS[@]}" \
    -H "mcp-session-id: $SID" \
    -H "Accept: text/event-stream" 2>/dev/null \
    | grep --line-buffered -E '"method":"notifications/resources/updated"' \
    | while IFS= read -r line; do
        echo "[NEW $(date +%H:%M:%S)] $line"
      done

  # 5) ストリーム切断時は再接続（reconnect ログは stderr で静音化）
  echo "[reconnect $(date +%H:%M:%S)] SSE stream closed, reconnecting in 3s..." >&2
  sleep 3
done
