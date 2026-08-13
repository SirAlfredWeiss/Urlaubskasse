class Config {
  // Trage hier deine Supabase-Daten ein (Supabase -> Project Settings -> API).
  // Alternativ per --dart-define=SUPABASE_URL=... ueberschreibbar (siehe README).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://DEINPROJEKT.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'DEIN_ANON_KEY',
  );
}
