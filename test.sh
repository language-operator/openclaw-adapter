#!/bin/sh
# Runs inside the container image to verify seed-config.mjs behaviour.
# Exit 0 = all pass, non-zero = failure.
set -e

PASS=0
FAIL=0

assert() {
  local desc="$1"; local cmd="$2"
  if eval "$cmd" > /dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

set_config() {
  mkdir -p /etc/agent
  cat > /etc/agent/config.yaml
}

clear_config() {
  rm -f /etc/agent/config.yaml
}

# ---------------------------------------------------------------------------
# Test 1: full config.yaml mapping
# ---------------------------------------------------------------------------
echo "--- Test 1: full config.yaml mapping ---"

set_config << 'EOF'
agent:
  name: test-agent
personas:
  - name: p
    displayName: Test Persona
    systemPrompt: You are a test agent.
    tone: professional
    description: A test persona.
    instructions:
      - Do the thing
    capabilities:
      - research
    limitations:
      - No speculation
tools:
  my-tool:
    endpoint: http://my-tool.default.svc.cluster.local:8080
    protocol: mcp
models:
  claude-sonnet:
    model: claude-sonnet-4-5
    endpoint: http://claude-sonnet.default.svc.cluster.local:8000
EOF

mkdir -p /tmp/t1/state
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t1/state \
  node /app/seed-config.mjs > /tmp/t1/out.txt 2>&1
clear_config

assert "openclaw.json created"         "[ -f /tmp/t1/state/openclaw.json ]"
assert "models.providers present"       "grep -q 'claude-sonnet' /tmp/t1/state/openclaw.json"
assert "correct baseUrl"               "grep -q 'claude-sonnet.default.svc' /tmp/t1/state/openclaw.json"
assert "api: openai-completions"       "grep -q 'openai-completions' /tmp/t1/state/openclaw.json"
assert "models array with id"          "grep -q 'claude-sonnet-4-5' /tmp/t1/state/openclaw.json"
assert "placeholder apiKey"            "grep -q 'sk-langop-proxy' /tmp/t1/state/openclaw.json"
assert "mcp.servers present"           "grep -q 'my-tool' /tmp/t1/state/openclaw.json"
assert "mcp server url"                "grep -q 'my-tool.default.svc' /tmp/t1/state/openclaw.json"
assert "agent identity name"           "grep -q 'test-agent' /tmp/t1/state/openclaw.json"
assert "AGENTS.md created"             "[ -f /tmp/t1/state/workspace/AGENTS.md ]"
assert "AGENTS.md has systemPrompt"    "grep -q 'You are a test agent' /tmp/t1/state/workspace/AGENTS.md"
assert "AGENTS.md has instructions"    "grep -q 'Do the thing' /tmp/t1/state/workspace/AGENTS.md"
assert "AGENTS.md has capabilities"    "grep -q 'research' /tmp/t1/state/workspace/AGENTS.md"
assert "AGENTS.md has limitations"     "grep -q 'No speculation' /tmp/t1/state/workspace/AGENTS.md"
assert "SOUL.md created"               "[ -f /tmp/t1/state/workspace/SOUL.md ]"
assert "SOUL.md has tone"              "grep -q 'professional' /tmp/t1/state/workspace/SOUL.md"
assert "SOUL.md has description"       "grep -q 'Test Persona' /tmp/t1/state/workspace/SOUL.md"

# ---------------------------------------------------------------------------
# Test 2: skip-if-exists (openclaw.json preserved across restarts)
# ---------------------------------------------------------------------------
echo "--- Test 2: skip-if-exists ---"

set_config << 'EOF'
personas:
  - name: p
    displayName: New Persona
    systemPrompt: New system prompt.
    tone: casual
EOF

mkdir -p /tmp/t2/state/workspace
echo '{"preserved":true}' > /tmp/t2/state/openclaw.json
echo "Old AGENTS" > /tmp/t2/state/workspace/AGENTS.md

AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t2/state \
  node /app/seed-config.mjs > /tmp/t2/out.txt 2>&1
clear_config

assert "openclaw.json not overwritten"  "grep -q 'preserved' /tmp/t2/state/openclaw.json"
assert "AGENTS.md overwritten"          "! grep -q 'Old AGENTS' /tmp/t2/state/workspace/AGENTS.md"

# ---------------------------------------------------------------------------
# Test 3: env var fallback (no config.yaml)
# ---------------------------------------------------------------------------
echo "--- Test 3: env var fallback ---"

mkdir -p /tmp/t3/state

AGENT_NAME=test-agent \
  MODEL_ENDPOINT=http://proxy.default.svc.cluster.local:8000 \
  LLM_MODEL=claude-sonnet-4-5 \
  OPENCLAW_STATE_DIR=/tmp/t3/state \
  node /app/seed-config.mjs > /tmp/t3/out.txt 2>&1

assert "openclaw.json created"          "[ -f /tmp/t3/state/openclaw.json ]"
assert "providers populated from env"   "grep -q 'proxy.default.svc' /tmp/t3/state/openclaw.json"
assert "model name from LLM_MODEL"      "grep -q 'claude-sonnet-4-5' /tmp/t3/state/openclaw.json"
assert "no AGENTS.md (no personas)"     "[ ! -f /tmp/t3/state/workspace/AGENTS.md ]"

# ---------------------------------------------------------------------------
# Test 4: no config.yaml, no env vars → graceful empty config
# ---------------------------------------------------------------------------
echo "--- Test 4: graceful empty (no config, no env vars) ---"

mkdir -p /tmp/t4/state

AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t4/state \
  node /app/seed-config.mjs > /tmp/t4/out.txt 2>&1

assert "openclaw.json still created"    "[ -f /tmp/t4/state/openclaw.json ]"
assert "only identity in config"        "grep -q 'test-agent' /tmp/t4/state/openclaw.json"

# ---------------------------------------------------------------------------
# Test 5: external MCP server with headers (language-operator#922)
# ---------------------------------------------------------------------------
echo "--- Test 5: external MCP server headers ---"

set_config << 'EOF'
tools:
  control-plane:
    endpoint: https://cloud.example.com/mcp
    protocol: mcp
    headers:
      Authorization: Bearer $(CONTROL_PLANE_TOKEN)
  partial:
    endpoint: https://other.example.com/mcp
    protocol: mcp
    headers:
      Authorization: Bearer $(CONTROL_PLANE_TOKEN)
      X-Optional: $(MISSING_TOKEN)
  in-cluster:
    endpoint: http://tool.default.svc.cluster.local:8080/mcp
    protocol: mcp
EOF

mkdir -p /tmp/t5/state
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t5/state CONTROL_PLANE_TOKEN=s3cret-value \
  node /app/seed-config.mjs > /tmp/t5/out.txt 2>&1
clear_config

assert "header written as \${NAME} reference"  "grep -q 'Bearer \${CONTROL_PLANE_TOKEN}' /tmp/t5/state/openclaw.json"
assert "token value never written"            "! grep -q 's3cret-value' /tmp/t5/state/openclaw.json"
assert "operator syntax translated"           "! grep -q '\$(CONTROL_PLANE_TOKEN)' /tmp/t5/state/openclaw.json"
assert "streamable-http transport set"        "grep -q 'streamable-http' /tmp/t5/state/openclaw.json"
assert "server with unset header not configured" "! grep -q 'other.example.com' /tmp/t5/state/openclaw.json"
assert "unset header warned"                  "grep -q 'partial.*X-Optional.*MISSING_TOKEN' /tmp/t5/out.txt"
assert "in-cluster tool has no headers"       "node -e 'const c=require(\"/tmp/t5/state/openclaw.json\"); process.exit(c.mcp.servers[\"in-cluster\"].headers ? 1 : 0)'"


# ---------------------------------------------------------------------------
# Test 6: model change between boots (operator providers re-applied)
# ---------------------------------------------------------------------------
echo "--- Test 6: model change between boots ---"

set_config << 'EOF2'
models:
  gpt:
    model: gpt-4o
    endpoint: http://gpt.default.svc.cluster.local:8000
EOF2

mkdir -p /tmp/t6/state
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t6/state \
  node /app/seed-config.mjs > /tmp/t6/out1.txt 2>&1

# Runtime state written between boots: a user-added provider, a primary model
# on the operator's provider, and an unrelated user key.
node -e '
const f = "/tmp/t6/state/openclaw.json"
const c = require(f)
c.models.providers.mine = { baseUrl: "http://mine", apiKey: "user-key", api: "openai-completions", models: [{ id: "m", name: "m" }] }
c.agents.defaults = { model: { primary: "gpt/gpt-4o" } }
c.preserved = true
require("fs").writeFileSync(f, JSON.stringify(c))
'

set_config << 'EOF2'
models:
  claude-sonnet:
    model: claude-sonnet-4-5
    endpoint: http://claude-sonnet.default.svc.cluster.local:8000
EOF2

AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t6/state \
  node /app/seed-config.mjs > /tmp/t6/out2.txt 2>&1

j() { node -e "const c=require('/tmp/t6/state/openclaw.json'); process.exit(($1) ? 0 : 1)"; }
assert "new provider applied"          "j 'c.models.providers[\"claude-sonnet\"].models[0].id === \"claude-sonnet-4-5\"'"
assert "old operator provider removed" "j '!c.models.providers.gpt'"
assert "user provider kept"            "j 'c.models.providers.mine.apiKey === \"user-key\"'"
assert "stale primary cleared"         "j '!c.agents.defaults.model.primary'"
assert "user state preserved"          "j 'c.preserved === true'"
assert "providers update logged"       "grep -q 'Updated models.providers' /tmp/t6/out2.txt"

# A primary on a user-added provider survives a re-seed.
node -e '
const f = "/tmp/t6/state/openclaw.json"
const c = require(f)
c.agents.defaults.model.primary = "mine/m"
require("fs").writeFileSync(f, JSON.stringify(c))
'
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t6/state \
  node /app/seed-config.mjs > /tmp/t6/out3.txt 2>&1
clear_config

assert "user primary kept"             "j 'c.agents.defaults.model.primary === \"mine/m\"'"

# ---------------------------------------------------------------------------
# Test 7: gateway key from MODEL_API_KEY (written as a reference, never the value)
# ---------------------------------------------------------------------------
echo "--- Test 7: gateway key from MODEL_API_KEY ---"

set_config << 'EOF2'
models:
  claude-sonnet:
    model: claude-sonnet-4-5
    endpoint: http://claude-sonnet.default.svc.cluster.local:8000
EOF2

mkdir -p /tmp/t7/state
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t7/state MODEL_API_KEY=sk-langop-abc.s3cretsig \
  node /app/seed-config.mjs > /tmp/t7/out1.txt 2>&1

k() { node -e "const c=require('$1'); process.exit(($2) ? 0 : 1)"; }
assert "apiKey is the \${MODEL_API_KEY} reference" "k /tmp/t7/state/openclaw.json 'c.models.providers[\"claude-sonnet\"].apiKey === \"\${MODEL_API_KEY}\"'"
assert "key value never written"            "! grep -q 's3cretsig' /tmp/t7/state/openclaw.json"
assert "key value never logged"             "! grep -q 's3cretsig' /tmp/t7/out1.txt"
assert "placeholder not used"               "! grep -q 'sk-langop-proxy' /tmp/t7/state/openclaw.json"

# Upgrade: seeded with the placeholder by an older operator, re-seeded with a key.
mkdir -p /tmp/t7/upgrade
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t7/upgrade \
  node /app/seed-config.mjs > /tmp/t7/out2.txt 2>&1
node -e '
const f = "/tmp/t7/upgrade/openclaw.json"
const c = require(f)
c.models.providers.mine = { baseUrl: "http://mine", apiKey: "user-key", api: "openai-completions", models: [{ id: "m", name: "m" }] }
require("fs").writeFileSync(f, JSON.stringify(c))
'
AGENT_NAME=test-agent OPENCLAW_STATE_DIR=/tmp/t7/upgrade MODEL_API_KEY=sk-langop-abc.s3cretsig \
  node /app/seed-config.mjs > /tmp/t7/out3.txt 2>&1
clear_config

assert "upgrade: provider switched to the reference" "k /tmp/t7/upgrade/openclaw.json 'c.models.providers[\"claude-sonnet\"].apiKey === \"\${MODEL_API_KEY}\"'"
assert "upgrade: no placeholder provider left"       "! grep -q 'sk-langop-proxy' /tmp/t7/upgrade/openclaw.json"
assert "upgrade: user provider kept"                 "k /tmp/t7/upgrade/openclaw.json 'c.models.providers.mine.apiKey === \"user-key\"'"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
