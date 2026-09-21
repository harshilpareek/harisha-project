// ============================================================
//  Date Deck — backend config
//  1. Copy this file to  config.js  (same folder)
//  2. Fill in the two values from Supabase → Settings → API
//  3. config.js is git-ignored, so your keys stay out of the repo
//
//  Note: the "anon public" key is meant for the browser. Your data
//  is protected by the row-level security policies in
//  supabase-schema.sql — never put the service_role key here.
// ============================================================
window.DATE_NIGHT_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT-REF.supabase.co",
  supabaseAnonKey: "YOUR-ANON-PUBLIC-KEY"
};
