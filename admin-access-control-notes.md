# Admin Access Control & RLS Notes

Reference for the Supabase row-level-security (RLS) setup on `admin_users`, `menu_items`, and `categories`, plus how to add new admins.

Last updated: 2026-09-26

---

## 0. Architecture: two separate apps

| App | Tech | Users | Repo |
|---|---|---|---|
| MrPizza mobile | Flutter | **customers and riders only** | this repo |
| MrPizza admin panel | Next.js | owners, branch managers, staff | **separate repo — not in this workspace** |

Consequences:

- The Flutter app never holds an admin or manager role. All admin/manager capability lives behind the Next.js panel.
- The Flutter app's `profiles.role` check constraint (`customer` / `rider`) is therefore **correct as-is** — do not widen it to hold admin roles.
- The RLS policies below are what the Next.js panel relies on. The Flutter app only ever needs the read side of `menu_items` and `categories`.

> **CRITICAL — the Next.js panel must not use the secret key.**
> Supabase's current key naming:
>
> | Current name | Legacy name | Key prefix | Use in |
> |---|---|---|---|
> | **Publishable key** | `anon` | `sb_publishable_...` | Flutter app and Next.js panel |
> | **Secret key** | `service_role` | `sb_secret_...` | trusted server-side only |
>
> The legacy names (`anon`, `service_role`) still resolve, so the Flutter app's `SUPABASE_ANON_KEY` env var is fine as-is. Use the publishable/secret terminology when adding new keys.
>
> The **secret key bypasses RLS entirely**, which would nullify every policy in this document and give the panel unrestricted read/write on all tables. The panel must sign in as a real user and send that user's JWT (publishable key + session). If it ever needs elevated writes, do them through a Supabase Edge Function rather than a secret-key client.
>
> Dashboard location: **Project Settings → API**. The secret key sits behind a "Reveal" button. Never paste it into chat, screenshots, or git — the dashboard has a **rotate** button to invalidate it if it ever leaks.

Because the panel is a separate repo, the SQL in section 2 cannot be verified from this workspace. If the panel reads or writes any of the unlocked tables in section 6, it currently has full access to them by accident, not by design.

---

## 1. How admin status works

Admin status lives in **one place only**: the `admin_users` table.

| Table | Holds | Role values allowed (DB-enforced) |
|---|---|---|
| `admin_users` | Owner / branch manager / staff | `owner`, `branch_manager`, `staff` |
| `profiles` | Customers / riders | `customer`, `rider` |

`admin_users.id` is a foreign key to `auth.users(id)`, so **a person cannot be made an admin until they have a login account.**

### Role capabilities

| Role | Can edit menu + categories | Can create other admins | Notes |
|---|---|---|---|
| `owner` | Yes | **Yes** | Give this to fellow devs |
| `staff` | Yes | No | Menu/catalog editing only |
| `branch_manager` | Yes | No | Requires a `branch_id` |

---

## 2. How to add a new admin

### Step 1 — the person needs an account

Pick one:

- **They sign up in the app themselves** (existing flow), or
- **You create it:** Supabase Dashboard -> Authentication -> Users -> green **"Add user"** -> set email + password -> tick auto-confirm

### Step 2 — copy their user ID

Supabase Dashboard -> Authentication -> Users -> click the person -> copy the UUID (the long `xxxx-xxxx-...` value).

### Step 3 — insert the admin row

Supabase Dashboard -> **SQL Editor** -> paste and run:

```sql
insert into public.admin_users (id, branch_id, role, full_name)
values (
  'PASTE-THEIR-UUID-HERE',
  null,            -- leave null for owner
  'owner',         -- or 'staff'
  'Their Name'
);
```

Only an `owner` can run this successfully. The table is locked so nobody can promote themselves.

### Removing an admin

```sql
delete from public.admin_users
where id = 'THEIR-UUID';
```

You cannot delete **your own** row — that guard exists so the last owner can't accidentally lock everyone out of admin management.

### Changing someone's role

```sql
update public.admin_users
set role = 'staff'
where id = 'THEIR-UUID';
```

Same guard: you cannot change your own role away from `owner`.

---

## 3. What was applied (migration `rls_lock_admin_users_categories_menu_items`)

### Helper functions

`public.is_owner()` and `public.is_staff()` are `SECURITY DEFINER` + `stable`, with `search_path = public`. They must be `SECURITY DEFINER` so they can still read `admin_users` after its own RLS is switched on, and so the "owner reads all admins" policy does not recurse into itself.

### Policies

**`admin_users`** — RLS enabled

| Policy | Command | Who |
|---|---|---|
| `admin_users read own row` | SELECT | any signed-in user (own row only) |
| `admin_users owner reads all` | SELECT | owners |
| `admin_users owner creates admins` | INSERT | owners |
| `admin_users owner updates admins` | UPDATE | owners (cannot self-demote) |
| `admin_users owner deletes admins` | DELETE | owners (cannot self-delete) |

**`menu_items`** — RLS already enabled

| Policy | Command | Who |
|---|---|---|
| `menu_items browse available` | SELECT | anon + authenticated; customers see only `is_available = true`, staff see all |
| `menu_items staff insert` | INSERT | staff |
| `menu_items staff update` | UPDATE | staff |
| `menu_items staff delete` | DELETE | staff |

**`categories`** — RLS enabled

