// RUXP Discord relay. A Cloudflare Worker that turns a `CommunityMoment` from the app into one
// Discord message. It is the only place a Discord token or webhook URL lives.
//
//   POST /moment        JSON body = CommunityMoment (see Shared/RUXP/CommunityMoment.swift)
//   GET  /health        200 "ok"
//
// Secrets (wrangler secret put ...):
//   DISCORD_BOT_TOKEN    posts to the moment's channelID via the bot (preferred: per-event channels)
//   DISCORD_WEBHOOK_URL  fallback when no bot token or no channelID: one webhook, one channel
// Bindings (wrangler.toml):
//   MOMENTS (KV)         idempotency: moment.id → 1, 24 h TTL, so every phone can report the same
//                        milestone and Discord sees it once
//
// What never arrives here: sets, body weight, heart rate, HealthKit data. The app has no field
// for them; the schema check below drops anything unexpected on the floor.

const KINDS = new Set([
  "sessionJoined", "personalRecord", "levelUp", "sessionComplete",
  "lifterMilestone", "volumeMilestone", "sessionLive", "eventComplete",
]);
const ALLOWED_FIELDS = new Set([
  "id", "kind", "at", "audience", "eventID", "eventTitle", "guildID", "channelID", "liftingNow",
  "lifters", "totalLB", "targetLB", "exercise", "weightLB", "reps", "xp", "level", "alias", "joinURL",
]);
const RATE_LIMIT_PER_MINUTE = 30;
const MAX_BODY_BYTES = 4096;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") return new Response("ok");
    if (request.method !== "POST" || url.pathname !== "/moment") return new Response("not found", { status: 404 });

    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    if (env.MOMENTS && !(await allow(env.MOMENTS, ip))) return new Response("slow down", { status: 429 });

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) return new Response("too large", { status: 413 });
    let moment;
    try { moment = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }
    const problem = validate(moment);
    if (problem) return new Response(problem, { status: 400 });
    if (!(moment.audience === "event" || moment.audience === "public")) return new Response("kept", { status: 202 });

    if (env.MOMENTS) {
      const seen = await env.MOMENTS.get(`m:${moment.id}`);
      if (seen) return new Response("duplicate", { status: 200 });
      ctx.waitUntil(env.MOMENTS.put(`m:${moment.id}`, "1", { expirationTtl: 60 * 60 * 24 }));
    }

    const message = render(moment, env);
    const result = await send(message, moment, env);
    return new Response(result.ok ? "posted" : `discord ${result.status}`, { status: result.ok ? 200 : 502 });
  },

  // Optional: `[triggers] crons` in wrangler.toml. Posts "starting soon" / "live now" from the
  // schedule with no phone involved. Left as the seam; the schedule mirrors ScheduledEventService.
  async scheduled(event, env, ctx) {},
};

