-- Update the governance functions to include notification system

-- Function to send notification to all users when proposal is approved
CREATE OR REPLACE FUNCTION notify_all_users_proposal_approved(proposal_id uuid, proposal_title text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_record RECORD;
  notification_id uuid;
BEGIN
  -- Loop through all users and send notification
  FOR user_record IN SELECT user_id FROM user_profiles LOOP
    INSERT INTO user_messages (
      sender_id,
      recipient_id,
      subject,
      message,
      message_type,
      is_popup_shown
    ) VALUES (
      '00000000-0000-0000-0000-000000000001', -- System sender
      user_record.user_id,
      'Governance Proposal Approved!',
      'A governance proposal "' || proposal_title || '" has been approved by the community! Rewards will be distributed shortly.',
      'success',
      false -- Will trigger popup
    );
  END LOOP;
END;
$$;

-- Update the submit governance vote function to include auto-approval logic
CREATE OR REPLACE FUNCTION submit_governance_vote(proposal_id uuid, support_vote boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_voting_power numeric;
  proposal_record governance_proposals%ROWTYPE;
  new_vote_count integer;
  new_support_votes integer;
BEGIN
  -- Get current user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Calculate user voting power (domains + staked amounts)
  SELECT 
    COALESCE(
      (SELECT SUM(staked_amount) FROM user_staking_pools WHERE user_id = auth.uid()),
      0
    ) + 
    CASE 
      WHEN EXISTS(SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND str_domain_owned IS NOT NULL AND str_domain_owned != '') 
      THEN 100 
      ELSE 0 
    END
  INTO user_voting_power;

  -- Insert the vote
  INSERT INTO governance_votes (
    user_id,
    proposal_id,
    support,
    voting_power
  ) VALUES (
    auth.uid(),
    proposal_id,
    support_vote,
    user_voting_power
  )
  ON CONFLICT (user_id, proposal_id) DO UPDATE SET
    support = EXCLUDED.support,
    voting_power = EXCLUDED.voting_power,
    created_at = now();

  -- Update proposal vote counts
  SELECT 
    COUNT(*) as total_votes,
    SUM(CASE WHEN support = true THEN 1 ELSE 0 END) as support_votes
  INTO new_vote_count, new_support_votes
  FROM governance_votes 
  WHERE proposal_id = submit_governance_vote.proposal_id;

  UPDATE governance_proposals 
  SET 
    vote_count = new_vote_count,
    support_votes = new_support_votes,
    updated_at = now()
  WHERE id = proposal_id;

  -- Get updated proposal
  SELECT * INTO proposal_record FROM governance_proposals WHERE id = proposal_id;

  -- Auto-approve if majority support and enough votes
  IF proposal_record.status = 'pending' AND 
     new_vote_count >= 10 AND 
     new_support_votes > (new_vote_count / 2) THEN
    
    UPDATE governance_proposals 
    SET status = 'approved', updated_at = now() 
    WHERE id = proposal_id;
    
    -- Send notifications to all users
    PERFORM notify_all_users_proposal_approved(proposal_id, proposal_record.title);
    
    -- Award domains based on vote count
    IF new_vote_count >= 1000 THEN
      INSERT INTO governance_domain_rewards (proposal_id, user_id, domains_awarded, reward_tier)
      VALUES (proposal_id, proposal_record.created_by, 1000, 'tier_1');
    ELSIF new_vote_count >= 500 THEN
      INSERT INTO governance_domain_rewards (proposal_id, user_id, domains_awarded, reward_tier)
      VALUES (proposal_id, proposal_record.created_by, 500, 'tier_2');
    ELSIF new_vote_count >= 100 THEN
      INSERT INTO governance_domain_rewards (proposal_id, user_id, domains_awarded, reward_tier)
      VALUES (proposal_id, proposal_record.created_by, 100, 'tier_3');
    END IF;
  END IF;
END;
$$;