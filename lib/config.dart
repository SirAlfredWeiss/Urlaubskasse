class Config {
  // Deine Supabase-Daten (bereits eingetragen).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zjoqbybxwpnvvxmpxqxj.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_TMrHTsqNYr45QKHgDtnvnw_9tqC6m4L',
  );
}
