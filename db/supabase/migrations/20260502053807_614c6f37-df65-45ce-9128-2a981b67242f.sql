ALTER TABLE public.str_dome_requests
  ADD COLUMN IF NOT EXISTS deliver_to_wallet boolean NOT NULL DEFAULT false;

ALTER TABLE public.str_dome_requests
  ALTER COLUMN delivery_email DROP NOT NULL;