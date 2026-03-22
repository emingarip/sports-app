import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { initializeApp, cert, getApps } from "npm:firebase-admin@11.11.1/app";
import { getMessaging } from "npm:firebase-admin@11.11.1/messaging";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

serve(async (req) => {
  try {
    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    let app;
    if (!serviceAccountStr) {
        throw new Error("FIREBASE_SERVICE_ACCOUNT is not set in environment variables");
    }
    
    // Initialize app only once
    const apps = getApps();
    if (!apps.length) {
        const serviceAccount = JSON.parse(serviceAccountStr);
        app = initializeApp({
            credential: cert(serviceAccount),
        });
    } else {
        app = apps[0];
    }
    const messaging = getMessaging(app);

    const payloadText = await req.text();
    console.log("Received push trigger payload string:", payloadText);
    
    let payload;
    try {
        payload = JSON.parse(payloadText);
    } catch {
        payload = {};
    }

    // The payload from the Postgres Trigger uses the standard webhook structure
    // { type: "INSERT", table: "notifications", record: { user_id: "...", title: "...", message: "..." }, schema: "public", old_record: null }
    if (payload.type !== "INSERT" || payload.table !== "notifications" || !payload.record) {
       console.log("Invalid payload structure:", payload);
       return new Response(JSON.stringify({ error: "Invalid payload structure", payload_received: payload }), { status: 400 });
    }

    const notification = payload.record;
    const userId = notification.user_id;

    if (!userId) {
       return new Response(JSON.stringify({ error: "No user_id in notification" }), { status: 400 });
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !supabaseKey) {
        throw new Error("Supabase credentials not found in env");
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Fetch tokens for this user
    const { data: devices, error: dbError } = await supabase
        .from('user_devices')
        .select('fcm_token')
        .eq('user_id', userId);

    if (dbError) {
        console.error("Supabase DB Error fetching devices:", dbError);
        throw dbError;
    }

    if (!devices || devices.length === 0) {
        console.log(`No devices found for user ${userId}, skipping push.`);
        return new Response(JSON.stringify({ success: true, message: "No devices found" }), {
          headers: { "Content-Type": "application/json" },
        });
    }

    const rawTokens = devices.map(d => d.fcm_token).filter(t => t);
    const tokens = Array.from(new Set(rawTokens));
    
    if (tokens.length === 0) {
        return new Response(JSON.stringify({ success: true, message: "No valid tokens found" }), {
          headers: { "Content-Type": "application/json" },
        });
    }

    const response = await messaging.sendEachForMulticast({
      tokens: tokens,
      notification: {
        title: notification.title,
        body: notification.message,
      },
      data: {
        notification_id: notification.id,
      },
      // Optional Android config for high priority
      android: {
        priority: 'high',
        notification: {
          channelId: 'sports_app_alerts',
        }
      },
      // Optional APNs config
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
            sound: 'default'
          }
        }
      }
    });

    console.log(`Successfully sent messages: ${response.successCount} success, ${response.failureCount} failed.`);
    if (response.failureCount > 0) {
       response.responses.forEach((resp, idx) => {
           if (!resp.success) {
               console.error(`Error sending to token ${tokens[idx]}:`, resp.error);
           }
       });
    }

    return new Response(JSON.stringify({ success: true, response }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
