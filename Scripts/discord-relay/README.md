# RUXP Discord relay

The one server-side piece of the Discord integration. The iPhone posts a `CommunityMoment`
here; the Worker holds the Discord credentials, formats one embed, adds a `JOIN WORKOUT` link
button, and posts it. The app never holds a token or webhook URL.

```
RUXP (phone) ──POST /moment──► Worker ──► Discord channel
                                   │            │
                                   └─ KV dedup  └─ [JOIN WORKOUT] → https://ruxp.app/join/<eventID>
```

## Deploy

1. `npm i -g wrangler && wrangler login`
2. `wrangler kv namespace create MOMENTS` and paste the id into `wrangler.toml`.
3. Credentials, one of:
   - Bot (per-event channels): create an application at discord.com/developers, add a bot,
     invite it to the server with `Send Messages` + `Embed Links` in the event channels, then
     `wrangler secret put DISCORD_BOT_TOKEN`.
   - Webhook (one channel): Server Settings › Integrations › Webhooks › New, copy the URL,
     `wrangler secret put DISCORD_WEBHOOK_URL`.
   With both set, a moment that names a `channelID` goes through the bot; the rest through the webhook.
4. `wrangler deploy`. Note the URL, e.g. `https://ruxp-discord-relay.<you>.workers.dev`.
5. Put it in `docs/community.json` as `relayURL`, with the channel ids the app should show.
   The app fetches the directory hourly on foreground and validates it before use.

## Test without a phone

```bash
curl -X POST "$RELAY/moment" -H 'content-type: application/json' -d '{
  "id":"volumeMilestone:fridayNight-2026-09-18:250000","kind":"volumeMilestone",
  "at":"2026-09-18T19:12:00Z","audience":"event","eventID":"fridayNight-2026-09-18",
  "eventTitle":"FRIDAY NIGHT","channelID":"123456789012345678",
  "totalLB":250000,"targetLB":1000000,"lifters":41,
  "joinURL":"https://ruxp.app/join/fridayNight-2026-09-18"}'
```

`wrangler dev` serves it locally; point `relayURL` at the tunnel URL from a `-RUXPCommunity`
file to test the phone end to end.

## Policy the app enforces before anything reaches here

- Sets are never moments. Nothing about body weight, heart rate, or health data has a field.
- Player moments (join, PR, level-up, session complete) leave the phone only when
  "Share my moments to Discord" is on. They carry the Game Center alias, nothing else.
- Aggregate moments (lifter and volume milestones) carry no identity. Every phone that observes
  the board may post them; the KV key on `moment.id` makes Discord see each once.
- `sessionLive` and `eventComplete` are reserved for the Worker's own schedule (`scheduled`),
  which nobody's phone has to be awake for. Not implemented yet.

## Known limits, and what replaces them

- Posts are unauthenticated beyond shape checks and a per-IP rate limit. Someone with the URL
  can post a fake milestone. The fix is a Game Center identity signature
  (`GKLocalPlayer.fetchItems(forIdentityVerificationSignature:)`) verified here against Apple's
  public key; the moment schema already carries what it would sign.
- Link buttons require https, so `joinURL` is a Universal Link. Until `ruxp.app` serves the
  association file, the link lands on the site's bridge page, which offers `ruxp://join/...`.
