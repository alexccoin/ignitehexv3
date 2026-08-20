
-- Enable realtime for starw_nodes table
ALTER TABLE public.starw_nodes REPLICA IDENTITY FULL;

-- Add starw_nodes to realtime publication if not already added
DO $$
BEGIN
  -- Check if the table is already in the publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'starw_nodes'
  ) THEN
    -- Add table to publication
    ALTER PUBLICATION supabase_realtime ADD TABLE public.starw_nodes;
  END IF;
END $$;
