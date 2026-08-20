-- Allow voucher-based redemptions to be recorded explicitly
ALTER TABLE public.voucher_redemptions
  DROP CONSTRAINT IF EXISTS voucher_redemptions_payment_type_check;

ALTER TABLE public.voucher_redemptions
  ADD CONSTRAINT voucher_redemptions_payment_type_check
  CHECK (
    payment_type = ANY (
      ARRAY[
        'crypto'::text,
        'bank'::text,
        'card'::text,
        'voucher'::text
      ]
    )
  );
