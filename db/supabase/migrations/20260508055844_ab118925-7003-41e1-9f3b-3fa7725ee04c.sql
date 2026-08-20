-- Enforce strict 60-day vesting lock on Pre-CEX STR voucher pools
CREATE OR REPLACE FUNCTION public.enforce_precex_str_voucher_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only enforce on pools tagged as Pre-CEX STR voucher vesting
  IF TG_OP = 'DELETE' THEN
    IF OLD.admin_notes LIKE 'precex_str_voucher_60d_vesting%'
       AND COALESCE(OLD.lock_end_date, NOW() + INTERVAL '1 day') > NOW() THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher pool is locked until % and cannot be deleted', OLD.lock_end_date;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.admin_notes LIKE 'precex_str_voucher_60d_vesting%'
     AND COALESCE(OLD.lock_end_date, NOW() + INTERVAL '1 day') > NOW() THEN

    -- Disallow ANY change to staked principal / balance / status / lock / type while locked
    IF COALESCE(NEW.balance, 0) <> COALESCE(OLD.balance, 0) THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher tokens are vesting until %. Balance cannot be modified.', OLD.lock_end_date;
    END IF;
    IF COALESCE(NEW.staked_amount, 0) <> COALESCE(OLD.staked_amount, 0) THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher tokens are vesting until %. Staked amount cannot be modified.', OLD.lock_end_date;
    END IF;
    IF COALESCE(NEW.status, '') <> COALESCE(OLD.status, '') THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher pool status is locked until %.', OLD.lock_end_date;
    END IF;
    IF COALESCE(NEW.lock_end_date, OLD.lock_end_date) < OLD.lock_end_date THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher lock end date cannot be shortened.';
    END IF;
    IF NEW.pool_type <> OLD.pool_type THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher pool type is immutable while locked.';
    END IF;
    IF COALESCE(NEW.apy_rate, 0) <> 0 THEN
      RAISE EXCEPTION 'Pre-CEX STR voucher pools must remain at 0%% APY (vesting only).';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_precex_str_voucher_lock ON public.user_staking_pools;
CREATE TRIGGER trg_enforce_precex_str_voucher_lock
BEFORE UPDATE OR DELETE ON public.user_staking_pools
FOR EACH ROW
EXECUTE FUNCTION public.enforce_precex_str_voucher_lock();