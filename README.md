# Aisma MCP server and API

<img src="assets/aisma-logo-400.png" alt="Aisma logo" width="96" height="96" align="right">

Edit a video you already shot by describing the change in plain words, from any AI assistant, agent or script.
Remove a person or an object, change an outfit, the background or a product, swap a face from your photos,
restyle the clip or add an effect. Aisma keeps the original framing and audio and delivers a private 720p
or 1080p result to your Aisma Library.

- **MCP server (remote, Streamable HTTP):** `https://api.aisma.ai/mcp`
- **REST API:** `https://api.aisma.ai/v1` ([OpenAPI 3.1](https://api.aisma.ai/v1/openapi.json))
- **Developer docs:** https://aisma.ai/developers
- **Official MCP Registry name:** `ai.aisma/aisma`

This repository holds documentation, the registry `server.json` and small client examples. The server
itself is hosted by Aisma; there is nothing to install or run.

## What you need

- An Aisma account signed in with Google, Apple or email. Guest profiles can't connect apps or hold keys.
- Credits in that account. Edits use the same credits as the Aisma app, and the price of each edit is shown
  before it starts. Credits are bought in Aisma, never through the API or MCP. Pricing: https://aisma.ai/pricing
- A clip of 2–60 seconds (MP4 or MOV, up to 500 MB), or a finished video from your Aisma Library.
  Optionally up to 10 reference photos (JPEG, PNG or WebP).

## Connect an AI assistant (MCP)

Your client opens Aisma's sign-in page on first use: OAuth 2.1 with PKCE and dynamic client registration,
so there is no client ID to copy. On the consent screen you choose what the connection may do and its
monthly credit limit. You can change limits or disconnect at any time in Aisma under
**Profile → Settings & help → Connected apps and keys** (https://aisma.ai/app/api-access).

Prefer a key? Create a personal API key on the same page and send it as `Authorization: Bearer aisma_live_…`.
Each key has its own permissions and limits, adjustable per key on that page.

**Claude Code**

```sh
claude mcp add --transport http aisma https://api.aisma.ai/mcp
# or with a personal API key
claude mcp add --transport http aisma https://api.aisma.ai/mcp --header "Authorization: Bearer $AISMA_API_KEY"
```

**Cursor** (`~/.cursor/mcp.json` or `.cursor/mcp.json` in a project)

```json
{
  "mcpServers": {
    "aisma": { "url": "https://api.aisma.ai/mcp" }
  }
}
```

With a key, add `"headers": { "Authorization": "Bearer aisma_live_…" }` next to `url`.

**VS Code** (`.vscode/mcp.json`)

```json
{
  "servers": {
    "aisma": { "type": "http", "url": "https://api.aisma.ai/mcp" }
  }
}
```

**ChatGPT** (custom MCP servers, where your plan and workspace allow them): open
[chatgpt.com/plugins](https://chatgpt.com/plugins), choose **+** → **Add custom MCP server**, enter
`https://api.aisma.ai/mcp`, pick OAuth and sign in to Aisma.

**Claude.ai and Claude Desktop:** Settings → Connectors → **Add custom connector** → `https://api.aisma.ai/mcp`.

**Other clients:** any client that supports remote MCP servers over Streamable HTTP works. The server is
stateless and answers protocol revisions 2025-11-25, 2025-06-18 and 2025-03-26. An unauthenticated request
gets `401` with `WWW-Authenticate: Bearer resource_metadata=…`, which is how clients discover the sign-in.

### Chat-only assistants: an honest limitation

Video files never travel inside MCP messages. `create_upload` returns a one-time HTTPS link and the
assistant uploads the file itself with an HTTP `PUT`. That works in assistants that can read your files and
run commands (Claude Code, Cursor, VS Code and other coding agents). A chat-only assistant (ChatGPT,
Claude.ai) can't upload a new clip this way; there it can re-edit videos that are already finished in your
Aisma Library (`list_library` → `use_library_video`).

## Tools

| Tool | What it does | Spends credits |
|---|---|---|
| `create_upload` | Returns a one-time HTTPS upload link and an asset id for a video or photo; the assistant PUTs the file itself | No |
| `get_asset` | Status of an upload: uploading, checking, ready, failed or expired | No |
| `use_library_video` | Uses one of your finished Aisma videos as the source of a new edit | No |
| `quote_edit` | Prices an edit of a ready source with your instruction and optional photos, at 720p or 1080p; nothing is charged and the quote holds for 15 minutes | No |
| `start_edit` | Starts a quoted edit and reserves its credits; marked destructive, and the assistant confirms with you first | Yes, after you confirm |
| `get_job` | Status and progress of an edit | No |
| `list_library` | Your Aisma Library, newest first, with each edit's status | No |
| `get_result_link` | A private link to the finished video, valid for one hour | No |
| `get_account` | Your credit balance and this connection's monthly limit and usage | No |

Every tool has a title, read-only or destructive hints and an output schema.

### Try it

- "Upload ~/Videos/wedding.mov to Aisma and remove the man in the red jacket behind the couple. Ask me before you start."
- "In product.mp4, swap the clear perfume bottle for the matte-black one in bottle.jpg."
- "Change her gray tracksuit in dance.mp4 to the red suit in photo.png."
- "Take my latest finished Aisma video and turn the corridor into a snowy pine forest at 1080p."
- "Check my Aisma edit and send me the link when it's ready."

## REST API quick start

Send your key as a bearer token and a descriptive `User-Agent` header (for example `my-app/1.0`): some HTTP
libraries' default agents are refused by our edge network. Bodies are JSON, ids are UUIDs.

1. `POST /v1/uploads` returns `uploadUrl`, `method` (`PUT`) and `headers`. PUT the file there with those headers.
2. Poll `GET /v1/assets/{id}` until `status` is `ready`.
3. `POST /v1/quotes` prices the edit. A `202` with `retryAfterMs` means the clip is still being checked; ask again after that delay.
4. `POST /v1/jobs` with an `Idempotency-Key` header starts the quoted edit. A retry with the same key returns the same edit.
5. Poll `GET /v1/jobs/{id}` (no more often than every 10 seconds) or register a webhook, then `POST /v1/jobs/{id}/result` for a one-hour link.

```sh
export AISMA_API_KEY=aisma_live_...
UA="my-app/1.0"

curl -s -X POST https://api.aisma.ai/v1/uploads \
  -H "Authorization: Bearer $AISMA_API_KEY" -H "User-Agent: $UA" -H "Content-Type: application/json" \
  -d '{"kind":"video","contentType":"video/mp4","bytes":12345678}'
# PUT clip.mp4 to uploadUrl with the returned headers, then wait for GET /v1/assets/ASSET_ID → ready

curl -s -X POST https://api.aisma.ai/v1/quotes \
  -H "Authorization: Bearer $AISMA_API_KEY" -H "User-Agent: $UA" -H "Content-Type: application/json" \
  -d '{"sourceId":"ASSET_ID","brief":"change the background to a snowy forest","quality":"720p"}'

curl -s -X POST https://api.aisma.ai/v1/jobs \
  -H "Authorization: Bearer $AISMA_API_KEY" -H "User-Agent: $UA" -H "Content-Type: application/json" \
  -H "Idempotency-Key: first-edit-0001" \
  -d '{"quoteId":"QUOTE_ID"}'

curl -s -X POST https://api.aisma.ai/v1/jobs/JOB_ID/result \
  -H "Authorization: Bearer $AISMA_API_KEY" -H "User-Agent: $UA"
```

Complete scripts that upload, price, ask you to confirm, start and download:

- [`examples/edit.sh`](examples/edit.sh) (curl + jq)
- [`examples/edit.py`](examples/edit.py) (Python 3 + `requests`)
- [`examples/edit.mjs`](examples/edit.mjs) (Node.js 18+ `fetch`)

Errors share one JSON shape, `{"error": {"code", "message"}}`, with readable messages. Webhooks
(`job.completed`, `job.failed`, `job.settled`) are signed per Standard Webhooks. Scopes, limits, webhooks
and the error table are documented at https://aisma.ai/developers.

## Privacy, terms and support

- Uploads and results are private to your account; every media link is signed and short-lived.
- Terms of Use (section 8, API and connected apps): https://aisma.ai/terms
- Privacy Policy: https://aisma.ai/privacy
- Pricing: https://aisma.ai/pricing
- Support: support@aisma.ai · https://aisma.ai/support

Aisma is made by BEINTOUCH PTE. LTD., Singapore.

## License

The examples and documentation in this repository are released under the [MIT License](LICENSE).
The Aisma service itself is governed by the Terms of Use above.