function validate(m) {
  if (typeof m !== "object" || m === null) return "not an object";
  for (const key of Object.keys(m)) if (!ALLOWED_FIELDS.has(key)) return `unexpected field ${key}`;
  if (typeof m.id !== "string" || m.id.length < 3 || m.id.length > 200) return "bad id";
  if (!KINDS.has(m.kind)) return "bad kind";
  if (m.channelID !== undefined && !/^\d{15,22}$/.test(m.channelID)) return "bad channelID";
  if (m.joinURL !== undefined && !/^https:\/\//.test(m.joinURL)) return "joinURL must be https";
  for (const n of ["liftingNow", "lifters", "reps", "xp", "level"]) {
    if (m[n] !== undefined && !(Number.isInteger(m[n]) && m[n] >= 0 && m[n] < 10_000_000)) return `bad ${n}`;
  }
  for (const n of ["totalLB", "targetLB", "weightLB"]) {
    if (m[n] !== undefined && !(typeof m[n] === "number" && m[n] >= 0 && m[n] < 1e10)) return `bad ${n}`;
  }
  for (const s of ["eventID", "eventTitle", "exercise", "alias"]) {
    if (m[s] !== undefined && (typeof m[s] !== "string" || m[s].length > 80)) return `bad ${s}`;
  }
  return null;
}

const GREEN = 0x5cff7a, MAGENTA = 0xff2daa, LIVE = 0xff3b5c, VIOLET = 0xa78bfa;
const lb = (n) => `${Math.round(n).toLocaleString("en-US")} LB`;
const num = (n) => n.toLocaleString("en-US");

// One embed per kind. Copy follows the app: uppercase eyebrows, short lines, no exclamation marks.
function render(m, env) {
  const title = (m.eventTitle || "RUXP").toUpperCase();
  const who = m.alias ? `**${escape(m.alias)}**` : "A player";
  let embed;
  switch (m.kind) {
    case "personalRecord":
      embed = {
        title: "PR HIT",
        description: `${who}\n${escape(m.exercise || "Lift")}\n**${num(Math.round(m.weightLB || 0))} × ${m.reps ?? "?"}**` + (m.xp ? `\n+${num(m.xp)} XP` : ""),
        color: GREEN,
      };
      break;
    case "levelUp":
      embed = { title: `LEVEL ${m.level}`, description: `${who} leveled up.`, color: MAGENTA };
      break;
    case "sessionJoined":
      embed = {
        title: `${who.replace(/\*/g, "")} joined ${title}`,
        description: m.liftingNow != null ? `${num(m.liftingNow)} lifting now.` : "Lifting now.",
        color: LIVE,
      };
      break;
    case "sessionComplete":
      embed = { title: `${title} COMPLETE`, description: `${who} showed up.` + (m.xp ? `\n+${num(m.xp)} XP` : ""), color: GREEN };
      break;
    case "lifterMilestone":
      embed = { title: `${num(m.lifters || 0)} LIFTERS ACTIVE`, description: `${title} is heating up.`, color: LIVE };
      break;
    case "volumeMilestone":
      embed = {
        title: `${lb(m.totalLB || 0)} MOVED`,
        description: `${title}` + (m.targetLB ? ` · ${Math.round(100 * (m.totalLB || 0) / m.targetLB)}% of ${lb(m.targetLB)} together.` : "."),
        color: VIOLET,
      };
      break;
    case "sessionLive":
      embed = { title: "LIVE NOW", description: `${title}` + (m.lifters != null ? `\n${num(m.lifters)} lifters` : "") + (m.totalLB != null ? `\n${lb(m.totalLB)} moved` : ""), color: LIVE };
      break;
    case "eventComplete":
      embed = { title: "EVENT COMPLETE", description: `${title}` + (m.lifters != null ? `\n${num(m.lifters)} lifters` : "") + (m.totalLB != null ? `\n${lb(m.totalLB)} moved` : ""), color: GREEN };
      break;
  }
  embed.footer = { text: "RUXP" };
  embed.timestamp = m.at || new Date().toISOString();
  const message = { embeds: [embed], allowed_mentions: { parse: [] } };
  if (m.joinURL && m.kind !== "eventComplete") {
    // Link buttons need https. This is why JOIN WORKOUT is a Universal Link, not ruxp://.
    message.components = [{ type: 1, components: [{ type: 2, style: 5, label: "JOIN WORKOUT", url: m.joinURL }] }];
  }
  return message;
}

async function send(message, m, env) {
  if (env.DISCORD_BOT_TOKEN && m.channelID) {
    return fetch(`https://discord.com/api/v10/channels/${m.channelID}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bot ${env.DISCORD_BOT_TOKEN}` },
      body: JSON.stringify(message),
    });
  }
  if (env.DISCORD_WEBHOOK_URL) {
    // A plain webhook may send non-interactive components (link buttons) only with with_components.
    const url = new URL(env.DISCORD_WEBHOOK_URL);
    url.searchParams.set("with_components", "true");
    return fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...message, username: "RUXP" }),
    });
  }
  return { ok: false, status: 503 };
}

async function allow(kv, ip) {
  const key = `r:${ip}:${Math.floor(Date.now() / 60000)}`;
  const n = parseInt((await kv.get(key)) || "0", 10) + 1;
  await kv.put(key, String(n), { expirationTtl: 120 });
  return n <= RATE_LIMIT_PER_MINUTE;
}

function escape(s) {
  return String(s).replace(/[*_~`|>#@]/g, "\\$&");
}
