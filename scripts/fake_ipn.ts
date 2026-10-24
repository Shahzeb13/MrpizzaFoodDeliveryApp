// Fake PayFast IPN sender — for testing the payfast-ipn Edge Function locally.
//
//   node scripts/fake_ipn.ts <basket_id> <err_code> <merchant_amount> [options]
//
// Options:
//   --bad-hash          send a deliberately wrong validation_hash (expect HTTP 400)
//   --txn=<id>          override the transaction_id
//   --url=<url>         override the function URL
//
// Secrets come from the ENVIRONMENT, never from this file and never from the repo:
//   PAYFAST_SECURED_KEY   required
//   PAYFAST_MERCHANT_ID   required
//
//   PowerShell:
//     $env:PAYFAST_SECURED_KEY = "..."; $env:PAYFAST_MERCHANT_ID = "102";
//     node scripts/fake_ipn.ts <basket> 000 1460.74
//
//   bash:
//     PAYFAST_SECURED_KEY=... PAYFAST_MERCHANT_ID=102 \
//       node scripts/fake_ipn.ts <basket> 000 1460.74
//
// The body mirrors PayFast's own sample IPN: form-encoded, carrying
// merchant_amount alongside transaction_amount (which includes gateway fees).
import { createHash } from 'node:crypto';

const DEFAULT_URL = 'https://eytsownrsujphibqpimt.supabase.co/functions/v1/payfast-ipn';

function sha256Hex(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

const argv = process.argv.slice(2);
const flags = argv.filter((a) => a.startsWith('--'));
const positional = argv.filter((a) => !a.startsWith('--'));

const [basketId, errCode, merchantAmount] = positional;

if (!basketId || !errCode || !merchantAmount) {
  console.error('usage: node scripts/fake_ipn.ts <basket_id> <err_code> <merchant_amount> [--bad-hash] [--txn=<id>] [--url=<url>]');
  process.exit(2);
}

const securedKey = process.env.PAYFAST_SECURED_KEY;
const merchantId = process.env.PAYFAST_MERCHANT_ID;

if (!securedKey || !merchantId) {
  console.error('PAYFAST_SECURED_KEY and PAYFAST_MERCHANT_ID must be set in the environment.');
  process.exit(2);
}

const badHash = flags.includes('--bad-hash');
const txn = flags.find((f) => f.startsWith('--txn='))?.slice('--txn='.length)
  ?? `FAKE-${Date.now().toString(36).toUpperCase()}`;
const url = flags.find((f) => f.startsWith('--url='))?.slice('--url='.length) ?? DEFAULT_URL;

// Same formula the Edge Function verifies against.
const expectedHash = sha256Hex(`${basketId}|${securedKey}|${merchantId}|${errCode}`);
const validationHash = badHash ? sha256Hex('deliberately-wrong') : expectedHash;

// PayFast's sample shape. transaction_amount is the gross figure including fees,
// merchant_amount is what actually belongs to the merchant.
const body = new URLSearchParams({
  validation_hash: validationHash,
  merchant_id: merchantId,
  basket_id: basketId,
  transaction_id: txn,
  order_date: new Date().toISOString().replace('T', ' ').slice(0, 19),
  transaction_amount: merchantAmount,
  merchant_amount: merchantAmount,
  err_code: errCode,
  PaymentName: 'Card',
});

console.log(`POST ${url}`);
console.log(`  basket_id       = ${basketId}`);
console.log(`  err_code        = ${errCode}`);
console.log(`  merchant_amount = ${merchantAmount}`);
console.log(`  transaction_id  = ${txn}`);
console.log(`  validation_hash = ${validationHash}${badHash ? '  (DELIBERATELY WRONG)' : ''}`);

const res = await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body,
});

const text = await res.text();
console.log(`\nHTTP ${res.status}`);
console.log(text || '(empty body)');