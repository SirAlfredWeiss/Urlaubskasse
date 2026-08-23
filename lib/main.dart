import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );
  runApp(const UrlaubskasseApp());
}

class UrlaubskasseApp extends StatelessWidget {
  const UrlaubskasseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urlaubskasse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C86)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
