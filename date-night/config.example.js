// ============================================================
//  Harisha — site config
//
//  1. Copy this file to  config.js  (same folder)
//  2. Fill in the values from Supabase -> Settings -> API
//  3. COMMIT config.js. Yes, really — see the note below.
//
//  Is it safe to commit?
//    Yes. The "anon public" key is designed to sit in a browser;
//    it's how every Supabase web app works. What actually protects
//    your data is row-level security plus the two-account allowlist
//    in supabase-schema.sql.
//    NEVER put the `service_role` key here — that one bypasses
//    every security rule.
//
//  Committing it means the hosted site just works for both of you,
//  instead of each of you pasting keys into every device.
// ============================================================
window.HARISHA_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT-REF.supabase.co",
  supabaseAnonKey: "YOUR-ANON-PUBLIC-KEY",

  // The two people who can sign in. Names and colors show on the
  // login screen; `color` is either "indigo" or "rose" and themes
  // the whole app for that person.
  //
  // `email` is OPTIONAL:
  //   - filled in  -> the login screen shows two name buttons and
  //                   only asks for a password. Nicer, but the
  //                   addresses are visible in the page source.
  //   - left blank -> a normal email + password form. Keeps your
  //                   addresses off a public page.
  // Either way, the database only ever allows these two accounts.
  people: [
    { name: "Harshil", color: "indigo", email: "" },
    { name: "Isha",    color: "rose",   email: "" }
  ]
};
