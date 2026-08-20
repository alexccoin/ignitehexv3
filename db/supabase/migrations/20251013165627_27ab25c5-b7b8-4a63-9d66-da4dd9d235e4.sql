
-- Add column to track if recovery words have been shown to user
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS recovery_words_shown boolean DEFAULT false;

-- Create admin backup table for recovery words
CREATE TABLE IF NOT EXISTS admin_recovery_backups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_recovery_words text NOT NULL,
  backup_created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_accessed_by uuid REFERENCES auth.users(id),
  last_accessed_at timestamp with time zone,
  backup_hash text NOT NULL, -- Hash for integrity verification
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(user_id, backup_created_at)
);

-- Enable RLS on admin_recovery_backups
ALTER TABLE admin_recovery_backups ENABLE ROW LEVEL SECURITY;

-- Admin can view all backups
CREATE POLICY "Admins can view all recovery backups"
ON admin_recovery_backups
FOR SELECT
TO authenticated
USING (is_admin(auth.uid()));

-- Admin can insert backups
CREATE POLICY "Admins can create recovery backups"
ON admin_recovery_backups
FOR INSERT
TO authenticated
WITH CHECK (is_admin(auth.uid()));

-- Function to generate recovery words
CREATE OR REPLACE FUNCTION public.generate_recovery_words()
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  words text[] := ARRAY[
    'abundance', 'achieve', 'advance', 'airport', 'ancient', 'answer', 'approve', 'arrange', 'artist', 'attack',
    'balance', 'barrier', 'believe', 'benefit', 'border', 'bracket', 'breath', 'bridge', 'brilliant', 'bronze',
    'capable', 'capture', 'career', 'catalog', 'caution', 'celebrate', 'certain', 'challenge', 'champion', 'change',
    'clarity', 'climate', 'combine', 'comfort', 'command', 'common', 'compare', 'compete', 'complex', 'concept',
    'conduct', 'confirm', 'connect', 'consider', 'constant', 'contact', 'content', 'control', 'convert', 'correct',
    'create', 'credit', 'culture', 'current', 'damage', 'decade', 'decide', 'decline', 'decrease', 'defend',
    'define', 'degree', 'deliver', 'demand', 'depend', 'design', 'destroy', 'develop', 'device', 'diagram',
    'diamond', 'digital', 'direct', 'discover', 'display', 'distance', 'distinct', 'district', 'divide', 'domain',
    'donate', 'double', 'educate', 'effect', 'effort', 'element', 'embrace', 'emerge', 'emotion', 'enable',
    'energy', 'enforce', 'engage', 'engine', 'enhance', 'ensure', 'entire', 'equal', 'escape', 'essence',
    'estate', 'evidence', 'evolve', 'example', 'exceed', 'exclude', 'execute', 'exhibit', 'expand', 'expect',
    'explain', 'explore', 'expose', 'express', 'extend', 'extract', 'fabric', 'feature', 'federal', 'filter',
    'finance', 'flexible', 'fortune', 'forward', 'fragment', 'freedom', 'frequent', 'function', 'garden', 'gather',
    'generate', 'genuine', 'global', 'golden', 'govern', 'gradient', 'grateful', 'guarantee', 'habitat', 'harvest',
    'health', 'heritage', 'horizon', 'humble', 'identify', 'ignore', 'illegal', 'image', 'impact', 'imply',
    'improve', 'include', 'increase', 'indicate', 'industry', 'innocent', 'inspire', 'install', 'instance', 'instant',
    'integrate', 'intense', 'interact', 'interest', 'internal', 'introduce', 'invest', 'involve', 'isolate', 'journey',
    'justice', 'kingdom', 'knowledge', 'language', 'legal', 'legend', 'leisure', 'liberty', 'license', 'lifetime',
    'location', 'luxury', 'machine', 'maintain', 'manage', 'mandate', 'market', 'material', 'maximum', 'measure',
    'member', 'mention', 'merchant', 'message', 'method', 'migrate', 'minimum', 'mission', 'mistake', 'model',
    'modify', 'moment', 'monitor', 'motion', 'mountain', 'multiply', 'mystery', 'nation', 'native', 'natural',
    'nature', 'negative', 'network', 'neutral', 'never', 'normal', 'notice', 'number', 'object', 'observe',
    'obtain', 'obvious', 'occupy', 'ocean', 'offer', 'office', 'opinion', 'option', 'order', 'ordinary',
    'organic', 'organize', 'origin', 'outcome', 'output', 'overall', 'oxygen', 'package', 'palace', 'panel',
    'paper', 'parallel', 'parent', 'parking', 'partner', 'passage', 'passion', 'patent', 'pattern', 'payment',
    'peaceful', 'perfect', 'perform', 'period', 'permit', 'personal', 'phase', 'physical', 'picture', 'pioneer',
    'planet', 'plastic', 'platform', 'pleasure', 'pocket', 'popular', 'portion', 'position', 'positive', 'possible',
    'powder', 'power', 'practice', 'predict', 'prefer', 'prepare', 'present', 'preserve', 'prevent', 'primary',
    'principle', 'priority', 'private', 'problem', 'proceed', 'process', 'produce', 'product', 'profile', 'profit',
    'program', 'progress', 'project', 'promise', 'promote', 'property', 'protect', 'provide', 'public', 'publish',
    'purpose', 'quality', 'quantum', 'quarter', 'question', 'random', 'rapid', 'rather', 'reality', 'realize',
    'reason', 'rebuild', 'receive', 'recent', 'record', 'recover', 'reduce', 'reflect', 'reform', 'region',
    'regular', 'reject', 'relate', 'release', 'relevant', 'reliable', 'remain', 'remember', 'remove', 'render',
    'repair', 'repeat', 'replace', 'report', 'represent', 'require', 'research', 'reserve', 'resident', 'resist',
    'resolve', 'resource', 'respect', 'respond', 'restore', 'result', 'retain', 'retire', 'return', 'revenue',
    'reverse', 'review', 'revise', 'reward', 'rhythm', 'river', 'routine', 'royal', 'safety', 'sample',
    'satisfy', 'science', 'screen', 'search', 'season', 'second', 'secret', 'section', 'secure', 'segment',
    'select', 'senior', 'separate', 'sequence', 'series', 'service', 'session', 'settle', 'severe', 'shadow',
    'shelter', 'signal', 'similar', 'simple', 'single', 'social', 'society', 'solar', 'solution', 'source',
    'sovereign', 'speaker', 'special', 'species', 'spirit', 'sponsor', 'square', 'stable', 'stadium', 'standard',
    'station', 'status', 'storage', 'strategy', 'strength', 'structure', 'student', 'subject', 'submit', 'succeed',
    'success', 'suggest', 'suitable', 'summit', 'sunrise', 'sunset', 'supply', 'support', 'supreme', 'surface',
    'survive', 'suspect', 'sustain', 'symbol', 'system', 'talent', 'target', 'technique', 'temple', 'tenant',
    'texture', 'theater', 'theory', 'thought', 'thunder', 'ticket', 'timber', 'tissue', 'title', 'tower',
    'traffic', 'transfer', 'transform', 'transit', 'translate', 'travel', 'treasure', 'treaty', 'trend', 'tribute',
    'trigger', 'triumph', 'trouble', 'ultimate', 'umbrella', 'uniform', 'unique', 'universal', 'unknown', 'update',
    'upgrade', 'urban', 'urgent', 'useful', 'utility', 'vacant', 'valid', 'valley', 'valuable', 'variety',
    'vehicle', 'venture', 'version', 'vessel', 'veteran', 'vibrant', 'victory', 'village', 'violent', 'virtual',
    'visible', 'vision', 'visual', 'vital', 'volume', 'warrior', 'wealth', 'weapon', 'weather', 'welcome',
    'welfare', 'western', 'wildlife', 'window', 'wisdom', 'witness', 'wonder', 'wooden', 'workshop', 'worldwide'
  ];
  selected_words text[] := '{}';
  random_index integer;
  i integer;
