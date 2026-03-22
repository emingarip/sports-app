---
description: Guidelines for Supabase Edge Functions development
---

# Supabase Edge Function Workflow

When asked to create, debug, or deploy a Supabase Edge Function, you MUST follow these guidelines:

## 1. Local Development via Deno
- Supabase Edge Functions run on Deno. Use TypeScript (`.ts`).
- Ensure your `index.ts` properly imports `@supabase/supabase-js` or other dependencies using HTTP URLs or Import Maps as standardized by Supabase.
- If making external API calls (e.g., to fetch live sports data), include robust error handling and timeout fallbacks.

## 2. Local Testing First
Before deploying a new or updated function to the production Supabase project, test it locally to verify logic and catch syntax errors.

```bash
npx supabase functions serve <function_name> --env-file supabase/.env.local
```
*(Do NOT auto-serve if running this block blocks the terminal. Use your judgement or run via `curl` against local invoke if needed).*

## 3. Deploying
When deploying a function, you strictly must decide if the function requires JWT verification (e.g., called by an internal app logic where user is authenticated) or if it handles incoming public webhooks/cron jobs.

- If it's a webhook or cron, disable JWT:
```bash
npx supabase functions deploy <function-name> --no-verify-jwt --project-ref <your-project-id>
```
- If it's securely called from the app, omit `--no-verify-jwt`.
