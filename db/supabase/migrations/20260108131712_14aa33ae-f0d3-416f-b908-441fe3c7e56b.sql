-- Allow vanquish token type for voucher redemptions
ALTER TABLE public.voucher_redemptions
  DROP CONSTRAINT IF EXISTS voucher_redemptions_token_type_check;

ALTER TABLE public.voucher_redemptions
  ADD CONSTRAINT voucher_redemptions_token_type_check
  CHECK (
    token_type = ANY (
      ARRAY[
        'str'::text,
        'ccos'::text,
        'arss'::text,
        'vanquish'::text
      ]
    )
  );