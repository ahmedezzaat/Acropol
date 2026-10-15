// Exercises POST /api/webhooks/whatsapp with WAHA-style payloads.
//
//   BASE_URL=http://localhost:3000 \
//   WAHA_WEBHOOK_HMAC_KEY=<same key as the server> \
//   WAHA_WEBHOOK_SECRET=<same secret as the server, if you use one> \
//   node scripts/test-waha-webhook.mjs
//
// The "created" cases make REAL leads in the database the server is connected
// to (notes start with "First message: [waha-test ...]" so they are easy to find
// and delete). Use a development / staging project.
import { createHmac, randomInt } from "node:crypto";

const BASE_URL = process.env.BASE_URL || "http://localhost:3000";
const URL_ = `${BASE_URL}/api/webhooks/whatsapp`;
const KEY = process.env.WAHA_WEBHOOK_HMAC_KEY || "";
const SECRET = process.env.WAHA_WEBHOOK_SECRET || "";
const tag = `[waha-test ${Date.now()}]`;

// A random Egyptian mobile number so repeated runs never collide with real leads.
const randomPhone = () => `2010${randomInt(10_000_000, 99_999_999)}`;
const person = randomPhone();
const lidPerson = randomPhone();

const message = (over = {}, payload = {}) => ({
  id: "evt_test",
  timestamp: Date.now(),
  event: "message",
  session: "default",
  me: { id: "201000000000@c.us", pushName: "My Business" },
  payload: {
    id: `false_${person}@c.us_3EB0TEST`,
    timestamp: Math.floor(Date.now() / 1000),
    from: `${person}@c.us`,
    fromMe: false,
    body: `${tag} Hi, do you have solar water heaters?`,
    hasMedia: false,
    _data: { notifyName: "Ahmed Ali" },
    ...payload,
  },
  engine: "NOWEB",
  ...over,
});

async function post(name, body, expected, { sign = true, hmac, raw } = {}) {
  const rawBody = raw ?? JSON.stringify(body);
  const headers = { "content-type": "application/json" };
  if (sign && KEY) {
    headers["x-webhook-hmac"] = hmac ?? createHmac("sha512", KEY).update(rawBody).digest("hex");
    headers["x-webhook-hmac-algorithm"] = "sha512";
  }
  if (sign && SECRET) headers["x-webhook-secret"] = SECRET;
  const res = await fetch(URL_, { method: "POST", headers, body: rawBody });
  let json = null;
  try { json = await res.json(); } catch { /* not JSON */ }
  const got = res.status >= 400 ? `HTTP ${res.status}` : `${json?.action}`;
  const ok = expected.split("|").includes(got);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(34)} expected ${expected.padEnd(9)} got ${got}${json?.reason ? ` (${json.reason})` : ""}`);
  return ok;
}

const results = [];
results.push(await post("normal person (new)", message(), "created"));
results.push(await post("same person again (duplicate)", message({}, { body: `${tag} second message` }), "duplicate"));
results.push(await post("group chat", message({}, { from: "120363000000000000@g.us" }), "ignored"));
results.push(await post("status broadcast", message({}, { from: "status@broadcast" }), "ignored"));
results.push(await post("fromMe", message({}, { fromMe: true }), "ignored"));
results.push(await post("@lid without a number", message({}, { from: "98765432101234@lid" }), "ignored"));
results.push(
  await post(
    "@lid with senderPn (new)",
    message({}, { from: "98765432101234@lid", _data: { notifyName: "Lid Person", key: { senderPn: `${lidPerson}@s.whatsapp.net` } } }),
    "created",
  ),
);
results.push(await post("media only (duplicate phone ok)", message({}, { body: "", hasMedia: true }), "duplicate"));
results.push(await post("media only, new person", message({}, { from: `${randomPhone()}@c.us`, body: "", hasMedia: true, _data: {} }), "created"));
// Two messages from a new person at the same instant must create exactly one lead.
{
  const body = message({}, { from: `${randomPhone()}@c.us`, _data: { notifyName: "Race Test" } });
  const sent = await Promise.all([post("simultaneous #1", body, "created|duplicate"), post("simultaneous #2", body, "created|duplicate")]);
  results.push(...sent);
}
results.push(await post("other event (message.ack)", message({ event: "message.ack" }), "ignored"));
results.push(await post("session.status", message({ event: "session.status" }, {}), "ignored"));
results.push(await post("not JSON", null, "HTTP 400", { raw: "this is not json" }));
if (KEY || SECRET) {
  results.push(await post("wrong HMAC", message(), "HTTP 401", { hmac: "00".repeat(64) }));
  results.push(await post("no auth headers", message(), "HTTP 401", { sign: false }));
} else {
  console.log("SKIP  wrong HMAC / no auth: set WAHA_WEBHOOK_HMAC_KEY (and restart the server) to test authentication");
}

const failed = results.filter((r) => !r).length;
console.log(`\n${results.length - failed}/${results.length} passed. Test leads carry the text ${tag}`);
process.exit(failed ? 1 : 0);
