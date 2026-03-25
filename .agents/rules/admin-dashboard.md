---
description: Architectural and Style Guidelines for the Web Administrator Dashboard
---

# Admin Dashboard Development Principles

When developing new features or components within the `admin_dashboard/` directory, you MUST adhere to the following technological constraints and architectural designs.

## 1. Technology Stack
- **Framework:** React 18, Vite, TypeScript
- **Styling:** Tailwind CSS (v4)
- **Icons:** `lucide-react` (Do NOT use `react-icons` or other icon libraries)
- **Routing:** `react-router-dom` (Version 6+)
- **Backend/Platform:** Supabase Client (`@supabase/supabase-js`)

## 2. Styling Guidelines
- **Dashboard Theme:** The dashboard uses a modern, clean, predominantly dark or sleek aesthetic similar to the main Sports App glassmorphism theme, although it favors structured tables and metric cards.
- **Tailwind v4:** Note that Tailwind CSS v4 is used; avoid any deprecated classes. Always use standard Tailwind utility classes instead of creating custom CSS files unless absolute necessary.
- **Responsive Design:** Every view must strictly be responsive (mobile, tablet, desktop) using standard `md:`, `lg:` prefixes.

## 3. Data Flow & Security (Supabase)
- **Authentication:** All pages except login are sealed behind an Auth verification layer. Attempting to access dashboard content without a valid Supabase session should redirect to the `/login` route.
- **RLS & RPCs:** The React app operates as an authenticated user on the browser. Therefore, it is subjected to the same Row Level Security (RLS) rules as the mobile app. Do not attempt to bypass RLS with direct `update` queries on protected tables (like user balances). Instead, always invoke pre-defined Postgres functions using `supabase.rpc('function_name')` that carry `SECURITY DEFINER` privileges.
- **Realtime / Presence:** Utilize Supabase realtime appropriately. Always ensure you unsubscribe from channels when the React component unmounts (`useEffect` cleanup) to prevent memory leaks and zombie connections.

## 4. Pre-Push Requirements
As mandated by the global `pre-push.md` rules, any modification within this directory triggers an explicit requirement to run `npm run lint` and `npm run build` locally within the `admin_dashboard/` folder before attempting any git commits.
