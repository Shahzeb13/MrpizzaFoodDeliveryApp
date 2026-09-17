# Safepay Integration Notes

Research notes from exploring Safepay's payment integration options for a Flutter + Supabase project.

## Integration Flow Options

Safepay offers four server-side integration flows. These are **alternatives to each other** — pick one:

| Feature | Express Checkout | Safepay Atoms | Safepay React Native | Cardinal |
|---|---|---|---|---|
| Any payment method | Yes | Yes | Yes | Yes |
| Tokenization | Yes | Yes | Yes | Yes |
| Zero amount verification | Yes | Yes | Yes | Yes |
| Separate Capture | **No** | Yes | Yes | Yes |
| Integration effort | Low | Medium | Medium | High |
| Endpoint requests from server | 2 | 3-4 | 3-4 | 7-8 |
| 3DS handling | Managed by Safepay | Self Managed | Self Managed | Managed by Safepay |

**Key notes:**
- **Safepay Atoms** = React-only web components. Not usable directly in Flutter.
- **Cardinal Mobile SDK** = true native mobile integration, but needs platform channels to bridge into Flutter — more setup work.
- **Express Checkout** is the best fit for Flutter + lowest effort: it *does* support tokenization (saved cards), it just lacks **Separate Capture** (authorize now, charge later as a distinct step).

## Tokenization

- Tokenization = storing a **token** (a meaningless placeholder string) instead of the raw card number.
- Enables: faster repeat checkout, subscriptions, automatic top-ups, "card on file" UX.
- **Security/compliance angle:** Safepay holds the real card data; your server only ever touches the token. This keeps you out of full PCI DSS compliance scope.
  - Not fully PCI DSS compliant (most businesses) → use Safepay tokens. Recommended default.
  - Fully PCI DSS compliant → you're allowed to store raw card data yourself or build your own token vault.
- It's simultaneously a **UX improvement** (no re-entering card details) and a **security/compliance shortcut** (no sensitive data on your servers).

## Flutter Package Warning

- `safepay_checkout` and `safepay_payment_gateway` on pub.dev are **unofficial, third-party packages** — not published or maintained by Safepay.
  - Published by a single indie developer (`asadshafique.com`), very low usage (~2 likes, ~30 weekly downloads).
  - Risky to depend on for a payment flow: if abandoned, no upstream support; bugs could silently mishandle payment data; may lag behind Safepay API changes.
- **Recommendation:** don't use these packages. Build your own thin wrapper instead:
  - Use a well-known, actively maintained WebView package (e.g. `webview_flutter` or `flutter_inappwebview`).
  - Point it at Safepay's hosted checkout page using the tracker/token from your backend.
  - Listen for the `successUrl` / `failUrl` redirect in the WebView's navigation callback.
  - This keeps all *payment-specific* logic going through Safepay's official REST API directly — only the WebView layer is third-party, and that's a generic, trustworthy package.

## Architecture: Supabase + Express Checkout

Supabase (Edge Functions + Postgres) is the **backend layer**, needed regardless of which checkout flow is chosen. The checkout flow is the **client-side experience** layered on top.

```
Supabase Edge Functions (backend — always present)
        ↓
   [pick ONE checkout flow]
        ↓
Express Checkout  OR  Atoms  OR  React Native  OR  Cardinal
```

### Recommended flow for this project (Flutter + Supabase + Express Checkout)

1. **Supabase Edge Function** (using the server-side/secret API key) calls Safepay's API to:
   - Create a **Tracker** (the payment session object)
   - Generate a **JWT / tbt token**
2. Safepay responds with the tracker reference + token.
3. Flutter app uses the tracker/token to render Safepay's hosted checkout — likely via a **WebView** (exact mechanics — whether a direct checkout URL is returned or the tracker/token is used to initialize a client-side session — need to be confirmed against the official Express Checkout guide).
4. Shopper completes payment on the hosted page.
5. Safepay redirects to `successUrl` / `failUrl` **and** fires a **webhook** to a separate Edge Function.
6. The **webhook** (not the redirect) is the source of truth — verify its signature server-side, then update the `orders`/`payments` table in Postgres. Never trust the client-side redirect alone to mark an order as paid.

### Where things live in Supabase specifically

| Safepay checklist item | Supabase equivalent |
|---|---|
| Server-side API key, secrets | Edge Function environment secrets / Supabase Vault |
| Create Tracker, Create Customer, Generate JWT | Edge Function (called from Flutter client) |
| Webhook endpoint, signature validation | Dedicated Edge Function (e.g. `safepay-webhook`) |
| Store token / payment status / tracker ID | Postgres tables (`orders`, `payments`, etc.) with RLS |
| Client-side checkout UI | Flutter app (WebView-based) |

## Open Questions / To Verify

- [ ] Does Express Checkout's Tracker-creation call return a ready-to-use checkout **URL**, or does the client need to initialize a checkout session using the tracker/JWT some other way? (Check the official Express Checkout guide page directly.)
- [ ] Confirm whether card-on-file / saved cards is an actual requirement for this project — if not, Express Checkout is sufficient; if separate capture is needed later, would need to move to Atoms (web-only) or Cardinal (native).



also created safepay sandbox account ! and also learned that you gotta apply for produciton acocunt relatively early becasue it takes fucking time