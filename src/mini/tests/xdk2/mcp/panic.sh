#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.mcp
import xdk.mcp
import xdk.codec
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    if name == "parseVersion" {
        McpProtocolVersion value = parseMcpProtocolVersion(null)
    } else if name == "resourceUri" {
        McpResource value = new McpResource("", "x")
    } else if name == "resourceSize" {
        McpResource value = new McpResource("file:///a", "a", "", "", "", -1 as Long)
    } else if name == "contentImage" {
        McpContent value = McpContent.image("", "image/png")
    } else if name == "contentAudio" {
        McpContent value = McpContent.audio("x", "")
    } else if name == "contentBlob" {
        McpResource resource = new McpResource("file:///a", "a", "", "", "text/plain", null)
        McpContent value = McpContent.embeddedBlob(resource, "")
    } else if name == "promptName" {
        List<String> names = []
        Map<String, String> descriptions = [:]
        Set<String> required = []
        List<String> roles = []
        List<McpContent> messages = []
        McpPrompt value = new McpPrompt("", "", "", names, descriptions, required, roles, messages)
    } else if name == "promptRole" {
        List<String> names = []
        Map<String, String> descriptions = [:]
        Set<String> required = []
        List<String> roles = ["system"]
        List<McpContent> messages = [McpContent.text("x")]
        McpPrompt value = new McpPrompt("p", "", "", names, descriptions, required, roles, messages)
    } else if name == "toolName" {
        JsonValue schema = Json.object()
        McpTool value = new McpTool("bad name", schema)
    } else if name == "toolSchema" {
        McpTool value = new McpTool("ok", null)
    } else if name == "toolResult" {
        McpToolResult value = new McpToolResult(null)
    } else if name == "sessionModern" {
        McpServerInfo server = new McpServerInfo("s", "1")
        McpClientInfo client = new McpClientInfo("c", "1")
        McpSession value = new McpSession(McpProtocolVersion.V2025_11_25, server, client, "", true, true, true)
    } else if name == "serverName" {
        McpServerInfo value = new McpServerInfo("", "1")
    } else if name == "serverCap" {
        Set<McpCapability> caps = Set.of(McpCapability.Sampling)
        List<McpProtocolVersion> versions = []
        versions.push(McpProtocolVersion.V2026_07_28)
        McpServerInfo value = new McpServerInfo("s", "", "1", "", "", caps, versions, "")
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "mcp panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "mcp panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic parseVersion "parseMcpProtocolVersion: null"
check_panic resourceUri "McpResource: invalid uri"
check_panic resourceSize "McpResource: negative size"
check_panic contentImage "McpContent.image: empty data"
check_panic contentAudio "McpContent.audio: empty mimeType"
check_panic contentBlob "McpContent.embeddedBlob: empty blob"
check_panic promptName "McpPrompt: empty name"
check_panic promptRole "McpPrompt: invalid role"
check_panic toolName "McpTool: invalid name"
check_panic toolSchema "McpTool: inputSchema must be object"
check_panic toolResult "McpToolResult: null contents"
check_panic sessionModern "McpSession: modern flag mismatch"
check_panic serverName "McpServerInfo: empty name"
check_panic serverCap "McpServerInfo: client capability not allowed"
echo "mcp_panic: PASS"
