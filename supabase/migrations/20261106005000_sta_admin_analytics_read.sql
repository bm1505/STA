-- Read-only admin visibility for analytics, support and audit screens.
drop policy if exists wallet_transactions_admin_select on public.wallet_transactions;
create policy wallet_transactions_admin_select on public.wallet_transactions
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists ride_ratings_admin_select on public.ride_ratings;
create policy ride_ratings_admin_select on public.ride_ratings
  for select to authenticated using (public.sta_is_active_admin());

drop policy if exists chat_messages_admin_select on public.chat_messages;
create policy chat_messages_admin_select on public.chat_messages
  for select to authenticated using (public.sta_is_active_admin());
