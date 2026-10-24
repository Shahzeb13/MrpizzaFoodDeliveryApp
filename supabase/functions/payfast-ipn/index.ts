// PayFast IPN receiver.
//
// This URL is the CHECKOUT_URL you pass to the SDK. PayFast's servers POST to it
// when a payment finishes. They send no Supabase JWT, so it is deployed with
// `--no-verify-jwt` -- which means the validation_hash below is the ONLY thing
// standing between this endpoint and the open internet.
//
// Secrets: PAYFAST_MERCHANT_ID, PAYFAST_SECURED_KEY (same ones payfast-token uses;
// nothing new is set, and neither value is hard-coded here).
//
// Schema adaptations: none needed. The function talks to the database only through
// the apply_payment_result RPC, whose signature is unchanged:
//   apply_payment_result(p_basket text, p_err text, p_txn text, p_paid numeric)
import { createClient } from 'npm:@supabase/supabase-js@2';

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// The docs say the IPN carries query-string parameters and also list it as POST,
// and the sample is form-encoded. Accept query string, form body and JSON body.
async function readParams(req: Request): Promise<URLSearchParams> {
  const params = new URLSearchParams(new URL(req.url).search);
  if (req.method === 'POST') {
    const raw = await req.text();
    if ((req.headers.get('content-type') ?? '').includes('json')) {
      try {
        for (const [k, v] of Object.entries(JSON.parse(raw))) params.set(k, String(v));
      } catch { /* ignore bad JSON */ }
    } else {
      for (const [k, v] of new URLSearchParams(raw)) params.set(k, v);
    }
  }
  return params;
}

Deno.serve(async (req) => {
  const p = await readParams(req);

  const basketId = p.get('basket_id') ?? '';
  const errCode = p.get('err_code') ?? '';
  const received = (p.get('validation_hash') ?? '').toLowerCase();

  if (!basketId || !errCode || !received) return new Response('bad request', { status: 400 });

  // 1. Verify the hash: sha256("basket_id|secured_key|merchant_id|err_code")
  const expected = await sha256Hex(
    `${basketId}|${Deno.env.get('PAYFAST_SECURED_KEY')}|${Deno.env.get('PAYFAST_MERCHANT_ID')}|${errCode}`,
  );
  if (!safeEqual(expected, received)) {
    console.warn('IPN rejected: hash mismatch', basketId);
    return new Response('invalid', { status: 400 });
  }

  // 2. Apply the result atomically. The amount is compared inside the DB function.
  //    Sample IPN: merchant_amount=2.00, transaction_amount=3.98 (likely includes fees),
  //    so we compare merchant_amount. Confirm this with PayFast.
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data, error } = await admin.rpc('apply_payment_result', {
    p_basket: basketId,
    p_err: errCode,
    p_txn: p.get('transaction_id'),
    p_paid: Number(p.get('merchant_amount')),
  });

  if (error) {
    console.error('apply_payment_result failed', error.message);
    return new Response('error', { status: 500 }); // non-200 so PayFast can retry
  }

  if (data === 'double_paid' || data === 'amount_mismatch') {
    console.error('IPN needs manual review:', data, basketId, p.get('transaction_id'));
  } else {
    console.log('IPN', basketId, errCode, data);
  }
  return new Response('OK', { status: 200 });
});