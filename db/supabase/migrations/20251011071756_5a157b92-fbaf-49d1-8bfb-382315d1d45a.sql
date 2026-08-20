-- Add RLS policies for ARX-related tables without policies

-- ARX Treasury Transactions: Admin-only access
CREATE POLICY "Admins can manage treasury transactions"
ON public.arx_treasury_transactions
FOR ALL
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ARX WNFT Registry: Members can view their own, admins can manage all
CREATE POLICY "Members can view own WNFT records"
ON public.arx_wnft_registry
FOR SELECT
TO authenticated
USING (
  member_id = (SELECT id FROM arx_club_members WHERE user_id = auth.uid())
  OR has_role(auth.uid(), 'admin'::app_role)
);

CREATE POLICY "Admins can manage WNFT records"
ON public.arx_wnft_registry
FOR ALL
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ARX Events: Public can view published events, admins can manage all
CREATE POLICY "Anyone can view published ARX events"
ON public.arx_events
FOR SELECT
TO authenticated
USING (status = 'published' OR has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can manage ARX events"
ON public.arx_events
FOR ALL
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ARX Event Attendees: Members can view/manage their own registrations, admins can view all
CREATE POLICY "Members can view own event registrations"
ON public.arx_event_attendees
FOR SELECT
TO authenticated
USING (
  member_id = (SELECT id FROM arx_club_members WHERE user_id = auth.uid())
  OR has_role(auth.uid(), 'admin'::app_role)
);

CREATE POLICY "Members can register for events"
ON public.arx_event_attendees
FOR INSERT
TO authenticated
WITH CHECK (member_id = (SELECT id FROM arx_club_members WHERE user_id = auth.uid()));

CREATE POLICY "Admins can manage event attendees"
ON public.arx_event_attendees
FOR ALL
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- ARX Legal Reports: Admin-only access
CREATE POLICY "Admins can manage legal reports"
ON public.arx_legal_reports
FOR ALL
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));