# Phone control (Mac)

A real Android phone, live in a page of unrealagency.ai/members ("Phone control" tab).

How it works: phone (USB) → this Mac (reader, port 8100) → Cloudflare tunnel → phone.unrealagency.ai → members page.
Access = a signed 12-hour pass from the site (Supabase function `phone-pass`), re-checked every minute by `phone-gate`.

Install on the Mac: double-click `install.command`. Check later: `bash install.command status`.
Logs: ~/UnrealPhone/logs/. Test without a phone: `node test/fake-phone.mjs 28100` then `FAKE_DEVICE_PORT=28100 node server.mjs`.
