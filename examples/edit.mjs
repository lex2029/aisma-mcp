#!/usr/bin/env node
// Edit a clip with the Aisma REST API: upload, price, confirm, start, wait, download.
//
// Usage (Node.js 20 or newer):
//   export AISMA_API_KEY=aisma_live_...
//   node edit.mjs clip.mp4 "change the background to a snowy forest" [720p|1080p]
//
// Nothing is charged until you answer "y" to the price question.
import { createWriteStream, openAsBlob, statSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { setTimeout as sleep } from 'node:timers/promises';

const API = 'https://api.aisma.ai/v1';
const USER_AGENT = 'aisma-example-node/1.0'; // use your own app name
const headers = { Authorization: `Bearer ${process.env.AISMA_API_KEY}`, 'User-Agent': USER_AGENT };

async function call(method, path, body, extra = {}) {
  const response = await fetch(API + path, {
    method,
    headers: { ...headers, ...(body ? { 'Content-Type': 'application/json' } : {}), ...extra },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = data.error ?? {};
    throw new Error(`${method} ${path} failed (${response.status}) ${error.code}: ${error.message} [request ${response.headers.get('x-request-id')}]`);
  }
  return { status: response.status, data };
}

const [path, brief, quality = '720p'] = process.argv.slice(2);
if (!path || !brief) {
  console.error('Usage: node edit.mjs clip.mp4 "what to change" [720p|1080p]');
  process.exit(1);
}
const contentType = path.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';

// 1. Ask for a one-time upload link, then PUT the file there with the headers it names.
const { data: upload } = await call('POST', '/uploads', { kind: 'video', contentType, bytes: statSync(path).size });
const put = await fetch(upload.uploadUrl, {
  method: 'PUT',
  headers: { 'Content-Type': contentType, 'User-Agent': USER_AGENT, ...upload.headers },
  body: await openAsBlob(path),
});
if (!put.ok) throw new Error(`Upload failed (${put.status})`);

// 2. Wait until Aisma has checked the clip.
for (;;) {
  const { data: asset } = await call('GET', `/assets/${upload.assetId}`);
  if (asset.status === 'ready') break;
  if (asset.status === 'failed' || asset.status === 'expired') throw new Error(`Upload ${asset.status}: ${asset.error}`);
  await sleep(3000);
}

// 3. Price the edit. Nothing is charged; a 202 means "ask again after retryAfterMs".
let quote;
for (;;) {
  const response = await call('POST', '/quotes', { sourceId: upload.assetId, brief, quality });
  if (response.status !== 202) { quote = response.data; break; }
  await sleep(response.data.retryAfterMs);
}

const prompt = createInterface({ input: process.stdin, output: process.stdout });
const answer = await prompt.question(`Start this edit for ${quote.credits} credits? [y/N] `);
prompt.close();
if (answer.trim().toLowerCase() !== 'y') {
  console.log('Not started. Nothing was charged.');
  process.exit(0);
}

// 4. Start it. The Idempotency-Key makes a retry return the same edit.
const { data: job } = await call('POST', '/jobs', { quoteId: quote.id }, { 'Idempotency-Key': `edit-${quote.id}` });
console.log(`Started edit ${job.jobId}`);

// 5. Follow it (no more often than every 10 seconds), then fetch the one-hour link.
for (;;) {
  const { data: status } = await call('GET', `/jobs/${job.jobId}`);
  console.log(`  ${status.stage} ${status.progress}%`);
  if (status.resultReady) break;
  if (status.status === 'failed') throw new Error(`The edit failed: ${JSON.stringify(status.issues)}`);
  await sleep(10_000);
}

const { data: link } = await call('POST', `/jobs/${job.jobId}/result`);
const out = path.replace(/\.[^.]+$/, '') + '-edited.mp4';
const download = await fetch(link.url, { headers: { 'User-Agent': USER_AGENT } });
if (!download.ok) throw new Error(`Download failed (${download.status})`);
await pipeline(Readable.fromWeb(download.body), createWriteStream(out));
console.log(`Saved ${out}. The edit is also in your Aisma Library.`);