| Policy | Command | Who |
|---|---|---|
| `categories browse all` | SELECT | anon + authenticated (all rows) |
| `categories staff insert` | INSERT | staff |
| `categories staff update` | UPDATE | staff |
| `categories staff delete` | DELETE | staff |

### The owner account

| Email | ID | Name | Role | Branch |
|---|---|---|---|---|
| `admin@mrpizza.com` | `6c90ef98-1036-447c-a26b-7e1d42a00fa9` | Panel Owner | `owner` | null (all branches) |

**Keep admin logins separate from app logins.** An earlier version of this setup made `razashahzaib119@gmail.com` (the Flutter app's everyday customer test login) the owner. That was wrong: the app is customer/rider only, so an owner role on a customer test account means the customer test session can bypass every policy, and customer-side testing tells you nothing about security. Admin powers belong only to the panel login.

The owner account has **no `profiles` row** — that is fine, because the panel reads `admin_users`, not `profiles`. It only means the panel must not expect a `profiles` entry for admin logins.

---

## 4. Decisions made

- **One shared menu for both branches.** `menu_items` and `categories` intentionally have **no `branch_id`** — Abbottabad and Mansehra use the same catalog. A price change in one branch changes it in both.
- **The menu is publicly readable.** Customers can browse before signing up. Sold-out items are hidden from customers but stay visible to staff so they can switch them back on.
- **`MenuRepository.fetchMenuItems()` needs no change.** It calls `.select()` with no filter; the policy does the filtering. A customer gets available items, staff get everything.

---

## 5. Gotchas

1. **`profiles.role` cannot hold an admin role.** That column has a DB check constraint allowing only `customer` or `rider`. Admin status is only ever in `admin_users`. Since the Flutter app is customer/rider only, this is **correct — leave it alone.** Just don't expect `profiles.role` to tell you who an admin is; query `admin_users` for that (which is what the Next.js panel should do).
2. **`branches` is empty (0 rows).** A `branch_manager` needs a `branch_id` pointing at `branches`, so add the Abbottabad and Mansehra branches before creating branch managers.
3. **There is no trigger creating a `profiles` row on signup.** The app inserts it manually (`lib/features/auth/data/auth_repository.dart:18`). Accounts created directly in the Supabase dashboard therefore have **no `profiles` row**, and `ProfileRepository.fetchProfile()` returns `null` for them (`profile_repository.dart:8`) — which makes two different dashboard-made accounts look identical in the app. This affects `admin@mrpizza.com` and `admin123@mrpizza.com`, both of which have no profile.
4. **`updateProfile()` sends a column that does not exist.** `profile_repository.dart:20` writes `updated_at`, but the `profiles` table only has `id`, `role`, `full_name`, `phone`, `created_at`. Saving a profile from the app will fail with a database error until this is fixed.
5. **The Flutter app has no real role enforcement yet.** Two stubs to be aware of:
   - `lib/core/routing/route_guard.dart:8-16` — `isLoggedIn()` and `canAccessRiderRoutes()` both `return true` unconditionally. Any user can navigate to rider screens today.
   - `lib/core/providers/role_provider.dart:12-14` — the role is a hardcoded in-memory default (`customer`), not read from the database. The role switcher on the profile screen (`lib/features/profile/screens/profile_screen.dart:340`) therefore only changes local UI state; it writes nothing.

   Neither is a security hole on its own, but the rider role must be sourced from the real `profiles.role` before rider screens are relied on. Note that `orders` is still unlocked (section 6), so an unverified rider toggle currently sits in front of unprotected order data.
6. **The helper functions are callable by `anon`/`authenticated` via RPC.** Supabase's security scanner warns about this. Not a real leak — they only ever answer "is *you* an admin". To silence it you must split the public browse policy so logged-out visitors don't invoke the function, then revoke `EXECUTE` from `PUBLIC`. (`anon` here is the Postgres role name, which is unchanged by the key renaming — it is not the key.)
7. **Deleting a category that has items is blocked** by the `menu_items.category_id` foreign key (`ON DELETE NO ACTION`). Good — no data loss, but the error is raw.

---

## 6. Still unlocked (RLS disabled, 10 tables)

Anyone holding the **publishable key** can currently read **and modify** every row in these. (The publishable key ships inside the mobile app, so it is not a secret — these tables are effectively public.)

| Table | Risk if left open |
|---|---|
| `orders` | Customer names, addresses, phone numbers |
| `transactions` | Payment records |
| `order_items` | What was ordered, tied to customers |
| `order_status_history` | Order tracking data |
| `voucher_redemptions` | Promo code abuse |
| `loyalty_ledger` | Customer balances |
| `rider_details` | Rider personal info |
| `rider_assignments` | Which rider has which order |
| `vouchers` | Promo code definitions |
| `branches` | Branch config |

Decision: lock these one at a time, as needed, when the matching feature gets built.

---

## 7. When adding policies to a new table

Order matters. The pattern that works here:

1. Create the `is_owner()` / `is_staff()` helpers **first** (they already exist).
2. Seed the admin row **before** locking, or nobody can write anything.
3. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`.
4. Add explicit policies. **No policy means no access** — RLS denies by default.

Watch out for: a policy on a table that queries that same table causes infinite recursion. Route those checks through a `SECURITY DEFINER` function instead.
