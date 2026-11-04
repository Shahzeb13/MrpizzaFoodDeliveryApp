# Neumorphic Soft-UI Redesign Specification

## 1. Overview & Visual Language
This specification documents the complete visual modernization of the Mr. Pizza Flutter application to precisely match the soft-neumorphic / claymorphic design language shown in the design references.

### 1.1 Color System
- **Canvas / Background**: `#EEF2F6` (Cool soft-gray tint)
- **Neumorphic Light Shadow**: `#FFFFFF` with blur 12-16, offset (-6, -6)
- **Neumorphic Dark Shadow**: `Color(0x2294A3B8)` or `Color(0x1E7B8FA8)` with blur 14-18, offset (6, 6)
- **Brand Primary Red**: `#E51926` / `#F01524` with soft glowing shadow `Color(0x40E51926)`
- **Debossed / Inset Surface Fill**: `#E5EBF2` or `#EAEFF5` with subtle inner edge borders
- **Text & Headings**: 
  - Title Primary: `#18202F` (Deep Slate Navy / Dark Charcoal, font weight 800)
  - Eyebrow / Tag: `#E51926` (Red uppercase, letter spacing 0.6)
  - Subtitle / Body: `#7B889B` (Neutral Cool Gray, font weight 500-600)

### 1.2 Neumorphic UI Primitives (`lib/core/theme/neumorphic.dart`)
1. **`NeuCard`**:
   - Convex/raised card with dual soft shadows (white top-left, soft slate bottom-right).
   - Configurable border radius (default 24.0), padding, and optional onTap.
2. **`NeuInset`**:
   - Concave/recessed container for text fields, category pill wells, and search bars.
   - Inner shadow effect created using gradient bevel or layered soft borders with `#E2E8F0` fill.
3. **`NeuCircleButton`**:
   - Elevated circular button for back buttons, hamburger menu, search icon, favorite/wishlist hearts, and social icons.
4. **`NeuPrimaryButton`**:
   - Vibrant red pill CTA ("Sign in ->", "CHECKOUT ->", "Save address", "+") with red glow shadow, white bold text, and forward arrow.
5. **`NeuBadge` / `NeuPill`**:
   - Eyebrow pill indicators (e.g. `DELIVER TO v`, `WELCOME`, `DELIVERING TO`, `3 OPTIONS`, `DELIVERED`, `DECLINED`).

---

## 2. Screens to Implement / Modernize

### 2.1 Customer Home / Catalog Screen (`lib/features/home/screens/home_screen.dart`)
- **Top Bar**:
  - Left: Neumorphic circular hamburger menu button.
  - Center: Neumorphic recessed/elevated pill showing `📍 DELIVER TO v` and live address line (`Triple one hotel near comsats`).
  - Right: Neumorphic circular search icon button.
- **Category Filter Rail**:
  - Horizontal scroll of rounded pills: Active pill has red dot (`🔴 Pizza Flavours`) with recessed active state; inactive pills (`Mr. Pizza Special`, `Burgers`, etc.) have elevated neumorphic look.
- **Brand Hero Card**:
  - Large rounded soft card with stylized "Mr. Pizza" logo, `LOVE IN EVERY BITE` badge, and subtitle `Wood-fired pizzas · Abbottabad`.
- **Promo Highlight Banner**:
  - Dark curved card with red pill badge `PIZZA FLAVOURS`, bold slogan `"Hand-tossed, baked fresh to order"`, and pizza photo cutout.
- **Catalog Section**:
  - Section header: `"Pizza Flavours"` with subtitle `"Prepared fresh in our kitchen"` and right-aligned pill `"3 OPTIONS"`.
  - Item Cards: Elevated neumorphic cards with red category tag, bold item title (`Chicken Tikka`, `Chicken Fajita`, `Super Supreme`), heart icon button on bottom-left, circular pizza image cutout in a debossed well on the right, and bright red circular `+` button.
