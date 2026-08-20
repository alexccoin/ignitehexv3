-- Create storage bucket for backups if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('backups', 'backups', false)
ON CONFLICT (id) DO NOTHING;

-- Create RLS policies for backup storage
CREATE POLICY "Admin users can view all backup files" ON storage.objects
FOR SELECT USING (
  bucket_id = 'backups' 
  AND is_admin(auth.uid())
);

CREATE POLICY "Admin users can upload backup files" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'backups' 
  AND is_admin(auth.uid())
);

CREATE POLICY "Admin users can update backup files" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'backups' 
  AND is_admin(auth.uid())
);

CREATE POLICY "Admin users can delete backup files" ON storage.objects
FOR DELETE USING (
  bucket_id = 'backups' 
  AND is_admin(auth.uid())
);

-- Create backup metadata table to track all backups
CREATE TABLE IF NOT EXISTS public.backup_metadata (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_name TEXT NOT NULL,
  backup_type TEXT NOT NULL, -- 'full', 'staking', 'daily'
  file_formats TEXT[] NOT NULL, -- ['json', 'csv', 'sql']
  file_paths JSONB NOT NULL, -- {json: 'path', csv: 'path', sql: 'path'}
  total_tables INTEGER NOT NULL DEFAULT 0,
  total_records INTEGER NOT NULL DEFAULT 0,
  backup_size_mb NUMERIC DEFAULT 0,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ DEFAULT (now() + INTERVAL '90 days'),
  download_count INTEGER DEFAULT 0,
  last_downloaded_at TIMESTAMPTZ,
  status TEXT DEFAULT 'completed',
  metadata JSONB DEFAULT '{}'
);

-- Enable RLS on backup metadata
ALTER TABLE public.backup_metadata ENABLE ROW LEVEL SECURITY;

-- RLS policies for backup metadata
CREATE POLICY "Admin users can manage backup metadata" ON public.backup_metadata
FOR ALL USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Add indexes for performance
CREATE INDEX idx_backup_metadata_type ON backup_metadata(backup_type);
CREATE INDEX idx_backup_metadata_created ON backup_metadata(created_at DESC);
CREATE INDEX idx_backup_metadata_status ON backup_metadata(status);