/* Verbindung zur Neighbr-Datenbank (Supabase).
   Der Schlüssel hier ist der ÖFFENTLICHE Schlüssel. Er darf in der App stehen,
   die Regeln in der Datenbank (supabase/setup.sql) entscheiden, wer was darf.
   Den geheimen Schlüssel (sb_secret_…) niemals hier eintragen! */
window.NEIGHBR_CONFIG = {
  supabaseUrl: 'https://kpbnmjsxodicuejdkgtf.supabase.co',
  supabaseKey: 'sb_publishable_J1pqGYlnVfTQ3DIaPoB0ig_RmOMGFGI'
};