- **Floating Cart Dock**:
  - Bottom floating neumorphic capsule with shopping bag icon, red item counter badge, `"TOTAL PRICE"`, bold price `Rs. 1753`, and vibrant red `"CHECKOUT ->"` button.

### 2.2 Auth / Login Screen (`lib/features/auth/screens/login_screen.dart`)
- Top cartoon bubble logo "Mr. PIZZA" with subtitle "LOVE IN EVERY BITE".
- Central elevated neumorphic card containing:
  - `WELCOME` red pill badge.
  - Headline `"Welcome back!"` and subtitle `"Sign in to order your favorite wood-fired pizzas."`.
  - Field labels with font weight 800.
  - Inset / recessed text fields for Email and Password with leading icons.
  - `"Forgot password?"` right-aligned red link.
  - Vibrant red pill `"Sign in ->"` button.
- Footer: `"Don't have an account? Sign up now"`.

### 2.3 Rider Dashboard (`lib/features/rider/screens/rider_screen.dart`)
- **Top Bar**: Circular menu button and `"Rider Dashboard"` headline.
- **Online Status Card**: Elevated card with red lightning badge, status text `"You are online / The shop can assign you orders."`, and dark capsule `"Go offline"` toggle button.
- **Metrics Grid**: Two side-by-side neumorphic cards:
  - Left: `"13"` deliveries completed (all time).
  - Right: `"Rate unavailable"` earnings (all time).
- **Empty State / Status Center**: Soft circular debossed recess with red bicycle icon, `"No deliveries waiting / When the shop assigns you an order it will appear here."`.
- **Recent Deliveries List**:
  - Section header `"Recent deliveries"`.
  - Delivery cards with Order ID (`ABT-063`), customer name (`Umer`), and soft status pills:
    - Delivered: Soft pill with checkmark and red/green text `"✓ DELIVERED"`.
    - Declined: Dark capsule pill with `"✕ DECLINED"`.

### 2.4 Add New Address Sheet (`lib/features/profile/screens/addresses_screen.dart` / sheet)
- Curved top sheet with drag indicator handle.
- Header: Red location pin badge, title `"Add new address"`, and circular close `✕` button.
- Fields:
  - `"Label (optional)"` with recessed tag icon text input (`Home, Office...`).
  - `"Complete address details"` with recessed pin icon text input (`Street, area, landmark`).
- Action: Neumorphic pill button `✛ Use my current location` with red crosshair icon.
- Bottom CTA: Vibrant red pill button `"Save address"`.

### 2.5 Side Drawer (`lib/widgets/app_drawer.dart`)
- Curved right-edge white/soft-slate drawer surface.
- Header:
  - Close circular button `✕` at top right.
  - `DELIVERING TO` pill badge.
  - Red circular avatar with user initial, user full name (`Muhammad shahzeb`), and phone with phone icon.
- Nav Items with soft elevated/recessed circular icon containers:
  - `Loyalty Points` (star icon)
  - `My Addresses` (pin icon)
  - `My Orders` (receipt icon)
  - `My Favourites` (heart icon)
  - `Support Center` (headphones icon)
  - Hairline separator
  - `Request Account Deletion` (user icon)
  - `Log out` (dark rounded icon box with exit icon)
- Drawer Footer:
  - Social media circular buttons: Instagram, X (Twitter), Website / Globe.
  - Cartoon logo "Mr. PIZZA" with version code `Version 1.1.8+18`.

---

## 3. Data & State Adaptation
- Ensure that the designs cleanly adapt to actual Supabase / Riverpod state:
  - Home screen binds to `menuCategoriesProvider`, `menuItemsProvider`, `cartProvider`, `locationProvider`.
  - Login screen binds to `authStateProvider` and form validation.
  - Rider screen binds to `riderDetailsProvider`, `riderDeliveriesProvider`, and toggle online status.
  - Address sheet binds to `locationProvider` and `addressBookProvider`.
  - Drawer binds to `profileFutureProvider`, `loyaltyBalanceProvider`, and `favoritesProvider`.
