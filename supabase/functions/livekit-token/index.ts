import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { AccessToken } from "npm:livekit-server-sdk";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { roomName, participantName, userId, pinCode } = await req.json();

    if (!roomName || !participantName) {
      return new Response(
        JSON.stringify({ error: "roomName and participantName are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Verify user JWT
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);

    // Determine secure permissions from DB
    let isHost = false;
    let canPublish = false;

    if (user) {
      console.log(`[AUTH SUCCESS] User identified: ${user.id}`);

      const { data: roomData, error: roomError } = await supabaseAdmin
        .from("audio_rooms")
        .select("host_id, is_private, pin_code")
        .eq("room_name", roomName)
        .maybeSingle();

      if (roomError) {
        console.error(`[DB ERROR] Failed to fetch room: ${roomError.message}`);
      }

      if (roomData) {
        // =====================================================
        // SECURITY: PIN enforcement for private rooms
        // =====================================================
        if (roomData.is_private && roomData.host_id !== user.id) {
          // User is NOT the host of a private room — require PIN
          if (!pinCode || pinCode !== roomData.pin_code) {
            return new Response(
              JSON.stringify({ error: "Invalid or missing PIN code for this private room." }),
              { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
          console.log(`[PIN VERIFIED] User ${user.id} provided correct PIN for private room ${roomName}`);
        }
        // =====================================================

        if (roomData.host_id === user.id) {
          isHost = true;
          canPublish = true;
          console.log(`[PERMISSIONS] User is HOST and CAN PUBLISH.`);
        } else {
          canPublish = false; 
          console.log(`[PERMISSIONS] User is NOT host. Host is ${roomData.host_id}, user is ${user.id}`);
        }
      } else {
        console.log(`[PERMISSIONS] Room data not found in database for room: ${roomName}`);
      }
    } else {
       console.log(`[AUTH FAILED] User is null. authError parameter is:`, authError);
    }

    const apiKey = Deno.env.get("LIVEKIT_API_KEY");
    const apiSecret = Deno.env.get("LIVEKIT_API_SECRET");

    if (!apiKey || !apiSecret) {
      return new Response(
        JSON.stringify({ error: "LiveKit credentials are not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Ensure identity is globally unique even for anonymous users
    let finalIdentity = userId || user?.id;
    if (!finalIdentity) {
      if (participantName && participantName !== "Anonymous") {
        finalIdentity = participantName + "_" + crypto.randomUUID().substring(0, 8);
      } else {
        finalIdentity = "anon_" + crypto.randomUUID();
      }
    }

    const at = new AccessToken(apiKey, apiSecret, {
      identity: finalIdentity,
      name: participantName || "Anonymous",
    });
    
    // Always grant publish exclusively based on Database state
    const publishGranted = canPublish || isHost;

    at.addGrant({ 
      roomJoin: true, 
      room: roomName,
      canPublish: publishGranted,
      canSubscribe: true,
      canPublishData: true,
    });

    const jwtToken = await at.toJwt();

    return new Response(JSON.stringify({ token: jwtToken }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: any) {
    console.error("Token error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
