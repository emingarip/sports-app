# UX Strategy: High-Volume Match Days
**Role**: Senior Product Designer & Mobile UX Strategist
**Product**: Kinetic Scores (Premium Sports App)

---

## 1. UX Strategy Explanation
The fundamental challenge of a sports app on a busy Saturday is the paradox of choice: the user wants to know *everything* is available, but they only *care* about a fraction of it. 

Our strategy revolves around **Progressive Disclosure guided by Relevance**. We will not hide matches, but we will manipulate their visual weight and default state (expanded vs. collapsed) based on the user's implicit preferences (favorites) and explicit global popularity (tier-1 leagues). The experience must feel like walking into a premium sports bar: the biggest games are on the main screens, but you can still find the local matches on the smaller screens in the back if you look for them.

## 2. Proposed Screen Structure (Top to Bottom)
1. **Global Header:** App Title, Search, User Profile. (Sticky Level 1)
2. **Sport Selector:** Football, Basketball, etc. (Horizontal scroll).
3. **Date Selector:** Weekly horizontal calendar. 
4. **Quick Filters Toolbar:** [All] [Live 🔴] [Starred ⭐] [Finished] (Sticky Level 2).
5. **The "Bento" Showcase:** A horizontal carousel of 2-3 massive, visually rich *Featured/Favorite* matches.
6. **Main Feed:** Vertically scrolling list grouped by Leagues.
7. **Bottom Navigation:** Fixed.

## 3. Interaction Model Step-by-Step
1. **The Entry:** User opens the app on a Saturday. The top Bento Showcase immediately hooks them with their favorite team (e.g., Galatasaray) and the biggest global match (e.g., El Clásico).
2. **The Scroll:** As they scroll past the Showcase, the Date Selector and Quick Filters lock to the top of the screen (Sticky). 
3. **The Scan:** They see "Premier League" fully expanded. They continue scrolling. The "Premier League" header sticks to the top, directly under the Quick Filters, providing context.
4. **The Discovery:** They reach "English League Two". It is collapsed by default, displaying just the league logo, name, and a pill saying "12 Matches". If they tap it, it smoothly expands inline.
5. **The Filter:** They only want to see what's happening *right now*. They tap the `[Live 🔴]` quick filter at the top. The feed instantly animates, collapsing all finished/upcoming matches and expanding any league (even lower-tier ones) that currently has a live match.

## 4. Crucial UI Components Needed
*   **Sticky Sub-Header Stack:** A layout mechanism that allows the Date Selector and Quick Filter bar to stack and stick to the top when scrolling.
*   **Bento Hero Card:** The high-fidelity, asymmetric card for the showcase (already in our Design System).
*   **Expandable League Header:** A component featuring a Chevron (`V` / `^`), League Logo, League Name, and a badge denoting match count.
*   **Compact Match Row:** The standard, highly optimized row for displaying a single match within a league. Extremely scan-able.
*   **Floating Anchors (Optional):** A small floating button (FAB) that opens a quick-jump menu to instantly scroll to a specific league.

## 5. Edge Cases: Extremely Busy Days (e.g., 300+ matches)
On a day with 300+ matches (e.g., early rounds of a domestic cup or a heavy weekend), a raw list will cause memory bloat and scroll fatigue.
*   **Solution:** Strict algorithmic collapsing. Only the user's explicitly favorited leagues and the top 3 global leagues are expanded by default. The other 20+ leagues are collapsed. 
*   **Memory Management:** Use Flutter's `SliverList` so off-screen collapsed matches are not rendered, keeping the app performing at 60/120fps regardless of the 300+ node count.

## 6. Final Production-Ready Recommendation
Adopt the **"Tiered Accordion Feed with Sticky Context"**. 

Do not try to invent a complex map or a confusing grid for the main feed. Users expect a vertical list for sports scores. Elevate the vertical list by adding **Smart Default States** (expanding only Tier-1/Favorites) and **Sticky Headers** (so they never forget which league they are looking at mid-scroll). Paired with our "Kinetic Curator" dark-blue/grey/yellow minimal aesthetic, this structure will handle 5 matches or 500 matches with identical elegance and zero cognitive overload.
