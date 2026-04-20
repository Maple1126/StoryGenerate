import 'package:supabase_flutter/supabase_flutter.dart';

// ========== 新的 Supabase 项目配置 ==========
const supabaseUrl = 'https://ynxngefbdijhsqkiyvbp.supabase.co';

const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlueG5nZWZiZGlqaHNxa2l5dmJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0Mjg4NDIsImV4cCI6MjA5MjAwNDg0Mn0.jnyMNRLXb815vwSEIj48ue_EVXMTwXv-LzkIg8Iswtw';

const supabaseServiceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlueG5nZWZiZGlqaHNxa2l5dmJwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjQyODg0MiwiZXhwIjoyMDkyMDA0ODQyfQ.I0HLf0zsxlSHdEIe7aWEgGAURL3jbul0cgbnE5HIMrw';
// ===========================================

final serviceSupabase = SupabaseClient(supabaseUrl, supabaseServiceRoleKey);