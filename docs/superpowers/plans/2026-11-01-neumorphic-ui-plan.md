# Neumorphic Soft-UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the exact soft neumorphic UI across Mr. Pizza (Home, Auth, Rider, Add Address, and Drawer) while maintaining full reactivity with existing live state, models, and database providers.

**Architecture:** Create reusable neumorphic design primitives (`NeuCard`, `NeuInset`, `NeuCircleButton`, `NeuPrimaryButton`, `NeuPill`) in `lib/core/theme/neumorphic.dart`, update the global `AppColors` and theme to match the light clay/slate palette, and systematically revamp each of the 5 screens to match the reference images.

**Tech Stack:** Flutter 3.x, Dart 3.x, Riverpod 2.x, GoRouter, Supabase Flutter.

**Spec:** `docs/superpowers/specs/2026-11-01-neumorphic-ui-design.md`

## Global Constraints
- Canvas background must be `#EEF2F6`.
- Neumorphic surfaces use dual-shadowing (light top-left `#FFFFFF` offset -5, -5; dark bottom-right `Color(0x1E7B8FA8)` offset 5, 5).
- Inset / debossed fields use `#E4EBF2` or subtle borders.
- Brand accent button is vibrant Red `#E51926` with red glow shadow.
- Preserve all existing business logic, Riverpod providers, Supabase data fetching, and navigation flows.

---

### Task 1: Neumorphic Theme Primitives and Palette Updates
**Files:**
- Create: `lib/core/theme/neumorphic.dart`
- Modify: `lib/core/theme/app_colors.dart`
- Modify: `lib/core/theme/app_theme.dart`

- [ ] **Step 1: Update `AppColors`**
Add `#EEF2F6` as `AppColors.background`, update `primary` to `#E51926`, and add neumorphic shadow constants.
- [ ] **Step 2: Create `lib/core/theme/neumorphic.dart`**
Implement `NeuCard`, `NeuInset`, `NeuCircleButton`, `NeuPrimaryButton`, and `NeuPill` widgets with high quality dual-shadow rendering and click responses.
- [ ] **Step 3: Run `flutter analyze` to verify zero compile or lint errors**
Run: `flutter analyze lib/core/theme/`

---

### Task 2: Auth Login Screen Redesign
**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart`

- [ ] **Step 1: Refactor `LoginScreen` layout**
Implement the cartoon Mr. Pizza logo header, the central elevated `NeuCard`, the `WELCOME` red badge, "Welcome back!" headline, debossed `NeuInset` email and password fields with leading icons, and red CTA `"Sign in ->"` button.
- [ ] **Step 2: Connect form validation & auth submission**
Ensure email and password validation, obscure text toggle, and loading state continue working with `authStateProvider`.
- [ ] **Step 3: Run `flutter analyze lib/features/auth/screens/login_screen.dart`**

---

### Task 3: Customer Home Feed & Menu Screen Redesign
**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`

- [ ] **Step 1: Top Navigation Bar & Category Filter Pills**
Implement circular hamburger menu button, `DELIVER TO` pill dropdown with live address, search button, and horizontal neumorphic category pills with active red dot.
- [ ] **Step 2: Brand Hero Card & Promo Banner**
Implement the elevated `Mr. Pizza` hero card with `LOVE IN EVERY BITE` badge and Abbottabad location text, followed by the dark curved promotional card with pizza image cutout.
- [ ] **Step 3: Catalog Pizza Flavor Cards & Floating Cart Dock**
Render elevated menu cards with red category tags, item name, heart icon button, right-aligned debossed image container, red circular `+` button, and bottom floating cart pill with total price and `"CHECKOUT ->"`.
- [ ] **Step 4: Run `flutter analyze lib/features/home/screens/home_screen.dart`**

---

### Task 4: Rider Dashboard Screen Redesign
**Files:**
- Modify: `lib/features/rider/screens/rider_screen.dart`

- [ ] **Step 1: Top Bar & Online Status Toggle Card**
Build circular menu button, `Rider Dashboard` title, and elevated status card with red lightning badge and `"Go offline"` capsule button.
- [ ] **Step 2: Dual Metrics Cards & Central Status Indicator**
Build side-by-side neumorphic cards for Deliveries completed (`13`) and Earnings (`Rate unavailable`), and the circular debossed center bike indicator with empty state messaging.
- [ ] **Step 3: Recent Deliveries List with Status Pills**
Render order history cards with Order ID, customer name, and soft pills for `"✓ DELIVERED"` and `"✕ DECLINED"`.
- [ ] **Step 4: Run `flutter analyze lib/features/rider/screens/rider_screen.dart`**

---

### Task 5: Side Drawer and Add Address Modal
**Files:**
- Modify: `lib/widgets/app_drawer.dart`
- Modify: `lib/features/profile/screens/addresses_screen.dart`

- [ ] **Step 1: Side Drawer Redesign**
Implement top `✕` close button, `DELIVERING TO` pill, circular initial avatar, user name & phone, soft icon container list tiles, social buttons (Instagram, X, Web), and bottom cartoon logo with version stamp.
- [ ] **Step 2: Add Address Modal Sheet**
Implement top drag handle, red pin badge, `Add new address` title, recessed text fields for Label and Address, `"Use my current location"` button with crosshair icon, and red `"Save address"` CTA.
- [ ] **Step 3: Run full `flutter analyze` across the whole repository**
Ensure clean build with zero issues.
