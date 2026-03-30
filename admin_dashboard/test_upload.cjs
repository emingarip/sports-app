const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://nigatikzsnxdqdwwqewr.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
// We fall back to Anon key if Service Key isn't provided, but trying bucket creation with anon key will fail.

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

async function testUpload() {
  console.log('Testing with API to create/update bucket...');
  
  // Create bucket
  const { data: createData, error: createError } = await supabase.storage.createBucket('avatars', {
    public: true,
    fileSizeLimit: 5242880,
    allowedMimeTypes: ['image/jpg', 'image/jpeg', 'image/png']
  });
  console.log('Create Bucket output:', createData, createError?.message);

  const dummyData = Buffer.from('fake image data');
  const { data, error } = await supabase.storage
    .from('avatars')
    .upload('test_service2.png', dummyData, {
      contentType: 'image/png',
      upsert: true
    });
    
  console.log('Upload Result:', { data, error: error?.message });
}

testUpload();
