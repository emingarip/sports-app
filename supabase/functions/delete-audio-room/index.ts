import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { RoomServiceClient } from "npm:livekit-server-sdk";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Verify user token exists and is valid
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error("Missing Authorization header");
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    
    if (userError || !user) {
      throw new Error("Unauthorized request");
    }

    const { room_name } = await req.json();
    if (!room_name) {
      throw new Error("room_name is required in the JSON payload");
    }

    const livekitUrl = Deno.env.get("LIVEKIT_URL") ?? "wss://boskalecom-2zi7gj0y.livekit.cloud";
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");

    if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
      throw new Error("LiveKit credentials are not correctly configured in Supabase Vault Environment Variables.");
    }

    // 1. Forcefully delete the room entirely from LiveKit (kicks everyone out)
    const roomService = new RoomServiceClient(livekitUrl, livekitApiKey, livekitApiSecret);
    
    try {
        await roomService.deleteRoom(room_name);
        console.log(`LiveKit room '${room_name}' forcefully deleted by admin: ${user.email}`);
    } catch (lkErr) {
        console.warn(`LiveKit deletion failed (perhaps the room was already empty/closed):`, lkErr);
        // We do not throw here! Even if the room vanished from LiveKit, we must clear it from our DB.
    }

    // 2. Remove the room record from our database so the UI clears it
    const { error: dbError } = await supabaseClient
      .from('audio_rooms')
      .delete()
      .eq('room_name', room_name);

    if (dbError) {
      console.error("Failed to delete from DB, but LiveKit room was deleted", dbError);
      throw new Error("Failed to sync DB deletion");
    }

    return new Response(JSON.stringify({ success: true, room_name }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
