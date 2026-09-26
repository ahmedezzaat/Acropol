-- 0021 dropped complete_deal_activity_with_followup to change its
-- parameters, which silently drops any grants tied to the old function
-- object — re-granting here since that was missed in the same migration.
grant execute on function public.complete_deal_activity_with_followup(uuid, text, text, timestamptz) to authenticated;