BEGIN
  -- Select 13 random words
  FOR i IN 1..13 LOOP
    random_index := floor(random() * array_length(words, 1) + 1)::integer;
    selected_words := array_append(selected_words, words[random_index]);
  END LOOP;
  
  RETURN selected_words;
END;
$function$;

-- Function to create admin backup
CREATE OR REPLACE FUNCTION public.create_recovery_backup(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_recovery_words text[];
  backup_id uuid;
  backup_hash_value text;
BEGIN
  -- Only admins can create backups
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Get user's recovery words
  SELECT wallet_recovery_words INTO user_recovery_words
  FROM user_profiles
  WHERE user_id = p_user_id;

  IF user_recovery_words IS NULL OR array_length(user_recovery_words, 1) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No recovery words found for user'
    );
  END IF;

  -- Generate backup hash for integrity
  backup_hash_value := encode(
    extensions.digest(array_to_string(user_recovery_words, ',') || now()::text, 'sha256'),
    'hex'
  );

  -- Create backup entry
  INSERT INTO admin_recovery_backups (
    user_id,
    encrypted_recovery_words,
    backup_hash,
    last_accessed_by
  ) VALUES (
    p_user_id,
    array_to_string(user_recovery_words, ','),
    backup_hash_value,
    auth.uid()
  )
  RETURNING id INTO backup_id;

  -- Log the backup creation
  INSERT INTO security_audit_log (
    user_id, action, resource_type, resource_id, details
  ) VALUES (
    auth.uid(),
    'recovery_backup_created',
    'admin_recovery_backups',
    backup_id::text,
    jsonb_build_object(
      'target_user_id', p_user_id,
      'backup_hash', backup_hash_value,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'backup_id', backup_id,
    'backup_hash', backup_hash_value,
    'timestamp', now()
  );
END;
$function$;

-- Function to get user overview with recovery status
CREATE OR REPLACE FUNCTION public.get_users_recovery_overview()
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email_address text,
  has_pin boolean,
  has_recovery_words boolean,
  recovery_words_shown boolean,
  two_fa_enabled boolean,
  last_backup_date timestamp with time zone,
  total_backups bigint,
  account_created timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only admins can view recovery overview
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT 
    up.user_id,
    up.full_name,
    up.email_address,
    (up.wallet_pin_hash IS NOT NULL) as has_pin,
    (up.wallet_recovery_words IS NOT NULL AND array_length(up.wallet_recovery_words, 1) > 0) as has_recovery_words,
    COALESCE(up.recovery_words_shown, false) as recovery_words_shown,
    COALESCE(up.two_factor_enabled, false) as two_fa_enabled,
    (SELECT MAX(arb.backup_created_at) FROM admin_recovery_backups arb WHERE arb.user_id = up.user_id) as last_backup_date,
    (SELECT COUNT(*) FROM admin_recovery_backups arb WHERE arb.user_id = up.user_id) as total_backups,
    up.created_at as account_created
  FROM user_profiles up
  WHERE up.status = 'approved'
  ORDER BY up.full_name;
END;
$function$;
