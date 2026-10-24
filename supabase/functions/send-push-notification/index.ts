// send-push-notification
// DO NOT DEPLOY without explicit permission.
// Uses Firebase Admin SDK. Set FIREBASE_SERVICE_ACCOUNT as a secret (JSON string).
// Reads tokens from user_fcm_tokens and sends via FCM.

import { createClient } from 'npm:@supabase/supabase-js@2';
import admin from 'npm:firebase-admin@12';

const app = admin.apps.length
  ? admin.app()
  : admin.initializeApp({
      credential: admin.credential.cert(
        JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}'),
      ),
    });

Deno.serve(async (req) => {
  try {
    const { user_id, title, body, data } = await req.json();

    if (!user_id || !title) {
      return new Response(JSON.stringify({ error: 'missing_params' }), { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: tokens } = await supabase
      .from('user_fcm_tokens')
      .select('token')
      .eq('user_id', user_id);

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ success: false, reason: 'no_tokens' }), { status: 200 });
    }

    const tokenList = tokens.map((t: any) => t.token).filter(Boolean);

    const message = {
      notification: { title, body },
      data: data || {},
      tokens: tokenList,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    return new Response(JSON.stringify({ success: true, response }), { status: 200 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
