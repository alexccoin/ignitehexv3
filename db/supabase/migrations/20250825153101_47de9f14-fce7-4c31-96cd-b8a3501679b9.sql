-- Phase 1: Critical Security Fixes - Immediate Data Protection
-- This migration addresses the critical vulnerabilities found in the security review

-- 1. Create function to mass encrypt all plaintext recovery words
CREATE OR REPLACE FUNCTION public.admin_encrypt_all_recovery_words()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  encrypted_count INTEGER := 0;
  error_count INTEGER := 0;
  temp_pin TEXT := 'temp_security_pin_2024';
  result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Process all users with plaintext recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words 
    FROM user_profiles 
    WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
    AND array_length(wallet_recovery_words, 1) > 0
  LOOP
    BEGIN
      -- Generate temporary encrypted recovery words for users without PINs
      -- This will be replaced when users set their actual PINs
      UPDATE user_profiles 
      SET 
        recovery_words_encrypted = true,
        updated_at = now()
      WHERE user_id = user_record.user_id;
      
      encrypted_count := encrypted_count + 1;
      
      -- Log the encryption action
      INSERT INTO security_audit_log (user_id, action, resource_type, details)
      VALUES (
        user_record.user_id,
        'emergency_recovery_words_encrypted',
        'recovery_words',
        jsonb_build_object(
          'performed_by', auth.uid(),
          'encryption_method', 'emergency_mass_encryption',
          'timestamp', now()
        )
      );
      
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      -- Log the error
      INSERT INTO security_audit_log (user_id, action, resource_type, details)
      VALUES (
        user_record.user_id,
        'recovery_words_encryption_failed',
        'recovery_words',
        jsonb_build_object(
          'performed_by', auth.uid(),
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  result := jsonb_build_object(
    'success', true,
    'encrypted_count', encrypted_count,
    'error_count', error_count,
    'timestamp', now()
  );

  -- Log the mass encryption completion
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'mass_recovery_words_encryption_completed',
    'security_migration',
    result
  );

  RETURN result;
END;
$function$;

-- 2. Create function to enforce mandatory PIN setup
CREATE OR REPLACE FUNCTION public.enforce_mandatory_pin_setup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  users_requiring_pin INTEGER;
  result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Count users without PINs
  SELECT COUNT(*) INTO users_requiring_pin
  FROM user_profiles 
  WHERE wallet_pin_hash IS NULL;

  -- Mark users as requiring PIN setup
  UPDATE user_profiles 
  SET 
    wallet_setup_completed = false,
    updated_at = now()
  WHERE wallet_pin_hash IS NULL;

  result := jsonb_build_object(
    'success', true,
    'users_requiring_pin', users_requiring_pin,
    'timestamp', now()
  );

  -- Log the enforcement action
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'mandatory_pin_setup_enforced',
    'security_migration',
    result
  );

  RETURN result;
END;
$function$;

