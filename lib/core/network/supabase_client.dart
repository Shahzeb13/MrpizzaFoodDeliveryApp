import 'package:supabase_flutter/supabase_flutter.dart';

/// Shorthand accessor to the initialized Supabase client.
///
/// Import this instead of typing `Supabase.instance.client` everywhere:
/// `import 'core/network/supabase_client.dart';`
final supabase = Supabase.instance.client;