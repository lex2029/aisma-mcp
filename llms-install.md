# Installing the Aisma MCP server

Aisma is a hosted, remote MCP server. There is nothing to clone, build or run.

- URL: `https://api.aisma.ai/mcp`
- Transport: Streamable HTTP (stateless)
- Authentication: OAuth 2.1 with PKCE and dynamic client registration, or a personal API key sent as
  `Authorization: Bearer aisma_live_…`

## Steps

1. Ask the user for a personal Aisma API key. They create one at https://aisma.ai/app/api-access
   (Profile → Settings & help → Connected apps and keys) in an Aisma account signed in with Google, Apple
   or email. Never print the key back or store it outside the MCP settings file.
2. Add the server to the MCP settings (for Cline, `cline_mcp_settings.json`):

```json
{
  "mcpServers": {
    "aisma": {
      "type": "streamableHttp",
      "url": "https://api.aisma.ai/mcp",
      "headers": { "Authorization": "Bearer aisma_live_..." }
    }
  }
}
```

   If the client supports OAuth for remote MCP servers, the `headers` entry can be left out; the client
   then opens Aisma's sign-in page on first use.
3. Check the connection by calling `get_account`. It returns the credit balance and this key's limits.

## Using it

- New clips are uploaded with `create_upload`: it returns a one-time HTTPS link, and you upload the file
  with an HTTP PUT using the returned headers. Then poll `get_asset` until the status is `ready`.
- `quote_edit` prices the edit; nothing is charged. Show the user the credits and wait for a clear yes
  before calling `start_edit`, which spends credits.
- Follow the edit with `get_job` no more often than every 10 seconds, then call `get_result_link`.
- Clips are 2–60 seconds, MP4 or MOV, up to 500 MB; up to 10 photos (JPEG, PNG or WebP).
