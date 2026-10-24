// POST /functions/v1/payfast-token   body: { order_id }
// Called by the Flutter app (with the user's JWT). Deployed with JWT verification ON.
//
// Secrets: PAYFAST_MERCHANT_ID, PAYFAST_SECURED_KEY, PAYFAST_MERCHANT_NAME, PAYFAST_ENV
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

const BASE = Deno.env.get('PAYFAST_ENV') === 'live'
  ? 'https://ipg1.apps.net.pk/Ecommerce/api'
  : 'https://ipguat.apps.net.pk/Ecommerce/api';

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

  // 3. Ask PayFast for an access token.
  const tokenRes = await fetch(`${BASE}/Transaction/GetAccessToken`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      MERCHANT_ID: merchantId,
      SECURED_KEY: Deno.env.get('PAYFAST_SECURED_KEY')!,
    }),
  });
  const tokenJson = await tokenRes.json().catch(() => ({}));
  if (!tokenJson.ACCESS_TOKEN) {
    console.error('payfast token failed', tokenJson.STATUS, tokenJson.MESSAGE);
    return json({ error: 'token_failed', message: tokenJson.MESSAGE ?? null }, 502);
  }

  // 4. Fresh basket id for every attempt, plus a pending payment row to match the IPN against.
  //    Distinct attempts must be given distinct baskets: basket_id is the payments
  //    primary key, so a repeat in the same millisecond would collide. The IPN echoes
  //    this back and apply_payment_result looks the order up by it.
  const basketId = `${String(order.id).slice(0, 8)}-${Date.now().toString(36)}`;
  const amount = Number(order.total).toFixed(2);

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