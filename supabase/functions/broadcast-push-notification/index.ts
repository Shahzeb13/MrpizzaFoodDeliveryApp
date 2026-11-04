// broadcast-push-notification
// Broadcast to all users

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
    const { title, body, data, topic } = await req.json();

    if (!title) {
      return new Response(JSON.stringify({ error: 'missing_params' }), { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    if (topic) {
      const message = {
        notification: { title, body },
        data: data || {},
        topic: topic,
      };
      const response = await admin.messaging().send(message);
      return new Response(JSON.stringify({ success: true, response }), { status: 200 });
    }

    const { data: tokens } = await supabase
      .from('user_fcm_tokens')
      .select('token')
      .not('token', 'is', null);

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ success: false, reason: 'no_tokens' }), { status: 200 });
    }

    const tokenList = tokens.map((t: any) => t.token).filter(Boolean);
    const results = [];
    for (let i = 0; i < tokenList.length; i += 500) {
      const batch = tokenList.slice(i, i + 500);
      const message = {
        notification: { title, body },
        data: data || {},
        tokens: batch,
      };
      const response = await admin.messaging().sendEachForMulticast(message);
      results.push(response);
    }
    return new Response(JSON.stringify({ success: true, results }), { status: 200 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
