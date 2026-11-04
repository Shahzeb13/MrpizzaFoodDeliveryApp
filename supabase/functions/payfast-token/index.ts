// POST /functions/v1/payfast-token   body: { order_id }
// Called by the Flutter app (with the user's JWT). Deployed with JWT verification ON.
//
// Secrets: PAYFAST_MERCHANT_ID, PAYFAST_SECURED_KEY, PAYFAST_MERCHANT_NAME
// (PAYFAST_ENV is gone — the URL below is hard-coded live.)
//
// Schema adaptations made for this project (everything else is verbatim):
//
//   select('id, user_id, total, payment_status')
//     -> select('id, customer_id, total, payment_status')
//   order.user_id !== user.id
//     -> order.customer_id !== user.id
//
// `orders` has no `user_id`. The customer is `orders.customer_id`, which is a FK to
// `profiles(id)`, and `profiles.id` is the auth user id — verified 35/35 existing
// orders join to auth.users on that column. So the ownership check is the same
// check, just under the right name.
import { createClient } from 'npm:@supabase/supabase-js@2';

// Live PayFast IPG (ipg1.apps.net.pk). Hard-coded live: a token minted by UAT
// is worthless on the live PostTransaction form and vice versa, so the two
// ends must never disagree.
const BASE = 'https://ipg1.apps.net.pk/Ecommerce/api';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;

  // 1. Who is calling?
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: 'unauthorized' }, 401);

  const { order_id } = await req.json().catch(() => ({}));
  if (!order_id) return json({ error: 'order_id_required' }, 400);

  // 2. Load the order with the service role; the amount comes from the DB, never from the app.
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: order } = await admin
    .from('orders')
    .select('id, customer_id, total, payment_status')
    .eq('id', order_id)
    .maybeSingle();

  if (!order || order.customer_id !== user.id) return json({ error: 'order_not_found' }, 404);
  if (order.payment_status === 'paid') return json({ error: 'already_paid' }, 409);

  const merchantId = Deno.env.get('PAYFAST_MERCHANT_ID')!;

  // 3. Fresh basket id + amount BEFORE the token call.
  //    The live gateway binds the token to the basket and the amount: both are
  //    sent to GetAccessToken, and the form must carry the same values or the
  //    payment is rejected (guide p12). basket_id is the `payments` primary key,
  //    so distinct attempts get distinct baskets — a repeat in the same
  //    millisecond would collide. The IPN echoes it back and apply_payment_result
  //    looks the order up by it.
  const basketId = `${String(order.id).slice(0, 8)}-${Date.now().toString(36)}`;
  const amount = Number(order.total).toFixed(2);

  // 4. Ask PayFast for an access token. All five fields are mandatory (guide p11);
  //    live answers errorCode 003 "Amount, Basket Id and Currency code must be
  //    required" without them. Empty user agents are rejected too (guide p10).
  const tokenRes = await fetch(`${BASE}/Transaction/GetAccessToken`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'MrPizzaApp/1.0',
    },
    body: new URLSearchParams({
      MERCHANT_ID: merchantId,
      SECURED_KEY: Deno.env.get('PAYFAST_SECURED_KEY')!,
      BASKET_ID: basketId,
      TXNAMT: amount,
      CURRENCY_CODE: 'PKR',
    }),
  });
  // Live IPG hides real errors behind {"Message":"An error has occurred."} with
  // no STATUS/MESSAGE, so log the raw body — the parsed shape alone says nothing.
  const tokenText = await tokenRes.text();
  let tokenJson: Record<string, unknown> = {};
  try {
    tokenJson = JSON.parse(tokenText);
  } catch {
    tokenJson = {};
  }
  if (!tokenJson.ACCESS_TOKEN) {
    console.error('payfast token failed', tokenRes.status, tokenText.slice(0, 500));
    return json({ error: 'token_failed', message: tokenJson.MESSAGE ?? null }, 502);
  }

  // 5. Store a pending payment row so the IPN has something to match against.
  const { error: insertError } = await admin.from('payments').insert({
    basket_id: basketId,
    order_id: order.id,
    amount,
  });
  if (insertError) {
    console.error('payment insert failed', insertError.message);
    return json({ error: 'server_error' }, 500);
  }

  return json({
    token: tokenJson.ACCESS_TOKEN,
    basket_id: basketId,
    amount,
    merchant_id: merchantId,
    merchant_name: Deno.env.get('PAYFAST_MERCHANT_NAME') ?? 'Mr. Pizza',
  });
});