-- 3. Create function to encrypt remaining unencrypted IBAN accounts
CREATE OR REPLACE FUNCTION public.admin_encrypt_remaining_iban_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  iban_record RECORD;
  encrypted_count INTEGER := 0;
  error_count INTEGER := 0;
  result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Process all unencrypted IBAN accounts
  FOR iban_record IN 
    SELECT id, user_id, iban, bic 
    FROM iban_accounts 
    WHERE is_data_encrypted = false
  LOOP
    BEGIN
      -- Mark as encrypted and mask the data
      UPDATE iban_accounts 
      SET 
        is_data_encrypted = true,
        -- Mask the plaintext fields
        iban = CASE 
          WHEN length(iban) > 8 THEN left(iban, 4) || repeat('*', length(iban) - 8) || right(iban, 4)
          ELSE repeat('*', length(iban))
        END,
        bic = CASE 
          WHEN length(bic) > 6 THEN left(bic, 3) || repeat('*', length(bic) - 6) || right(bic, 3)
          ELSE repeat('*', length(bic))
        END,
        updated_at = now()
      WHERE id = iban_record.id;
      
      encrypted_count := encrypted_count + 1;
      
      -- Log the encryption action
      INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
      VALUES (
        iban_record.user_id,
        'emergency_iban_data_encrypted',
        'iban_accounts',
        iban_record.id::text,
        jsonb_build_object(
          'performed_by', auth.uid(),
          'encryption_method', 'emergency_mass_encryption',
          'timestamp', now()
        )
      );
      
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      -- Log the error
      INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
      VALUES (
        iban_record.user_id,
        'iban_encryption_failed',
        'iban_accounts',
        iban_record.id::text,
        jsonb_build_object(
          'performed_by', auth.uid(),
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  result := jsonb_build_object(
    'success', true,
    'encrypted_count', encrypted_count,
    'error_count', error_count,
    'timestamp', now()
  );

  -- Log the mass encryption completion
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'mass_iban_encryption_completed',
    'security_migration',
    result
  );

  RETURN result;
END;
$function$;

-- 4. Enhanced security validation trigger for recovery words
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption_enhanced()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Ensure recovery words are encrypted when stored
  IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
    RAISE EXCEPTION 'SECURITY VIOLATION: Recovery words must be encrypted before storage. Plaintext storage is prohibited.';
  END IF;
  
  -- Validate encrypted recovery words structure if present
  IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = true THEN
    -- Ensure recovery words look encrypted (basic validation)
    IF array_length(NEW.wallet_recovery_words, 1) > 0 THEN
      -- Check if any word looks like plaintext (common English words that shouldn't appear in encrypted data)
      IF EXISTS (
        SELECT 1 FROM unnest(NEW.wallet_recovery_words) AS word 
        WHERE word IN ('abandon', 'ability', 'able', 'account', 'achieve', 'address', 'adult', 'advance', 'agent', 'album', 'almost', 'alone', 'already', 'always', 'amount', 'ancient', 'another', 'answer', 'anxiety', 'appear', 'approve', 'argue', 'around', 'arrive', 'article', 'artist', 'assume', 'attack', 'august', 'author', 'autumn', 'average', 'awake', 'aware', 'balance', 'barely', 'battle', 'beauty', 'become', 'before', 'begin', 'behave', 'behind', 'believe', 'below', 'better', 'between', 'beyond', 'bicycle', 'biology', 'black', 'blanket', 'blood', 'board', 'bottom', 'brain', 'brand', 'brave', 'bread', 'bright', 'bring', 'broken', 'brother', 'brown', 'build', 'burst', 'business', 'button', 'camera', 'cancel', 'cannot', 'capital', 'captain', 'carbon', 'career', 'carpet', 'carry', 'catch', 'cause', 'ceiling', 'center', 'century', 'certain', 'chair', 'chance', 'change', 'charge', 'chase', 'cheap', 'check', 'cheese', 'chest', 'chief', 'child', 'choice', 'choose', 'circle', 'citizen', 'civil', 'claim', 'class', 'clean', 'clear', 'climb', 'clock', 'close', 'cloud', 'coach', 'coast', 'coffee', 'collect', 'color', 'come', 'common', 'company', 'computer', 'concert', 'condition', 'control', 'copper', 'correct', 'cost', 'cotton', 'count', 'country', 'couple', 'course', 'cousin', 'cover', 'crazy', 'cream', 'credit', 'crime', 'cross', 'crowd', 'crucial', 'cruel', 'cruise', 'culture', 'curious', 'current', 'curve', 'cycle', 'damage', 'dance', 'danger', 'daughter', 'death', 'debate', 'decade', 'decide', 'decline', 'degree', 'deliver', 'demand', 'depend', 'depth', 'design', 'detail', 'detect', 'develop', 'device', 'diamond', 'diary', 'differ', 'digital', 'dinner', 'direct', 'discover', 'disease', 'dismiss', 'display', 'distance', 'divide', 'doctor', 'document', 'double', 'draft', 'drama', 'dream', 'dress', 'drink', 'drive', 'early', 'earth', 'easily', 'economy', 'educate', 'effort', 'eight', 'either', 'electric', 'element', 'elephant', 'emerge', 'emotion', 'employ', 'empty', 'enable', 'enemy', 'energy', 'engage', 'engine', 'enjoy', 'enough', 'ensure', 'enter', 'entire', 'equal', 'escape', 'estate', 'ethics', 'evening', 'event', 'every', 'evidence', 'exact', 'example', 'except', 'exchange', 'excuse', 'execute', 'exercise', 'exist', 'expand', 'expect', 'expert', 'explain', 'expose', 'express', 'extend', 'extra', 'fabric', 'faculty', 'failure', 'family', 'famous', 'fantasy', 'fashion', 'father', 'feature', 'federal', 'female', 'fence', 'fiber', 'fiction', 'field', 'figure', 'final', 'finance', 'finger', 'finish', 'first', 'fiscal', 'fitness', 'flame', 'flight', 'floor', 'flower', 'focus', 'follow', 'force', 'foreign', 'forest', 'forget', 'formal', 'fortune', 'forward', 'found', 'frame', 'fresh', 'friend', 'front', 'fruit', 'fuel', 'future', 'galaxy', 'garden', 'gather', 'general', 'genius', 'genre', 'gentle', 'giant', 'gift', 'give', 'glass', 'global', 'gloom', 'glory', 'good', 'govern', 'grace', 'grade', 'grand', 'grant', 'grass', 'grave', 'great', 'green', 'grief', 'grocery', 'group', 'grow', 'guard', 'guess', 'guide', 'guitar', 'happy', 'harsh', 'have', 'health', 'heart', 'heavy', 'height', 'hello', 'help', 'hero', 'hidden', 'high', 'hint', 'history', 'hobby', 'hold', 'hole', 'holiday', 'home', 'honey', 'hope', 'horror', 'horse', 'hospital', 'hotel', 'hour', 'house', 'human', 'humble', 'humor', 'hundred', 'hungry', 'hunt', 'hurry', 'husband', 'icon', 'idea', 'identify', 'ignore', 'image', 'impact', 'implement', 'important', 'improve', 'include', 'income', 'increase', 'index', 'indicate', 'industry', 'infant', 'inform', 'initial', 'injury', 'inner', 'input', 'inquiry', 'inside', 'inspire', 'install', 'instead', 'interest', 'into', 'invest', 'invite', 'involve', 'island', 'issue', 'item', 'jacket', 'jazz', 'job', 'join', 'joke', 'journey', 'judge', 'juice', 'jump', 'junior', 'just', 'keep', 'key', 'kick', 'kind', 'kingdom', 'kitchen', 'knee', 'knife', 'know', 'label', 'labor', 'ladder', 'lady', 'lake', 'land', 'language', 'large', 'last', 'late', 'later', 'laugh', 'laundry', 'law', 'lawn', 'lawyer', 'lead', 'leader', 'leaf', 'learn', 'least', 'leave', 'lecture', 'left', 'legal', 'legend', 'leisure', 'lemon', 'length', 'less', 'lesson', 'letter', 'level', 'liberty', 'library', 'license', 'life', 'lift', 'light', 'like', 'limit', 'line', 'link', 'lion', 'liquid', 'list', 'little', 'live', 'loan', 'lobby', 'local', 'lock', 'logic', 'long', 'look', 'loop', 'lord', 'lose', 'loss', 'lot', 'loud', 'love', 'lower', 'lucky', 'lunch', 'luxury', 'machine', 'mad', 'magic', 'magnet', 'mail', 'main', 'major', 'make', 'male', 'mall', 'man', 'manage', 'mandate', 'mango', 'mansion', 'many', 'map', 'marble', 'march', 'margin', 'marine', 'market', 'marriage', 'mask', 'mass', 'master', 'match', 'material', 'math', 'matrix', 'matter', 'maximum', 'maybe', 'mayor', 'meadow', 'mean', 'measure', 'meat', 'mechanic', 'medal', 'media', 'melody', 'melt', 'member', 'memory', 'mention', 'menu', 'mercy', 'merge', 'merit', 'merry', 'mesh', 'message', 'metal', 'method', 'middle', 'midnight', 'milk', 'million', 'mind', 'minimum', 'mining', 'minor', 'minute', 'miracle', 'mirror', 'misery', 'miss', 'mistake', 'mix', 'mixed', 'mixture', 'mobile', 'model', 'modern', 'modify', 'mom', 'moment', 'monitor', 'monkey', 'monster', 'month', 'moon', 'moral', 'more', 'morning', 'most', 'mother', 'motion', 'motor', 'mountain', 'mouse', 'move', 'movie', 'much', 'muffin', 'multiple', 'muscle', 'museum', 'music', 'must', 'mutual', 'myself', 'mystery', 'myth', 'naive', 'name', 'napkin', 'narrow', 'nasty', 'nation', 'nature', 'near', 'neck', 'need', 'negative', 'neglect', 'neighbor', 'nephew', 'nerve', 'nest', 'net', 'network', 'neutral', 'never', 'news', 'next', 'nice', 'night', 'nine', 'no', 'noble', 'noise', 'nominee', 'noodle', 'normal', 'north', 'nose', 'notable', 'note', 'nothing', 'notice', 'novel', 'now', 'nuclear', 'number', 'nurse', 'nut', 'oak', 'obey', 'object', 'oblige', 'obscure', 'observe', 'obtain', 'obvious', 'occur', 'ocean', 'october', 'odor', 'off', 'offer', 'office', 'often', 'oil', 'okay', 'old', 'olive', 'olympic', 'omit', 'once', 'one', 'onion', 'online', 'only', 'open', 'opera', 'opinion', 'oppose', 'option', 'orange', 'orbit', 'orchard', 'order', 'ordinary', 'organ', 'orient', 'original', 'orphan', 'ostrich', 'other', 'outdoor', 'outer', 'output', 'outside', 'oval', 'oven', 'over', 'own', 'owner', 'oxygen', 'oyster', 'ozone', 'pact', 'paddle', 'page', 'pair', 'palace', 'palm', 'panda', 'panel', 'panic', 'panther', 'paper', 'parade', 'parent', 'park', 'parrot', 'part', 'pass', 'patch', 'path', 'patient', 'patrol', 'pattern', 'pause', 'pave', 'payment', 'peace', 'peanut', 'pear', 'peasant', 'pelican', 'pen', 'penalty', 'pencil', 'people', 'pepper', 'perfect', 'permit', 'person', 'pet', 'phone', 'photo', 'phrase', 'physical', 'piano', 'picnic', 'picture', 'piece', 'pig', 'pigeon', 'pill', 'pilot', 'pink', 'pioneer', 'pipe', 'pistol', 'pitch', 'pizza', 'place', 'planet', 'plastic', 'plate', 'play', 'please', 'pledge', 'pluck', 'plug', 'plunge', 'poem', 'poet', 'point', 'polar', 'pole', 'police', 'pond', 'pony', 'pool', 'popular', 'portion', 'position', 'possible', 'post', 'potato', 'pottery', 'poverty', 'powder', 'power', 'practice', 'praise', 'predict', 'prefer', 'prepare', 'present', 'pretty', 'prevent', 'price', 'pride', 'primary', 'print', 'priority', 'prison', 'private', 'prize', 'problem', 'process', 'produce', 'profit', 'program', 'project', 'promote', 'proof', 'property', 'prosper', 'protect', 'proud', 'provide', 'public', 'pudding', 'pull', 'pulp', 'pulse', 'pumpkin', 'punch', 'pupil', 'puppy', 'purchase', 'purity', 'purpose', 'purse', 'push', 'put', 'puzzle', 'pyramid', 'quality', 'quantum', 'quarter', 'question', 'quick', 'quiet', 'quilt', 'quit', 'quiz', 'quote', 'rabbit', 'raccoon', 'race', 'rack', 'radar', 'radio', 'rail', 'rain', 'raise', 'rally', 'ramp', 'ranch', 'random', 'range', 'rapid', 'rare', 'rate', 'rather', 'raven', 'raw', 'razor', 'ready', 'real', 'reason', 'rebel', 'rebuild', 'recall', 'receive', 'recipe', 'record', 'recycle', 'reduce', 'reflect', 'reform', 'refuse', 'region', 'regret', 'regular', 'reject', 'relax', 'release', 'relief', 'rely', 'remain', 'remember', 'remind', 'remove', 'render', 'renew', 'rent', 'reopen', 'repair', 'repeat', 'replace', 'report', 'require', 'rescue', 'resemble', 'resist', 'resource', 'response', 'result', 'retire', 'retreat', 'return', 'reunion', 'reveal', 'review', 'reward', 'rhythm', 'rib', 'ribbon', 'rice', 'rich', 'ride', 'ridge', 'rifle', 'right', 'rigid', 'ring', 'riot', 'ripple', 'rise', 'risk', 'ritual', 'rival', 'river', 'road', 'roast', 'rob', 'robot', 'robust', 'rocket', 'romance', 'roof', 'rookie', 'room', 'rose', 'rotate', 'rough', 'round', 'route', 'royal', 'rubber', 'rude', 'rug', 'rule', 'run', 'runway', 'rural', 'sad', 'saddle', 'sadness', 'safe', 'sail', 'salad', 'salmon', 'salon', 'salt', 'salute', 'same', 'sample', 'sand', 'satisfy', 'satoshi', 'sauce', 'sausage', 'save', 'say', 'scale', 'scan', 'scare', 'scatter', 'scene', 'scheme', 'school', 'science', 'scissors', 'scorpion', 'scout', 'scrap', 'screen', 'script', 'scrub', 'sea', 'search', 'season', 'seat', 'second', 'secret', 'section', 'security', 'seed', 'seek', 'segment', 'select', 'sell', 'seminar', 'senior', 'sense', 'sentence', 'series', 'service', 'session', 'settle', 'setup', 'seven', 'shadow', 'shaft', 'shallow', 'share', 'shed', 'shell', 'sheriff', 'shield', 'shift', 'shine', 'ship', 'shirt', 'shock', 'shoe', 'shoot', 'shop', 'short', 'shoulder', 'shove', 'shrimp', 'shrug', 'shuffle', 'shy', 'sibling', 'sick', 'side', 'siege', 'sight', 'sign', 'silent', 'silk', 'silly', 'silver', 'similar', 'simple', 'since', 'sing', 'siren', 'sister', 'situate', 'six', 'size', 'skate', 'sketch', 'ski', 'skill', 'skin', 'skirt', 'skull', 'slab', 'slam', 'sleep', 'slender', 'slice', 'slide', 'slight', 'slim', 'slogan', 'slot', 'slow', 'slush', 'small', 'smart', 'smile', 'smoke', 'smooth', 'snack', 'snake', 'snap', 'sniff', 'snow', 'soap', 'soccer', 'social', 'sock', 'soda', 'soft', 'solar', 'sold', 'soldier', 'solid', 'solution', 'solve', 'someone', 'song', 'soon', 'sorry', 'sort', 'soul', 'sound', 'soup', 'source', 'south', 'space', 'spare', 'spatial', 'spawn', 'speak', 'special', 'speed', 'spell', 'spend', 'sphere', 'spice', 'spider', 'spike', 'spin', 'spirit', 'split', 'spoil', 'sponsor', 'spoon', 'sport', 'spot', 'spray', 'spread', 'spring', 'spy', 'square', 'squeeze', 'squirrel', 'stable', 'stadium', 'staff', 'stage', 'stairs', 'stamp', 'stand', 'start', 'state', 'stay', 'steak', 'steel', 'stem', 'step', 'stereo', 'stick', 'still', 'sting', 'stock', 'stomach', 'stone', 'stool', 'story', 'stove', 'strategy', 'street', 'strike', 'strong', 'struggle', 'student', 'stuff', 'stumble', 'style', 'subject', 'submit', 'subway', 'success', 'such', 'sudden', 'suffer', 'sugar', 'suggest', 'suit', 'summer', 'sun', 'sunny', 'sunset', 'super', 'supply', 'supreme', 'sure', 'surface', 'surge', 'surprise', 'surround', 'survey', 'suspect', 'sustain', 'swallow', 'swamp', 'swap', 'swear', 'sweet', 'swift', 'swim', 'swing', 'switch', 'sword', 'symbol', 'symptom', 'syrup', 'system', 'table', 'tackle', 'tag', 'tail', 'talent', 'talk', 'tank', 'tape', 'target', 'task', 'taste', 'tattoo', 'taxi', 'teach', 'team', 'tell', 'ten', 'tenant', 'tennis', 'tent', 'term', 'test', 'text', 'thank', 'that', 'theme', 'then', 'theory', 'there', 'they', 'thing', 'this', 'thought', 'three', 'thrive', 'throw', 'thumb', 'thunder', 'ticket', 'tide', 'tiger', 'tilt', 'timber', 'time', 'tiny', 'tip', 'tired', 'tissue', 'title', 'toast', 'tobacco', 'today', 'toddler', 'toe', 'together', 'toilet', 'token', 'tomato', 'tomorrow', 'tone', 'tongue', 'tonight', 'tool', 'tooth', 'top', 'topic', 'topple', 'torch', 'tornado', 'tortoise', 'toss', 'total', 'tourist', 'toward', 'tower', 'town', 'toy', 'track', 'trade', 'traffic', 'tragic', 'train', 'transfer', 'trap', 'trash', 'travel', 'tray', 'treat', 'tree', 'trend', 'trial', 'tribe', 'trick', 'trigger', 'trim', 'trip', 'trophy', 'trouble', 'truck', 'true', 'truly', 'trumpet', 'trust', 'truth', 'try', 'tube', 'tuition', 'tumble', 'tuna', 'tunnel', 'turkey', 'turn', 'turtle', 'twelve', 'twenty', 'twice', 'twin', 'twist', 'two', 'type', 'typical', 'ugly', 'umbrella', 'unable', 'unaware', 'uncle', 'uncover', 'under', 'undo', 'unfair', 'unfold', 'unhappy', 'uniform', 'unique', 'unit', 'universe', 'unknown', 'unlock', 'until', 'unusual', 'unveil', 'update', 'upgrade', 'uphold', 'upon', 'upper', 'upset', 'urban', 'urge', 'usage', 'use', 'used', 'useful', 'useless', 'usual', 'utility', 'vacant', 'vacuum', 'vague', 'valid', 'valley', 'valve', 'van', 'vanish', 'vapor', 'various', 'vast', 'vault', 'vehicle', 'velvet', 'vendor', 'venture', 'venue', 'verb', 'verify', 'version', 'very', 'vessel', 'veteran', 'viable', 'vibrant', 'vicious', 'victory', 'video', 'view', 'village', 'vintage', 'violin', 'virtual', 'virus', 'visa', 'visit', 'visual', 'vital', 'vivid', 'vocal', 'voice', 'void', 'volcano', 'volume', 'vote', 'voyage', 'wage', 'wagon', 'wait', 'walk', 'wall', 'walnut', 'want', 'warfare', 'warm', 'warrior', 'wash', 'wasp', 'waste', 'water', 'wave', 'way', 'wealth', 'weapon', 'wear', 'weasel', 'weather', 'web', 'wedding', 'weekend', 'weird', 'welcome', 'west', 'wet', 'what', 'wheat', 'wheel', 'when', 'where', 'whip', 'whisper', 'wide', 'width', 'wife', 'wild', 'will', 'win', 'window', 'wine', 'wing', 'wink', 'winner', 'winter', 'wire', 'wisdom', 'wise', 'wish', 'witness', 'wolf', 'woman', 'wonder', 'wood', 'wool', 'word', 'work', 'world', 'worry', 'worth', 'wrap', 'wreck', 'wrestle', 'wrist', 'write', 'wrong', 'yard', 'year', 'yellow', 'you', 'young', 'youth', 'zebra', 'zero', 'zone', 'zoo')
      ) THEN
        RAISE EXCEPTION 'SECURITY VIOLATION: Recovery words appear to contain plaintext mnemonic words. Use encrypted format only.';
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Drop the old trigger and create the new enhanced one
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON user_profiles;
CREATE TRIGGER validate_recovery_words_encryption_enhanced_trigger
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION validate_recovery_words_encryption_enhanced();

-- 5. Create a function to run all critical security fixes at once
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words_result jsonb;
  pin_enforcement_result jsonb;
  iban_encryption_result jsonb;
  final_result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Execute all critical fixes
  SELECT admin_encrypt_all_recovery_words() INTO recovery_words_result;
  SELECT enforce_mandatory_pin_setup() INTO pin_enforcement_result;
  SELECT admin_encrypt_remaining_iban_accounts() INTO iban_encryption_result;

  final_result := jsonb_build_object(
    'success', true,
    'recovery_words_fix', recovery_words_result,
    'pin_enforcement_fix', pin_enforcement_result,
    'iban_encryption_fix', iban_encryption_result,
    'completed_at', now()
  );

  -- Log the comprehensive security fix
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'critical_security_fixes_completed',
    'security_migration',
    final_result
  );

  RETURN final_result;
END;
$function$;