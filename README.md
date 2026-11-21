# Aisma MCP server and API

<img src="assets/aisma-logo-400.png" alt="Aisma logo" width="96" height="96" align="right">

Edit a video you already shot by describing the change in plain words, from any AI assistant, agent or script.
Remove a person or an object, change an outfit, the background or a product, swap a face from your photos,
restyle the clip or add an effect. Aisma keeps the original framing and audio and delivers a private 720p
or 1080p result to your Aisma Library.

- **MCP server (remote, Streamable HTTP):** `https://api.aisma.ai/mcp`
- **ChatGPT plugin:** [Aisma in ChatGPT](https://chatgpt.com/plugins/plugin_asdk_app_6af464388c4881919dab901a9adfd4d9)
- **REST API:** `https://api.aisma.ai/v1` ([OpenAPI 3.1](https://api.aisma.ai/v1/openapi.json))
- **Developer docs:** https://aisma.ai/developers
- **MCP Registry name:** `ai.aisma/aisma`

This repository holds documentation, the registry `server.json` and small client examples. The server
itself is hosted by Aisma; there is nothing to install or run.

## What you need

- An Aisma account signed in with Google, Apple or email. Guest profiles can't connect apps or hold keys.
- Edits use the connected account's Aisma credits. Confirm each edit's credit cost before it starts.
  Account and credit information is on the [pricing page](https://aisma.ai/pricing).
- A clip of 2–60 seconds (MP4 or MOV, up to 500 MB), or a finished video from your Aisma Library.
  Optionally up to 10 reference photos (JPEG, PNG or WebP).

## Use Aisma in ChatGPT

When you start a ChatGPT prompt with “Aisma”, ChatGPT will automatically surface the plugin in your chat and
use relevant context to accomplish the task. The first time you use the plugin, ChatGPT will prompt you to
connect so you know what data may be shared. Sign in to Aisma with Google, Apple or email and approve the
connection. Then attach a video and any reference photos in the chat and describe the change. You can also
choose a finished video from your Aisma Library. Find it in ChatGPT's plugin directory:
[Aisma in ChatGPT](https://chatgpt.com/plugins/plugin_asdk_app_6af464388c4881919dab901a9adfd4d9).

Available in all markets where plugins in ChatGPT are available.

Ask ChatGPT to open the Aisma edit card. In clients that support inline cards, `show_edit` opens three
real Before/After examples: an outfit change, a new background and object removal. **Use on my video**
sends the idea back to the chat so you can attach your own video and reference photos; it does not import
the demonstration or start an edit.

The Aisma plugin copies attached files with `import_chat_media`, then checks their asset ids with
`get_asset`. A new user's first edit goes through a preparation question round before it can start.
The assistant calls `start_preview` and presents its useful questions in the chat or edit card. A question
round already completed on aisma.ai also satisfies this first-use requirement.

`get_preview` reads the preparation and `answer_preview` saves your choices. Once the offer is ready,
confirm the edit before `start_prepared_edit` starts it with those answers. For an account that has
already edited or completed a question round, `preview_unavailable` permits the ordinary `quote_edit` → confirmation → `start_edit` path. A temporary
`unavailable` response means try later; a content refusal is shown without switching to that path.

If a first start returns `preview_required` but preparation returns `preview_unavailable`, the assistant
explains that preparation is unavailable and points you to [Aisma](https://aisma.ai/app/) to continue.
It must not keep switching between preview and ordinary start attempts.

The card can show the same account-owned preparation, with its questions and saved choices, and lets
you finish the question round and explicitly confirm the edit. A changed offer needs another explicit
confirmation; refreshing the card never starts an edit. Once started, the card shows progress and a private result player,
with **Open in Aisma** for the full task page. Opening a card does not repeat preparation or start another job.

Follow the task's `webUrl` in Aisma, or ask ChatGPT to check `get_job` and provide `get_result_link` once
the result is ready. Available timing is approximate; a finished result is confirmed by `resultReady`.
If your client cannot display the card, continue with the same tools and answers in the chat or open the
task in Aisma.

The published plugin uses `https://api.aisma.ai/mcp/catalog`. Custom connections to `/mcp` use the standard
MCP workflow below.

## Connect another AI assistant (MCP)

Your client opens Aisma's sign-in page on first use: OAuth 2.1 with PKCE and dynamic client registration,
so there is no client ID to copy. On the consent screen you choose what the connection may do and can
set an optional monthly credit limit. You can change limits or disconnect at any time in Aisma under
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

**Claude.ai and Claude Desktop:** Settings → Connectors → **Add custom connector** → `https://api.aisma.ai/mcp`.

**Other clients:** any client that supports remote MCP servers over Streamable HTTP works. The server is
stateless and answers protocol revisions 2025-11-25, 2025-06-18 and 2025-03-26. An unauthenticated request
gets `401` with `WWW-Authenticate: Bearer resource_metadata=…`, which is how clients discover the sign-in.

### Uploading through standard MCP

Standard MCP's `create_upload` returns a one-time HTTPS link and the client uploads the file itself with
an HTTP `PUT`. This works in assistants that can read your files and run commands, including Claude Code,
Cursor, VS Code and other coding agents. Clients without that capability can use finished videos from
your Aisma Library (`list_library` → `use_library_video`). Chat attachments use the Aisma plugin's
`import_chat_media` flow described above.

## Standard MCP tools

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

### Plugin-only MCP tools

The Aisma plugin in ChatGPT shares the standard tools except `create_upload` and adds these tools for attachments,
preparation and an optional inline card. The standard `/mcp` endpoint and REST API use the upload → quote →
confirmed start flow. They do not provide interactive preparation questions or catalog previews; Aisma uses its evidence-based
choices for those ordinary edits.

| Tool | What it does | Spends credits |
|---|---|---|
| `show_edit` | Opens the starter card (`kind: start`), or the connected account's existing preparation or task (`kind: preview` or `job`, with its id); does not start an edit | No |
| `import_chat_media` | Copies the video and photos attached in this chat into your private Aisma account | No |
| `start_preview` | Prepares an eligible edit and its questions; reuse the same input on retries and supply a new `requestId` for an intentionally new preparation with identical input | No |
| `get_preview` | Reads the preparation, its questions and the offer | No |
| `answer_preview` | Saves your choices for the current question round | No |
| `start_prepared_edit` | Starts the prepared edit with its saved answers after you confirm it | Yes, after you confirm |

### Try it

- In ChatGPT, attach a clip and say, “Aisma, change the background to a snowy pine forest. Keep the person and the camera movement.”
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
