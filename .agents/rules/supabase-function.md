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

## 3. Deploying via Supabase MCP Server (MANDATORY)
When deploying a function, you strictly MUST use the `mcp_supabase-mcp-server_*` tools provided by the Supabase MCP Server. DO NOT use `npx supabase functions deploy` from the terminal, as local CLI environments might lack the correct authentication tokens.

- To deploy an edge function, call the `mcp_supabase-mcp-server_deploy_edge_function` tool.
- Provide the `project_id` (use `mcp_supabase-mcp-server_list_projects` to find the correct active ref if unsure).
- Set `verify_jwt` to `false` if it is a public webhook or cron script; otherwise, omit or set to `true`.
- Always rely on the MCP tools for any Supabase interactions (e.g., executing SQL, querying schemas, reading logs) rather than using terminal commands.
