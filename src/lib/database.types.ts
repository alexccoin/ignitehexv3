export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      admin_approval_queue: {
        Row: {
          approved_at: string | null
          approving_admin: string | null
          executed_at: string | null
          expires_at: string | null
          id: string
          operation_details: Json
          operation_type: string
          requested_at: string
          requesting_admin: string
          risk_level: string | null
          status: string | null
          target_user_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approving_admin?: string | null
          executed_at?: string | null
          expires_at?: string | null
          id?: string
          operation_details: Json
          operation_type: string
          requested_at?: string
          requesting_admin: string
          risk_level?: string | null
          status?: string | null
          target_user_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approving_admin?: string | null
          executed_at?: string | null
          expires_at?: string | null
          id?: string
          operation_details?: Json
          operation_type?: string
          requested_at?: string
          requesting_admin?: string
          risk_level?: string | null
          status?: string | null
          target_user_id?: string | null
        }
        Relationships: []
      }
      admin_recovery_backups: {
        Row: {
          backup_created_at: string
          backup_hash: string
          created_at: string
          encrypted_recovery_words: string
          id: string
          last_accessed_at: string | null
          last_accessed_by: string | null
          user_id: string
        }
        Insert: {
          backup_created_at?: string
          backup_hash: string
          created_at?: string
          encrypted_recovery_words: string
          id?: string
          last_accessed_at?: string | null
          last_accessed_by?: string | null
          user_id: string
        }
        Update: {
          backup_created_at?: string
          backup_hash?: string
          created_at?: string
          encrypted_recovery_words?: string
          id?: string
          last_accessed_at?: string | null
          last_accessed_by?: string | null
          user_id?: string
        }
        Relationships: []
      }
      admin_session_log: {
        Row: {
          actions_performed: number | null
          admin_user_id: string
          id: string
          ip_address: unknown
          is_active: boolean | null
          login_at: string
          logout_at: string | null
          risk_score: number | null
          sensitive_operations: Json | null
          session_token: string | null
          user_agent: string | null
        }
        Insert: {
          actions_performed?: number | null
          admin_user_id: string
          id?: string
          ip_address?: unknown
          is_active?: boolean | null
          login_at?: string
          logout_at?: string | null
          risk_score?: number | null
          sensitive_operations?: Json | null
          session_token?: string | null
          user_agent?: string | null
        }
        Update: {
          actions_performed?: number | null
          admin_user_id?: string
          id?: string
          ip_address?: unknown
          is_active?: boolean | null
          login_at?: string
          logout_at?: string | null
          risk_score?: number | null
          sensitive_operations?: Json | null
          session_token?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      ai_usage_sessions: {
        Row: {
          compute_cost: number
          duration_seconds: number | null
          ended_at: string | null
          id: string
          session_type: string
          started_at: string
          status: string
          tokens_used: number
          user_id: string
        }
        Insert: {
          compute_cost?: number
          duration_seconds?: number | null
          ended_at?: string | null
          id?: string
          session_type: string
          started_at?: string
          status?: string
          tokens_used?: number
          user_id: string
        }
        Update: {
          compute_cost?: number
          duration_seconds?: number | null
          ended_at?: string | null
          id?: string
          session_type?: string
          started_at?: string
          status?: string
          tokens_used?: number
          user_id?: string
        }
        Relationships: []
      }
      airdrop_registrations: {
        Row: {
          admin_notes: string | null
          created_at: string
          credited_amount: number | null
          credited_at: string | null
          email_address: string
          event_type: string | null
          full_name: string
          id: string
          processed_at: string | null
          processed_by: string | null
          requested_amount: number
          status: string
          tokens_credited: boolean | null
          updated_at: string
          user_id: string
          voucher_id: string | null
          voucher_type: string | null
          wallet_address: string
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          email_address: string
          event_type?: string | null
          full_name: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          requested_amount?: number
          status?: string
          tokens_credited?: boolean | null
          updated_at?: string
          user_id: string
          voucher_id?: string | null
          voucher_type?: string | null
          wallet_address: string
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          email_address?: string
          event_type?: string | null
          full_name?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          requested_amount?: number
          status?: string
          tokens_credited?: boolean | null
          updated_at?: string
          user_id?: string
          voucher_id?: string | null
          voucher_type?: string | null
          wallet_address?: string
        }
        Relationships: [
          {
            foreignKeyName: "airdrop_registrations_voucher_id_fkey"
            columns: ["voucher_id"]
            isOneToOne: false
            referencedRelation: "voucher_redemptions"
            referencedColumns: ["id"]
          },
        ]
      }
      api_access_logs: {
        Row: {
          api_key_hash: string
          created_at: string
          endpoint: string
          id: string
          ip_address: unknown
          method: string
          request_params: Json | null
          response_status: number | null
          user_agent: string | null
        }
        Insert: {
          api_key_hash: string
          created_at?: string
          endpoint: string
          id?: string
          ip_address?: unknown
          method: string
          request_params?: Json | null
          response_status?: number | null
          user_agent?: string | null
        }
        Update: {
          api_key_hash?: string
          created_at?: string
          endpoint?: string
          id?: string
          ip_address?: unknown
          method?: string
          request_params?: Json | null
          response_status?: number | null
          user_agent?: string | null
        }
        Relationships: []
      }
      api_rate_limits: {
        Row: {
          api_key_hash: string
          created_at: string
          id: string
          ip_address: unknown
          request_count: number
          updated_at: string
          window_start: string
        }
        Insert: {
          api_key_hash: string
          created_at?: string
          id?: string
          ip_address?: unknown
          request_count?: number
          updated_at?: string
          window_start?: string
        }
        Update: {
          api_key_hash?: string
          created_at?: string
          id?: string
          ip_address?: unknown
          request_count?: number
          updated_at?: string
          window_start?: string
        }
        Relationships: []
      }
      arss_token_purchases: {
        Row: {
          admin_notes: string | null
          arss_amount: number
          arss_price_at_purchase: number
          bonus_amount: number | null
          bonus_percent: number | null
          created_at: string
          credited_at: string | null
          credited_by: string | null
          crypto_amount: number
          crypto_currency: string
          crypto_price_at_purchase: number
          email: string
          full_name: string | null
          id: string
          payment_address: string
          status: string
          total_arss_amount: number
          transaction_hash: string | null
          updated_at: string
          usd_amount: number
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          arss_amount: number
          arss_price_at_purchase: number
          bonus_amount?: number | null
          bonus_percent?: number | null
          created_at?: string
          credited_at?: string | null
          credited_by?: string | null
          crypto_amount: number
          crypto_currency: string
          crypto_price_at_purchase: number
          email: string
          full_name?: string | null
          id?: string
          payment_address: string
          status?: string
          total_arss_amount: number
          transaction_hash?: string | null
          updated_at?: string
          usd_amount: number
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          arss_amount?: number
          arss_price_at_purchase?: number
          bonus_amount?: number | null
          bonus_percent?: number | null
          created_at?: string
          credited_at?: string | null
          credited_by?: string | null
          crypto_amount?: number
          crypto_currency?: string
          crypto_price_at_purchase?: number
          email?: string
          full_name?: string | null
          id?: string
          payment_address?: string
          status?: string
          total_arss_amount?: number
          transaction_hash?: string | null
          updated_at?: string
          usd_amount?: number
          user_id?: string
        }
        Relationships: []
      }
      arss_transactions: {
        Row: {
          amount: number
          created_at: string
          currency: string | null
          description: string
          id: string
          source_id: string | null
          source_type: string
          status: string
          transaction_hash: string | null
          transaction_type: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          currency?: string | null
          description: string
          id?: string
          source_id?: string | null
          source_type: string
          status?: string
          transaction_hash?: string | null
          transaction_type: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          currency?: string | null
          description?: string
          id?: string
          source_id?: string | null
          source_type?: string
          status?: string
          transaction_hash?: string | null
          transaction_type?: string
          user_id?: string
        }
        Relationships: []
      }
      arx_applications: {
        Row: {
          admin_notes: string | null
          application_date: string
          charter_accepted_at: string | null
          created_at: string
          email: string
          full_name: string
          gdpr_accepted_at: string | null
          id: string
          ip_address: unknown
          location_data: Json | null
          metadata: Json | null
          nda_accepted_at: string | null
          processed_at: string | null
          processed_by: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          application_date?: string
          charter_accepted_at?: string | null
          created_at?: string
          email: string
          full_name: string
          gdpr_accepted_at?: string | null
          id?: string
          ip_address?: unknown
          location_data?: Json | null
          metadata?: Json | null
          nda_accepted_at?: string | null
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          application_date?: string
          charter_accepted_at?: string | null
          created_at?: string
          email?: string
          full_name?: string
          gdpr_accepted_at?: string | null
          id?: string
          ip_address?: unknown
          location_data?: Json | null
          metadata?: Json | null
          nda_accepted_at?: string | null
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      arx_audit_trail: {
        Row: {
          action_type: string
          attestation_hash: string | null
          changes: Json | null
          id: string
          ip_address: unknown
          performed_by: string
          resource_id: string
          resource_type: string
          timestamp: string
          user_agent: string | null
        }
        Insert: {
          action_type: string
          attestation_hash?: string | null
          changes?: Json | null
          id?: string
          ip_address?: unknown
          performed_by: string
          resource_id: string
          resource_type: string
          timestamp?: string
          user_agent?: string | null
        }
        Update: {
          action_type?: string
          attestation_hash?: string | null
          changes?: Json | null
          id?: string
          ip_address?: unknown
          performed_by?: string
          resource_id?: string
          resource_type?: string
          timestamp?: string
          user_agent?: string | null
        }
        Relationships: []
      }
      arx_club_members: {
        Row: {
          activation_hash: string | null
          benefits: Json | null
          council_member: boolean | null
          created_at: string
          executive_board: boolean | null
          expires_at: string | null
          governance_role: string | null
          id: string
          joined_at: string
          kyc_status: string | null
          kyc_verified_at: string | null
          membership_tier: string
          metadata: Json | null
          node_operator: boolean | null
          status: string
          updated_at: string
          user_id: string
          voting_weight: number | null
          wnft_credential: string | null
        }
        Insert: {
          activation_hash?: string | null
          benefits?: Json | null
          council_member?: boolean | null
          created_at?: string
          executive_board?: boolean | null
          expires_at?: string | null
          governance_role?: string | null
          id?: string
          joined_at?: string
          kyc_status?: string | null
          kyc_verified_at?: string | null
          membership_tier?: string
          metadata?: Json | null
          node_operator?: boolean | null
          status?: string
          updated_at?: string
          user_id: string
          voting_weight?: number | null
          wnft_credential?: string | null
        }
        Update: {
          activation_hash?: string | null
          benefits?: Json | null
          council_member?: boolean | null
          created_at?: string
          executive_board?: boolean | null
          expires_at?: string | null
          governance_role?: string | null
          id?: string
          joined_at?: string
          kyc_status?: string | null
          kyc_verified_at?: string | null
          membership_tier?: string
          metadata?: Json | null
          node_operator?: boolean | null
          status?: string
          updated_at?: string
          user_id?: string
          voting_weight?: number | null
          wnft_credential?: string | null
        }
        Relationships: []
      }
      arx_documentation_vault: {
        Row: {
          access_level: string
          access_log: Json | null
          allowed_roles: Json | null
          attestation_hash: string | null
          created_at: string
          document_title: string
          document_type: string
          encrypted: boolean | null
          encryption_key_id: string | null
          file_path: string | null
          id: string
          redacted_sections: Json | null
          updated_at: string
          uploaded_by: string
          zk_proof_available: boolean | null
        }
        Insert: {
          access_level?: string
          access_log?: Json | null
          allowed_roles?: Json | null
          attestation_hash?: string | null
          created_at?: string
          document_title: string
          document_type: string
          encrypted?: boolean | null
          encryption_key_id?: string | null
          file_path?: string | null
          id?: string
          redacted_sections?: Json | null
          updated_at?: string
          uploaded_by: string
          zk_proof_available?: boolean | null
        }
        Update: {
          access_level?: string
          access_log?: Json | null
          allowed_roles?: Json | null
          attestation_hash?: string | null
          created_at?: string
          document_title?: string
          document_type?: string
          encrypted?: boolean | null
          encryption_key_id?: string | null
          file_path?: string | null
          id?: string
          redacted_sections?: Json | null
          updated_at?: string
          uploaded_by?: string
          zk_proof_available?: boolean | null
        }
        Relationships: []
      }
      arx_event_attendees: {
        Row: {
          attended: boolean | null
          created_at: string
          event_id: string
          id: string
          member_id: string
          rsvp_status: string | null
        }
        Insert: {
          attended?: boolean | null
          created_at?: string
          event_id: string
          id?: string
          member_id: string
          rsvp_status?: string | null
        }
        Update: {
          attended?: boolean | null
          created_at?: string
          event_id?: string
          id?: string
          member_id?: string
          rsvp_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "arx_event_attendees_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "arx_events"
            referencedColumns: ["id"]
          },
        ]
      }
      arx_events: {
        Row: {
          access_level: string
          agenda: Json | null
          allowed_roles: Json | null
          attestation_hash: string | null
          created_at: string
          created_by: string
          description: string | null
          duration_minutes: number | null
          event_title: string
          event_type: string
          id: string
          location: string | null
          minutes_document_id: string | null
          scheduled_at: string
          status: string
          virtual_meeting_link: string | null
        }
        Insert: {
          access_level?: string
          agenda?: Json | null
          allowed_roles?: Json | null
          attestation_hash?: string | null
          created_at?: string
          created_by: string
          description?: string | null
          duration_minutes?: number | null
          event_title: string
          event_type: string
          id?: string
          location?: string | null
          minutes_document_id?: string | null
          scheduled_at: string
          status?: string
          virtual_meeting_link?: string | null
        }
        Update: {
          access_level?: string
          agenda?: Json | null
          allowed_roles?: Json | null
          attestation_hash?: string | null
          created_at?: string
          created_by?: string
          description?: string | null
          duration_minutes?: number | null
          event_title?: string
          event_type?: string
          id?: string
          location?: string | null
          minutes_document_id?: string | null
          scheduled_at?: string
          status?: string
          virtual_meeting_link?: string | null
        }
        Relationships: []
      }
      arx_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invitation_code: string
          invited_by: string
          metadata: Json | null
          role_preset: string | null
          status: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invitation_code: string
          invited_by: string
          metadata?: Json | null
          role_preset?: string | null
          status?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invitation_code?: string
          invited_by?: string
          metadata?: Json | null
          role_preset?: string | null
          status?: string
        }
        Relationships: []
      }
      arx_legal_reports: {
        Row: {
          attestation_hash: string
          created_at: string
          document_id: string | null
          fiscal_period: string | null
          id: string
          published_at: string | null
          published_by: string
          report_title: string
          report_type: string
          signatures: Json | null
          status: string
          verifier_metadata: Json | null
        }
        Insert: {
          attestation_hash: string
          created_at?: string
          document_id?: string | null
          fiscal_period?: string | null
          id?: string
          published_at?: string | null
          published_by: string
          report_title: string
          report_type: string
          signatures?: Json | null
          status?: string
          verifier_metadata?: Json | null
        }
        Update: {
          attestation_hash?: string
          created_at?: string
          document_id?: string | null
          fiscal_period?: string | null
          id?: string
          published_at?: string | null
          published_by?: string
          report_title?: string
          report_type?: string
          signatures?: Json | null
          status?: string
          verifier_metadata?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "arx_legal_reports_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "arx_documentation_vault"
            referencedColumns: ["id"]
          },
        ]
      }
      arx_member_registry: {
        Row: {
          activation_snapshot_hash: string | null
          asset_verification: Json | null
          created_at: string
          domain_records: Json | null
          domain_verified: boolean | null
          entity_type: string
          id: string
          jurisdiction: string | null
          kyc_documents: Json | null
          legal_name: string
          member_id: string
          node_id: string | null
          node_status: string | null
          signing_key_hash: string | null
          updated_at: string
          verification_status: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          activation_snapshot_hash?: string | null
          asset_verification?: Json | null
          created_at?: string
          domain_records?: Json | null
          domain_verified?: boolean | null
          entity_type?: string
          id?: string
          jurisdiction?: string | null
          kyc_documents?: Json | null
          legal_name: string
          member_id: string
          node_id?: string | null
          node_status?: string | null
          signing_key_hash?: string | null
          updated_at?: string
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          activation_snapshot_hash?: string | null
          asset_verification?: Json | null
          created_at?: string
          domain_records?: Json | null
          domain_verified?: boolean | null
          entity_type?: string
          id?: string
          jurisdiction?: string | null
          kyc_documents?: Json | null
          legal_name?: string
          member_id?: string
          node_id?: string | null
          node_status?: string | null
          signing_key_hash?: string | null
          updated_at?: string
          verification_status?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "arx_member_registry_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "arx_club_members"
            referencedColumns: ["id"]
          },
        ]
      }
      arx_support_tickets: {
        Row: {
          assigned_to: string | null
          attestation_hash: string | null
          category: string
          created_at: string
          description: string | null
          escalation_level: number | null
          id: string
          metadata: Json | null
          priority: string
          resolved_at: string | null
          sla_deadline: string | null
          status: string
          subject: string
          submitted_by: string
          ticket_number: string
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          attestation_hash?: string | null
          category: string
          created_at?: string
          description?: string | null
          escalation_level?: number | null
          id?: string
          metadata?: Json | null
          priority?: string
          resolved_at?: string | null
          sla_deadline?: string | null
          status?: string
          subject: string
          submitted_by: string
          ticket_number: string
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          attestation_hash?: string | null
          category?: string
          created_at?: string
          description?: string | null
          escalation_level?: number | null
          id?: string
          metadata?: Json | null
          priority?: string
          resolved_at?: string | null
          sla_deadline?: string | null
          status?: string
          subject?: string
          submitted_by?: string
          ticket_number?: string
          updated_at?: string
        }
        Relationships: []
      }
      arx_treasury_pools: {
        Row: {
          balance_ars: number | null
          balance_arx: number | null
          balance_usd: number | null
          created_at: string
          id: string
          lock_schedule: Json | null
          locked_amount: number | null
          multisig_signers: Json | null
          multisig_threshold: number
          oracle_price_feed: string | null
          pool_name: string
          pool_type: string
          release_calendar: Json | null
          status: string
          updated_at: string
        }
        Insert: {
          balance_ars?: number | null
          balance_arx?: number | null
          balance_usd?: number | null
          created_at?: string
          id?: string
          lock_schedule?: Json | null
          locked_amount?: number | null
          multisig_signers?: Json | null
          multisig_threshold?: number
          oracle_price_feed?: string | null
          pool_name: string
          pool_type: string
          release_calendar?: Json | null
          status?: string
          updated_at?: string
        }
        Update: {
          balance_ars?: number | null
          balance_arx?: number | null
          balance_usd?: number | null
          created_at?: string
          id?: string
          lock_schedule?: Json | null
          locked_amount?: number | null
          multisig_signers?: Json | null
          multisig_threshold?: number
          oracle_price_feed?: string | null
          pool_name?: string
          pool_type?: string
          release_calendar?: Json | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      arx_treasury_transactions: {
        Row: {
          amount: number
          attestation_hash: string | null
          collected_signatures: Json | null
          created_at: string
          currency: string
          executed_at: string | null
          id: string
          initiated_by: string
          metadata: Json | null
          multisig_approval_hash: string | null
          oracle_rate: number | null
          pool_id: string
          required_signatures: number
          status: string
          transaction_type: string
          usd_equivalent: number | null
        }
        Insert: {
          amount: number
          attestation_hash?: string | null
          collected_signatures?: Json | null
          created_at?: string
          currency: string
          executed_at?: string | null
          id?: string
          initiated_by: string
          metadata?: Json | null
          multisig_approval_hash?: string | null
          oracle_rate?: number | null
          pool_id: string
          required_signatures: number
          status?: string
          transaction_type: string
          usd_equivalent?: number | null
        }
        Update: {
          amount?: number
          attestation_hash?: string | null
          collected_signatures?: Json | null
          created_at?: string
          currency?: string
          executed_at?: string | null
          id?: string
          initiated_by?: string
          metadata?: Json | null
          multisig_approval_hash?: string | null
          oracle_rate?: number | null
          pool_id?: string
          required_signatures?: number
          status?: string
          transaction_type?: string
          usd_equivalent?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "arx_treasury_transactions_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "arx_treasury_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      arx_voting_ballots: {
        Row: {
          attestation_hash: string | null
          ballot_type: string
          created_at: string
          created_by: string
          description: string | null
          id: string
          oracle_data: Json | null
          published_at: string | null
          quorum_required: number | null
          results: Json | null
          snapshot_block: string | null
          snapshot_hash: string | null
          status: string
          title: string
          voting_end: string
          voting_start: string
          worker_node_signatures: Json | null
        }
        Insert: {
          attestation_hash?: string | null
          ballot_type?: string
          created_at?: string
          created_by: string
          description?: string | null
          id?: string
          oracle_data?: Json | null
          published_at?: string | null
          quorum_required?: number | null
          results?: Json | null
          snapshot_block?: string | null
          snapshot_hash?: string | null
          status?: string
          title: string
          voting_end: string
          voting_start: string
          worker_node_signatures?: Json | null
        }
        Update: {
          attestation_hash?: string | null
          ballot_type?: string
          created_at?: string
          created_by?: string
          description?: string | null
          id?: string
          oracle_data?: Json | null
          published_at?: string | null
          quorum_required?: number | null
          results?: Json | null
          snapshot_block?: string | null
          snapshot_hash?: string | null
          status?: string
          title?: string
          voting_end?: string
          voting_start?: string
          worker_node_signatures?: Json | null
        }
        Relationships: []
      }
      arx_voting_records: {
        Row: {
          ballot_id: string
          id: string
          signature_hash: string | null
          vote_choice: string
          voted_at: string
          voter_id: string
          voting_weight: number
        }
        Insert: {
          ballot_id: string
          id?: string
          signature_hash?: string | null
          vote_choice: string
          voted_at?: string
          voter_id: string
          voting_weight?: number
        }
        Update: {
          ballot_id?: string
          id?: string
          signature_hash?: string | null
          vote_choice?: string
          voted_at?: string
          voter_id?: string
          voting_weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "arx_voting_records_ballot_id_fkey"
            columns: ["ballot_id"]
            isOneToOne: false
            referencedRelation: "arx_voting_ballots"
            referencedColumns: ["id"]
          },
        ]
      }
      arx_wnft_registry: {
        Row: {
          attestation_hash: string | null
          created_at: string
          credential_code: string
          id: string
          member_id: string
          metadata: Json | null
          minted_at: string | null
          status: string
          token_id: string | null
          transfer_restricted: boolean | null
        }
        Insert: {
          attestation_hash?: string | null
          created_at?: string
          credential_code: string
          id?: string
          member_id: string
          metadata?: Json | null
          minted_at?: string | null
          status?: string
          token_id?: string | null
          transfer_restricted?: boolean | null
        }
        Update: {
          attestation_hash?: string | null
          created_at?: string
          credential_code?: string
          id?: string
          member_id?: string
          metadata?: Json | null
          minted_at?: string | null
          status?: string
          token_id?: string | null
          transfer_restricted?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "arx_wnft_registry_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "arx_club_members"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          action: string
          created_at: string
          id: string
          ip_address: unknown
          new_values: Json | null
          old_values: Json | null
          table_name: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          action: string
          created_at?: string
          id?: string
          ip_address?: unknown
          new_values?: Json | null
          old_values?: Json | null
          table_name: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          action?: string
          created_at?: string
          id?: string
          ip_address?: unknown
          new_values?: Json | null
          old_values?: Json | null
          table_name?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      auth_attempts: {
        Row: {
          additional_data: Json | null
          attempt_type: string
          created_at: string | null
          id: string
          ip_address: unknown
          success: boolean
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          additional_data?: Json | null
          attempt_type: string
          created_at?: string | null
          id?: string
          ip_address?: unknown
          success?: boolean
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          additional_data?: Json | null
          attempt_type?: string
          created_at?: string | null
          id?: string
          ip_address?: unknown
          success?: boolean
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      backup_metadata: {
        Row: {
          backup_name: string
          backup_size_mb: number | null
          backup_type: string
          created_at: string | null
          created_by: string
          download_count: number | null
          expires_at: string | null
          file_formats: string[]
          file_paths: Json
          id: string
          last_downloaded_at: string | null
          metadata: Json | null
          status: string | null
          total_records: number
          total_tables: number
        }
        Insert: {
          backup_name: string
          backup_size_mb?: number | null
          backup_type: string
          created_at?: string | null
          created_by: string
          download_count?: number | null
          expires_at?: string | null
          file_formats: string[]
          file_paths: Json
          id?: string
          last_downloaded_at?: string | null
          metadata?: Json | null
          status?: string | null
          total_records?: number
          total_tables?: number
        }
        Update: {
          backup_name?: string
          backup_size_mb?: number | null
          backup_type?: string
          created_at?: string | null
          created_by?: string
          download_count?: number | null
          expires_at?: string | null
          file_formats?: string[]
          file_paths?: Json
          id?: string
          last_downloaded_at?: string | null
          metadata?: Json | null
          status?: string | null
          total_records?: number
          total_tables?: number
        }
        Relationships: []
      }
      balance_correction_jobs: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string
          error_log: string[] | null
          fail_count: number
          id: string
          last_updated: string | null
          processed_count: number
          progress_percentage: number
          started_at: string | null
          status: string
          success_count: number
          total_users: number
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by: string
          error_log?: string[] | null
          fail_count?: number
          id?: string
          last_updated?: string | null
          processed_count?: number
          progress_percentage?: number
          started_at?: string | null
          status?: string
          success_count?: number
          total_users?: number
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string
          error_log?: string[] | null
          fail_count?: number
          id?: string
          last_updated?: string | null
          processed_count?: number
          progress_percentage?: number
          started_at?: string | null
          status?: string
          success_count?: number
          total_users?: number
        }
        Relationships: []
      }
      business_domain_applications: {
        Row: {
          admin_notes: string | null
          business_address: Json | null
          business_description: string | null
          business_email: string | null
          business_name: string
          business_phone: string | null
          business_type: string
          created_at: string
          date_of_incorporation: string | null
          id: string
          industry: string | null
          ownership_type: string | null
          personal_domain_id: string
          power_of_attorney_document_url: string | null
          processed_at: string | null
          processed_by: string | null
          registration_number: string | null
          requested_domain: string
          state_province: string | null
          status: string
          tax_id: string | null
          trading_name: string | null
          updated_at: string
          user_id: string
          vat_number: string | null
          website_url: string | null
        }
        Insert: {
          admin_notes?: string | null
          business_address?: Json | null
          business_description?: string | null
          business_email?: string | null
          business_name: string
          business_phone?: string | null
          business_type?: string
          created_at?: string
          date_of_incorporation?: string | null
          id?: string
          industry?: string | null
          ownership_type?: string | null
          personal_domain_id: string
          power_of_attorney_document_url?: string | null
          processed_at?: string | null
          processed_by?: string | null
          registration_number?: string | null
          requested_domain: string
          state_province?: string | null
          status?: string
          tax_id?: string | null
          trading_name?: string | null
          updated_at?: string
          user_id: string
          vat_number?: string | null
          website_url?: string | null
        }
        Update: {
          admin_notes?: string | null
          business_address?: Json | null
          business_description?: string | null
          business_email?: string | null
          business_name?: string
          business_phone?: string | null
          business_type?: string
          created_at?: string
          date_of_incorporation?: string | null
          id?: string
          industry?: string | null
          ownership_type?: string | null
          personal_domain_id?: string
          power_of_attorney_document_url?: string | null
          processed_at?: string | null
          processed_by?: string | null
          registration_number?: string | null
          requested_domain?: string
          state_province?: string | null
          status?: string
          tax_id?: string | null
          trading_name?: string | null
          updated_at?: string
          user_id?: string
          vat_number?: string | null
          website_url?: string | null
        }
        Relationships: []
      }
      business_domains: {
        Row: {
          application_id: string
          business_name: string
          business_type: string
          created_at: string
          domain_name: string
          id: string
          minted_at: string
          personal_domain_id: string
          registration_number: string | null
          status: string
          tax_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          application_id: string
          business_name: string
          business_type: string
          created_at?: string
          domain_name: string
          id?: string
          minted_at?: string
          personal_domain_id: string
          registration_number?: string | null
          status?: string
          tax_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          application_id?: string
          business_name?: string
          business_type?: string
          created_at?: string
          domain_name?: string
          id?: string
          minted_at?: string
          personal_domain_id?: string
          registration_number?: string | null
          status?: string
          tax_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_domains_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "business_domain_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      business_invoices: {
        Row: {
          client_address: string | null
          client_email: string | null
          client_name: string
          client_tax_id: string | null
          created_at: string
          currency: string
          due_date: string | null
          id: string
          invoice_number: string
          merchant_id: string
          notes: string | null
          paid_at: string | null
          payment_method: string | null
          status: string
          subtotal: number
          tax_amount: number | null
          tax_rate: number | null
          total_amount: number
          updated_at: string
          user_id: string
        }
        Insert: {
          client_address?: string | null
          client_email?: string | null
          client_name: string
          client_tax_id?: string | null
          created_at?: string
          currency?: string
          due_date?: string | null
          id?: string
          invoice_number: string
          merchant_id: string
          notes?: string | null
          paid_at?: string | null
          payment_method?: string | null
          status?: string
          subtotal?: number
          tax_amount?: number | null
          tax_rate?: number | null
          total_amount?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          client_address?: string | null
          client_email?: string | null
          client_name?: string
          client_tax_id?: string | null
          created_at?: string
          currency?: string
          due_date?: string | null
          id?: string
          invoice_number?: string
          merchant_id?: string
          notes?: string | null
          paid_at?: string | null
          payment_method?: string | null
          status?: string
          subtotal?: number
          tax_amount?: number | null
          tax_rate?: number | null
          total_amount?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_invoices_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "merchant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      business_profiles: {
        Row: {
          address_line_2: string | null
          admin_notes: string | null
          business_description: string | null
          business_domain_application_id: string | null
          business_domain_id: string | null
          business_domain_name: string | null
          business_email: string
          business_legal_name: string
          business_phone: string
          business_type: string
          city: string
          country: string
          country_of_incorporation: string
          created_at: string
          date_of_incorporation: string | null
          id: string
          industry: string | null
          metadata: Json | null
          ownership_type: string
          personal_domain_id: string
          postal_code: string
          power_of_attorney_document_url: string | null
          registration_number: string | null
          state_province: string | null
          status: string
          street_address: string
          tax_id: string | null
          trading_name: string | null
          updated_at: string
          user_id: string
          vat_number: string | null
          verified_at: string | null
          verified_by: string | null
          website_url: string | null
        }
        Insert: {
          address_line_2?: string | null
          admin_notes?: string | null
          business_description?: string | null
          business_domain_application_id?: string | null
          business_domain_id?: string | null
          business_domain_name?: string | null
          business_email: string
          business_legal_name: string
          business_phone: string
          business_type?: string
          city: string
          country: string
          country_of_incorporation: string
          created_at?: string
          date_of_incorporation?: string | null
          id?: string
          industry?: string | null
          metadata?: Json | null
          ownership_type?: string
          personal_domain_id: string
          postal_code: string
          power_of_attorney_document_url?: string | null
          registration_number?: string | null
          state_province?: string | null
          status?: string
          street_address: string
          tax_id?: string | null
          trading_name?: string | null
          updated_at?: string
          user_id: string
          vat_number?: string | null
          verified_at?: string | null
          verified_by?: string | null
          website_url?: string | null
        }
        Update: {
          address_line_2?: string | null
          admin_notes?: string | null
          business_description?: string | null
          business_domain_application_id?: string | null
          business_domain_id?: string | null
          business_domain_name?: string | null
          business_email?: string
          business_legal_name?: string
          business_phone?: string
          business_type?: string
          city?: string
          country?: string
          country_of_incorporation?: string
          created_at?: string
          date_of_incorporation?: string | null
          id?: string
          industry?: string | null
          metadata?: Json | null
          ownership_type?: string
          personal_domain_id?: string
          postal_code?: string
          power_of_attorney_document_url?: string | null
          registration_number?: string | null
          state_province?: string | null
          status?: string
          street_address?: string
          tax_id?: string | null
          trading_name?: string | null
          updated_at?: string
          user_id?: string
          vat_number?: string | null
          verified_at?: string | null
          verified_by?: string | null
          website_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "business_profiles_business_domain_application_id_fkey"
            columns: ["business_domain_application_id"]
            isOneToOne: false
            referencedRelation: "business_domain_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_profiles_business_domain_id_fkey"
            columns: ["business_domain_id"]
            isOneToOne: false
            referencedRelation: "business_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      business_transactions: {
        Row: {
          amount: number
          created_at: string
          currency: string
          description: string | null
          id: string
          invoice_id: string | null
          merchant_id: string
          processed_at: string | null
          recipient_bic: string | null
          recipient_email: string | null
          recipient_iban: string | null
          recipient_name: string | null
          reference: string | null
          sender_iban: string | null
          sender_name: string | null
          status: string
          transaction_type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          currency?: string
          description?: string | null
          id?: string
          invoice_id?: string | null
          merchant_id: string
          processed_at?: string | null
          recipient_bic?: string | null
          recipient_email?: string | null
          recipient_iban?: string | null
          recipient_name?: string | null
          reference?: string | null
          sender_iban?: string | null
          sender_name?: string | null
          status?: string
          transaction_type: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          currency?: string
          description?: string | null
          id?: string
          invoice_id?: string | null
          merchant_id?: string
          processed_at?: string | null
          recipient_bic?: string | null
          recipient_email?: string | null
          recipient_iban?: string | null
          recipient_name?: string | null
          reference?: string | null
          sender_iban?: string | null
          sender_name?: string | null
          status?: string
          transaction_type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "business_transactions_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "business_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "business_transactions_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "merchant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      capacity_sharing: {
        Row: {
          capacity_amount: number
          capacity_unit: string
          created_at: string
          hourly_rate: number
          id: string
          sharing_type: string
          status: string
          total_earned: number | null
          total_hours_shared: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          capacity_amount: number
          capacity_unit: string
          created_at?: string
          hourly_rate: number
          id?: string
          sharing_type: string
          status?: string
          total_earned?: number | null
          total_hours_shared?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          capacity_amount?: number
          capacity_unit?: string
          created_at?: string
          hourly_rate?: number
          id?: string
          sharing_type?: string
          status?: string
          total_earned?: number | null
          total_hours_shared?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      car_listings: {
        Row: {
          admin_notes: string | null
          body_type: string | null
          color: string | null
          condition: string
          created_at: string
          currency: string
          description: string | null
          fuel_type: string | null
          id: string
          images: string[]
          location: string | null
          make: string
          mileage_km: number | null
          model: string
          price: number
          reviewed_at: string | null
          reviewed_by: string | null
          seller_id: string
          status: string
          title: string
          transmission: string | null
          updated_at: string
          vin: string | null
          year: number | null
        }
        Insert: {
          admin_notes?: string | null
          body_type?: string | null
          color?: string | null
          condition?: string
          created_at?: string
          currency?: string
          description?: string | null
          fuel_type?: string | null
          id?: string
          images?: string[]
          location?: string | null
          make: string
          mileage_km?: number | null
          model: string
          price: number
          reviewed_at?: string | null
          reviewed_by?: string | null
          seller_id: string
          status?: string
          title: string
          transmission?: string | null
          updated_at?: string
          vin?: string | null
          year?: number | null
        }
        Update: {
          admin_notes?: string | null
          body_type?: string | null
          color?: string | null
          condition?: string
          created_at?: string
          currency?: string
          description?: string | null
          fuel_type?: string | null
          id?: string
          images?: string[]
          location?: string | null
          make?: string
          mileage_km?: number | null
          model?: string
          price?: number
          reviewed_at?: string | null
          reviewed_by?: string | null
          seller_id?: string
          status?: string
          title?: string
          transmission?: string | null
          updated_at?: string
          vin?: string | null
          year?: number | null
        }
        Relationships: []
      }
      car_orders: {
        Row: {
          admin_notes: string | null
          amount: number
          buyer_contact: string | null
          buyer_id: string
          buyer_message: string | null
          created_at: string
          currency: string
          escrow_reference: string | null
          id: string
          listing_id: string
          seller_id: string
          status: string
          updated_at: string
        }
        Insert: {
          admin_notes?: string | null
          amount: number
          buyer_contact?: string | null
          buyer_id: string
          buyer_message?: string | null
          created_at?: string
          currency?: string
          escrow_reference?: string | null
          id?: string
          listing_id: string
          seller_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          admin_notes?: string | null
          amount?: number
          buyer_contact?: string | null
          buyer_id?: string
          buyer_message?: string | null
          created_at?: string
          currency?: string
          escrow_reference?: string | null
          id?: string
          listing_id?: string
          seller_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "car_orders_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "car_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      card_shipping_details: {
        Row: {
          address_line1: string
          address_line2: string | null
          card_type: string
          city: string
          country: string
          created_at: string
          full_name: string
          id: string
          phone: string | null
          postal_code: string
          state_province: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          address_line1: string
          address_line2?: string | null
          card_type: string
          city: string
          country: string
          created_at?: string
          full_name: string
          id?: string
          phone?: string | null
          postal_code: string
          state_province?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          address_line1?: string
          address_line2?: string | null
          card_type?: string
          city?: string
          country?: string
          created_at?: string
          full_name?: string
          id?: string
          phone?: string | null
          postal_code?: string
          state_province?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ccoin_bank_applications: {
        Row: {
          account_type: string | null
          admin_notes: string | null
          application_metadata: Json | null
          company_name: string | null
          company_registration_number: string | null
          created_at: string
          email: string
          full_name: string
          gdpr_accepted: boolean
          gdpr_accepted_at: string | null
          id: string
          ip_address: unknown
          nda_accepted: boolean
          nda_accepted_at: string | null
          processed_at: string | null
          processed_by: string | null
          requested_products: Json | null
          signature_date: string
          signature_full_name: string
          status: string
          terms_accepted: boolean
          terms_accepted_at: string | null
          updated_at: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          account_type?: string | null
          admin_notes?: string | null
          application_metadata?: Json | null
          company_name?: string | null
          company_registration_number?: string | null
          created_at?: string
          email: string
          full_name: string
          gdpr_accepted?: boolean
          gdpr_accepted_at?: string | null
          id?: string
          ip_address?: unknown
          nda_accepted?: boolean
          nda_accepted_at?: string | null
          processed_at?: string | null
          processed_by?: string | null
          requested_products?: Json | null
          signature_date?: string
          signature_full_name: string
          status?: string
          terms_accepted?: boolean
          terms_accepted_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          account_type?: string | null
          admin_notes?: string | null
          application_metadata?: Json | null
          company_name?: string | null
          company_registration_number?: string | null
          created_at?: string
          email?: string
          full_name?: string
          gdpr_accepted?: boolean
          gdpr_accepted_at?: string | null
          id?: string
          ip_address?: unknown
          nda_accepted?: boolean
          nda_accepted_at?: string | null
          processed_at?: string | null
          processed_by?: string | null
          requested_products?: Json | null
          signature_date?: string
          signature_full_name?: string
          status?: string
          terms_accepted?: boolean
          terms_accepted_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      ccoin_bank_cancellation_history: {
        Row: {
          action: string
          cancellation_id: string
          created_at: string
          id: string
          metadata: Json | null
          new_status: string | null
          notes: string | null
          old_status: string | null
          performed_by: string | null
        }
        Insert: {
          action: string
          cancellation_id: string
          created_at?: string
          id?: string
          metadata?: Json | null
          new_status?: string | null
          notes?: string | null
          old_status?: string | null
          performed_by?: string | null
        }
        Update: {
          action?: string
          cancellation_id?: string
          created_at?: string
          id?: string
          metadata?: Json | null
          new_status?: string | null
          notes?: string | null
          old_status?: string | null
          performed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ccoin_bank_cancellation_history_cancellation_id_fkey"
            columns: ["cancellation_id"]
            isOneToOne: false
            referencedRelation: "ccoin_bank_cancellations"
            referencedColumns: ["id"]
          },
        ]
      }
      ccoin_bank_cancellations: {
        Row: {
          admin_notes: string | null
          created_at: string
          id: string
          processed_at: string | null
          processed_by: string | null
          reason: string | null
          status: string
          str_domain: string | null
          updated_at: string
          user_email: string | null
          user_full_name: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          reason?: string | null
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_email?: string | null
          user_full_name?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          reason?: string | null
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_email?: string | null
          user_full_name?: string | null
          user_id?: string
        }
        Relationships: []
      }
      ccoin_banking_profiles: {
        Row: {
          account_type: string | null
          authorized_signatories: Json | null
          banking_status: string | null
          business_address: Json | null
          business_type: string | null
          card_networks_enabled: string[] | null
          ccoin_card_created: boolean | null
          ccoin_card_id: string | null
          chf_iban_created: boolean | null
          chf_iban_id: string | null
          company_name: string | null
          company_registration_number: string | null
          corporate_structure: Json | null
          created_at: string
          default_iban_country: string | null
          email_address: string
          eur_iban_created: boolean | null
          eur_iban_id: string | null
          full_name: string
          gbp_iban_created: boolean | null
          gbp_iban_id: string | null
          id: string
          kyc_status: string | null
          last_banking_sync: string | null
          preferred_iban_currencies: string[] | null
          str_domain: string | null
          str_wallet_address: string | null
          tax_id: string | null
          updated_at: string
          user_id: string
          visa_card_created: boolean | null
          visa_card_id: string | null
        }
        Insert: {
          account_type?: string | null
          authorized_signatories?: Json | null
          banking_status?: string | null
          business_address?: Json | null
          business_type?: string | null
          card_networks_enabled?: string[] | null
          ccoin_card_created?: boolean | null
          ccoin_card_id?: string | null
          chf_iban_created?: boolean | null
          chf_iban_id?: string | null
          company_name?: string | null
          company_registration_number?: string | null
          corporate_structure?: Json | null
          created_at?: string
          default_iban_country?: string | null
          email_address: string
          eur_iban_created?: boolean | null
          eur_iban_id?: string | null
          full_name: string
          gbp_iban_created?: boolean | null
          gbp_iban_id?: string | null
          id?: string
          kyc_status?: string | null
          last_banking_sync?: string | null
          preferred_iban_currencies?: string[] | null
          str_domain?: string | null
          str_wallet_address?: string | null
          tax_id?: string | null
          updated_at?: string
          user_id: string
          visa_card_created?: boolean | null
          visa_card_id?: string | null
        }
        Update: {
          account_type?: string | null
          authorized_signatories?: Json | null
          banking_status?: string | null
          business_address?: Json | null
          business_type?: string | null
          card_networks_enabled?: string[] | null
          ccoin_card_created?: boolean | null
          ccoin_card_id?: string | null
          chf_iban_created?: boolean | null
          chf_iban_id?: string | null
          company_name?: string | null
          company_registration_number?: string | null
          corporate_structure?: Json | null
          created_at?: string
          default_iban_country?: string | null
          email_address?: string
          eur_iban_created?: boolean | null
          eur_iban_id?: string | null
          full_name?: string
          gbp_iban_created?: boolean | null
          gbp_iban_id?: string | null
          id?: string
          kyc_status?: string | null
          last_banking_sync?: string | null
          preferred_iban_currencies?: string[] | null
          str_domain?: string | null
          str_wallet_address?: string | null
          tax_id?: string | null
          updated_at?: string
          user_id?: string
          visa_card_created?: boolean | null
          visa_card_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ccoin_banking_profiles_ccoin_card_id_fkey"
            columns: ["ccoin_card_id"]
            isOneToOne: false
            referencedRelation: "prepaid_cards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ccoin_banking_profiles_chf_iban_id_fkey"
            columns: ["chf_iban_id"]
            isOneToOne: false
            referencedRelation: "iban_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ccoin_banking_profiles_eur_iban_id_fkey"
            columns: ["eur_iban_id"]
            isOneToOne: false
            referencedRelation: "iban_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ccoin_banking_profiles_gbp_iban_id_fkey"
            columns: ["gbp_iban_id"]
            isOneToOne: false
            referencedRelation: "iban_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ccoin_banking_profiles_visa_card_id_fkey"
            columns: ["visa_card_id"]
            isOneToOne: false
            referencedRelation: "prepaid_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      ccoin_card_applications: {
        Row: {
          admin_notes: string | null
          created_at: string
          id: string
          processed_at: string | null
          processed_by: string | null
          status: string
          str_domain_id: string
          str_domain_name: string
          updated_at: string
          user_id: string
          wallet_address: string | null
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain_id: string
          str_domain_name: string
          updated_at?: string
          user_id: string
          wallet_address?: string | null
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain_id?: string
          str_domain_name?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string | null
        }
        Relationships: []
      }
      ccoin_internal_iban_currencies: {
        Row: {
          balance: number | null
          card_id: string
          created_at: string
          currency: string
          id: string
          internal_iban: string
          magnet_address: string
          status: string
          updated_at: string
        }
        Insert: {
          balance?: number | null
          card_id: string
          created_at?: string
          currency: string
          id?: string
          internal_iban: string
          magnet_address: string
          status?: string
          updated_at?: string
        }
        Update: {
          balance?: number | null
          card_id?: string
          created_at?: string
          currency?: string
          id?: string
          internal_iban?: string
          magnet_address?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ccoin_internal_iban_currencies_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "ccoin_network_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      ccoin_ledger: {
        Row: {
          amount: number
          counterparty_user_id: string | null
          created_at: string
          currency: string
          from_identifier: string
          id: string
          metadata: Json | null
          network: string
          status: string
          to_identifier: string
          tx_id: string
          updated_at: string
          user_id: string
          validated_at: string | null
          validator_node: string | null
        }
        Insert: {
          amount: number
          counterparty_user_id?: string | null
          created_at?: string
          currency?: string
          from_identifier: string
          id?: string
          metadata?: Json | null
          network?: string
          status?: string
          to_identifier: string
          tx_id: string
          updated_at?: string
          user_id: string
          validated_at?: string | null
          validator_node?: string | null
        }
        Update: {
          amount?: number
          counterparty_user_id?: string | null
          created_at?: string
          currency?: string
          from_identifier?: string
          id?: string
          metadata?: Json | null
          network?: string
          status?: string
          to_identifier?: string
          tx_id?: string
          updated_at?: string
          user_id?: string
          validated_at?: string | null
          validator_node?: string | null
        }
        Relationships: []
      }
      ccoin_network_cards: {
        Row: {
          card_number: string
          created_at: string
          id: string
          internal_iban: string
          issued_at: string
          last_activity: string | null
          metadata: Json | null
          status: string
          str_domain: string
          updated_at: string
          user_id: string
          wallet_address: string
        }
        Insert: {
          card_number: string
          created_at?: string
          id?: string
          internal_iban: string
          issued_at?: string
          last_activity?: string | null
          metadata?: Json | null
          status?: string
          str_domain: string
          updated_at?: string
          user_id: string
          wallet_address: string
        }
        Update: {
          card_number?: string
          created_at?: string
          id?: string
          internal_iban?: string
          issued_at?: string
          last_activity?: string | null
          metadata?: Json | null
          status?: string
          str_domain?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string
        }
        Relationships: []
      }
      ccoin_network_transactions: {
        Row: {
          amount: number
          card_id: string
          completed_at: string | null
          created_at: string
          currency: string
          from_address: string
          id: string
          metadata: Json | null
          status: string
          to_address: string
          transaction_type: string
          tx_hash: string | null
          validated_at: string | null
          validator_node: string | null
        }
        Insert: {
          amount: number
          card_id: string
          completed_at?: string | null
          created_at?: string
          currency: string
          from_address: string
          id?: string
          metadata?: Json | null
          status?: string
          to_address: string
          transaction_type: string
          tx_hash?: string | null
          validated_at?: string | null
          validator_node?: string | null
        }
        Update: {
          amount?: number
          card_id?: string
          completed_at?: string | null
          created_at?: string
          currency?: string
          from_address?: string
          id?: string
          metadata?: Json | null
          status?: string
          to_address?: string
          transaction_type?: string
          tx_hash?: string | null
          validated_at?: string | null
          validator_node?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ccoin_network_transactions_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "ccoin_network_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      ccoin_pool_connections: {
        Row: {
          allocation_percentage: number | null
          auto_transfer_enabled: boolean | null
          created_at: string | null
          iban_account_id: string
          id: string
          min_transfer_amount: number | null
          pool_type: string
        }
        Insert: {
          allocation_percentage?: number | null
          auto_transfer_enabled?: boolean | null
          created_at?: string | null
          iban_account_id: string
          id?: string
          min_transfer_amount?: number | null
          pool_type: string
        }
        Update: {
          allocation_percentage?: number | null
          auto_transfer_enabled?: boolean | null
          created_at?: string | null
          iban_account_id?: string
          id?: string
          min_transfer_amount?: number | null
          pool_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "ccoin_pool_connections_iban_account_id_fkey"
            columns: ["iban_account_id"]
            isOneToOne: false
            referencedRelation: "iban_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      ccoin_validations: {
        Row: {
          card_identifier: string
          created_at: string
          details: Json | null
          id: string
          result: string
          user_id: string | null
        }
        Insert: {
          card_identifier: string
          created_at?: string
          details?: Json | null
          id?: string
          result: string
          user_id?: string | null
        }
        Update: {
          card_identifier?: string
          created_at?: string
          details?: Json | null
          id?: string
          result?: string
          user_id?: string | null
        }
        Relationships: []
      }
      ccos_purchases: {
        Row: {
          admin_notes: string | null
          created_at: string
          email_address: string
          full_name: string
          id: string
          package_amount_usd: number
          payment_method: string | null
          processed_at: string | null
          processed_by: string | null
          status: string
          str_domain: string | null
          transaction_hash: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          email_address: string
          full_name: string
          id?: string
          package_amount_usd: number
          payment_method?: string | null
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain?: string | null
          transaction_hash?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          email_address?: string
          full_name?: string
          id?: string
          package_amount_usd?: number
          payment_method?: string | null
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain?: string | null
          transaction_hash?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      chat_bans: {
        Row: {
          banned_by: string
          created_at: string
          expires_at: string | null
          id: string
          reason: string | null
          room_type: string
          user_id: string
        }
        Insert: {
          banned_by: string
          created_at?: string
          expires_at?: string | null
          id?: string
          reason?: string | null
          room_type: string
          user_id: string
        }
        Update: {
          banned_by?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          reason?: string | null
          room_type?: string
          user_id?: string
        }
        Relationships: []
      }
      chat_messages: {
        Row: {
          created_at: string
          deleted_at: string | null
          deleted_by: string | null
          id: string
          is_deleted: boolean
          message: string
          moderated_reason: string | null
          reply_to_id: string | null
          room_type: string
          updated_at: string
          user_id: string
          username: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          id?: string
          is_deleted?: boolean
          message: string
          moderated_reason?: string | null
          reply_to_id?: string | null
          room_type?: string
          updated_at?: string
          user_id: string
          username: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          id?: string
          is_deleted?: boolean
          message?: string
          moderated_reason?: string | null
          reply_to_id?: string | null
          room_type?: string
          updated_at?: string
          user_id?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_messages_reply_to_id_fkey"
            columns: ["reply_to_id"]
            isOneToOne: false
            referencedRelation: "chat_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      cross_border_payments: {
        Row: {
          amount: number
          compliance_score: number | null
          created_at: string
          currency: string
          fee_amount: number
          id: string
          payment_rail: string
          processed_at: string | null
          receiver_country: string | null
          recipient_name: string | null
          reference: string | null
          sender_country: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount: number
          compliance_score?: number | null
          created_at?: string
          currency: string
          fee_amount?: number
          id?: string
          payment_rail: string
          processed_at?: string | null
          receiver_country?: string | null
          recipient_name?: string | null
          reference?: string | null
          sender_country?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          compliance_score?: number | null
          created_at?: string
          currency?: string
          fee_amount?: number
          id?: string
          payment_rail?: string
          processed_at?: string | null
          receiver_country?: string | null
          recipient_name?: string | null
          reference?: string | null
          sender_country?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      crypto_orders: {
        Row: {
          amount_to_pay: number | null
          coinpayments_txn_id: string | null
          created_at: string
          id: string
          package_amount_usd: number
          payment_address: string | null
          payment_currency: string | null
          status: string
          timeout_at: string | null
          token_amount: number
          token_price_at_time: number
          token_symbol: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_to_pay?: number | null
          coinpayments_txn_id?: string | null
          created_at?: string
          id?: string
          package_amount_usd: number
          payment_address?: string | null
          payment_currency?: string | null
          status?: string
          timeout_at?: string | null
          token_amount: number
          token_price_at_time: number
          token_symbol: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_to_pay?: number | null
          coinpayments_txn_id?: string | null
          created_at?: string
          id?: string
          package_amount_usd?: number
          payment_address?: string | null
          payment_currency?: string | null
          status?: string
          timeout_at?: string | null
          token_amount?: number
          token_price_at_time?: number
          token_symbol?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      crypto_wallets: {
        Row: {
          available_balance: number
          balance: number
          created_at: string
          held_balance: number
          id: string
          token_type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          available_balance?: number
          balance?: number
          created_at?: string
          held_balance?: number
          id?: string
          token_type: string
          updated_at?: string
          user_id: string
        }
        Update: {
          available_balance?: number
          balance?: number
          created_at?: string
          held_balance?: number
          id?: string
          token_type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      currency_exchanges: {
        Row: {
          created_at: string
          exchange_rate: number
          fee_amount: number
          fee_ccos: number
          fee_ledger_id: string | null
          from_amount: number
          from_currency: string
          id: string
          rail: string | null
          status: string
          to_amount: number
          to_currency: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          exchange_rate: number
          fee_amount?: number
          fee_ccos?: number
          fee_ledger_id?: string | null
          from_amount: number
          from_currency: string
          id?: string
          rail?: string | null
          status?: string
          to_amount: number
          to_currency: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          exchange_rate?: number
          fee_amount?: number
          fee_ccos?: number
          fee_ledger_id?: string | null
          from_amount?: number
          from_currency?: string
          id?: string
          rail?: string | null
          status?: string
          to_amount?: number
          to_currency?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      data_export_history: {
        Row: {
          completed_at: string | null
          created_at: string
          csv_zip_path: string | null
          error_message: string | null
          format: string
          id: string
          requested_by: string
          sql_dump_path: string | null
          started_at: string
          status: string
          total_bytes: number | null
          total_rows: number | null
          total_tables: number | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          csv_zip_path?: string | null
          error_message?: string | null
          format?: string
          id?: string
          requested_by: string
          sql_dump_path?: string | null
          started_at?: string
          status?: string
          total_bytes?: number | null
          total_rows?: number | null
          total_tables?: number | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          csv_zip_path?: string | null
          error_message?: string | null
          format?: string
          id?: string
          requested_by?: string
          sql_dump_path?: string | null
          started_at?: string
          status?: string
          total_bytes?: number | null
          total_rows?: number | null
          total_tables?: number | null
        }
        Relationships: []
      }
      domain_marketplace_bids: {
        Row: {
          bid_amount: number
          bidder_id: string
          created_at: string
          currency: string
          id: string
          is_winning_bid: boolean | null
          listing_id: string
          status: string
        }
        Insert: {
          bid_amount: number
          bidder_id: string
          created_at?: string
          currency?: string
          id?: string
          is_winning_bid?: boolean | null
          listing_id: string
          status?: string
        }
        Update: {
          bid_amount?: number
          bidder_id?: string
          created_at?: string
          currency?: string
          id?: string
          is_winning_bid?: boolean | null
          listing_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "domain_marketplace_bids_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "domain_marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_marketplace_listings: {
        Row: {
          accepted_bid_id: string | null
          auction_end_at: string | null
          buy_now_price: number | null
          category: string | null
          created_at: string
          currency: string
          current_bid: number | null
          current_bidder_id: string | null
          description: string | null
          domain_id: string | null
          domain_name: string
          domain_type: string
          id: string
          image_url: string | null
          is_admin_listing: boolean | null
          listing_type: string
          reservation_expires_at: string | null
          reserve_price: number | null
          reserved_at: string | null
          reserved_by: string | null
          seller_eth_wallet: string | null
          seller_id: string
          seller_wallet_address: string | null
          seller_wallet_currency: string | null
          starting_bid: number | null
          status: string
          updated_at: string
          views_count: number | null
        }
        Insert: {
          accepted_bid_id?: string | null
          auction_end_at?: string | null
          buy_now_price?: number | null
          category?: string | null
          created_at?: string
          currency?: string
          current_bid?: number | null
          current_bidder_id?: string | null
          description?: string | null
          domain_id?: string | null
          domain_name: string
          domain_type: string
          id?: string
          image_url?: string | null
          is_admin_listing?: boolean | null
          listing_type: string
          reservation_expires_at?: string | null
          reserve_price?: number | null
          reserved_at?: string | null
          reserved_by?: string | null
          seller_eth_wallet?: string | null
          seller_id: string
          seller_wallet_address?: string | null
          seller_wallet_currency?: string | null
          starting_bid?: number | null
          status?: string
          updated_at?: string
          views_count?: number | null
        }
        Update: {
          accepted_bid_id?: string | null
          auction_end_at?: string | null
          buy_now_price?: number | null
          category?: string | null
          created_at?: string
          currency?: string
          current_bid?: number | null
          current_bidder_id?: string | null
          description?: string | null
          domain_id?: string | null
          domain_name?: string
          domain_type?: string
          id?: string
          image_url?: string | null
          is_admin_listing?: boolean | null
          listing_type?: string
          reservation_expires_at?: string | null
          reserve_price?: number | null
          reserved_at?: string | null
          reserved_by?: string | null
          seller_eth_wallet?: string | null
          seller_id?: string
          seller_wallet_address?: string | null
          seller_wallet_currency?: string | null
          starting_bid?: number | null
          status?: string
          updated_at?: string
          views_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "domain_marketplace_listings_accepted_bid_id_fkey"
            columns: ["accepted_bid_id"]
            isOneToOne: false
            referencedRelation: "domain_marketplace_bids"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domain_marketplace_listings_domain_id_fkey"
            columns: ["domain_id"]
            isOneToOne: false
            referencedRelation: "str_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_marketplace_transactions: {
        Row: {
          admin_approved_at: string | null
          admin_approved_by: string | null
          admin_notes: string | null
          buyer_id: string
          buyer_wallet_address: string | null
          completed_at: string | null
          created_at: string
          currency: string
          domain_id: string | null
          escrow_status: string
          expires_at: string | null
          id: string
          listing_id: string | null
          payment_proof_url: string | null
          released_at: string | null
          sale_price: number
          sale_type: string
          seller_id: string
          status: string
          transaction_fee: number | null
          transaction_hash: string | null
        }
        Insert: {
          admin_approved_at?: string | null
          admin_approved_by?: string | null
          admin_notes?: string | null
          buyer_id: string
          buyer_wallet_address?: string | null
          completed_at?: string | null
          created_at?: string
          currency?: string
          domain_id?: string | null
          escrow_status?: string
          expires_at?: string | null
          id?: string
          listing_id?: string | null
          payment_proof_url?: string | null
          released_at?: string | null
          sale_price: number
          sale_type: string
          seller_id: string
          status?: string
          transaction_fee?: number | null
          transaction_hash?: string | null
        }
        Update: {
          admin_approved_at?: string | null
          admin_approved_by?: string | null
          admin_notes?: string | null
          buyer_id?: string
          buyer_wallet_address?: string | null
          completed_at?: string | null
          created_at?: string
          currency?: string
          domain_id?: string | null
          escrow_status?: string
          expires_at?: string | null
          id?: string
          listing_id?: string | null
          payment_proof_url?: string | null
          released_at?: string | null
          sale_price?: number
          sale_type?: string
          seller_id?: string
          status?: string
          transaction_fee?: number | null
          transaction_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "domain_marketplace_transactions_domain_id_fkey"
            columns: ["domain_id"]
            isOneToOne: false
            referencedRelation: "str_domains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domain_marketplace_transactions_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "domain_marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_nodes: {
        Row: {
          assigned_at: string | null
          created_at: string
          domain_id: string
          id: string
          is_active: boolean | null
          is_primary: boolean | null
          last_sync: string | null
          node_status: string
          node_type: string
          performance_metrics: Json | null
          updated_at: string
          user_id: string
          wallet_id: string
        }
        Insert: {
          assigned_at?: string | null
          created_at?: string
          domain_id: string
          id?: string
          is_active?: boolean | null
          is_primary?: boolean | null
          last_sync?: string | null
          node_status?: string
          node_type?: string
          performance_metrics?: Json | null
          updated_at?: string
          user_id: string
          wallet_id: string
        }
        Update: {
          assigned_at?: string | null
          created_at?: string
          domain_id?: string
          id?: string
          is_active?: boolean | null
          is_primary?: boolean | null
          last_sync?: string | null
          node_status?: string
          node_type?: string
          performance_metrics?: Json | null
          updated_at?: string
          user_id?: string
          wallet_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "domain_nodes_domain_id_fkey"
            columns: ["domain_id"]
            isOneToOne: false
            referencedRelation: "str_domains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "domain_nodes_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "domain_wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_wallets: {
        Row: {
          created_at: string
          domain_id: string
          id: string
          metadata: Json | null
          private_key_encrypted: string
          public_key: string
          status: string
          updated_at: string
          user_id: string
          wallet_address: string
          wallet_type: string
        }
        Insert: {
          created_at?: string
          domain_id: string
          id?: string
          metadata?: Json | null
          private_key_encrypted: string
          public_key: string
          status?: string
          updated_at?: string
          user_id: string
          wallet_address: string
          wallet_type?: string
        }
        Update: {
          created_at?: string
          domain_id?: string
          id?: string
          metadata?: Json | null
          private_key_encrypted?: string
          public_key?: string
          status?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string
          wallet_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "domain_wallets_domain_id_fkey"
            columns: ["domain_id"]
            isOneToOne: false
            referencedRelation: "str_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      ecosystem_apps: {
        Row: {
          active: boolean
          category: string
          created_at: string
          description: string | null
          embeddable: boolean
          icon: string | null
          id: string
          name: string
          requires_role: Database["public"]["Enums"]["app_role"] | null
          slug: string
          sort_order: number
          updated_at: string
          url: string
        }
        Insert: {
          active?: boolean
          category?: string
          created_at?: string
          description?: string | null
          embeddable?: boolean
          icon?: string | null
          id?: string
          name: string
          requires_role?: Database["public"]["Enums"]["app_role"] | null
          slug: string
          sort_order?: number
          updated_at?: string
          url: string
        }
        Update: {
          active?: boolean
          category?: string
          created_at?: string
          description?: string | null
          embeddable?: boolean
          icon?: string | null
          id?: string
          name?: string
          requires_role?: Database["public"]["Enums"]["app_role"] | null
          slug?: string
          sort_order?: number
          updated_at?: string
          url?: string
        }
        Relationships: []
      }
      ecosystem_component: {
        Row: {
          created_at: string
          id: string
          name: string
          ordinal: number
          section_id: string
          source_page: number
          status: string
          status_note: string | null
          summary: string
          url: string | null
        }
        Insert: {
          created_at?: string
          id: string
          name: string
          ordinal?: number
          section_id: string
          source_page: number
          status?: string
          status_note?: string | null
          summary: string
          url?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          ordinal?: number
          section_id?: string
          source_page?: number
          status?: string
          status_note?: string | null
          summary?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ecosystem_component_section_id_fkey"
            columns: ["section_id"]
            isOneToOne: false
            referencedRelation: "ecosystem_section"
            referencedColumns: ["id"]
          },
        ]
      }
      ecosystem_discrepancy: {
        Row: {
          checked_at: string | null
          created_at: string
          evidence: string | null
          id: string
          kind: string
          note: string | null
          ordinal: number
          resolution: string | null
          says_a: string
          says_b: string
          severity: string
          source_page: string | null
          subject: string
          verdict: string
        }
        Insert: {
          checked_at?: string | null
          created_at?: string
          evidence?: string | null
          id: string
          kind: string
          note?: string | null
          ordinal?: number
          resolution?: string | null
          says_a: string
          says_b: string
          severity?: string
          source_page?: string | null
          subject: string
          verdict?: string
        }
        Update: {
          checked_at?: string | null
          created_at?: string
          evidence?: string | null
          id?: string
          kind?: string
          note?: string | null
          ordinal?: number
          resolution?: string | null
          says_a?: string
          says_b?: string
          severity?: string
          source_page?: string | null
          subject?: string
          verdict?: string
        }
        Relationships: []
      }
      ecosystem_section: {
        Row: {
          created_at: string
          id: string
          ordinal: number
          subtitle: string | null
          title: string
        }
        Insert: {
          created_at?: string
          id: string
          ordinal: number
          subtitle?: string | null
          title: string
        }
        Update: {
          created_at?: string
          id?: string
          ordinal?: number
          subtitle?: string | null
          title?: string
        }
        Relationships: []
      }
      ecosystem_token: {
        Row: {
          created_at: string
          in_overview: boolean
          name: string
          ordinal: number
          role: string
          source_page: number | null
          symbol: string
        }
        Insert: {
          created_at?: string
          in_overview?: boolean
          name: string
          ordinal?: number
          role: string
          source_page?: number | null
          symbol: string
        }
        Update: {
          created_at?: string
          in_overview?: boolean
          name?: string
          ordinal?: number
          role?: string
          source_page?: number | null
          symbol?: string
        }
        Relationships: []
      }
      email_campaign_recipients: {
        Row: {
          campaign_id: string
          created_at: string
          email: string
          error_message: string | null
          full_name: string | null
          id: string
          last_opened_at: string | null
          open_count: number
          opened_at: string | null
          sent_at: string | null
          status: string
          track_token: string
          user_id: string | null
        }
        Insert: {
          campaign_id: string
          created_at?: string
          email: string
          error_message?: string | null
          full_name?: string | null
          id?: string
          last_opened_at?: string | null
          open_count?: number
          opened_at?: string | null
          sent_at?: string | null
          status?: string
          track_token?: string
          user_id?: string | null
        }
        Update: {
          campaign_id?: string
          created_at?: string
          email?: string
          error_message?: string | null
          full_name?: string | null
          id?: string
          last_opened_at?: string | null
          open_count?: number
          opened_at?: string | null
          sent_at?: string | null
          status?: string
          track_token?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "email_campaign_recipients_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "email_campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      email_campaigns: {
        Row: {
          body_html: string
          completed_at: string | null
          created_at: string
          created_by: string | null
          cta_label: string | null
          cta_url: string | null
          failed_count: number
          from_email: string
          from_name: string
          headline: string
          id: string
          name: string
          opened_count: number
          preheader: string | null
          sent_at: string | null
          sent_count: number
          status: string
          subject: string
          total_recipients: number
          updated_at: string
        }
        Insert: {
          body_html: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          cta_label?: string | null
          cta_url?: string | null
          failed_count?: number
          from_email?: string
          from_name?: string
          headline: string
          id?: string
          name: string
          opened_count?: number
          preheader?: string | null
          sent_at?: string | null
          sent_count?: number
          status?: string
          subject: string
          total_recipients?: number
          updated_at?: string
        }
        Update: {
          body_html?: string
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          cta_label?: string | null
          cta_url?: string | null
          failed_count?: number
          from_email?: string
          from_name?: string
          headline?: string
          id?: string
          name?: string
          opened_count?: number
          preheader?: string | null
          sent_at?: string | null
          sent_count?: number
          status?: string
          subject?: string
          total_recipients?: number
          updated_at?: string
        }
        Relationships: []
      }
      email_unsubscribes: {
        Row: {
          campaign_id: string | null
          created_at: string
          email: string
          id: string
          reason: string | null
          source: string
          user_id: string | null
        }
        Insert: {
          campaign_id?: string | null
          created_at?: string
          email: string
          id?: string
          reason?: string | null
          source?: string
          user_id?: string | null
        }
        Update: {
          campaign_id?: string | null
          created_at?: string
          email?: string
          id?: string
          reason?: string | null
          source?: string
          user_id?: string | null
        }
        Relationships: []
      }
      enhanced_rate_limits: {
        Row: {
          attempts: number
          blocked_until: string | null
          created_at: string
          id: string
          identifier: string
          last_attempt: string
          operation_type: string
          window_start: string
        }
        Insert: {
          attempts?: number
          blocked_until?: string | null
          created_at?: string
          id?: string
          identifier: string
          last_attempt?: string
          operation_type: string
          window_start?: string
        }
        Update: {
          attempts?: number
          blocked_until?: string | null
          created_at?: string
          id?: string
          identifier?: string
          last_attempt?: string
          operation_type?: string
          window_start?: string
        }
        Relationships: []
      }
      enhanced_staking_pools: {
        Row: {
          apr_max: number
          apr_min: number
          compounding: boolean | null
          created_at: string | null
          description: string | null
          duration_months: number
          end_date: string | null
          icon: string | null
          id: string
          max_stake_amount: number | null
          min_stake_amount: number | null
          name: string
          reward_curve: Database["public"]["Enums"]["reward_curve"] | null
          start_date: string | null
          status: Database["public"]["Enums"]["pool_status"] | null
          theme: string
          token_type: string
          tvl_cap: number | null
          updated_at: string | null
          whitelist_only: boolean | null
        }
        Insert: {
          apr_max: number
          apr_min: number
          compounding?: boolean | null
          created_at?: string | null
          description?: string | null
          duration_months: number
          end_date?: string | null
          icon?: string | null
          id?: string
          max_stake_amount?: number | null
          min_stake_amount?: number | null
          name: string
          reward_curve?: Database["public"]["Enums"]["reward_curve"] | null
          start_date?: string | null
          status?: Database["public"]["Enums"]["pool_status"] | null
          theme: string
          token_type?: string
          tvl_cap?: number | null
          updated_at?: string | null
          whitelist_only?: boolean | null
        }
        Update: {
          apr_max?: number
          apr_min?: number
          compounding?: boolean | null
          created_at?: string | null
          description?: string | null
          duration_months?: number
          end_date?: string | null
          icon?: string | null
          id?: string
          max_stake_amount?: number | null
          min_stake_amount?: number | null
          name?: string
          reward_curve?: Database["public"]["Enums"]["reward_curve"] | null
          start_date?: string | null
          status?: Database["public"]["Enums"]["pool_status"] | null
          theme?: string
          token_type?: string
          tvl_cap?: number | null
          updated_at?: string | null
          whitelist_only?: boolean | null
        }
        Relationships: []
      }
      error_logs: {
        Row: {
          action_attempted: string | null
          component_name: string | null
          context: Json | null
          created_at: string | null
          device_info: Json | null
          error_code: string | null
          error_message: string
          error_stack: string | null
          error_type: string
          id: string
          resolution_notes: string | null
          resolved: boolean | null
          resolved_at: string | null
          resolved_by: string | null
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          action_attempted?: string | null
          component_name?: string | null
          context?: Json | null
          created_at?: string | null
          device_info?: Json | null
          error_code?: string | null
          error_message: string
          error_stack?: string | null
          error_type: string
          id?: string
          resolution_notes?: string | null
          resolved?: boolean | null
          resolved_at?: string | null
          resolved_by?: string | null
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          action_attempted?: string | null
          component_name?: string | null
          context?: Json | null
          created_at?: string | null
          device_info?: Json | null
          error_code?: string | null
          error_message?: string
          error_stack?: string | null
          error_type?: string
          id?: string
          resolution_notes?: string | null
          resolved?: boolean | null
          resolved_at?: string | null
          resolved_by?: string | null
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      fiat_transactions: {
        Row: {
          amount: number
          approved_at: string | null
          approved_by: string | null
          completed_at: string | null
          created_at: string
          currency: string
          fee: number
          from_identifier: string
          from_user_id: string
          id: string
          metadata: Json | null
          requires_approval: boolean
          status: string
          to_identifier: string
          to_user_id: string | null
          transfer_type: string
          tx_id: string
        }
        Insert: {
          amount: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          currency: string
          fee?: number
          from_identifier: string
          from_user_id: string
          id?: string
          metadata?: Json | null
          requires_approval?: boolean
          status?: string
          to_identifier: string
          to_user_id?: string | null
          transfer_type: string
          tx_id: string
        }
        Update: {
          amount?: number
          approved_at?: string | null
          approved_by?: string | null
          completed_at?: string | null
          created_at?: string
          currency?: string
          fee?: number
          from_identifier?: string
          from_user_id?: string
          id?: string
          metadata?: Json | null
          requires_approval?: boolean
          status?: string
          to_identifier?: string
          to_user_id?: string | null
          transfer_type?: string
          tx_id?: string
        }
        Relationships: []
      }
      fiat_wallets: {
        Row: {
          available_balance: number
          balance: number
          created_at: string
          currency: string
          held_balance: number
          id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          available_balance?: number
          balance?: number
          created_at?: string
          currency: string
          held_balance?: number
          id?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          available_balance?: number
          balance?: number
          created_at?: string
          currency?: string
          held_balance?: number
          id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      founder_access: {
        Row: {
          access_granted_at: string
          id: string
          is_active: boolean
          last_access: string | null
          user_id: string
        }
        Insert: {
          access_granted_at?: string
          id?: string
          is_active?: boolean
          last_access?: string | null
          user_id: string
        }
        Update: {
          access_granted_at?: string
          id?: string
          is_active?: boolean
          last_access?: string | null
          user_id?: string
        }
        Relationships: []
      }
      founder_pool_transactions: {
        Row: {
          amount: number
          ccos_minted: number | null
          created_at: string
          founder_position_id: string | null
          id: string
          is_founder_position: boolean | null
          mint_percentage: number | null
          pool_type: string
          status: string
          transaction_hash: string | null
          transaction_type: string
          updated_at: string
          usd_value_at_time: number
          user_id: string
        }
        Insert: {
          amount: number
          ccos_minted?: number | null
          created_at?: string
          founder_position_id?: string | null
          id?: string
          is_founder_position?: boolean | null
          mint_percentage?: number | null
          pool_type: string
          status?: string
          transaction_hash?: string | null
          transaction_type: string
          updated_at?: string
          usd_value_at_time?: number
          user_id: string
        }
        Update: {
          amount?: number
          ccos_minted?: number | null
          created_at?: string
          founder_position_id?: string | null
          id?: string
          is_founder_position?: boolean | null
          mint_percentage?: number | null
          pool_type?: string
          status?: string
          transaction_hash?: string | null
          transaction_type?: string
          updated_at?: string
          usd_value_at_time?: number
          user_id?: string
        }
        Relationships: []
      }
      founder_pools: {
        Row: {
          balance: number
          created_at: string
          founder_position_id: string | null
          id: string
          is_founder_position: boolean | null
          last_price: number
          pool_type: string
          updated_at: string
          usd_value: number
          user_id: string
        }
        Insert: {
          balance?: number
          created_at?: string
          founder_position_id?: string | null
          id?: string
          is_founder_position?: boolean | null
          last_price?: number
          pool_type: string
          updated_at?: string
          usd_value?: number
          user_id: string
        }
        Update: {
          balance?: number
          created_at?: string
          founder_position_id?: string | null
          id?: string
          is_founder_position?: boolean | null
          last_price?: number
          pool_type?: string
          updated_at?: string
          usd_value?: number
          user_id?: string
        }
        Relationships: []
      }
      founder_positions: {
        Row: {
          access_password: string | null
          btc_wallet_locked: boolean | null
          ccos_mint_percentage: number | null
          created_at: string
          current_usd_value: number
          deposit_date: string | null
          expected_btc_return: number | null
          id: string
          input_btc_amount: number | null
          is_prime: boolean | null
          lock_end_date: string | null
          lock_start_date: string | null
          max_usd_limit: number
          min_deposit_usd: number
          output_btc_amount: number | null
          position_number: number
          position_type: string | null
          status: string
          title: string | null
          unique_link_id: string | null
          updated_at: string
          user_id: string
          withdrawal_address: string | null
          withdrawal_available_date: string | null
          withdrawal_executed: boolean | null
          withdrawal_transaction_hash: string | null
        }
        Insert: {
          access_password?: string | null
          btc_wallet_locked?: boolean | null
          ccos_mint_percentage?: number | null
          created_at?: string
          current_usd_value?: number
          deposit_date?: string | null
          expected_btc_return?: number | null
          id?: string
          input_btc_amount?: number | null
          is_prime?: boolean | null
          lock_end_date?: string | null
          lock_start_date?: string | null
          max_usd_limit?: number
          min_deposit_usd?: number
          output_btc_amount?: number | null
          position_number: number
          position_type?: string | null
          status?: string
          title?: string | null
          unique_link_id?: string | null
          updated_at?: string
          user_id: string
          withdrawal_address?: string | null
          withdrawal_available_date?: string | null
          withdrawal_executed?: boolean | null
          withdrawal_transaction_hash?: string | null
        }
        Update: {
          access_password?: string | null
          btc_wallet_locked?: boolean | null
          ccos_mint_percentage?: number | null
          created_at?: string
          current_usd_value?: number
          deposit_date?: string | null
          expected_btc_return?: number | null
          id?: string
          input_btc_amount?: number | null
          is_prime?: boolean | null
          lock_end_date?: string | null
          lock_start_date?: string | null
          max_usd_limit?: number
          min_deposit_usd?: number
          output_btc_amount?: number | null
          position_number?: number
          position_type?: string | null
          status?: string
          title?: string | null
          unique_link_id?: string | null
          updated_at?: string
          user_id?: string
          withdrawal_address?: string | null
          withdrawal_available_date?: string | null
          withdrawal_executed?: boolean | null
          withdrawal_transaction_hash?: string | null
        }
        Relationships: []
      }
      github_integrations: {
        Row: {
          created_at: string
          encrypted_access_token: string | null
          encryption_version: number | null
          github_username: string
          id: string
          integration_status: string
          is_token_encrypted: boolean | null
          last_sync: string | null
          repo_count: number | null
          token_encryption_iv: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          encrypted_access_token?: string | null
          encryption_version?: number | null
          github_username: string
          id?: string
          integration_status?: string
          is_token_encrypted?: boolean | null
          last_sync?: string | null
          repo_count?: number | null
          token_encryption_iv?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          encrypted_access_token?: string | null
          encryption_version?: number | null
          github_username?: string
          id?: string
          integration_status?: string
          is_token_encrypted?: boolean | null
          last_sync?: string | null
          repo_count?: number | null
          token_encryption_iv?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      governance_proposals: {
        Row: {
          created_at: string
          description: string
          id: string
          status: string
          support_votes: number
          title: string
          updated_at: string
          user_id: string
          vote_count: number
          voting_ends_at: string
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          status?: string
          support_votes?: number
          title: string
          updated_at?: string
          user_id: string
          vote_count?: number
          voting_ends_at?: string
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          status?: string
          support_votes?: number
          title?: string
          updated_at?: string
          user_id?: string
          vote_count?: number
          voting_ends_at?: string
        }
        Relationships: []
      }
      governance_votes: {
        Row: {
          created_at: string
          id: string
          proposal_id: string
          support: boolean
          user_id: string
          voting_power: number
        }
        Insert: {
          created_at?: string
          id?: string
          proposal_id: string
          support: boolean
          user_id: string
          voting_power?: number
        }
        Update: {
          created_at?: string
          id?: string
          proposal_id?: string
          support?: boolean
          user_id?: string
          voting_power?: number
        }
        Relationships: [
          {
            foreignKeyName: "governance_votes_proposal_id_fkey"
            columns: ["proposal_id"]
            isOneToOne: false
            referencedRelation: "governance_proposals"
            referencedColumns: ["id"]
          },
        ]
      }
      guardian_flash_alerts: {
        Row: {
          acted_at: string | null
          acted_by: string | null
          action_taken: string | null
          alert_type: string
          asset_symbol: string
          created_at: string
          description: string | null
          id: string
          market_price: number | null
          severity: string
          status: string
          title: string
          trigger_price: number | null
        }
        Insert: {
          acted_at?: string | null
          acted_by?: string | null
          action_taken?: string | null
          alert_type: string
          asset_symbol: string
          created_at?: string
          description?: string | null
          id?: string
          market_price?: number | null
          severity?: string
          status?: string
          title: string
          trigger_price?: number | null
        }
        Update: {
          acted_at?: string | null
          acted_by?: string | null
          action_taken?: string | null
          alert_type?: string
          asset_symbol?: string
          created_at?: string
          description?: string | null
          id?: string
          market_price?: number | null
          severity?: string
          status?: string
          title?: string
          trigger_price?: number | null
        }
        Relationships: []
      }
      guardian_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          expires_at: string
          id: string
          invited_by: string
          invited_email: string | null
          invited_str_domain: string | null
          status: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          invited_by: string
          invited_email?: string | null
          invited_str_domain?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          invited_by?: string
          invited_email?: string | null
          invited_str_domain?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      guardian_margin_settings: {
        Row: {
          asset_symbol: string
          auto_buy_threshold: number | null
          auto_sell_threshold: number | null
          created_at: string
          id: string
          is_active: boolean
          margin_percent: number
          set_by: string
          target_markets: string[] | null
          updated_at: string
        }
        Insert: {
          asset_symbol: string
          auto_buy_threshold?: number | null
          auto_sell_threshold?: number | null
          created_at?: string
          id?: string
          is_active?: boolean
          margin_percent?: number
          set_by: string
          target_markets?: string[] | null
          updated_at?: string
        }
        Update: {
          asset_symbol?: string
          auto_buy_threshold?: number | null
          auto_sell_threshold?: number | null
          created_at?: string
          id?: string
          is_active?: boolean
          margin_percent?: number
          set_by?: string
          target_markets?: string[] | null
          updated_at?: string
        }
        Relationships: []
      }
      guardian_recovery_keys: {
        Row: {
          created_at: string
          encrypted_words: string
          id: string
          iv: string
          salt: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          encrypted_words: string
          id?: string
          iv: string
          salt: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          encrypted_words?: string
          id?: string
          iv?: string
          salt?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      guardian_safeguard_wallets: {
        Row: {
          asset_symbol: string
          balance: number
          created_at: string
          created_by: string
          id: string
          is_active: boolean
          network: string
          updated_at: string
          wallet_address: string
          wallet_name: string
          wallet_type: string
        }
        Insert: {
          asset_symbol: string
          balance?: number
          created_at?: string
          created_by: string
          id?: string
          is_active?: boolean
          network: string
          updated_at?: string
          wallet_address: string
          wallet_name: string
          wallet_type?: string
        }
        Update: {
          asset_symbol?: string
          balance?: number
          created_at?: string
          created_by?: string
          id?: string
          is_active?: boolean
          network?: string
          updated_at?: string
          wallet_address?: string
          wallet_name?: string
          wallet_type?: string
        }
        Relationships: []
      }
      guardian_transactions: {
        Row: {
          amount: number
          asset_symbol: string
          created_at: string
          from_address: string | null
          id: string
          notes: string | null
          status: string
          to_address: string | null
          transaction_type: string
          tx_hash: string | null
          usd_value: number | null
          user_id: string | null
          wallet_id: string | null
        }
        Insert: {
          amount: number
          asset_symbol: string
          created_at?: string
          from_address?: string | null
          id?: string
          notes?: string | null
          status?: string
          to_address?: string | null
          transaction_type: string
          tx_hash?: string | null
          usd_value?: number | null
          user_id?: string | null
          wallet_id?: string | null
        }
        Update: {
          amount?: number
          asset_symbol?: string
          created_at?: string
          from_address?: string | null
          id?: string
          notes?: string | null
          status?: string
          to_address?: string | null
          transaction_type?: string
          tx_hash?: string | null
          usd_value?: number | null
          user_id?: string | null
          wallet_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "guardian_transactions_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "guardian_wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      guardian_wallets: {
        Row: {
          asset_name: string
          asset_symbol: string
          balance: number
          created_at: string
          deposit_address: string | null
          external_balance: number
          icon_color: string | null
          id: string
          is_active: boolean
          network: string
          updated_at: string
          usd_value: number
          user_external_address: string | null
          user_id: string
          wallet_address: string | null
        }
        Insert: {
          asset_name: string
          asset_symbol: string
          balance?: number
          created_at?: string
          deposit_address?: string | null
          external_balance?: number
          icon_color?: string | null
          id?: string
          is_active?: boolean
          network: string
          updated_at?: string
          usd_value?: number
          user_external_address?: string | null
          user_id: string
          wallet_address?: string | null
        }
        Update: {
          asset_name?: string
          asset_symbol?: string
          balance?: number
          created_at?: string
          deposit_address?: string | null
          external_balance?: number
          icon_color?: string | null
          id?: string
          is_active?: boolean
          network?: string
          updated_at?: string
          usd_value?: number
          user_external_address?: string | null
          user_id?: string
          wallet_address?: string | null
        }
        Relationships: []
      }
      guardian_withdrawal_requests: {
        Row: {
          admin_notes: string | null
          amount: number
          asset_symbol: string
          created_at: string
          destination_address: string
          id: string
          network: string
          processed_at: string | null
          processed_by: string | null
          requested_at: string
          status: string
          updated_at: string
          user_id: string
          wallet_id: string | null
          window_expires_at: string
        }
        Insert: {
          admin_notes?: string | null
          amount: number
          asset_symbol: string
          created_at?: string
          destination_address: string
          id?: string
          network: string
          processed_at?: string | null
          processed_by?: string | null
          requested_at?: string
          status?: string
          updated_at?: string
          user_id: string
          wallet_id?: string | null
          window_expires_at?: string
        }
        Update: {
          admin_notes?: string | null
          amount?: number
          asset_symbol?: string
          created_at?: string
          destination_address?: string
          id?: string
          network?: string
          processed_at?: string | null
          processed_by?: string | null
          requested_at?: string
          status?: string
          updated_at?: string
          user_id?: string
          wallet_id?: string | null
          window_expires_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "guardian_withdrawal_requests_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "guardian_wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      iban_accounts: {
        Row: {
          account_category: string | null
          account_holder: string
          account_type: string
          balance: number | null
          bic: string
          country_code: string
          created_at: string | null
          currency: string
          encrypted_bic: string | null
          encrypted_iban: string | null
          encryption_version: number | null
          iban: string
          iban_encryption_iv: string | null
          id: string
          is_data_encrypted: boolean | null
          legacy_iban: string | null
          merchant_account: boolean | null
          pos_enabled: boolean | null
          status: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          account_category?: string | null
          account_holder: string
          account_type: string
          balance?: number | null
          bic: string
          country_code: string
          created_at?: string | null
          currency: string
          encrypted_bic?: string | null
          encrypted_iban?: string | null
          encryption_version?: number | null
          iban: string
          iban_encryption_iv?: string | null
          id?: string
          is_data_encrypted?: boolean | null
          legacy_iban?: string | null
          merchant_account?: boolean | null
          pos_enabled?: boolean | null
          status?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          account_category?: string | null
          account_holder?: string
          account_type?: string
          balance?: number | null
          bic?: string
          country_code?: string
          created_at?: string | null
          currency?: string
          encrypted_bic?: string | null
          encrypted_iban?: string | null
          encryption_version?: number | null
          iban?: string
          iban_encryption_iv?: string | null
          id?: string
          is_data_encrypted?: boolean | null
          legacy_iban?: string | null
          merchant_account?: boolean | null
          pos_enabled?: boolean | null
          status?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      iban_data_confirmations: {
        Row: {
          address: string | null
          admin_notes: string | null
          city: string | null
          confirmation_status: string
          confirmed_at: string | null
          country: string | null
          created_at: string
          email: string
          full_name: string
          id: string
          phone: string | null
          postal_code: string | null
          rejection_reason: string | null
          str_domain: string | null
          updated_at: string
          user_id: string
          wants_iban: boolean | null
        }
        Insert: {
          address?: string | null
          admin_notes?: string | null
          city?: string | null
          confirmation_status?: string
          confirmed_at?: string | null
          country?: string | null
          created_at?: string
          email: string
          full_name: string
          id?: string
          phone?: string | null
          postal_code?: string | null
          rejection_reason?: string | null
          str_domain?: string | null
          updated_at?: string
          user_id: string
          wants_iban?: boolean | null
        }
        Update: {
          address?: string | null
          admin_notes?: string | null
          city?: string | null
          confirmation_status?: string
          confirmed_at?: string | null
          country?: string | null
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          phone?: string | null
          postal_code?: string | null
          rejection_reason?: string | null
          str_domain?: string | null
          updated_at?: string
          user_id?: string
          wants_iban?: boolean | null
        }
        Relationships: []
      }
      invoice_line_items: {
        Row: {
          created_at: string
          description: string
          id: string
          invoice_id: string
          quantity: number
          total_price: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          invoice_id: string
          quantity?: number
          total_price: number
          unit_price: number
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          invoice_id?: string
          quantity?: number
          total_price?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_line_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "business_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      ipo_listing_requests: {
        Row: {
          address: string | null
          admin_message: string | null
          admin_notes: string | null
          bank_name: string
          bank_swift: string
          created_at: string
          email: string
          full_name: string
          iban: string
          id: string
          number_of_shares: number
          phone: string | null
          price_per_share: number
          processed_at: string | null
          processed_by: string | null
          receiving_currency: string
          share_type: string
          status: string
          total_usd_value: number
          updated_at: string
          user_id: string
        }
        Insert: {
          address?: string | null
          admin_message?: string | null
          admin_notes?: string | null
          bank_name: string
          bank_swift: string
          created_at?: string
          email: string
          full_name: string
          iban: string
          id?: string
          number_of_shares: number
          phone?: string | null
          price_per_share?: number
          processed_at?: string | null
          processed_by?: string | null
          receiving_currency: string
          share_type: string
          status?: string
          total_usd_value: number
          updated_at?: string
          user_id: string
        }
        Update: {
          address?: string | null
          admin_message?: string | null
          admin_notes?: string | null
          bank_name?: string
          bank_swift?: string
          created_at?: string
          email?: string
          full_name?: string
          iban?: string
          id?: string
          number_of_shares?: number
          phone?: string | null
          price_per_share?: number
          processed_at?: string | null
          processed_by?: string | null
          receiving_currency?: string
          share_type?: string
          status?: string
          total_usd_value?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      learning_contributions: {
        Row: {
          arss_reward: number | null
          content_text: string | null
          content_url: string | null
          contribution_type: string
          created_at: string
          description: string | null
          id: string
          processed_at: string | null
          quality_score: number | null
          status: string
          tags: string[] | null
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          arss_reward?: number | null
          content_text?: string | null
          content_url?: string | null
          contribution_type: string
          created_at?: string
          description?: string | null
          id?: string
          processed_at?: string | null
          quality_score?: number | null
          status?: string
          tags?: string[] | null
          title: string
          updated_at?: string
          user_id: string
        }
        Update: {
          arss_reward?: number | null
          content_text?: string | null
          content_url?: string | null
          contribution_type?: string
          created_at?: string
          description?: string | null
          id?: string
          processed_at?: string | null
          quality_score?: number | null
          status?: string
          tags?: string[] | null
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ledger_account: {
        Row: {
          allow_negative: boolean
          asset: string
          balance: number
          bucket: string
          id: string
          opened_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          allow_negative?: boolean
          asset: string
          balance?: number
          bucket: string
          id?: string
          opened_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          allow_negative?: boolean
          asset?: string
          balance?: number
          bucket?: string
          id?: string
          opened_at?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ledger_account_asset_fkey"
            columns: ["asset"]
            isOneToOne: false
            referencedRelation: "ledger_asset"
            referencedColumns: ["asset"]
          },
        ]
      }
      ledger_anchor: {
        Row: {
          attempts: number
          block_hash: string | null
          block_number: number | null
          chain_id: number | null
          claimed_at: string | null
          claimed_by: string | null
          confirmations: number
          confirmed_at: string | null
          content_hash: string
          enqueued_at: string
          failed_at: string | null
          hash_algorithm: string
          id: string
          journal_id: string
          last_error: string | null
          lease_expires_at: string | null
          ledger_label: string
          reorg_count: number
          required_confirmations: number | null
          status: string
          submitted_at: string | null
          tx_hash: string | null
          updated_at: string
        }
        Insert: {
          attempts?: number
          block_hash?: string | null
          block_number?: number | null
          chain_id?: number | null
          claimed_at?: string | null
          claimed_by?: string | null
          confirmations?: number
          confirmed_at?: string | null
          content_hash: string
          enqueued_at?: string
          failed_at?: string | null
          hash_algorithm?: string
          id?: string
          journal_id: string
          last_error?: string | null
          lease_expires_at?: string | null
          ledger_label?: string
          reorg_count?: number
          required_confirmations?: number | null
          status?: string
          submitted_at?: string | null
          tx_hash?: string | null
          updated_at?: string
        }
        Update: {
          attempts?: number
          block_hash?: string | null
          block_number?: number | null
          chain_id?: number | null
          claimed_at?: string | null
          claimed_by?: string | null
          confirmations?: number
          confirmed_at?: string | null
          content_hash?: string
          enqueued_at?: string
          failed_at?: string | null
          hash_algorithm?: string
          id?: string
          journal_id?: string
          last_error?: string | null
          lease_expires_at?: string | null
          ledger_label?: string
          reorg_count?: number
          required_confirmations?: number | null
          status?: string
          submitted_at?: string | null
          tx_hash?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ledger_anchor_chain_id_fkey"
            columns: ["chain_id"]
            isOneToOne: false
            referencedRelation: "ledger_anchor_chain"
            referencedColumns: ["chain_id"]
          },
          {
            foreignKeyName: "ledger_anchor_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: true
            referencedRelation: "ledger_anchor_queue"
            referencedColumns: ["journal_id"]
          },
          {
            foreignKeyName: "ledger_anchor_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: true
            referencedRelation: "ledger_journal"
            referencedColumns: ["id"]
          },
        ]
      }
      ledger_anchor_attempt: {
        Row: {
          anchor_id: string
          attempt_no: number
          chain_id: number | null
          confirmations: number | null
          created_at: string
          detail: string | null
          id: string
          journal_id: string
          outcome: string
          tx_hash: string | null
          worker: string | null
        }
        Insert: {
          anchor_id: string
          attempt_no: number
          chain_id?: number | null
          confirmations?: number | null
          created_at?: string
          detail?: string | null
          id?: string
          journal_id: string
          outcome: string
          tx_hash?: string | null
          worker?: string | null
        }
        Update: {
          anchor_id?: string
          attempt_no?: number
          chain_id?: number | null
          confirmations?: number | null
          created_at?: string
          detail?: string | null
          id?: string
          journal_id?: string
          outcome?: string
          tx_hash?: string | null
          worker?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ledger_anchor_attempt_anchor_id_fkey"
            columns: ["anchor_id"]
            isOneToOne: false
            referencedRelation: "ledger_anchor"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_anchor_attempt_anchor_id_fkey"
            columns: ["anchor_id"]
            isOneToOne: false
            referencedRelation: "ledger_anchor_queue"
            referencedColumns: ["anchor_id"]
          },
        ]
      }
      ledger_anchor_chain: {
        Row: {
          anchor_target: string | null
          chain_id: number
          contract_address: string | null
          created_at: string
          disabled_reason: string | null
          enabled: boolean
          explorer_url: string | null
          is_default: boolean
          last_probe_at: string | null
          last_probe_error: string | null
          last_probe_ok: boolean | null
          name: string
          native_decimals: number
          native_symbol: string
          required_confirmations: number
          rpc_url: string | null
          tx_hash_pattern: string
          updated_at: string
        }
        Insert: {
          anchor_target?: string | null
          chain_id: number
          contract_address?: string | null
          created_at?: string
          disabled_reason?: string | null
          enabled?: boolean
          explorer_url?: string | null
          is_default?: boolean
          last_probe_at?: string | null
          last_probe_error?: string | null
          last_probe_ok?: boolean | null
          name: string
          native_decimals: number
          native_symbol: string
          required_confirmations?: number
          rpc_url?: string | null
          tx_hash_pattern?: string
          updated_at?: string
        }
        Update: {
          anchor_target?: string | null
          chain_id?: number
          contract_address?: string | null
          created_at?: string
          disabled_reason?: string | null
          enabled?: boolean
          explorer_url?: string | null
          is_default?: boolean
          last_probe_at?: string | null
          last_probe_error?: string | null
          last_probe_ok?: boolean | null
          name?: string
          native_decimals?: number
          native_symbol?: string
          required_confirmations?: number
          rpc_url?: string | null
          tx_hash_pattern?: string
          updated_at?: string
        }
        Relationships: []
      }
      ledger_asset: {
        Row: {
          asset: string
          created_at: string
          kind: string
          legacy_store: string
          scale: number
        }
        Insert: {
          asset: string
          created_at?: string
          kind: string
          legacy_store: string
          scale: number
        }
        Update: {
          asset?: string
          created_at?: string
          kind?: string
          legacy_store?: string
          scale?: number
        }
        Relationships: []
      }
      ledger_entry: {
        Row: {
          account_id: string
          amount: number
          asset: string
          balance_after: number
          created_at: string
          id: string
          journal_id: string
        }
        Insert: {
          account_id: string
          amount: number
          asset: string
          balance_after: number
          created_at?: string
          id?: string
          journal_id: string
        }
        Update: {
          account_id?: string
          amount?: number
          asset?: string
          balance_after?: number
          created_at?: string
          id?: string
          journal_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ledger_entry_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "ledger_account"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_entry_asset_fkey"
            columns: ["asset"]
            isOneToOne: false
            referencedRelation: "ledger_asset"
            referencedColumns: ["asset"]
          },
          {
            foreignKeyName: "ledger_entry_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: false
            referencedRelation: "ledger_anchor_queue"
            referencedColumns: ["journal_id"]
          },
          {
            foreignKeyName: "ledger_entry_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: false
            referencedRelation: "ledger_journal"
            referencedColumns: ["id"]
          },
        ]
      }
      ledger_journal: {
        Row: {
          entry_count: number
          id: string
          posted_at: string
          posted_by: string | null
          posted_role: string
          reason: string
          reference: string
        }
        Insert: {
          entry_count: number
          id?: string
          posted_at?: string
          posted_by?: string | null
          posted_role: string
          reason: string
          reference: string
        }
        Update: {
          entry_count?: number
          id?: string
          posted_at?: string
          posted_by?: string | null
          posted_role?: string
          reason?: string
          reference?: string
        }
        Relationships: []
      }
      ledger_system: {
        Row: {
          code: string
          description: string
          user_id: string
        }
        Insert: {
          code: string
          description: string
          user_id: string
        }
        Update: {
          code?: string
          description?: string
          user_id?: string
        }
        Relationships: []
      }
      liquidity_pools: {
        Row: {
          apy: number | null
          apy_rate: number
          base_token: string | null
          created_at: string
          description: string | null
          fee_percentage: number | null
          id: string
          is_active: boolean
          pool_name: string
          pool_symbol: string
          pool_type: string
          quote_token: string | null
          total_liquidity: number
          total_liquidity_usd: number
          updated_at: string
        }
        Insert: {
          apy?: number | null
          apy_rate?: number
          base_token?: string | null
          created_at?: string
          description?: string | null
          fee_percentage?: number | null
          id?: string
          is_active?: boolean
          pool_name: string
          pool_symbol: string
          pool_type: string
          quote_token?: string | null
          total_liquidity?: number
          total_liquidity_usd?: number
          updated_at?: string
        }
        Update: {
          apy?: number | null
          apy_rate?: number
          base_token?: string | null
          created_at?: string
          description?: string | null
          fee_percentage?: number | null
          id?: string
          is_active?: boolean
          pool_name?: string
          pool_symbol?: string
          pool_type?: string
          quote_token?: string | null
          total_liquidity?: number
          total_liquidity_usd?: number
          updated_at?: string
        }
        Relationships: []
      }
      liquidity_transactions: {
        Row: {
          amount: number
          created_at: string
          id: string
          pool_id: string
          status: string
          transaction_hash: string | null
          transaction_type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          pool_id: string
          status?: string
          transaction_hash?: string | null
          transaction_type: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          pool_id?: string
          status?: string
          transaction_hash?: string | null
          transaction_type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "liquidity_transactions_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "liquidity_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      marketplace_escrow_balances: {
        Row: {
          amount: number
          asset_symbol: string
          created_at: string
          id: string
          listing_id: string
          released_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          amount: number
          asset_symbol: string
          created_at?: string
          id?: string
          listing_id: string
          released_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          amount?: number
          asset_symbol?: string
          created_at?: string
          id?: string
          listing_id?: string
          released_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketplace_escrow_balances_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "token_marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      marketplace_stablecoin_wallets: {
        Row: {
          created_at: string
          id: string
          network: string
          updated_at: string
          usdc_address: string | null
          usdt_address: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          network?: string
          updated_at?: string
          usdc_address?: string | null
          usdt_address?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          network?: string
          updated_at?: string
          usdc_address?: string | null
          usdt_address?: string | null
          user_id?: string
        }
        Relationships: []
      }
      member_support_tickets: {
        Row: {
          admin_notes: string | null
          category: string
          created_at: string
          error_details: string
          full_name: string | null
          id: string
          resolution_time_hours: number | null
          resolved_at: string | null
          resolved_by: string | null
          severity: string
          status: string
          str_domain: string | null
          updated_at: string
          user_email: string
          user_id: string
          user_phone: string | null
        }
        Insert: {
          admin_notes?: string | null
          category: string
          created_at?: string
          error_details: string
          full_name?: string | null
          id?: string
          resolution_time_hours?: number | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity?: string
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_email: string
          user_id: string
          user_phone?: string | null
        }
        Update: {
          admin_notes?: string | null
          category?: string
          created_at?: string
          error_details?: string
          full_name?: string | null
          id?: string
          resolution_time_hours?: number | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity?: string
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_email?: string
          user_id?: string
          user_phone?: string | null
        }
        Relationships: []
      }
      merchant_account_applications: {
        Row: {
          admin_notes: string | null
          average_transaction_size: string | null
          business_description: string | null
          business_domain_id: string
          business_name: string
          created_at: string
          expected_monthly_volume: string | null
          id: string
          personal_banking_id: string
          processed_at: string | null
          processed_by: string | null
          products_services: string | null
          requested_products: Json | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          average_transaction_size?: string | null
          business_description?: string | null
          business_domain_id: string
          business_name: string
          created_at?: string
          expected_monthly_volume?: string | null
          id?: string
          personal_banking_id: string
          processed_at?: string | null
          processed_by?: string | null
          products_services?: string | null
          requested_products?: Json | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          average_transaction_size?: string | null
          business_description?: string | null
          business_domain_id?: string
          business_name?: string
          created_at?: string
          expected_monthly_volume?: string | null
          id?: string
          personal_banking_id?: string
          processed_at?: string | null
          processed_by?: string | null
          products_services?: string | null
          requested_products?: Json | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "merchant_account_applications_business_domain_id_fkey"
            columns: ["business_domain_id"]
            isOneToOne: false
            referencedRelation: "business_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      merchant_accounts: {
        Row: {
          api_key_hash: string | null
          application_id: string
          business_domain_id: string
          business_name: string
          chf_iban_id: string | null
          created_at: string
          eur_iban_id: string | null
          gbp_iban_id: string | null
          id: string
          merchant_id: string
          payment_processing_enabled: boolean | null
          status: string
          updated_at: string
          usd_iban_id: string | null
          user_id: string
          webhook_url: string | null
        }
        Insert: {
          api_key_hash?: string | null
          application_id: string
          business_domain_id: string
          business_name: string
          chf_iban_id?: string | null
          created_at?: string
          eur_iban_id?: string | null
          gbp_iban_id?: string | null
          id?: string
          merchant_id: string
          payment_processing_enabled?: boolean | null
          status?: string
          updated_at?: string
          usd_iban_id?: string | null
          user_id: string
          webhook_url?: string | null
        }
        Update: {
          api_key_hash?: string | null
          application_id?: string
          business_domain_id?: string
          business_name?: string
          chf_iban_id?: string | null
          created_at?: string
          eur_iban_id?: string | null
          gbp_iban_id?: string | null
          id?: string
          merchant_id?: string
          payment_processing_enabled?: boolean | null
          status?: string
          updated_at?: string
          usd_iban_id?: string | null
          user_id?: string
          webhook_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "merchant_accounts_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "merchant_account_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "merchant_accounts_business_domain_id_fkey"
            columns: ["business_domain_id"]
            isOneToOne: false
            referencedRelation: "business_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      merchant_business_ibans: {
        Row: {
          account_holder: string
          balance: number
          bic: string
          created_at: string
          currency: string
          iban: string
          id: string
          is_encrypted: boolean | null
          merchant_id: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_holder: string
          balance?: number
          bic: string
          created_at?: string
          currency: string
          iban: string
          id?: string
          is_encrypted?: boolean | null
          merchant_id: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_holder?: string
          balance?: number
          bic?: string
          created_at?: string
          currency?: string
          iban?: string
          id?: string
          is_encrypted?: boolean | null
          merchant_id?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "merchant_business_ibans_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "merchant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      merchant_products: {
        Row: {
          category: string | null
          created_at: string
          crypto_currency: string | null
          crypto_price: number | null
          description: string | null
          id: string
          image_url: string | null
          is_active: boolean | null
          is_digital: boolean | null
          merchant_id: string
          metadata: Json | null
          price: number
          price_currency: string
          product_name: string
          stock_quantity: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          crypto_currency?: string | null
          crypto_price?: number | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean | null
          is_digital?: boolean | null
          merchant_id: string
          metadata?: Json | null
          price: number
          price_currency?: string
          product_name: string
          stock_quantity?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          category?: string | null
          created_at?: string
          crypto_currency?: string | null
          crypto_price?: number | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean | null
          is_digital?: boolean | null
          merchant_id?: string
          metadata?: Json | null
          price?: number
          price_currency?: string
          product_name?: string
          stock_quantity?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "merchant_products_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "merchant_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      migrated_accounts: {
        Row: {
          imported_at: string
          ledger_journal_id: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          source_email: string
          source_project: string
          source_snapshot: Json
          source_user_id: string
          state: Database["public"]["Enums"]["migration_state"]
          user_id: string
        }
        Insert: {
          imported_at?: string
          ledger_journal_id?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_email: string
          source_project: string
          source_snapshot?: Json
          source_user_id: string
          state?: Database["public"]["Enums"]["migration_state"]
          user_id: string
        }
        Update: {
          imported_at?: string
          ledger_journal_id?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_email?: string
          source_project?: string
          source_snapshot?: Json
          source_user_id?: string
          state?: Database["public"]["Enums"]["migration_state"]
          user_id?: string
        }
        Relationships: []
      }
      migration_login_attempts: {
        Row: {
          at: string
          email: string
          id: number
          ip: string
          succeeded: boolean
        }
        Insert: {
          at?: string
          email: string
          id?: number
          ip: string
          succeeded: boolean
        }
        Update: {
          at?: string
          email?: string
          id?: number
          ip?: string
          succeeded?: boolean
        }
        Relationships: []
      }
      missing_asset_reports: {
        Row: {
          admin_notes: string | null
          claimed_amounts: Json | null
          created_at: string
          email_address: string | null
          full_name: string | null
          id: string
          missing_crypto: string[] | null
          resolution_log: Json | null
          reviewed_at: string | null
          reviewed_by: string | null
          starw_nodes_count: number | null
          status: string
          supernodes_count: number | null
          transaction_hash: string | null
          updated_at: string
          user_comment: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          claimed_amounts?: Json | null
          created_at?: string
          email_address?: string | null
          full_name?: string | null
          id?: string
          missing_crypto?: string[] | null
          resolution_log?: Json | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          starw_nodes_count?: number | null
          status?: string
          supernodes_count?: number | null
          transaction_hash?: string | null
          updated_at?: string
          user_comment?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          claimed_amounts?: Json | null
          created_at?: string
          email_address?: string | null
          full_name?: string | null
          id?: string
          missing_crypto?: string[] | null
          resolution_log?: Json | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          starw_nodes_count?: number | null
          status?: string
          supernodes_count?: number | null
          transaction_hash?: string | null
          updated_at?: string
          user_comment?: string | null
          user_id?: string
        }
        Relationships: []
      }
      pending_balance_locks: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          locked_amount: number
          token_type: string
          transaction_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at?: string
          id?: string
          locked_amount: number
          token_type: string
          transaction_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          locked_amount?: number
          token_type?: string
          transaction_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pending_balance_locks_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: true
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      pending_profile_changes: {
        Row: {
          admin_notes: string | null
          change_reason: string | null
          confirmation_token: string | null
          created_at: string
          id: string
          ip_address: unknown
          requested_changes: Json
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          token_expires_at: string | null
          updated_at: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          change_reason?: string | null
          confirmation_token?: string | null
          created_at?: string
          id?: string
          ip_address?: unknown
          requested_changes: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          token_expires_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          change_reason?: string | null
          confirmation_token?: string | null
          created_at?: string
          id?: string
          ip_address?: unknown
          requested_changes?: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          token_expires_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      pending_transfers_treasury: {
        Row: {
          admin_notes: string | null
          amount: number
          created_at: string
          currency: string
          fee: number | null
          fee_ccos: number
          fee_ledger_id: string | null
          from_user_id: string
          held_until: string | null
          id: string
          metadata: Json | null
          processed_at: string | null
          processed_by: string | null
          rail: string | null
          status: string
          to_identifier: string
          transfer_type: string
          tx_id: string
        }
        Insert: {
          admin_notes?: string | null
          amount: number
          created_at?: string
          currency: string
          fee?: number | null
          fee_ccos?: number
          fee_ledger_id?: string | null
          from_user_id: string
          held_until?: string | null
          id?: string
          metadata?: Json | null
          processed_at?: string | null
          processed_by?: string | null
          rail?: string | null
          status?: string
          to_identifier: string
          transfer_type: string
          tx_id: string
        }
        Update: {
          admin_notes?: string | null
          amount?: number
          created_at?: string
          currency?: string
          fee?: number | null
          fee_ccos?: number
          fee_ledger_id?: string | null
          from_user_id?: string
          held_until?: string | null
          id?: string
          metadata?: Json | null
          processed_at?: string | null
          processed_by?: string | null
          rail?: string | null
          status?: string
          to_identifier?: string
          transfer_type?: string
          tx_id?: string
        }
        Relationships: []
      }
      personal_nodes: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          node_name: string
          node_number: number
          str_domain: string
          updated_at: string
          user_id: string
          wallet_address: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          node_name?: string
          node_number: number
          str_domain: string
          updated_at?: string
          user_id: string
          wallet_address: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          node_name?: string
          node_number?: number
          str_domain?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string
        }
        Relationships: []
      }
      pin_reset_otps: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          otp_hash: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          otp_hash: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          otp_hash?: string
          user_id?: string
        }
        Relationships: []
      }
      pool_access: {
        Row: {
          expires_at: string | null
          granted_at: string
          granted_by: string
          id: string
          is_active: boolean
          user_id: string
        }
        Insert: {
          expires_at?: string | null
          granted_at?: string
          granted_by: string
          id?: string
          is_active?: boolean
          user_id: string
        }
        Update: {
          expires_at?: string | null
          granted_at?: string
          granted_by?: string
          id?: string
          is_active?: boolean
          user_id?: string
        }
        Relationships: []
      }
      pos_transactions: {
        Row: {
          amount: number
          completed_at: string | null
          created_at: string
          currency: string
          customer_user_id: string | null
          description: string | null
          exchange_rate: number | null
          fiat_currency: string | null
          fiat_equivalent: number | null
          id: string
          merchant_id: string
          merchant_user_id: string
          metadata: Json | null
          payment_method: string | null
          product_id: string | null
          reference_id: string
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          completed_at?: string | null
          created_at?: string
          currency: string
          customer_user_id?: string | null
          description?: string | null
          exchange_rate?: number | null
          fiat_currency?: string | null
          fiat_equivalent?: number | null
          id?: string
          merchant_id: string
          merchant_user_id: string
          metadata?: Json | null
          payment_method?: string | null
          product_id?: string | null
          reference_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          completed_at?: string | null
          created_at?: string
          currency?: string
          customer_user_id?: string | null
          description?: string | null
          exchange_rate?: number | null
          fiat_currency?: string | null
          fiat_equivalent?: number | null
          id?: string
          merchant_id?: string
          merchant_user_id?: string
          metadata?: Json | null
          payment_method?: string | null
          product_id?: string | null
          reference_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pos_transactions_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "merchant_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pos_transactions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "merchant_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pos_transactions_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "public_product_catalog"
            referencedColumns: ["id"]
          },
        ]
      }
      praeco_peers: {
        Row: {
          address: string
          id: string
          is_online: boolean | null
          last_seen: string | null
          metadata: Json | null
          node_id: string
          node_type: string
          port: number | null
          user_id: string
        }
        Insert: {
          address: string
          id?: string
          is_online?: boolean | null
          last_seen?: string | null
          metadata?: Json | null
          node_id: string
          node_type?: string
          port?: number | null
          user_id: string
        }
        Update: {
          address?: string
          id?: string
          is_online?: boolean | null
          last_seen?: string | null
          metadata?: Json | null
          node_id?: string
          node_type?: string
          port?: number | null
          user_id?: string
        }
        Relationships: []
      }
      prepaid_cards: {
        Row: {
          balance: number
          bin: string | null
          card_last4: string
          card_status: string | null
          card_type: string
          created_at: string
          currency: string
          domain_part: string | null
          expiry_date: string | null
          full_identifier: string | null
          id: string
          issuer: string | null
          masked_card: string
          metadata: Json | null
          network: string
          pan_hash: string | null
          physical_card: boolean | null
          shipping_status: string | null
          status: string
          updated_at: string
          user_id: string
          wallet_suffix: string | null
        }
        Insert: {
          balance?: number
          bin?: string | null
          card_last4: string
          card_status?: string | null
          card_type: string
          created_at?: string
          currency: string
          domain_part?: string | null
          expiry_date?: string | null
          full_identifier?: string | null
          id?: string
          issuer?: string | null
          masked_card: string
          metadata?: Json | null
          network?: string
          pan_hash?: string | null
          physical_card?: boolean | null
          shipping_status?: string | null
          status?: string
          updated_at?: string
          user_id: string
          wallet_suffix?: string | null
        }
        Update: {
          balance?: number
          bin?: string | null
          card_last4?: string
          card_status?: string | null
          card_type?: string
          created_at?: string
          currency?: string
          domain_part?: string | null
          expiry_date?: string | null
          full_identifier?: string | null
          id?: string
          issuer?: string | null
          masked_card?: string
          metadata?: Json | null
          network?: string
          pan_hash?: string | null
          physical_card?: boolean | null
          shipping_status?: string | null
          status?: string
          updated_at?: string
          user_id?: string
          wallet_suffix?: string | null
        }
        Relationships: []
      }
      private_digital_shares_purchases: {
        Row: {
          admin_notes: string | null
          affiliate_code: string | null
          created_at: string
          email: string
          full_name: string | null
          id: string
          metadata: Json | null
          payment_amount: number | null
          payment_crypto: string | null
          payment_deadline: string | null
          payment_hash: string | null
          payment_status: string
          price_per_share: number
          referred_by: string | null
          shares_quantity: number
          total_usd: number
          updated_at: string
          user_id: string
          wnft_redeemed_at: string | null
          wnft_status: string
        }
        Insert: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email: string
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string
          price_per_share?: number
          referred_by?: string | null
          shares_quantity: number
          total_usd: number
          updated_at?: string
          user_id: string
          wnft_redeemed_at?: string | null
          wnft_status?: string
        }
        Update: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string
          price_per_share?: number
          referred_by?: string | null
          shares_quantity?: number
          total_usd?: number
          updated_at?: string
          user_id?: string
          wnft_redeemed_at?: string | null
          wnft_status?: string
        }
        Relationships: []
      }
      private_seed_str_access_log: {
        Row: {
          action: string
          application_id: string
          created_at: string
          id: string
          ip_address: unknown
          user_agent: string | null
          user_id: string
        }
        Insert: {
          action: string
          application_id: string
          created_at?: string
          id?: string
          ip_address?: unknown
          user_agent?: string | null
          user_id: string
        }
        Update: {
          action?: string
          application_id?: string
          created_at?: string
          id?: string
          ip_address?: unknown
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "private_seed_str_access_log_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "private_seed_str_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      private_seed_str_applications: {
        Row: {
          acknowledgment_accepted: boolean
          admin_notes: string | null
          application_date: string | null
          browser: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          city: string | null
          country: string | null
          created_at: string | null
          credited_amount: number | null
          credited_at: string | null
          device_type: string | null
          email: string
          expected_return_rate: number | null
          full_name: string
          gdpr_accepted: boolean | null
          gdpr_accepted_at: string | null
          id: string
          investment_amount: number | null
          investment_tier: string | null
          ip_address: unknown
          location_city: string | null
          location_country: string | null
          lock_period_months: number | null
          metadata: Json | null
          nda_accepted: boolean | null
          nda_accepted_at: string | null
          payment_amount: number | null
          payment_crypto: string | null
          payment_deadline: string | null
          payment_hash: string | null
          payment_status: string | null
          payment_submitted_at: string | null
          phone: string | null
          postal_code: string | null
          presented_by: string | null
          processed_at: string | null
          processed_by: string | null
          purpose_of_report: string | null
          risk_disclosure_accepted: boolean | null
          risk_disclosure_accepted_at: string | null
          signature_date: string | null
          signature_first_name: string | null
          signature_last_name: string | null
          state_province: string | null
          status: string | null
          str_backing_amount: number | null
          str_shares_credited: number | null
          street_address: string | null
          suspended_at: string | null
          suspended_by: string | null
          suspension_reason: string | null
          terms_accepted: boolean | null
          terms_accepted_at: string | null
          updated_at: string | null
          user_agent: string | null
          user_id: string
        }
        Insert: {
          acknowledgment_accepted?: boolean
          admin_notes?: string | null
          application_date?: string | null
          browser?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          city?: string | null
          country?: string | null
          created_at?: string | null
          credited_amount?: number | null
          credited_at?: string | null
          device_type?: string | null
          email: string
          expected_return_rate?: number | null
          full_name: string
          gdpr_accepted?: boolean | null
          gdpr_accepted_at?: string | null
          id?: string
          investment_amount?: number | null
          investment_tier?: string | null
          ip_address?: unknown
          location_city?: string | null
          location_country?: string | null
          lock_period_months?: number | null
          metadata?: Json | null
          nda_accepted?: boolean | null
          nda_accepted_at?: string | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string | null
          payment_submitted_at?: string | null
          phone?: string | null
          postal_code?: string | null
          presented_by?: string | null
          processed_at?: string | null
          processed_by?: string | null
          purpose_of_report?: string | null
          risk_disclosure_accepted?: boolean | null
          risk_disclosure_accepted_at?: string | null
          signature_date?: string | null
          signature_first_name?: string | null
          signature_last_name?: string | null
          state_province?: string | null
          status?: string | null
          str_backing_amount?: number | null
          str_shares_credited?: number | null
          street_address?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          terms_accepted?: boolean | null
          terms_accepted_at?: string | null
          updated_at?: string | null
          user_agent?: string | null
          user_id: string
        }
        Update: {
          acknowledgment_accepted?: boolean
          admin_notes?: string | null
          application_date?: string | null
          browser?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          city?: string | null
          country?: string | null
          created_at?: string | null
          credited_amount?: number | null
          credited_at?: string | null
          device_type?: string | null
          email?: string
          expected_return_rate?: number | null
          full_name?: string
          gdpr_accepted?: boolean | null
          gdpr_accepted_at?: string | null
          id?: string
          investment_amount?: number | null
          investment_tier?: string | null
          ip_address?: unknown
          location_city?: string | null
          location_country?: string | null
          lock_period_months?: number | null
          metadata?: Json | null
          nda_accepted?: boolean | null
          nda_accepted_at?: string | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string | null
          payment_submitted_at?: string | null
          phone?: string | null
          postal_code?: string | null
          presented_by?: string | null
          processed_at?: string | null
          processed_by?: string | null
          purpose_of_report?: string | null
          risk_disclosure_accepted?: boolean | null
          risk_disclosure_accepted_at?: string | null
          signature_date?: string | null
          signature_first_name?: string | null
          signature_last_name?: string | null
          state_province?: string | null
          status?: string | null
          str_backing_amount?: number | null
          str_shares_credited?: number | null
          street_address?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          terms_accepted?: boolean | null
          terms_accepted_at?: string | null
          updated_at?: string | null
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      private_seed_str_audit_log: {
        Row: {
          action_details: Json | null
          action_type: string
          application_id: string | null
          created_at: string | null
          id: string
          performed_by: string
          user_id: string
        }
        Insert: {
          action_details?: Json | null
          action_type: string
          application_id?: string | null
          created_at?: string | null
          id?: string
          performed_by: string
          user_id: string
        }
        Update: {
          action_details?: Json | null
          action_type?: string
          application_id?: string | null
          created_at?: string | null
          id?: string
          performed_by?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "private_seed_str_audit_log_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "private_seed_str_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      private_str_ipo_purchases: {
        Row: {
          admin_notes: string | null
          affiliate_code: string | null
          created_at: string
          email: string
          full_name: string | null
          id: string
          metadata: Json | null
          payment_amount: number | null
          payment_crypto: string | null
          payment_deadline: string | null
          payment_hash: string | null
          payment_status: string
          phase: string
          price_per_str: number
          processed_at: string | null
          processed_by: string | null
          referred_by: string | null
          str_amount: number
          updated_at: string
          usd_amount: number
          user_id: string
          vesting_end_date: string | null
        }
        Insert: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email: string
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string
          phase?: string
          price_per_str: number
          processed_at?: string | null
          processed_by?: string | null
          referred_by?: string | null
          str_amount: number
          updated_at?: string
          usd_amount: number
          user_id: string
          vesting_end_date?: string | null
        }
        Update: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string
          phase?: string
          price_per_str?: number
          processed_at?: string | null
          processed_by?: string | null
          referred_by?: string | null
          str_amount?: number
          updated_at?: string
          usd_amount?: number
          user_id?: string
          vesting_end_date?: string | null
        }
        Relationships: []
      }
      private_str_prelisting_purchases: {
        Row: {
          admin_notes: string | null
          affiliate_code: string | null
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          metadata: Json | null
          payment_amount: number | null
          payment_crypto: string | null
          payment_deadline: string | null
          payment_hash: string | null
          payment_network: string | null
          payment_status: string
          phase: string
          price_per_str: number
          referred_by: string | null
          str_amount: number
          updated_at: string
          usd_amount: number
          user_id: string
          vesting_end_date: string | null
        }
        Insert: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_network?: string | null
          payment_status?: string
          phase: string
          price_per_str: number
          referred_by?: string | null
          str_amount: number
          updated_at?: string
          usd_amount: number
          user_id: string
          vesting_end_date?: string | null
        }
        Update: {
          admin_notes?: string | null
          affiliate_code?: string | null
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          metadata?: Json | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_network?: string | null
          payment_status?: string
          phase?: string
          price_per_str?: number
          referred_by?: string | null
          str_amount?: number
          updated_at?: string
          usd_amount?: number
          user_id?: string
          vesting_end_date?: string | null
        }
        Relationships: []
      }
      profile_change_otps: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          otp_hash: string
          pending_change_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          otp_hash: string
          pending_change_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          otp_hash?: string
          pending_change_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_change_otps_pending_change_id_fkey"
            columns: ["pending_change_id"]
            isOneToOne: false
            referencedRelation: "pending_profile_changes"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_changes: {
        Row: {
          change_reason: string | null
          changed_by: string
          created_at: string
          field_name: string
          id: string
          ip_address: unknown
          new_value: string | null
          old_value: string | null
          user_agent: string | null
          user_id: string
        }
        Insert: {
          change_reason?: string | null
          changed_by: string
          created_at?: string
          field_name: string
          id?: string
          ip_address?: unknown
          new_value?: string | null
          old_value?: string | null
          user_agent?: string | null
          user_id: string
        }
        Update: {
          change_reason?: string | null
          changed_by?: string
          created_at?: string
          field_name?: string
          id?: string
          ip_address?: unknown
          new_value?: string | null
          old_value?: string | null
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string | null
          id: string
          role: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name?: string | null
          id?: string
          role?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          role?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      quarantined_balances: {
        Row: {
          asset: string
          bucket: string
          corrected_amount: number | null
          corrected_at: string | null
          corrected_by: string | null
          id: string
          note: string | null
          source_amount: number
          user_id: string
        }
        Insert: {
          asset: string
          bucket?: string
          corrected_amount?: number | null
          corrected_at?: string | null
          corrected_by?: string | null
          id?: string
          note?: string | null
          source_amount?: number
          user_id: string
        }
        Update: {
          asset?: string
          bucket?: string
          corrected_amount?: number | null
          corrected_at?: string | null
          corrected_by?: string | null
          id?: string
          note?: string | null
          source_amount?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quarantined_balances_asset_fkey"
            columns: ["asset"]
            isOneToOne: false
            referencedRelation: "ledger_asset"
            referencedColumns: ["asset"]
          },
        ]
      }
      referrals: {
        Row: {
          claimed_at: string | null
          created_at: string
          id: string
          referred_id: string
          referrer_id: string
          reward_amount: number | null
          reward_claimed: boolean | null
          status: string
        }
        Insert: {
          claimed_at?: string | null
          created_at?: string
          id?: string
          referred_id: string
          referrer_id: string
          reward_amount?: number | null
          reward_claimed?: boolean | null
          status?: string
        }
        Update: {
          claimed_at?: string | null
          created_at?: string
          id?: string
          referred_id?: string
          referrer_id?: string
          reward_amount?: number | null
          reward_claimed?: boolean | null
          status?: string
        }
        Relationships: []
      }
      safe_admins: {
        Row: {
          created_at: string
          full_name: string | null
          granted_by: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          full_name?: string | null
          granted_by?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          full_name?: string | null
          granted_by?: string | null
          user_id?: string
        }
        Relationships: []
      }
      safe_purchases: {
        Row: {
          address: string
          bonus_pct: number
          bonus_shares: number
          created_at: string
          credited_at: string | null
          credited_by: string | null
          credited_shares: number | null
          crypto: string
          email: string
          full_name: string
          id: string
          notes: string | null
          pep_declared: boolean
          phone: string
          presenter_email: string | null
          presenter_full_name: string | null
          presenter_phone: string | null
          presenter_ref: string | null
          price_per_share_usd: number
          shares: number
          status: string
          total_shares: number
          total_usd: number
          tx_hash: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          address: string
          bonus_pct?: number
          bonus_shares?: number
          created_at?: string
          credited_at?: string | null
          credited_by?: string | null
          credited_shares?: number | null
          crypto: string
          email: string
          full_name: string
          id?: string
          notes?: string | null
          pep_declared?: boolean
          phone: string
          presenter_email?: string | null
          presenter_full_name?: string | null
          presenter_phone?: string | null
          presenter_ref?: string | null
          price_per_share_usd?: number
          shares: number
          status?: string
          total_shares: number
          total_usd: number
          tx_hash: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          address?: string
          bonus_pct?: number
          bonus_shares?: number
          created_at?: string
          credited_at?: string | null
          credited_by?: string | null
          credited_shares?: number | null
          crypto?: string
          email?: string
          full_name?: string
          id?: string
          notes?: string | null
          pep_declared?: boolean
          phone?: string
          presenter_email?: string | null
          presenter_full_name?: string | null
          presenter_phone?: string | null
          presenter_ref?: string | null
          price_per_share_usd?: number
          shares?: number
          status?: string
          total_shares?: number
          total_usd?: number
          tx_hash?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      security_audit_log: {
        Row: {
          action: string
          created_at: string | null
          details: Json | null
          id: string
          ip_address: unknown
          resource_id: string | null
          resource_type: string
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          action: string
          created_at?: string | null
          details?: Json | null
          id?: string
          ip_address?: unknown
          resource_id?: string | null
          resource_type: string
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string | null
          details?: Json | null
          id?: string
          ip_address?: unknown
          resource_id?: string | null
          resource_type?: string
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      security_events: {
        Row: {
          created_at: string
          details: Json | null
          event_type: string
          id: string
          ip_address: unknown
          severity: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          details?: Json | null
          event_type: string
          id?: string
          ip_address?: unknown
          severity: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          details?: Json | null
          event_type?: string
          id?: string
          ip_address?: unknown
          severity?: string
          user_id?: string | null
        }
        Relationships: []
      }
      seed_str_affiliates: {
        Row: {
          affiliate_code: string
          created_at: string
          email: string
          full_name: string
          id: string
          status: string | null
          str_domain: string
          total_conversions: number | null
          total_investment_referred: number | null
          total_referrals: number | null
          updated_at: string
          usdc_address: string | null
          usdc_network: string | null
          usdt_address: string | null
          usdt_network: string | null
          user_id: string
        }
        Insert: {
          affiliate_code: string
          created_at?: string
          email: string
          full_name: string
          id?: string
          status?: string | null
          str_domain: string
          total_conversions?: number | null
          total_investment_referred?: number | null
          total_referrals?: number | null
          updated_at?: string
          usdc_address?: string | null
          usdc_network?: string | null
          usdt_address?: string | null
          usdt_network?: string | null
          user_id: string
        }
        Update: {
          affiliate_code?: string
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          status?: string | null
          str_domain?: string
          total_conversions?: number | null
          total_investment_referred?: number | null
          total_referrals?: number | null
          updated_at?: string
          usdc_address?: string | null
          usdc_network?: string | null
          usdt_address?: string | null
          usdt_network?: string | null
          user_id?: string
        }
        Relationships: []
      }
      seed_str_applications: {
        Row: {
          admin_notes: string | null
          affiliate_email: string | null
          affiliate_id: string | null
          affiliate_name: string | null
          application_date: string
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          credited_amount: number | null
          credited_at: string | null
          email: string
          expected_return_rate: number
          full_name: string
          gdpr_accepted: boolean
          gdpr_accepted_at: string | null
          id: string
          investment_amount: number
          investment_currency: string
          investment_tier: string
          ip_address: unknown
          lock_period_months: number
          metadata: Json | null
          nda_accepted: boolean
          nda_accepted_at: string | null
          payment_amount: number | null
          payment_crypto: string | null
          payment_deadline: string | null
          payment_hash: string | null
          payment_status: string | null
          payment_submitted_at: string | null
          payment_verified_at: string | null
          payment_verified_by: string | null
          processed_at: string | null
          processed_by: string | null
          risk_disclosure_accepted: boolean
          risk_disclosure_accepted_at: string | null
          status: string
          str_backing_amount: number
          str_shares_credited: number | null
          suspended_at: string | null
          suspended_by: string | null
          suspension_reason: string | null
          terms_accepted: boolean
          terms_accepted_at: string | null
          updated_at: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          affiliate_email?: string | null
          affiliate_id?: string | null
          affiliate_name?: string | null
          application_date?: string
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          email: string
          expected_return_rate?: number
          full_name: string
          gdpr_accepted?: boolean
          gdpr_accepted_at?: string | null
          id?: string
          investment_amount?: number
          investment_currency?: string
          investment_tier?: string
          ip_address?: unknown
          lock_period_months?: number
          metadata?: Json | null
          nda_accepted?: boolean
          nda_accepted_at?: string | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string | null
          payment_submitted_at?: string | null
          payment_verified_at?: string | null
          payment_verified_by?: string | null
          processed_at?: string | null
          processed_by?: string | null
          risk_disclosure_accepted?: boolean
          risk_disclosure_accepted_at?: string | null
          status?: string
          str_backing_amount?: number
          str_shares_credited?: number | null
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          terms_accepted?: boolean
          terms_accepted_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          affiliate_email?: string | null
          affiliate_id?: string | null
          affiliate_name?: string | null
          application_date?: string
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          email?: string
          expected_return_rate?: number
          full_name?: string
          gdpr_accepted?: boolean
          gdpr_accepted_at?: string | null
          id?: string
          investment_amount?: number
          investment_currency?: string
          investment_tier?: string
          ip_address?: unknown
          lock_period_months?: number
          metadata?: Json | null
          nda_accepted?: boolean
          nda_accepted_at?: string | null
          payment_amount?: number | null
          payment_crypto?: string | null
          payment_deadline?: string | null
          payment_hash?: string | null
          payment_status?: string | null
          payment_submitted_at?: string | null
          payment_verified_at?: string | null
          payment_verified_by?: string | null
          processed_at?: string | null
          processed_by?: string | null
          risk_disclosure_accepted?: boolean
          risk_disclosure_accepted_at?: string | null
          status?: string
          str_backing_amount?: number
          str_shares_credited?: number | null
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          terms_accepted?: boolean
          terms_accepted_at?: string | null
          updated_at?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "seed_str_applications_affiliate_id_fkey"
            columns: ["affiliate_id"]
            isOneToOne: false
            referencedRelation: "seed_str_affiliates"
            referencedColumns: ["id"]
          },
        ]
      }
      seed_str_audit_log: {
        Row: {
          action_details: Json | null
          action_type: string
          application_id: string | null
          created_at: string
          id: string
          ip_address: unknown
          performed_by: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          action_details?: Json | null
          action_type: string
          application_id?: string | null
          created_at?: string
          id?: string
          ip_address?: unknown
          performed_by: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          action_details?: Json | null
          action_type?: string
          application_id?: string | null
          created_at?: string
          id?: string
          ip_address?: unknown
          performed_by?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "seed_str_audit_log_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "seed_str_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      seed_str_backups: {
        Row: {
          backup_data: Json
          backup_name: string
          backup_type: string
          created_at: string
          created_by: string
          expires_at: string | null
          id: string
          total_applications: number
          total_investment_value: number
        }
        Insert: {
          backup_data: Json
          backup_name: string
          backup_type?: string
          created_at?: string
          created_by: string
          expires_at?: string | null
          id?: string
          total_applications?: number
          total_investment_value?: number
        }
        Update: {
          backup_data?: Json
          backup_name?: string
          backup_type?: string
          created_at?: string
          created_by?: string
          expires_at?: string | null
          id?: string
          total_applications?: number
          total_investment_value?: number
        }
        Relationships: []
      }
      seed_str_referrals: {
        Row: {
          affiliate_id: string
          application_id: string | null
          commission_amount: number | null
          converted_at: string | null
          created_at: string
          id: string
          investment_amount: number | null
          referred_user_id: string | null
          status: string | null
        }
        Insert: {
          affiliate_id: string
          application_id?: string | null
          commission_amount?: number | null
          converted_at?: string | null
          created_at?: string
          id?: string
          investment_amount?: number | null
          referred_user_id?: string | null
          status?: string | null
        }
        Update: {
          affiliate_id?: string
          application_id?: string | null
          commission_amount?: number | null
          converted_at?: string | null
          created_at?: string
          id?: string
          investment_amount?: number | null
          referred_user_id?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "seed_str_referrals_affiliate_id_fkey"
            columns: ["affiliate_id"]
            isOneToOne: false
            referencedRelation: "seed_str_affiliates"
            referencedColumns: ["id"]
          },
        ]
      }
      staking_data_cache: {
        Row: {
          cache_key: string
          created_at: string | null
          data: Json
          id: string
          updated_at: string | null
        }
        Insert: {
          cache_key: string
          created_at?: string | null
          data: Json
          id?: string
          updated_at?: string | null
        }
        Update: {
          cache_key?: string
          created_at?: string | null
          data?: Json
          id?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      staking_pool_duplicate_backlog: {
        Row: {
          blocks: string
          detected_at: string
          id: string
          pool_type: string
          resolution: string | null
          resolved_at: string | null
          row_count: number
          rows: Json
          stake_duration_months: number | null
          user_id: string
        }
        Insert: {
          blocks: string
          detected_at?: string
          id?: string
          pool_type: string
          resolution?: string | null
          resolved_at?: string | null
          row_count: number
          rows: Json
          stake_duration_months?: number | null
          user_id: string
        }
        Update: {
          blocks?: string
          detected_at?: string
          id?: string
          pool_type?: string
          resolution?: string | null
          resolved_at?: string | null
          row_count?: number
          rows?: Json
          stake_duration_months?: number | null
          user_id?: string
        }
        Relationships: []
      }
      staking_requests: {
        Row: {
          admin_notes: string | null
          amount: number
          approved_by: string | null
          created_at: string | null
          description: string | null
          domain_name: string | null
          duration_months: number
          full_name: string | null
          id: string
          pool_type: string
          processed_at: string | null
          request_type: string
          requested_at: string | null
          status: string
          str_domain_owned: string | null
          str_domain_username: string | null
          transaction_hash: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          amount: number
          approved_by?: string | null
          created_at?: string | null
          description?: string | null
          domain_name?: string | null
          duration_months: number
          full_name?: string | null
          id?: string
          pool_type: string
          processed_at?: string | null
          request_type: string
          requested_at?: string | null
          status?: string
          str_domain_owned?: string | null
          str_domain_username?: string | null
          transaction_hash?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          amount?: number
          approved_by?: string | null
          created_at?: string | null
          description?: string | null
          domain_name?: string | null
          duration_months?: number
          full_name?: string | null
          id?: string
          pool_type?: string
          processed_at?: string | null
          request_type?: string
          requested_at?: string | null
          status?: string
          str_domain_owned?: string | null
          str_domain_username?: string | null
          transaction_hash?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      staking_rewards_distribution: {
        Row: {
          calculated_apy: number
          created_at: string | null
          distribution_date: string | null
          estimated_reward: number
          id: string
          network_efficiency: number | null
          pool_id: string
          stake_amount: number
          status: string | null
          user_id: string
        }
        Insert: {
          calculated_apy: number
          created_at?: string | null
          distribution_date?: string | null
          estimated_reward: number
          id?: string
          network_efficiency?: number | null
          pool_id: string
          stake_amount: number
          status?: string | null
          user_id: string
        }
        Update: {
          calculated_apy?: number
          created_at?: string | null
          distribution_date?: string | null
          estimated_reward?: number
          id?: string
          network_efficiency?: number | null
          pool_id?: string
          stake_amount?: number
          status?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staking_rewards_distribution_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "enhanced_staking_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      starw_interaction_history: {
        Row: {
          action_description: string
          action_type: string
          created_at: string
          id: string
          ip_address: unknown
          metadata: Json | null
          payment_details: Json | null
          performed_by: string | null
          starw_purchase_id: string | null
          status_from: string | null
          status_to: string | null
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          action_description: string
          action_type: string
          created_at?: string
          id?: string
          ip_address?: unknown
          metadata?: Json | null
          payment_details?: Json | null
          performed_by?: string | null
          starw_purchase_id?: string | null
          status_from?: string | null
          status_to?: string | null
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          action_description?: string
          action_type?: string
          created_at?: string
          id?: string
          ip_address?: unknown
          metadata?: Json | null
          payment_details?: Json | null
          performed_by?: string | null
          starw_purchase_id?: string | null
          status_from?: string | null
          status_to?: string | null
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "starw_interaction_history_starw_purchase_id_fkey"
            columns: ["starw_purchase_id"]
            isOneToOne: false
            referencedRelation: "starw_purchases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "starw_interaction_history_starw_purchase_id_fkey"
            columns: ["starw_purchase_id"]
            isOneToOne: false
            referencedRelation: "starw_purchases_comprehensive"
            referencedColumns: ["id"]
          },
        ]
      }
      starw_nodes: {
        Row: {
          assigned_at: string | null
          assigned_by: string | null
          created_at: string
          id: string
          node_number: number
          status: string
          updated_at: string
          user_id: string
          worker_nodes_count: number
        }
        Insert: {
          assigned_at?: string | null
          assigned_by?: string | null
          created_at?: string
          id?: string
          node_number: number
          status?: string
          updated_at?: string
          user_id: string
          worker_nodes_count?: number
        }
        Update: {
          assigned_at?: string | null
          assigned_by?: string | null
          created_at?: string
          id?: string
          node_number?: number
          status?: string
          updated_at?: string
          user_id?: string
          worker_nodes_count?: number
        }
        Relationships: []
      }
      starw_purchases: {
        Row: {
          admin_notes: string | null
          arss_bonus: string | null
          btc_amount: number | null
          created_at: string
          crypto_prices_at_purchase: Json | null
          email_address: string
          eth_amount: number | null
          full_name: string
          id: string
          ip_address: unknown
          node_count: number
          payment_currency: string | null
          payment_info: Json | null
          payment_method: string | null
          processed_at: string | null
          processed_by: string | null
          referral_source: string | null
          session_metadata: Json | null
          stage: number | null
          status: string
          str_domain: string | null
          total_cost: number
          updated_at: string
          user_agent: string | null
          user_id: string | null
          wallet_address: string | null
        }
        Insert: {
          admin_notes?: string | null
          arss_bonus?: string | null
          btc_amount?: number | null
          created_at?: string
          crypto_prices_at_purchase?: Json | null
          email_address: string
          eth_amount?: number | null
          full_name: string
          id?: string
          ip_address?: unknown
          node_count?: number
          payment_currency?: string | null
          payment_info?: Json | null
          payment_method?: string | null
          processed_at?: string | null
          processed_by?: string | null
          referral_source?: string | null
          session_metadata?: Json | null
          stage?: number | null
          status?: string
          str_domain?: string | null
          total_cost: number
          updated_at?: string
          user_agent?: string | null
          user_id?: string | null
          wallet_address?: string | null
        }
        Update: {
          admin_notes?: string | null
          arss_bonus?: string | null
          btc_amount?: number | null
          created_at?: string
          crypto_prices_at_purchase?: Json | null
          email_address?: string
          eth_amount?: number | null
          full_name?: string
          id?: string
          ip_address?: unknown
          node_count?: number
          payment_currency?: string | null
          payment_info?: Json | null
          payment_method?: string | null
          processed_at?: string | null
          processed_by?: string | null
          referral_source?: string | null
          session_metadata?: Json | null
          stage?: number | null
          status?: string
          str_domain?: string | null
          total_cost?: number
          updated_at?: string
          user_agent?: string | null
          user_id?: string | null
          wallet_address?: string | null
        }
        Relationships: []
      }
      starw_wstr_rewards: {
        Row: {
          created_at: string
          id: string
          reward_amount: number
          reward_date: string
          starw_node_id: string
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          reward_amount?: number
          reward_date?: string
          starw_node_id: string
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          reward_amount?: number
          reward_date?: string
          starw_node_id?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "starw_wstr_rewards_starw_node_id_fkey"
            columns: ["starw_node_id"]
            isOneToOne: false
            referencedRelation: "starw_nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      str_domain_connections: {
        Row: {
          api_key: string | null
          connection_status: string
          created_at: string
          domain_name: string
          id: string
          last_sync: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          api_key?: string | null
          connection_status?: string
          created_at?: string
          domain_name: string
          id?: string
          last_sync?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          api_key?: string | null
          connection_status?: string
          created_at?: string
          domain_name?: string
          id?: string
          last_sync?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      str_domains: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          domain_name: string
          domain_type: string
          domains_count: number | null
          id: string
          is_from_str_dome: boolean | null
          is_main_domain: boolean | null
          metadata: Json | null
          minted_at: string | null
          status: string
          str_dome_purchase_date: string | null
          str_dome_transaction_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          domain_name: string
          domain_type: string
          domains_count?: number | null
          id?: string
          is_from_str_dome?: boolean | null
          is_main_domain?: boolean | null
          metadata?: Json | null
          minted_at?: string | null
          status?: string
          str_dome_purchase_date?: string | null
          str_dome_transaction_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          domain_name?: string
          domain_type?: string
          domains_count?: number | null
          id?: string
          is_from_str_dome?: boolean | null
          is_main_domain?: boolean | null
          metadata?: Json | null
          minted_at?: string | null
          status?: string
          str_dome_purchase_date?: string | null
          str_dome_transaction_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      str_dome_requests: {
        Row: {
          account_email: string
          admin_notes: string | null
          created_at: string
          deliver_to_wallet: boolean
          delivery_email: string | null
          esim_country: string
          esim_file_path: string | null
          id: string
          notes: string | null
          package_name: string
          package_price_usd: number
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          str_dome_username: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_email: string
          admin_notes?: string | null
          created_at?: string
          deliver_to_wallet?: boolean
          delivery_email?: string | null
          esim_country: string
          esim_file_path?: string | null
          id?: string
          notes?: string | null
          package_name: string
          package_price_usd: number
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          str_dome_username: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_email?: string
          admin_notes?: string | null
          created_at?: string
          deliver_to_wallet?: boolean
          delivery_email?: string | null
          esim_country?: string
          esim_file_path?: string | null
          id?: string
          notes?: string | null
          package_name?: string
          package_price_usd?: number
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          str_dome_username?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      supernode_purchases: {
        Row: {
          btc_amount: number | null
          company_name: string | null
          created_at: string | null
          crypto_prices_at_purchase: Json | null
          email_address: string
          eth_amount: number | null
          full_name: string
          id: string
          package_type: string
          processed_at: string | null
          processed_by: string | null
          stage: number | null
          status: string | null
          str_domain: string | null
          supernode_count: number
          total_cost: number
          transaction_hash: string | null
          user_id: string | null
        }
        Insert: {
          btc_amount?: number | null
          company_name?: string | null
          created_at?: string | null
          crypto_prices_at_purchase?: Json | null
          email_address: string
          eth_amount?: number | null
          full_name: string
          id?: string
          package_type: string
          processed_at?: string | null
          processed_by?: string | null
          stage?: number | null
          status?: string | null
          str_domain?: string | null
          supernode_count?: number
          total_cost: number
          transaction_hash?: string | null
          user_id?: string | null
        }
        Update: {
          btc_amount?: number | null
          company_name?: string | null
          created_at?: string | null
          crypto_prices_at_purchase?: Json | null
          email_address?: string
          eth_amount?: number | null
          full_name?: string
          id?: string
          package_type?: string
          processed_at?: string | null
          processed_by?: string | null
          stage?: number | null
          status?: string | null
          str_domain?: string | null
          supernode_count?: number
          total_cost?: number
          transaction_hash?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      supernode_wstr_rewards: {
        Row: {
          created_at: string
          id: string
          reward_amount: number
          reward_date: string
          status: string
          supernode_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          reward_amount?: number
          reward_date?: string
          status?: string
          supernode_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          reward_amount?: number
          reward_date?: string
          status?: string
          supernode_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "supernode_wstr_rewards_supernode_id_fkey"
            columns: ["supernode_id"]
            isOneToOne: false
            referencedRelation: "supernodes"
            referencedColumns: ["id"]
          },
        ]
      }
      supernodes: {
        Row: {
          assigned_at: string | null
          assigned_by: string | null
          created_at: string
          id: string
          node_number: number
          status: string
          updated_at: string
          user_id: string
          worker_nodes_count: number
        }
        Insert: {
          assigned_at?: string | null
          assigned_by?: string | null
          created_at?: string
          id?: string
          node_number: number
          status?: string
          updated_at?: string
          user_id: string
          worker_nodes_count?: number
        }
        Update: {
          assigned_at?: string | null
          assigned_by?: string | null
          created_at?: string
          id?: string
          node_number?: number
          status?: string
          updated_at?: string
          user_id?: string
          worker_nodes_count?: number
        }
        Relationships: []
      }
      support_ticket_analyses: {
        Row: {
          analysis_result: string | null
          completed_at: string | null
          created_at: string
          created_by: string | null
          error_message: string | null
          id: string
          started_at: string | null
          status: string
          ticket_count: number
        }
        Insert: {
          analysis_result?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          id?: string
          started_at?: string | null
          status?: string
          ticket_count?: number
        }
        Update: {
          analysis_result?: string | null
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          error_message?: string | null
          id?: string
          started_at?: string | null
          status?: string
          ticket_count?: number
        }
        Relationships: []
      }
      support_ticket_fix_history: {
        Row: {
          actions_taken: Json
          admin_id: string | null
          after_state: Json
          before_state: Json
          created_at: string
          error_message: string | null
          fix_attempted_at: string
          fix_completed_at: string | null
          id: string
          issue_type: string
          success: boolean
          ticket_id: string
          user_id: string
        }
        Insert: {
          actions_taken?: Json
          admin_id?: string | null
          after_state?: Json
          before_state?: Json
          created_at?: string
          error_message?: string | null
          fix_attempted_at?: string
          fix_completed_at?: string | null
          id?: string
          issue_type: string
          success?: boolean
          ticket_id: string
          user_id: string
        }
        Update: {
          actions_taken?: Json
          admin_id?: string | null
          after_state?: Json
          before_state?: Json
          created_at?: string
          error_message?: string | null
          fix_attempted_at?: string
          fix_completed_at?: string | null
          id?: string
          issue_type?: string
          success?: boolean
          ticket_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_ticket_fix_history_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "member_support_tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      support_ticket_fix_jobs: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string
          error_log: string[] | null
          fail_count: number
          id: string
          last_updated: string | null
          processed_count: number
          progress_percentage: number
          results: Json | null
          started_at: string | null
          status: string
          success_count: number
          total_items: number
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by: string
          error_log?: string[] | null
          fail_count?: number
          id?: string
          last_updated?: string | null
          processed_count?: number
          progress_percentage?: number
          results?: Json | null
          started_at?: string | null
          status?: string
          success_count?: number
          total_items?: number
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string
          error_log?: string[] | null
          fail_count?: number
          id?: string
          last_updated?: string | null
          processed_count?: number
          progress_percentage?: number
          results?: Json | null
          started_at?: string | null
          status?: string
          success_count?: number
          total_items?: number
        }
        Relationships: []
      }
      token_marketplace_listings: {
        Row: {
          amount: number
          asset_symbol: string
          asset_type: string
          auction_end_at: string | null
          category: string | null
          created_at: string
          current_bid: number | null
          current_bidder_id: string | null
          description: string | null
          domain_id: string | null
          id: string
          listing_type: string
          price_per_unit: number | null
          reserve_price: number | null
          seller_id: string
          seller_usdc_address: string | null
          seller_usdt_address: string | null
          starting_bid: number | null
          status: string
          total_price: number | null
          updated_at: string
          views_count: number
        }
        Insert: {
          amount?: number
          asset_symbol: string
          asset_type: string
          auction_end_at?: string | null
          category?: string | null
          created_at?: string
          current_bid?: number | null
          current_bidder_id?: string | null
          description?: string | null
          domain_id?: string | null
          id?: string
          listing_type?: string
          price_per_unit?: number | null
          reserve_price?: number | null
          seller_id: string
          seller_usdc_address?: string | null
          seller_usdt_address?: string | null
          starting_bid?: number | null
          status?: string
          total_price?: number | null
          updated_at?: string
          views_count?: number
        }
        Update: {
          amount?: number
          asset_symbol?: string
          asset_type?: string
          auction_end_at?: string | null
          category?: string | null
          created_at?: string
          current_bid?: number | null
          current_bidder_id?: string | null
          description?: string | null
          domain_id?: string | null
          id?: string
          listing_type?: string
          price_per_unit?: number | null
          reserve_price?: number | null
          seller_id?: string
          seller_usdc_address?: string | null
          seller_usdt_address?: string | null
          starting_bid?: number | null
          status?: string
          total_price?: number | null
          updated_at?: string
          views_count?: number
        }
        Relationships: []
      }
      token_transfers: {
        Row: {
          amount: number
          created_at: string
          id: string
          notes: string | null
          processed_at: string | null
          processed_by: string | null
          recipient_id: string
          sender_id: string
          status: string
          token_type: string
          transaction_hash: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          notes?: string | null
          processed_at?: string | null
          processed_by?: string | null
          recipient_id: string
          sender_id: string
          status?: string
          token_type: string
          transaction_hash?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          notes?: string | null
          processed_at?: string | null
          processed_by?: string | null
          recipient_id?: string
          sender_id?: string
          status?: string
          token_type?: string
          transaction_hash?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount: number
          btc_payout_amount: number
          btc_price_at_time: number
          ccos_pool_addition: number
          ccos_price_at_time: number
          completed_at: string | null
          created_at: string
          email_address: string
          full_name: string
          id: string
          invoice_number: string
          metadata: Json | null
          origin_wallet: string | null
          receiver_wallet: string
          status: string
          transaction_hash: string
          transaction_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount: number
          btc_payout_amount: number
          btc_price_at_time: number
          ccos_pool_addition: number
          ccos_price_at_time: number
          completed_at?: string | null
          created_at?: string
          email_address: string
          full_name: string
          id?: string
          invoice_number: string
          metadata?: Json | null
          origin_wallet?: string | null
          receiver_wallet: string
          status: string
          transaction_hash: string
          transaction_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          btc_payout_amount?: number
          btc_price_at_time?: number
          ccos_pool_addition?: number
          ccos_price_at_time?: number
          completed_at?: string | null
          created_at?: string
          email_address?: string
          full_name?: string
          id?: string
          invoice_number?: string
          metadata?: Json | null
          origin_wallet?: string | null
          receiver_wallet?: string
          status?: string
          transaction_hash?: string
          transaction_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      transfer_reports: {
        Row: {
          amount: number
          created_at: string | null
          currency: string
          exchange_rate: number | null
          fee_amount: number | null
          from_account_id: string
          from_account_type: string
          id: string
          processed_at: string | null
          reference: string | null
          status: string | null
          to_account_id: string
          to_account_type: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string | null
          currency: string
          exchange_rate?: number | null
          fee_amount?: number | null
          from_account_id: string
          from_account_type: string
          id?: string
          processed_at?: string | null
          reference?: string | null
          status?: string | null
          to_account_id: string
          to_account_type: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string | null
          currency?: string
          exchange_rate?: number | null
          fee_amount?: number | null
          from_account_id?: string
          from_account_type?: string
          id?: string
          processed_at?: string | null
          reference?: string | null
          status?: string | null
          to_account_id?: string
          to_account_type?: string
          user_id?: string
        }
        Relationships: []
      }
      user_domain_profiles: {
        Row: {
          assigned_at: string | null
          created_at: string
          display_order: number | null
          domain_id: string
          id: string
          is_primary_domain: boolean | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          assigned_at?: string | null
          created_at?: string
          display_order?: number | null
          domain_id: string
          id?: string
          is_primary_domain?: boolean | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          assigned_at?: string | null
          created_at?: string
          display_order?: number | null
          domain_id?: string
          id?: string
          is_primary_domain?: boolean | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_domain_profiles_domain_id_fkey"
            columns: ["domain_id"]
            isOneToOne: false
            referencedRelation: "str_domains"
            referencedColumns: ["id"]
          },
        ]
      }
      user_liquidity_positions: {
        Row: {
          amount_deposited: number
          created_at: string
          id: string
          pool_id: string
          rewards_earned: number
          share_percentage: number
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_deposited?: number
          created_at?: string
          id?: string
          pool_id: string
          rewards_earned?: number
          share_percentage?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_deposited?: number
          created_at?: string
          id?: string
          pool_id?: string
          rewards_earned?: number
          share_percentage?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_liquidity_positions_pool_id_fkey"
            columns: ["pool_id"]
            isOneToOne: false
            referencedRelation: "liquidity_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      user_messages: {
        Row: {
          created_at: string
          id: string
          is_popup_shown: boolean
          is_read: boolean
          message: string
          message_type: string
          read_at: string | null
          recipient_id: string
          sender_id: string
          subject: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_popup_shown?: boolean
          is_read?: boolean
          message: string
          message_type?: string
          read_at?: string | null
          recipient_id: string
          sender_id: string
          subject: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_popup_shown?: boolean
          is_read?: boolean
          message?: string
          message_type?: string
          read_at?: string | null
          recipient_id?: string
          sender_id?: string
          subject?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_personal_data_encrypted: {
        Row: {
          created_at: string | null
          encrypted_address: string | null
          encrypted_bsc_wallet: string | null
          encrypted_btc_wallet: string | null
          encrypted_city: string | null
          encrypted_country: string | null
          encrypted_full_name: string | null
          encrypted_postal_code: string | null
          encryption_iv: string | null
          encryption_salt: string | null
          id: string
          updated_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          encrypted_address?: string | null
          encrypted_bsc_wallet?: string | null
          encrypted_btc_wallet?: string | null
          encrypted_city?: string | null
          encrypted_country?: string | null
          encrypted_full_name?: string | null
          encrypted_postal_code?: string | null
          encryption_iv?: string | null
          encryption_salt?: string | null
          id?: string
          updated_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          encrypted_address?: string | null
          encrypted_bsc_wallet?: string | null
          encrypted_btc_wallet?: string | null
          encrypted_city?: string | null
          encrypted_country?: string | null
          encrypted_full_name?: string | null
          encrypted_postal_code?: string | null
          encryption_iv?: string | null
          encryption_salt?: string | null
          id?: string
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_plain_ccoin_cards: {
        Row: {
          account_type: string | null
          balance: number
          card_identifier: string
          card_last4: string | null
          card_type: string
          cardholder_name: string | null
          created_at: string
          currency: string
          daily_limit: number | null
          id: string
          masked_card: string | null
          monthly_limit: number | null
          network: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_type?: string | null
          balance?: number
          card_identifier: string
          card_last4?: string | null
          card_type?: string
          cardholder_name?: string | null
          created_at?: string
          currency?: string
          daily_limit?: number | null
          id?: string
          masked_card?: string | null
          monthly_limit?: number | null
          network?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_type?: string | null
          balance?: number
          card_identifier?: string
          card_last4?: string | null
          card_type?: string
          cardholder_name?: string | null
          created_at?: string
          currency?: string
          daily_limit?: number | null
          id?: string
          masked_card?: string | null
          monthly_limit?: number | null
          network?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_plain_ibans: {
        Row: {
          account_holder: string | null
          account_name: string | null
          account_type: string | null
          balance: number | null
          bic: string
          country_code: string | null
          created_at: string
          currency: string
          daily_limit: number | null
          iban: string
          id: string
          legacy_iban: string | null
          monthly_limit: number | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_holder?: string | null
          account_name?: string | null
          account_type?: string | null
          balance?: number | null
          bic: string
          country_code?: string | null
          created_at?: string
          currency?: string
          daily_limit?: number | null
          iban: string
          id?: string
          legacy_iban?: string | null
          monthly_limit?: number | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_holder?: string | null
          account_name?: string | null
          account_type?: string | null
          balance?: number | null
          bic?: string
          country_code?: string | null
          created_at?: string
          currency?: string
          daily_limit?: number | null
          iban?: string
          id?: string
          legacy_iban?: string | null
          monthly_limit?: number | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_profile_addendum: {
        Row: {
          address_line2: string | null
          card_limits: Json | null
          compliance_flags: Json | null
          created_at: string
          date_of_birth: string | null
          default_card_network: string | null
          iban_country_code: string | null
          iban_currency_preferences: string[] | null
          id: string
          kyc_status: string | null
          metadata: Json | null
          phone_number: string | null
          tax_residency_country_code: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          address_line2?: string | null
          card_limits?: Json | null
          compliance_flags?: Json | null
          created_at?: string
          date_of_birth?: string | null
          default_card_network?: string | null
          iban_country_code?: string | null
          iban_currency_preferences?: string[] | null
          id?: string
          kyc_status?: string | null
          metadata?: Json | null
          phone_number?: string | null
          tax_residency_country_code?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          address_line2?: string | null
          card_limits?: Json | null
          compliance_flags?: Json | null
          created_at?: string
          date_of_birth?: string | null
          default_card_network?: string | null
          iban_country_code?: string | null
          iban_currency_preferences?: string[] | null
          id?: string
          kyc_status?: string | null
          metadata?: Json | null
          phone_number?: string | null
          tax_residency_country_code?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_addendum_user"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_profile_connections: {
        Row: {
          ccoin_pool_balance: number | null
          created_at: string | null
          iban_account_id: string | null
          id: string
          sourceless_account_id: string | null
          sourceless_wallet_address: string | null
          str_domain: string | null
          updated_at: string | null
          user_id: string
          visa_card_number: string | null
          visa_card_status: string | null
        }
        Insert: {
          ccoin_pool_balance?: number | null
          created_at?: string | null
          iban_account_id?: string | null
          id?: string
          sourceless_account_id?: string | null
          sourceless_wallet_address?: string | null
          str_domain?: string | null
          updated_at?: string | null
          user_id: string
          visa_card_number?: string | null
          visa_card_status?: string | null
        }
        Update: {
          ccoin_pool_balance?: number | null
          created_at?: string | null
          iban_account_id?: string | null
          id?: string
          sourceless_account_id?: string | null
          sourceless_wallet_address?: string | null
          str_domain?: string | null
          updated_at?: string | null
          user_id?: string
          visa_card_number?: string | null
          visa_card_status?: string | null
        }
        Relationships: []
      }
      user_profiles: {
        Row: {
          account_status: string
          address: string
          airdrop_applications_count: number | null
          backup_codes: string[] | null
          bsc_wallet_address: string
          btc_wallet_address: string
          ccoin_offshore_account_usd: string | null
          ccoin_visa_card: string | null
          city: string
          closed_at: string | null
          closure_reason: string | null
          country: string
          created_at: string
          crypto_experience_level: string | null
          device_fingerprints: Json | null
          email_address: string
          encryption_version: number | null
          expected_monthly_volume_eur: number | null
          full_name: string
          id: string
          investor_classification: string | null
          ip_address: unknown
          is_pep: boolean | null
          last_airdrop_application_date: string | null
          mica_approved_at: string | null
          mica_profile_source_id: string | null
          mica_terms_accepted: boolean | null
          mica_terms_accepted_at: string | null
          mica_terms_version: string | null
          postal_code: string
          profile_update_status: string
          recovery_words_encrypted: boolean | null
          recovery_words_iv: string | null
          recovery_words_shown: boolean | null
          referral_code: string | null
          referred_by: string | null
          region: string | null
          risk_acknowledged: boolean | null
          sanctions_declaration: boolean | null
          source_of_funds: string | null
          source_of_wealth: string | null
          status: Database["public"]["Enums"]["account_status"] | null
          str_domain_owned: string
          str_domain_username: string
          str_wallet_address: string | null
          suspended_at: string | null
          suspension_reason: string | null
          tax_identification_number: string | null
          tax_residency_country: string | null
          two_factor_enabled: boolean | null
          two_factor_secret: string | null
          updated_at: string
          user_id: string
          user_status: Database["public"]["Enums"]["user_status"] | null
          wallet_created_at: string | null
          wallet_pin_hash: string | null
          wallet_recovery_words: string[] | null
          wallet_setup_completed: boolean | null
        }
        Insert: {
          account_status?: string
          address: string
          airdrop_applications_count?: number | null
          backup_codes?: string[] | null
          bsc_wallet_address: string
          btc_wallet_address: string
          ccoin_offshore_account_usd?: string | null
          ccoin_visa_card?: string | null
          city: string
          closed_at?: string | null
          closure_reason?: string | null
          country: string
          created_at?: string
          crypto_experience_level?: string | null
          device_fingerprints?: Json | null
          email_address: string
          encryption_version?: number | null
          expected_monthly_volume_eur?: number | null
          full_name: string
          id?: string
          investor_classification?: string | null
          ip_address?: unknown
          is_pep?: boolean | null
          last_airdrop_application_date?: string | null
          mica_approved_at?: string | null
          mica_profile_source_id?: string | null
          mica_terms_accepted?: boolean | null
          mica_terms_accepted_at?: string | null
          mica_terms_version?: string | null
          postal_code: string
          profile_update_status?: string
          recovery_words_encrypted?: boolean | null
          recovery_words_iv?: string | null
          recovery_words_shown?: boolean | null
          referral_code?: string | null
          referred_by?: string | null
          region?: string | null
          risk_acknowledged?: boolean | null
          sanctions_declaration?: boolean | null
          source_of_funds?: string | null
          source_of_wealth?: string | null
          status?: Database["public"]["Enums"]["account_status"] | null
          str_domain_owned: string
          str_domain_username: string
          str_wallet_address?: string | null
          suspended_at?: string | null
          suspension_reason?: string | null
          tax_identification_number?: string | null
          tax_residency_country?: string | null
          two_factor_enabled?: boolean | null
          two_factor_secret?: string | null
          updated_at?: string
          user_id: string
          user_status?: Database["public"]["Enums"]["user_status"] | null
          wallet_created_at?: string | null
          wallet_pin_hash?: string | null
          wallet_recovery_words?: string[] | null
          wallet_setup_completed?: boolean | null
        }
        Update: {
          account_status?: string
          address?: string
          airdrop_applications_count?: number | null
          backup_codes?: string[] | null
          bsc_wallet_address?: string
          btc_wallet_address?: string
          ccoin_offshore_account_usd?: string | null
          ccoin_visa_card?: string | null
          city?: string
          closed_at?: string | null
          closure_reason?: string | null
          country?: string
          created_at?: string
          crypto_experience_level?: string | null
          device_fingerprints?: Json | null
          email_address?: string
          encryption_version?: number | null
          expected_monthly_volume_eur?: number | null
          full_name?: string
          id?: string
          investor_classification?: string | null
          ip_address?: unknown
          is_pep?: boolean | null
          last_airdrop_application_date?: string | null
          mica_approved_at?: string | null
          mica_profile_source_id?: string | null
          mica_terms_accepted?: boolean | null
          mica_terms_accepted_at?: string | null
          mica_terms_version?: string | null
          postal_code?: string
          profile_update_status?: string
          recovery_words_encrypted?: boolean | null
          recovery_words_iv?: string | null
          recovery_words_shown?: boolean | null
          referral_code?: string | null
          referred_by?: string | null
          region?: string | null
          risk_acknowledged?: boolean | null
          sanctions_declaration?: boolean | null
          source_of_funds?: string | null
          source_of_wealth?: string | null
          status?: Database["public"]["Enums"]["account_status"] | null
          str_domain_owned?: string
          str_domain_username?: string
          str_wallet_address?: string | null
          suspended_at?: string | null
          suspension_reason?: string | null
          tax_identification_number?: string | null
          tax_residency_country?: string | null
          two_factor_enabled?: boolean | null
          two_factor_secret?: string | null
          updated_at?: string
          user_id?: string
          user_status?: Database["public"]["Enums"]["user_status"] | null
          wallet_created_at?: string | null
          wallet_pin_hash?: string | null
          wallet_recovery_words?: string[] | null
          wallet_setup_completed?: boolean | null
        }
        Relationships: []
      }
      user_profiles_updated: {
        Row: {
          address: string | null
          admin_notes: string | null
          bsc_wallet_address: string | null
          btc_wallet_address: string | null
          change_reason: string | null
          city: string | null
          country: string | null
          created_at: string
          crypto_experience_level: string | null
          email_address: string | null
          expected_monthly_volume_eur: number | null
          full_name: string | null
          id: string
          investor_classification: string | null
          is_pep: boolean
          mica_terms_accepted: boolean
          mica_terms_accepted_at: string | null
          mica_terms_version: string | null
          otp_verified: boolean
          postal_code: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          risk_acknowledged: boolean
          sanctions_declaration: boolean
          source_of_funds: string | null
          source_of_wealth: string | null
          str_domain_owned: string | null
          str_wallet_address: string | null
          submission_status: string
          suitability_answers: Json
          tax_identification_number: string | null
          tax_residency_country: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          address?: string | null
          admin_notes?: string | null
          bsc_wallet_address?: string | null
          btc_wallet_address?: string | null
          change_reason?: string | null
          city?: string | null
          country?: string | null
          created_at?: string
          crypto_experience_level?: string | null
          email_address?: string | null
          expected_monthly_volume_eur?: number | null
          full_name?: string | null
          id?: string
          investor_classification?: string | null
          is_pep?: boolean
          mica_terms_accepted?: boolean
          mica_terms_accepted_at?: string | null
          mica_terms_version?: string | null
          otp_verified?: boolean
          postal_code?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          risk_acknowledged?: boolean
          sanctions_declaration?: boolean
          source_of_funds?: string | null
          source_of_wealth?: string | null
          str_domain_owned?: string | null
          str_wallet_address?: string | null
          submission_status?: string
          suitability_answers?: Json
          tax_identification_number?: string | null
          tax_residency_country?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          address?: string | null
          admin_notes?: string | null
          bsc_wallet_address?: string | null
          btc_wallet_address?: string | null
          change_reason?: string | null
          city?: string | null
          country?: string | null
          created_at?: string
          crypto_experience_level?: string | null
          email_address?: string | null
          expected_monthly_volume_eur?: number | null
          full_name?: string | null
          id?: string
          investor_classification?: string | null
          is_pep?: boolean
          mica_terms_accepted?: boolean
          mica_terms_accepted_at?: string | null
          mica_terms_version?: string | null
          otp_verified?: boolean
          postal_code?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          risk_acknowledged?: boolean
          sanctions_declaration?: boolean
          source_of_funds?: string | null
          source_of_wealth?: string | null
          str_domain_owned?: string | null
          str_wallet_address?: string | null
          submission_status?: string
          suitability_answers?: Json
          tax_identification_number?: string | null
          tax_residency_country?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string | null
          created_by: string | null
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_sessions: {
        Row: {
          created_at: string
          device_fingerprint: string | null
          expires_at: string
          id: string
          ip_address: unknown
          is_active: boolean
          last_activity: string
          revoked_at: string | null
          revoked_reason: string | null
          session_token: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          device_fingerprint?: string | null
          expires_at: string
          id?: string
          ip_address?: unknown
          is_active?: boolean
          last_activity?: string
          revoked_at?: string | null
          revoked_reason?: string | null
          session_token: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          device_fingerprint?: string | null
          expires_at?: string
          id?: string
          ip_address?: unknown
          is_active?: boolean
          last_activity?: string
          revoked_at?: string | null
          revoked_reason?: string | null
          session_token?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_staking_pools: {
        Row: {
          admin_notes: string | null
          apy_rate: number | null
          balance: number | null
          created_at: string | null
          declined_at: string | null
          declined_by: string | null
          dynamic_apy: number | null
          enhanced_pool_id: string | null
          id: string
          is_enhanced_pool: boolean | null
          last_reward_date: string | null
          lock_end_date: string | null
          network_efficiency: number | null
          original_stake_amount: number | null
          pool_type: string
          rewards_earned: number | null
          stake_duration_months: number | null
          staked_amount: number | null
          status: string
          updated_at: string | null
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          apy_rate?: number | null
          balance?: number | null
          created_at?: string | null
          declined_at?: string | null
          declined_by?: string | null
          dynamic_apy?: number | null
          enhanced_pool_id?: string | null
          id?: string
          is_enhanced_pool?: boolean | null
          last_reward_date?: string | null
          lock_end_date?: string | null
          network_efficiency?: number | null
          original_stake_amount?: number | null
          pool_type: string
          rewards_earned?: number | null
          stake_duration_months?: number | null
          staked_amount?: number | null
          status?: string
          updated_at?: string | null
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          apy_rate?: number | null
          balance?: number | null
          created_at?: string | null
          declined_at?: string | null
          declined_by?: string | null
          dynamic_apy?: number | null
          enhanced_pool_id?: string | null
          id?: string
          is_enhanced_pool?: boolean | null
          last_reward_date?: string | null
          lock_end_date?: string | null
          network_efficiency?: number | null
          original_stake_amount?: number | null
          pool_type?: string
          rewards_earned?: number | null
          stake_duration_months?: number | null
          staked_amount?: number | null
          status?: string
          updated_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_staking_pools_enhanced_pool_id_fkey"
            columns: ["enhanced_pool_id"]
            isOneToOne: false
            referencedRelation: "enhanced_staking_pools"
            referencedColumns: ["id"]
          },
        ]
      }
      user_str_shares: {
        Row: {
          balance: number
          created_at: string
          id: string
          locked_balance: number
          source_application_id: string | null
          updated_at: string
          user_id: string
          vesting_end_date: string | null
          wnft_shares: number
        }
        Insert: {
          balance?: number
          created_at?: string
          id?: string
          locked_balance?: number
          source_application_id?: string | null
          updated_at?: string
          user_id: string
          vesting_end_date?: string | null
          wnft_shares?: number
        }
        Update: {
          balance?: number
          created_at?: string
          id?: string
          locked_balance?: number
          source_application_id?: string | null
          updated_at?: string
          user_id?: string
          vesting_end_date?: string | null
          wnft_shares?: number
        }
        Relationships: [
          {
            foreignKeyName: "user_str_shares_source_application_id_fkey"
            columns: ["source_application_id"]
            isOneToOne: false
            referencedRelation: "seed_str_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      user_wallet_security: {
        Row: {
          backup_codes_iv: string | null
          created_at: string | null
          device_fingerprints: Json | null
          encrypted_backup_codes: string | null
          encrypted_recovery_words: string | null
          id: string
          recovery_words_iv: string | null
          recovery_words_salt: string | null
          two_factor_secret: string | null
          updated_at: string | null
          user_id: string
          wallet_pin_hash: string | null
        }
        Insert: {
          backup_codes_iv?: string | null
          created_at?: string | null
          device_fingerprints?: Json | null
          encrypted_backup_codes?: string | null
          encrypted_recovery_words?: string | null
          id?: string
          recovery_words_iv?: string | null
          recovery_words_salt?: string | null
          two_factor_secret?: string | null
          updated_at?: string | null
          user_id: string
          wallet_pin_hash?: string | null
        }
        Update: {
          backup_codes_iv?: string | null
          created_at?: string | null
          device_fingerprints?: Json | null
          encrypted_backup_codes?: string | null
          encrypted_recovery_words?: string | null
          id?: string
          recovery_words_iv?: string | null
          recovery_words_salt?: string | null
          two_factor_secret?: string | null
          updated_at?: string | null
          user_id?: string
          wallet_pin_hash?: string | null
        }
        Relationships: []
      }
      user_wallets: {
        Row: {
          arss_balance: number
          created_at: string
          id: string
          total_earned: number
          total_spent: number
          updated_at: string
          user_id: string
          wallet_address: string
        }
        Insert: {
          arss_balance?: number
          created_at?: string
          id?: string
          total_earned?: number
          total_spent?: number
          updated_at?: string
          user_id: string
          wallet_address: string
        }
        Update: {
          arss_balance?: number
          created_at?: string
          id?: string
          total_earned?: number
          total_spent?: number
          updated_at?: string
          user_id?: string
          wallet_address?: string
        }
        Relationships: []
      }
      v2_accounts: {
        Row: {
          account_mode: string
          account_mode_selected_at: string | null
          address_line1: string | null
          address_line2: string | null
          assets_declared_at: string | null
          city: string | null
          country_of_residence: string | null
          created_at: string
          date_of_birth: string | null
          email: string | null
          email_confirmed_at: string | null
          full_name: string | null
          id: string
          id_document_number: string | null
          id_document_type: string | null
          investor_classification: string | null
          mica_terms_accepted: boolean
          mica_terms_version: string | null
          nationality: string | null
          pep_status: boolean
          phone: string | null
          postal_code: string | null
          rejection_reason: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          risk_acknowledged: boolean
          sanctions_declaration: boolean
          source_of_funds: string | null
          source_of_wealth: string | null
          status: string
          str_domain: string | null
          submitted_at: string | null
          tax_identification_number: string | null
          tax_residency: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          account_mode?: string
          account_mode_selected_at?: string | null
          address_line1?: string | null
          address_line2?: string | null
          assets_declared_at?: string | null
          city?: string | null
          country_of_residence?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          email_confirmed_at?: string | null
          full_name?: string | null
          id?: string
          id_document_number?: string | null
          id_document_type?: string | null
          investor_classification?: string | null
          mica_terms_accepted?: boolean
          mica_terms_version?: string | null
          nationality?: string | null
          pep_status?: boolean
          phone?: string | null
          postal_code?: string | null
          rejection_reason?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          risk_acknowledged?: boolean
          sanctions_declaration?: boolean
          source_of_funds?: string | null
          source_of_wealth?: string | null
          status?: string
          str_domain?: string | null
          submitted_at?: string | null
          tax_identification_number?: string | null
          tax_residency?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          account_mode?: string
          account_mode_selected_at?: string | null
          address_line1?: string | null
          address_line2?: string | null
          assets_declared_at?: string | null
          city?: string | null
          country_of_residence?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          email_confirmed_at?: string | null
          full_name?: string | null
          id?: string
          id_document_number?: string | null
          id_document_type?: string | null
          investor_classification?: string | null
          mica_terms_accepted?: boolean
          mica_terms_version?: string | null
          nationality?: string | null
          pep_status?: boolean
          phone?: string | null
          postal_code?: string | null
          rejection_reason?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          risk_acknowledged?: boolean
          sanctions_declaration?: boolean
          source_of_funds?: string | null
          source_of_wealth?: string | null
          status?: string
          str_domain?: string | null
          submitted_at?: string | null
          tax_identification_number?: string | null
          tax_residency?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      v2_admin_actions: {
        Row: {
          account_id: string | null
          action: string
          actor_id: string | null
          after_data: Json | null
          before_data: Json | null
          created_at: string
          entity_id: string | null
          entity_type: string
          from_status: string | null
          id: string
          notes: string | null
          to_status: string | null
          user_id: string | null
        }
        Insert: {
          account_id?: string | null
          action: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          from_status?: string | null
          id?: string
          notes?: string | null
          to_status?: string | null
          user_id?: string | null
        }
        Update: {
          account_id?: string | null
          action?: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          from_status?: string | null
          id?: string
          notes?: string | null
          to_status?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      v2_asset_claims: {
        Row: {
          account_id: string
          asset_label: string | null
          asset_symbol: string
          asset_type: string | null
          category: string
          claimed_amount: number
          created_at: string
          duplicate_of: string | null
          evidence_url: string | null
          flagged_reason: string | null
          id: string
          notes: string | null
          platform: string | null
          reference: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          tx_currency: string | null
          tx_hash: string | null
          updated_at: string
          user_id: string
          verified_amount: number | null
          wallet_address: string | null
        }
        Insert: {
          account_id: string
          asset_label?: string | null
          asset_symbol: string
          asset_type?: string | null
          category: string
          claimed_amount?: number
          created_at?: string
          duplicate_of?: string | null
          evidence_url?: string | null
          flagged_reason?: string | null
          id?: string
          notes?: string | null
          platform?: string | null
          reference?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          tx_currency?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id: string
          verified_amount?: number | null
          wallet_address?: string | null
        }
        Update: {
          account_id?: string
          asset_label?: string | null
          asset_symbol?: string
          asset_type?: string | null
          category?: string
          claimed_amount?: number
          created_at?: string
          duplicate_of?: string | null
          evidence_url?: string | null
          flagged_reason?: string | null
          id?: string
          notes?: string | null
          platform?: string | null
          reference?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          tx_currency?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
          verified_amount?: number | null
          wallet_address?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "v2_asset_claims_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "v2_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "v2_asset_claims_duplicate_of_fkey"
            columns: ["duplicate_of"]
            isOneToOne: false
            referencedRelation: "v2_asset_claims"
            referencedColumns: ["id"]
          },
        ]
      }
      v2_request_messages: {
        Row: {
          body: string
          created_at: string
          id: string
          request_id: string
          requires_response: boolean
          sender_id: string | null
          sender_role: string
          source: string
          user_id: string | null
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          request_id: string
          requires_response?: boolean
          sender_id?: string | null
          sender_role: string
          source: string
          user_id?: string | null
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          request_id?: string
          requires_response?: boolean
          sender_id?: string | null
          sender_role?: string
          source?: string
          user_id?: string | null
        }
        Relationships: []
      }
      v2_service_connections: {
        Row: {
          account_id: string
          connected_at: string | null
          created_at: string
          external_reference: string | null
          id: string
          metadata: Json
          requested_at: string | null
          service: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_id: string
          connected_at?: string | null
          created_at?: string
          external_reference?: string | null
          id?: string
          metadata?: Json
          requested_at?: string | null
          service: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_id?: string
          connected_at?: string | null
          created_at?: string
          external_reference?: string | null
          id?: string
          metadata?: Json
          requested_at?: string | null
          service?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "v2_service_connections_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "v2_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      v2_verified_assets: {
        Row: {
          account_id: string
          amount: number
          asset_label: string | null
          asset_symbol: string
          category: string
          claim_id: string | null
          created_at: string
          id: string
          reference: string | null
          updated_at: string
          user_id: string
          verified_at: string
          verified_by: string | null
        }
        Insert: {
          account_id: string
          amount?: number
          asset_label?: string | null
          asset_symbol: string
          category: string
          claim_id?: string | null
          created_at?: string
          id?: string
          reference?: string | null
          updated_at?: string
          user_id: string
          verified_at?: string
          verified_by?: string | null
        }
        Update: {
          account_id?: string
          amount?: number
          asset_label?: string | null
          asset_symbol?: string
          category?: string
          claim_id?: string | null
          created_at?: string
          id?: string
          reference?: string | null
          updated_at?: string
          user_id?: string
          verified_at?: string
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "v2_verified_assets_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "v2_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "v2_verified_assets_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "v2_asset_claims"
            referencedColumns: ["id"]
          },
        ]
      }
      vesting_tokens: {
        Row: {
          amount: number
          created_at: string
          id: string
          metadata: Json | null
          released_at: string | null
          released_to_staking_pool_id: string | null
          source: string
          source_id: string | null
          status: string
          token_type: string
          updated_at: string
          user_id: string
          vesting_end_date: string
          vesting_months: number
          vesting_start_date: string
        }
        Insert: {
          amount?: number
          created_at?: string
          id?: string
          metadata?: Json | null
          released_at?: string | null
          released_to_staking_pool_id?: string | null
          source?: string
          source_id?: string | null
          status?: string
          token_type: string
          updated_at?: string
          user_id: string
          vesting_end_date: string
          vesting_months?: number
          vesting_start_date?: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          metadata?: Json | null
          released_at?: string | null
          released_to_staking_pool_id?: string | null
          source?: string
          source_id?: string | null
          status?: string
          token_type?: string
          updated_at?: string
          user_id?: string
          vesting_end_date?: string
          vesting_months?: number
          vesting_start_date?: string
        }
        Relationships: []
      }
      vip_users: {
        Row: {
          created_at: string | null
          id: string
          last_checked: string | null
          qualification_type: string
          qualified_at: string | null
          total_domains_staked: number | null
          total_str_staked: number | null
          updated_at: string | null
          user_id: string
          vip_status: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          last_checked?: string | null
          qualification_type: string
          qualified_at?: string | null
          total_domains_staked?: number | null
          total_str_staked?: number | null
          updated_at?: string | null
          user_id: string
          vip_status?: string
        }
        Update: {
          created_at?: string | null
          id?: string
          last_checked?: string | null
          qualification_type?: string
          qualified_at?: string | null
          total_domains_staked?: number | null
          total_str_staked?: number | null
          updated_at?: string | null
          user_id?: string
          vip_status?: string
        }
        Relationships: []
      }
      visa_card_applications: {
        Row: {
          admin_notes: string | null
          card_type: string
          created_at: string
          email: string
          full_name: string
          id: string
          processed_at: string | null
          processed_by: string | null
          status: string
          str_domain: string | null
          updated_at: string
          user_id: string
          wallet_address: string | null
        }
        Insert: {
          admin_notes?: string | null
          card_type: string
          created_at?: string
          email: string
          full_name: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_id: string
          wallet_address?: string | null
        }
        Update: {
          admin_notes?: string | null
          card_type?: string
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          processed_at?: string | null
          processed_by?: string | null
          status?: string
          str_domain?: string | null
          updated_at?: string
          user_id?: string
          wallet_address?: string | null
        }
        Relationships: []
      }
      voucher_corrections: {
        Row: {
          corrected_amount: number
          corrected_at: string
          corrected_by: string
          correction_reason: string | null
          correction_type: string
          created_at: string
          difference: number
          email_address: string
          full_name: string
          id: string
          metadata: Json | null
          package_type: string
          previous_amount: number
          token_type: string
          user_id: string
          voucher_id: string
        }
        Insert: {
          corrected_amount: number
          corrected_at?: string
          corrected_by: string
          correction_reason?: string | null
          correction_type: string
          created_at?: string
          difference: number
          email_address: string
          full_name: string
          id?: string
          metadata?: Json | null
          package_type: string
          previous_amount: number
          token_type: string
          user_id: string
          voucher_id: string
        }
        Update: {
          corrected_amount?: number
          corrected_at?: string
          corrected_by?: string
          correction_reason?: string | null
          correction_type?: string
          created_at?: string
          difference?: number
          email_address?: string
          full_name?: string
          id?: string
          metadata?: Json | null
          package_type?: string
          previous_amount?: number
          token_type?: string
          user_id?: string
          voucher_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "voucher_corrections_voucher_id_fkey"
            columns: ["voucher_id"]
            isOneToOne: false
            referencedRelation: "voucher_redemptions"
            referencedColumns: ["id"]
          },
        ]
      }
      voucher_error_log: {
        Row: {
          created_at: string
          error_details: Json | null
          error_message: string
          error_type: string
          id: string
          ip_address: unknown
          performed_by: string | null
          stack_trace: string | null
          user_agent: string | null
          user_id: string | null
          voucher_redemption_id: string | null
        }
        Insert: {
          created_at?: string
          error_details?: Json | null
          error_message: string
          error_type: string
          id?: string
          ip_address?: unknown
          performed_by?: string | null
          stack_trace?: string | null
          user_agent?: string | null
          user_id?: string | null
          voucher_redemption_id?: string | null
        }
        Update: {
          created_at?: string
          error_details?: Json | null
          error_message?: string
          error_type?: string
          id?: string
          ip_address?: unknown
          performed_by?: string | null
          stack_trace?: string | null
          user_agent?: string | null
          user_id?: string | null
          voucher_redemption_id?: string | null
        }
        Relationships: []
      }
      voucher_redemption_history: {
        Row: {
          action_performed: string
          admin_notes: string | null
          created_at: string
          error_details: Json | null
          id: string
          ip_address: unknown
          metadata: Json | null
          performed_by: string | null
          status_from: string | null
          status_to: string
          user_agent: string | null
          voucher_redemption_id: string
        }
        Insert: {
          action_performed: string
          admin_notes?: string | null
          created_at?: string
          error_details?: Json | null
          id?: string
          ip_address?: unknown
          metadata?: Json | null
          performed_by?: string | null
          status_from?: string | null
          status_to: string
          user_agent?: string | null
          voucher_redemption_id: string
        }
        Update: {
          action_performed?: string
          admin_notes?: string | null
          created_at?: string
          error_details?: Json | null
          id?: string
          ip_address?: unknown
          metadata?: Json | null
          performed_by?: string | null
          status_from?: string | null
          status_to?: string
          user_agent?: string | null
          voucher_redemption_id?: string
        }
        Relationships: []
      }
      voucher_redemptions: {
        Row: {
          admin_notes: string | null
          amount: string | null
          confirmation_number: string | null
          created_at: string
          credited_amount: number | null
          credited_at: string | null
          deposit_address: string | null
          email_address: string
          full_name: string
          id: string
          package_type: string
          payment_hash: string | null
          payment_type: string
          processed_at: string | null
          processed_by: string | null
          proof_of_payment_url: string | null
          status: string
          str_dome_email: string
          str_dome_username: string
          token_type: string
          tokens_credited: boolean | null
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_notes?: string | null
          amount?: string | null
          confirmation_number?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          deposit_address?: string | null
          email_address: string
          full_name: string
          id?: string
          package_type: string
          payment_hash?: string | null
          payment_type: string
          processed_at?: string | null
          processed_by?: string | null
          proof_of_payment_url?: string | null
          status?: string
          str_dome_email: string
          str_dome_username: string
          token_type: string
          tokens_credited?: boolean | null
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_notes?: string | null
          amount?: string | null
          confirmation_number?: string | null
          created_at?: string
          credited_amount?: number | null
          credited_at?: string | null
          deposit_address?: string | null
          email_address?: string
          full_name?: string
          id?: string
          package_type?: string
          payment_hash?: string | null
          payment_type?: string
          processed_at?: string | null
          processed_by?: string | null
          proof_of_payment_url?: string | null
          status?: string
          str_dome_email?: string
          str_dome_username?: string
          token_type?: string
          tokens_credited?: boolean | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      wallet_pools: {
        Row: {
          balance: number
          created_at: string
          id: string
          pool_type: string
          updated_at: string
          user_id: string
          wallet_address: string
        }
        Insert: {
          balance?: number
          created_at?: string
          id?: string
          pool_type: string
          updated_at?: string
          user_id: string
          wallet_address: string
        }
        Update: {
          balance?: number
          created_at?: string
          id?: string
          pool_type?: string
          updated_at?: string
          user_id?: string
          wallet_address?: string
        }
        Relationships: []
      }
      wallet_security_log: {
        Row: {
          action: string
          created_at: string | null
          id: string
          ip_address: unknown
          user_agent: string | null
          user_id: string
        }
        Insert: {
          action: string
          created_at?: string | null
          id?: string
          ip_address?: unknown
          user_agent?: string | null
          user_id: string
        }
        Update: {
          action?: string
          created_at?: string | null
          id?: string
          ip_address?: unknown
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      wallet_transactions: {
        Row: {
          amount: number
          completed_at: string | null
          created_at: string
          failure_reason: string | null
          from_address: string
          from_user_id: string | null
          id: string
          metadata: Json | null
          status: string
          to_address: string
          to_user_id: string | null
          token_type: string
          transaction_hash: string | null
          updated_at: string
        }
        Insert: {
          amount: number
          completed_at?: string | null
          created_at?: string
          failure_reason?: string | null
          from_address: string
          from_user_id?: string | null
          id?: string
          metadata?: Json | null
          status?: string
          to_address: string
          to_user_id?: string | null
          token_type?: string
          transaction_hash?: string | null
          updated_at?: string
        }
        Update: {
          amount?: number
          completed_at?: string | null
          created_at?: string
          failure_reason?: string | null
          from_address?: string
          from_user_id?: string | null
          id?: string
          metadata?: Json | null
          status?: string
          to_address?: string
          to_user_id?: string | null
          token_type?: string
          transaction_hash?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      withdrawal_requests: {
        Row: {
          btc_amount: number
          created_at: string
          founder_position_id: string
          id: string
          processed_at: string | null
          requested_at: string
          status: string
          transaction_hash: string | null
          updated_at: string
          usd_value_at_request: number
          user_id: string
          withdrawal_address: string
        }
        Insert: {
          btc_amount: number
          created_at?: string
          founder_position_id: string
          id?: string
          processed_at?: string | null
          requested_at?: string
          status?: string
          transaction_hash?: string | null
          updated_at?: string
          usd_value_at_request: number
          user_id: string
          withdrawal_address: string
        }
        Update: {
          btc_amount?: number
          created_at?: string
          founder_position_id?: string
          id?: string
          processed_at?: string | null
          requested_at?: string
          status?: string
          transaction_hash?: string | null
          updated_at?: string
          usd_value_at_request?: number
          user_id?: string
          withdrawal_address?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawal_requests_founder_position_id_fkey"
            columns: ["founder_position_id"]
            isOneToOne: false
            referencedRelation: "founder_positions"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      ledger_anchor_queue: {
        Row: {
          age: string | null
          anchor_id: string | null
          attempts: number | null
          chain_id: number | null
          claimed_by: string | null
          content_hash: string | null
          entry_count: number | null
          journal_id: string | null
          last_error: string | null
          lease_expires_at: string | null
          leased: boolean | null
          ledger_label: string | null
          missing_anchor_row: boolean | null
          posted_at: string | null
          reason: string | null
          reference: string | null
          status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ledger_anchor_chain_id_fkey"
            columns: ["chain_id"]
            isOneToOne: false
            referencedRelation: "ledger_anchor_chain"
            referencedColumns: ["chain_id"]
          },
        ]
      }
      public_product_catalog: {
        Row: {
          category: string | null
          created_at: string | null
          crypto_currency: string | null
          crypto_price: number | null
          description: string | null
          id: string | null
          image_url: string | null
          is_digital: boolean | null
          price: number | null
          price_currency: string | null
          product_name: string | null
        }
        Insert: {
          category?: string | null
          created_at?: string | null
          crypto_currency?: string | null
          crypto_price?: number | null
          description?: string | null
          id?: string | null
          image_url?: string | null
          is_digital?: boolean | null
          price?: number | null
          price_currency?: string | null
          product_name?: string | null
        }
        Update: {
          category?: string | null
          created_at?: string | null
          crypto_currency?: string | null
          crypto_price?: number | null
          description?: string | null
          id?: string | null
          image_url?: string | null
          is_digital?: boolean | null
          price?: number | null
          price_currency?: string | null
          product_name?: string | null
        }
        Relationships: []
      }
      starw_purchases_comprehensive: {
        Row: {
          admin_notes: string | null
          arss_bonus: string | null
          btc_amount: number | null
          created_at: string | null
          crypto_prices_at_purchase: Json | null
          customer_bsc_wallet: string | null
          customer_wallet: string | null
          email_address: string | null
          eth_amount: number | null
          full_name: string | null
          id: string | null
          interaction_count: number | null
          interaction_history: Json | null
          ip_address: unknown
          node_count: number | null
          payment_currency: string | null
          payment_info: Json | null
          payment_method: string | null
          processed_at: string | null
          processed_by: string | null
          processed_by_email: string | null
          processed_by_name: string | null
          referral_source: string | null
          session_metadata: Json | null
          stage: number | null
          status: string | null
          str_domain: string | null
          total_cost: number | null
          updated_at: string | null
          user_agent: string | null
          user_id: string | null
          wallet_address: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      _current_is_privileged: { Args: never; Returns: boolean }
      admin_adjust_member_balance: {
        Args: {
          p_amount_minor: number
          p_asset: string
          p_bucket: string
          p_counterparty: string
          p_reason: string
          p_reference: string
          p_user_id: string
        }
        Returns: Json
      }
      admin_assign_starw_nodes: {
        Args: {
          admin_user_id?: string
          node_count: number
          node_status: string
          start_number: number
          target_user_id: string
          worker_nodes: number
        }
        Returns: Json
      }
      admin_ban_user: {
        Args: {
          duration_minutes?: number
          reason: string
          room_type: string
          target_user_id: string
        }
        Returns: boolean
      }
      admin_bulk_create_banking:
        | {
            Args: {
              p_create_ccoin_cards?: boolean
              p_create_ibans?: boolean
              p_create_visa_cards?: boolean
            }
            Returns: Json
          }
        | { Args: { product_type: string }; Returns: Json }
      admin_bulk_set_profile_status: {
        Args: { new_status: string; reason?: string; target_user_ids: string[] }
        Returns: Json
      }
      admin_confirm_user_email: {
        Args: { target_user_id: string }
        Returns: boolean
      }
      admin_correct_unbacked_positions: {
        Args: {
          dry_run?: boolean
          reason?: string
          scale: number
          target_user_id: string
        }
        Returns: Json
      }
      admin_correct_voucher_tokens: {
        Args: { admin_user_id: string; voucher_id_param: string }
        Returns: Json
      }
      admin_delete_chat_message: {
        Args: { message_id: string; reason?: string }
        Returns: boolean
      }
      admin_encrypt_all_recovery_words: { Args: never; Returns: Json }
      admin_encrypt_remaining_iban_accounts: { Args: never; Returns: Json }
      admin_get_complete_banking_overview: {
        Args: never
        Returns: {
          banking_status: string
          ccoin_card_id: string
          ccoin_card_masked: string
          chf_iban: string
          chf_iban_id: string
          created_at: string
          email_address: string
          eur_iban: string
          eur_iban_id: string
          full_name: string
          gbp_iban: string
          gbp_iban_id: string
          str_domain: string
          user_id: string
          visa_card_id: string
          visa_card_masked: string
        }[]
      }
      admin_get_starw_nodes: {
        Args: never
        Returns: {
          assigned_at: string
          assigned_by: string
          created_at: string
          email_address: string
          full_name: string
          id: string
          node_number: number
          status: string
          updated_at: string
          user_id: string
          worker_nodes_count: number
        }[]
      }
      admin_revert_position_correction: {
        Args: { action_id: string }
        Returns: Json
      }
      admin_review_updated_profile: {
        Args: {
          _action: string
          _notes?: string
          _reason?: string
          _submission_id: string
        }
        Returns: Json
      }
      admin_sweep_row_counts: {
        Args: { p_tables?: string[] }
        Returns: {
          table_name: string
          total_rows: number
        }[]
      }
      admin_unban_user:
        | { Args: { ban_id: string }; Returns: boolean }
        | {
            Args: { room_type: string; target_user_id: string }
            Returns: boolean
          }
      admin_upsert_user_profile_status: {
        Args: {
          email_address?: string
          full_name?: string
          new_status: string
          target_user_id: string
        }
        Returns: boolean
      }
      approve_migration: {
        Args: { p_note?: string; p_user_id: string }
        Returns: Json
      }
      assert_caller_owns: { Args: { p_user_id: string }; Returns: undefined }
      assign_admin_role: { Args: { target_email: string }; Returns: boolean }
      assign_user_role: {
        Args: { target_email: string; user_role: string }
        Returns: boolean
      }
      auto_generate_user_pin: {
        Args: { user_id_param: string }
        Returns: string
      }
      backfill_historical_rewards: { Args: never; Returns: Json }
      bulk_encrypt_existing_data: { Args: never; Returns: Json }
      bulk_generate_missing_pins: { Args: never; Returns: Json }
      bulk_provision_ccoin_banking: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      calculate_ccos_mint: {
        Args: { current_price: number; pool_amount: number; pool_type: string }
        Returns: number
      }
      calculate_contribution_reward: {
        Args: {
          content_size?: number
          contribution_type: string
          quality_score: number
        }
        Returns: number
      }
      calculate_daily_rewards: { Args: never; Returns: undefined }
      calculate_dynamic_apy: {
        Args: {
          duration_months: number
          network_efficiency?: number
          str_amount: number
        }
        Returns: number
      }
      calculate_staking_rewards: {
        Args: {
          p_pool_type: string
          p_stake_duration_months: number
          p_user_id: string
        }
        Returns: number
      }
      ccoin_bic_for_country: { Args: { p_country: string }; Returns: string }
      ccoin_fix_iban: { Args: { p_iban: string }; Returns: string }
      charge_ccos_fee: {
        Args: {
          p_fee: number
          p_rail: string
          p_ref_id: string
          p_ref_table: string
          p_user_id: string
        }
        Returns: Json
      }
      check_advanced_rate_limit: {
        Args: {
          identifier_param: string
          max_attempts_param?: number
          operation_type_param: string
          progressive_delay_param?: boolean
          window_minutes_param?: number
        }
        Returns: Json
      }
      check_rate_limit: {
        Args: {
          attempt_type_param?: string
          check_ip_address?: unknown
          check_user_id?: string
          max_attempts?: number
          time_window_minutes?: number
        }
        Returns: boolean
      }
      check_rate_limit_with_progressive_delay: {
        Args: {
          attempt_type_param?: string
          check_ip_address?: unknown
          check_user_id?: string
          max_attempts?: number
          time_window_minutes?: number
        }
        Returns: Json
      }
      check_user_security_compliance: {
        Args: { check_user_id: string }
        Returns: Json
      }
      cleanup_expired_otps: { Args: never; Returns: undefined }
      cleanup_expired_sessions: { Args: never; Returns: undefined }
      comprehensive_user_migration_from_acceptance: {
        Args: never
        Returns: Json
      }
      convert_wstr_to_fiat: {
        Args: {
          p_target_currency: string
          p_user_id: string
          p_wstr_amount: number
        }
        Returns: number
      }
      convert_wstr_to_fiat_atomic: {
        Args: {
          p_currency: string
          p_description: string
          p_fiat_amount: number
          p_user_id: string
          p_wstr_amount: number
        }
        Returns: undefined
      }
      correct_voucher_amount: {
        Args: {
          p_corrected_amount: number
          p_correction_reason?: string
          p_voucher_id: string
        }
        Returns: Json
      }
      correct_voucher_credits_batch: { Args: never; Returns: Json }
      create_ccoin_card_for_user:
        | { Args: { p_str_domain: string; p_user_id: string }; Returns: string }
        | {
            Args: {
              p_str_domain: string
              p_str_wallet: string
              p_user_id: string
            }
            Returns: string
          }
      create_ccoin_iban_for_user:
        | { Args: { p_full_name: string; p_user_id: string }; Returns: string }
        | {
            Args: {
              p_currency?: string
              p_full_name: string
              p_user_id: string
            }
            Returns: string
          }
      create_complete_banking_products: {
        Args: { p_str_domain?: string; p_user_id: string }
        Returns: Json
      }
      create_complete_banking_via_profile: {
        Args: { p_user_id: string }
        Returns: Json
      }
      create_iban_for_user:
        | { Args: { p_currency: string; p_user_id: string }; Returns: string }
        | {
            Args: {
              p_bic?: string
              p_country?: string
              p_currency: string
              p_user_id: string
            }
            Returns: string
          }
      create_personal_node_for_user: {
        Args: {
          p_str_domain: string
          p_user_id: string
          p_wallet_address: string
        }
        Returns: string
      }
      create_prime_founder_position: {
        Args: { target_user_id: string }
        Returns: string
      }
      create_recovery_backup: { Args: { p_user_id: string }; Returns: Json }
      create_visa_card_for_user: {
        Args: { p_str_domain: string; p_user_id: string }
        Returns: string
      }
      credit_voucher_tokens:
        | {
            Args: {
              package_type_param: string
              token_type_param: string
              user_id_param: string
            }
            Returns: Json
          }
        | {
            Args: {
              package_type_param: string
              token_type_param: string
              user_id_param: string
              voucher_id: string
            }
            Returns: number
          }
      debit_fiat_wallet: {
        Args: { p_amount: number; p_currency: string; p_user_id: string }
        Returns: boolean
      }
      debit_staking_pool_balance: {
        Args: { p_amount: number; p_pool_type: string; p_user_id: string }
        Returns: boolean
      }
      distribute_enhanced_rewards: {
        Args: {
          amount: number
          duration_months_param: number
          network_efficiency_param?: number
          token_type_param: string
          user_id_param: string
        }
        Returns: Json
      }
      distribute_starw_wstr_rewards: { Args: never; Returns: Json }
      distribute_supernode_wstr_rewards: { Args: never; Returns: Json }
      distribute_vested_rewards: { Args: never; Returns: Json }
      emergency_assign_admin: { Args: never; Returns: boolean }
      emergency_disable_sensitive_access: { Args: never; Returns: boolean }
      emergency_encrypt_all_data: { Args: never; Returns: Json }
      emergency_encrypt_recovery_words: {
        Args: never
        Returns: {
          error_count: number
          processed_users: number
          success_count: number
        }[]
      }
      emergency_encrypt_specific_ibans: { Args: never; Returns: Json }
      emergency_security_fix_system: { Args: never; Returns: Json }
      enable_auto_encryption_triggers: { Args: never; Returns: Json }
      enable_strict_security_enforcement: { Args: never; Returns: Json }
      encrypt_recovery_words_batch: { Args: never; Returns: Json }
      enforce_mandatory_2fa_setup: { Args: never; Returns: Json }
      enhanced_rate_limit_check: {
        Args: {
          check_ip_address?: unknown
          check_user_id?: string
          max_attempts?: number
          operation_type?: string
          time_window_minutes?: number
        }
        Returns: Json
      }
      enhanced_sanitize_input: {
        Args: { input_text: string; input_type?: string }
        Returns: string
      }
      fix_all_user_voucher_balances: { Args: never; Returns: Json }
      fix_enhanced_pools_based_on_original_selections: {
        Args: never
        Returns: Json
      }
      fix_incomplete_user_accounts: { Args: never; Returns: Json }
      fix_missing_voucher_transaction_records: { Args: never; Returns: Json }
      fix_my_security_issues: { Args: never; Returns: Json }
      fix_str_balance_discrepancies: { Args: never; Returns: Json }
      generate_2fa_secret: { Args: never; Returns: Json }
      generate_backup_codes: { Args: { user_uuid: string }; Returns: Json }
      generate_ccoin_iban: { Args: { p_country: string }; Returns: string }
      generate_recovery_words: { Args: never; Returns: string[] }
      generate_str_wallet_address: { Args: never; Returns: string }
      get_admin_security_status: { Args: never; Returns: Json }
      get_aggregate_staking_stats: {
        Args: never
        Returns: {
          avg_ccos_apy: number
          avg_domain_apy: number
          avg_str_apy: number
          total_ccos_staked: number
          total_ccos_stakers: number
          total_domain_staked: number
          total_domain_stakers: number
          total_domains_owned: number
          total_str_staked: number
          total_str_stakers: number
        }[]
      }
      get_all_users_admin: { Args: never; Returns: Json[] }
      get_all_users_admin_unlimited: { Args: never; Returns: Json[] }
      get_available_balance: {
        Args: { p_token_type: string; p_user_id: string }
        Returns: number
      }
      get_ccoin_banking_overview: {
        Args: never
        Returns: {
          banking_status: string
          created_at: string
          email_address: string
          full_name: string
          has_any_iban: boolean
          has_ccoin_card: boolean
          has_chf_iban: boolean
          has_eur_iban: boolean
          has_gbp_iban: boolean
          has_visa_card: boolean
          kyc_status: string
          last_sync: string
          str_domain: string
          total_cards: number
          user_id: string
        }[]
      }
      get_client_ip: { Args: never; Returns: unknown }
      get_comprehensive_security_health: { Args: never; Returns: Json }
      get_domain_staking_stats: { Args: never; Returns: Json }
      get_emergency_pin_backup: { Args: never; Returns: Json }
      get_emergency_security_status: {
        Args: never
        Returns: {
          github_token_unencrypted: boolean
          iban_unencrypted: boolean
          pin_missing: boolean
          recovery_words_plaintext: boolean
          security_risk_level: string
          user_id: string
        }[]
      }
      get_founder_position_details: {
        Args: { link_id: string }
        Returns: {
          btc_wallet_locked: boolean
          ccos_mint_percentage: number
          current_usd_value: number
          deposit_date: string
          expected_btc_return: number
          id: string
          input_btc_amount: number
          is_prime: boolean
          is_withdrawal_ready: boolean
          lock_end_date: string
          output_btc_amount: number
          position_number: number
          position_type: string
          status: string
          title: string
          unique_link_id: string
          user_id: string
          withdrawal_address: string
          withdrawal_available_date: string
          withdrawal_executed: boolean
        }[]
      }
      get_member_banking_overview: {
        Args: never
        Returns: {
          account_status: string
          created_at: string
          email_address: string
          full_name: string
          has_ccoin_card: boolean
          has_iban: boolean
          has_visa_card: boolean
          str_domain: string
          total_cards: number
          user_id: string
        }[]
      }
      get_next_node_number: { Args: never; Returns: number }
      get_public_domain_staking_overview: {
        Args: never
        Returns: {
          average_domain_apy: number
          total_domain_rewards: number
          total_domain_staked: number
          total_domain_stakers: number
        }[]
      }
      get_public_pool_info: {
        Args: never
        Returns: {
          description: string
          id: string
          is_active: boolean
          pool_name: string
          pool_symbol: string
          pool_type: string
        }[]
      }
      get_security_health_summary: { Args: never; Returns: Json }
      get_security_metrics: {
        Args: { time_period_hours?: number }
        Returns: Json
      }
      get_security_metrics_unified: { Args: never; Returns: Json }
      get_total_ecosystem_value: { Args: never; Returns: number }
      get_user_enhanced_stakes: {
        Args: { user_id_param: string }
        Returns: {
          balance: number
          created_at: string
          duration_months: number
          dynamic_apy: number
          id: string
          is_locked: boolean
          lock_end_date: string
          network_efficiency: number
          pool_name: string
          pool_type: string
          rewards_earned: number
          staked_amount: number
          token_type: string
        }[]
      }
      get_user_financial_profile: {
        Args: { target_user_id: string }
        Returns: {
          ccoin_pool_balance: number
          iban_accounts: Json
          profile_id: string
          recent_transfers: Json
          sourceless_account: Json
          str_domain: string
          visa_card_info: Json
        }[]
      }
      get_user_profile_data: {
        Args: { target_user_id?: string }
        Returns: {
          email_address: string
          full_name: string
          id: string
          recovery_words_encrypted: boolean
          status: Database["public"]["Enums"]["account_status"]
          str_domain_owned: string
          two_factor_enabled: boolean
          user_id: string
          user_status: Database["public"]["Enums"]["user_status"]
          wallet_setup_completed: boolean
        }[]
      }
      get_user_profile_secure: {
        Args: { target_user_id?: string }
        Returns: {
          created_at: string
          email_address: string
          full_name: string
          id: string
          recovery_words_encrypted: boolean
          status: Database["public"]["Enums"]["account_status"]
          str_domain_owned: string
          two_factor_enabled: boolean
          updated_at: string
          user_id: string
          user_status: Database["public"]["Enums"]["user_status"]
          wallet_setup_completed: boolean
        }[]
      }
      get_user_role: {
        Args: { _user_id: string }
        Returns: Database["public"]["Enums"]["app_role"]
      }
      get_user_transactions: {
        Args: { limit_count?: number }
        Returns: {
          amount: number
          created_at: string
          id: string
          status: string
          transaction_id: string
        }[]
      }
      get_user_wstr_balance: { Args: { p_user_id: string }; Returns: number }
      get_users_recovery_overview: {
        Args: never
        Returns: {
          account_created: string
          email_address: string
          full_name: string
          has_pin: boolean
          has_recovery_words: boolean
          last_backup_date: string
          recovery_words_shown: boolean
          total_backups: number
          two_fa_enabled: boolean
          user_id: string
        }[]
      }
      get_vip_users_detailed: {
        Args: never
        Returns: {
          email_address: string
          full_name: string
          qualification_type: string
          qualified_at: string
          total_domains_staked: number
          total_str_staked: number
          user_id: string
          vip_status: string
        }[]
      }
      get_voucher_audit_trail: {
        Args: { voucher_id: string }
        Returns: {
          action_performed: string
          admin_notes: string
          created_at: string
          error_details: Json
          id: string
          metadata: Json
          performed_by: string
          performer_email: string
          status_from: string
          status_to: string
        }[]
      }
      get_wallet_recovery_words: {
        Args: { input_pin?: string; user_uuid: string }
        Returns: string[]
      }
      get_wallet_recovery_words_secure:
        | { Args: { user_pin: string }; Returns: Json }
        | {
            Args: { client_ip?: unknown; input_pin: string; user_uuid: string }
            Returns: Json
          }
        | {
            Args: { client_ip?: string; input_pin: string; user_uuid: string }
            Returns: Json
          }
      has_pool_access: { Args: { user_uuid: string }; Returns: boolean }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      has_seed_str_admin_access: {
        Args: { check_user_id: string }
        Returns: boolean
      }
      hash_existing_position_passwords: { Args: never; Returns: undefined }
      hash_password: { Args: { password_text: string }; Returns: string }
      hash_pin_secure: {
        Args: { pin_text: string; user_uuid: string }
        Returns: string
      }
      hash_wallet_pin: { Args: { plain_pin: string }; Returns: string }
      iban_is_valid: { Args: { p_iban: string }; Returns: boolean }
      iban_mod97: { Args: { p_text: string }; Returns: number }
      initialize_ccoin_banking_profile: {
        Args: { p_user_id: string }
        Returns: string
      }
      initialize_user_staking_pools: {
        Args: { target_user_id: string }
        Returns: undefined
      }
      is_admin: { Args: { check_user_id?: string }; Returns: boolean }
      is_domain_available_for_listing: {
        Args: { p_domain_name: string }
        Returns: boolean
      }
      is_safe_admin: { Args: { _user_id: string }; Returns: boolean }
      is_seed_str_admin: { Args: { check_user_id?: string }; Returns: boolean }
      is_strict_admin: { Args: { check_user_id?: string }; Returns: boolean }
      is_withdrawal_available: {
        Args: { position_id: string }
        Returns: boolean
      }
      ledger_anchor_assert_reader: {
        Args: { p_what: string }
        Returns: undefined
      }
      ledger_anchor_assert_service: {
        Args: { p_what: string }
        Returns: undefined
      }
      ledger_anchor_claim: {
        Args: { p_lease_seconds?: number; p_limit?: number; p_worker: string }
        Returns: {
          anchor_target: string
          attempt_no: number
          chain_id: number
          content_hash: string
          contract_address: string
          hash_algorithm: string
          journal_id: string
          lease_expires_at: string
          reference: string
          required_confirmations: number
          rpc_url: string
          tx_hash_pattern: string
        }[]
      }
      ledger_anchor_content_hash: {
        Args: { p_journal_id: string }
        Returns: string
      }
      ledger_anchor_export: { Args: { p_journal_id: string }; Returns: Json }
      ledger_anchor_payload: { Args: { p_journal_id: string }; Returns: string }
      ledger_anchor_record_confirmation: {
        Args: {
          p_block_hash?: string
          p_block_number?: number
          p_confirmations: number
          p_journal_id: string
          p_worker?: string
        }
        Returns: Json
      }
      ledger_anchor_record_failure: {
        Args: { p_error: string; p_journal_id: string; p_worker?: string }
        Returns: Json
      }
      ledger_anchor_record_submission: {
        Args: {
          p_journal_id: string
          p_submitted_at?: string
          p_tx_hash: string
          p_worker?: string
        }
        Returns: Json
      }
      ledger_anchor_reset: {
        Args: { p_journal_id: string; p_reason: string }
        Returns: Json
      }
      ledger_anchor_status: { Args: never; Returns: Json }
      ledger_anchor_verify: { Args: { p_journal_id: string }; Returns: Json }
      ledger_anchor_verify_range: {
        Args: { p_from?: string; p_to?: string }
        Returns: {
          anchor_status: string
          anchored_hash: string
          confirmations: number
          journal_id: string
          ledger_label: string
          matches: boolean
          posted_at: string
          recomputed_hash: string
          reference: string
          required_confirmations: number
          tx_hash: string
          verdict: string
        }[]
      }
      ledger_apply_projection: {
        Args: {
          p_asset: string
          p_bucket: string
          p_delta_minor: number
          p_user_id: string
        }
        Returns: undefined
      }
      ledger_is_system: { Args: { p_user_id: string }; Returns: boolean }
      ledger_major: {
        Args: { p_asset: string; p_minor: number }
        Returns: number
      }
      ledger_minor: {
        Args: { p_amount: number; p_asset: string }
        Returns: number
      }
      ledger_opening_balance: {
        Args: { p_asset: string; p_bucket: string; p_user_id: string }
        Returns: number
      }
      ledger_resolve_account: {
        Args: { p_asset: string; p_bucket: string; p_user_id: string }
        Returns: string
      }
      ledger_restore_pool_unique_key: { Args: never; Returns: string }
      ledger_system_user: { Args: { p_code: string }; Returns: string }
      link_iban_to_pool: {
        Args: { iban_id: string; pool_type_param?: string }
        Returns: boolean
      }
      log_critical_security_event:
        | { Args: { details?: Json; event_type: string }; Returns: undefined }
        | {
            Args: {
              details_param?: Json
              event_type: string
              operation: string
              table_name: string
              user_id_param?: string
            }
            Returns: undefined
          }
      log_emergency_security_action: {
        Args: {
          action_details?: Json
          action_type: string
          action_user_id: string
        }
        Returns: undefined
      }
      log_security_access_pattern: {
        Args: {
          operation_type: string
          row_count?: number
          table_name: string
          user_id_param: string
        }
        Returns: undefined
      }
      log_security_audit: {
        Args: {
          audit_action: string
          audit_details?: Json
          audit_resource: string
        }
        Returns: undefined
      }
      log_security_event: {
        Args: {
          action_name: string
          details_json?: Json
          resource_id_val?: string
          resource_type_name: string
        }
        Returns: undefined
      }
      log_security_violation: {
        Args: {
          details_param?: Json
          resource_table: string
          user_id_param?: string
          violation_type: string
        }
        Returns: undefined
      }
      manual_calculate_rewards: { Args: never; Returns: string }
      mark_data_encrypted: {
        Args: {
          p_encrypted_data: string
          p_field_name: string
          p_record_id: string
          p_table_name: string
        }
        Returns: boolean
      }
      mark_user_data_encrypted: {
        Args: { user_id_param: string }
        Returns: Json
      }
      marketplace_escrow_lock: { Args: { p_listing_id: string }; Returns: Json }
      mask_sensitive_fields: {
        Args: { data_type: string; field_value: string; show_full?: boolean }
        Returns: string
      }
      migrate_sensitive_data_to_secure_tables: { Args: never; Returns: Json }
      migrate_staking_history_to_enhanced: { Args: never; Returns: Json }
      migrate_users_to_enhanced_pools: { Args: never; Returns: Json }
      migrate_users_to_enhanced_pools_by_request: { Args: never; Returns: Json }
      migration_login_allowed: {
        Args: { p_email: string; p_ip: string }
        Returns: boolean
      }
      migration_login_record: {
        Args: { p_email: string; p_ip: string; p_ok: boolean }
        Returns: undefined
      }
      notify_all_users_proposal_approved: {
        Args: { proposal_id: string; proposal_title: string }
        Returns: undefined
      }
      perform_security_health_check: { Args: never; Returns: Json }
      post_entries: {
        Args: { p_entries: Json; p_reason: string; p_reference: string }
        Returns: Json
      }
      process_pending_transfer: {
        Args: {
          p_action: string
          p_admin_id: string
          p_admin_notes?: string
          p_tx_id: string
        }
        Returns: Json
      }
      process_staking_request:
        | {
            Args: {
              p_action: string
              p_admin_notes?: string
              p_request_id: string
            }
            Returns: Json
          }
        | {
            Args: {
              admin_notes_param?: string
              approve: boolean
              request_id: string
            }
            Returns: Json
          }
      process_voucher_redemption_with_audit: {
        Args: {
          admin_notes_param?: string
          client_ip?: unknown
          new_status: string
          performed_by_user_id: string
          user_agent_param?: string
          voucher_id: string
        }
        Returns: Json
      }
      provision_banking_for_user: {
        Args: {
          p_currencies?: string[]
          p_full_name: string
          p_user_id: string
        }
        Returns: Json
      }
      quarantine_import: {
        Args: {
          p_balances: Json
          p_snapshot: Json
          p_source_email: string
          p_source_project: string
          p_source_user_id: string
          p_user_id: string
        }
        Returns: Json
      }
      refund_held_transfer_atomic: {
        Args: { p_tx_id: string; p_user_id: string }
        Returns: Json
      }
      reject_migration: {
        Args: { p_note: string; p_user_id: string }
        Returns: Json
      }
      release_expired_domain_reservations: { Args: never; Returns: number }
      release_marketplace_escrow: {
        Args: { p_listing_id: string }
        Returns: Json
      }
      reset_user_pin: { Args: never; Returns: Json }
      resolve_str_address: {
        Args: { p_address: string }
        Returns: {
          address_type: string
          full_address: string
          user_id: string
        }[]
      }
      rollback_enhanced_pool_migration: { Args: never; Returns: Json }
      run_critical_security_fixes: { Args: never; Returns: Json }
      run_security_health_check: {
        Args: { check_user_id: string }
        Returns: Json
      }
      sanitize_chat_message: { Args: { message_text: string }; Returns: string }
      sanitize_text_input: { Args: { input_text: string }; Returns: string }
      sanitize_user_input: {
        Args: { allow_html?: boolean; input_text: string; max_length?: number }
        Returns: string
      }
      secure_update_user_profile: {
        Args: { profile_data: Json }
        Returns: boolean
      }
      send_chat_message:
        | { Args: { message_text: string }; Returns: string }
        | {
            Args: { message_text: string; room_type?: string }
            Returns: string
          }
        | {
            Args: {
              message_text: string
              reply_to_id?: string
              room_type: string
            }
            Returns: undefined
          }
      set_ecosystem_app_active: {
        Args: { p_active: boolean; p_slug: string }
        Returns: Json
      }
      set_quarantine_correction: {
        Args: {
          p_amount: number
          p_asset: string
          p_bucket: string
          p_note?: string
          p_user_id: string
        }
        Returns: Json
      }
      split_user_pools_by_duration: { Args: never; Returns: Json }
      submit_governance_vote: {
        Args: { proposal_id: string; support_vote: boolean }
        Returns: undefined
      }
      sync_ccoin_banking_profiles: { Args: never; Returns: Json }
      sync_profiles_from_auth: { Args: never; Returns: undefined }
      test_critical_security_fixes: { Args: never; Returns: Json }
      transfer_staking_pool_atomic: {
        Args: {
          p_amount: number
          p_from_user_id: string
          p_pool_type: string
          p_to_user_id: string
        }
        Returns: boolean
      }
      update_pool_apy_by_duration: { Args: never; Returns: Json }
      update_pool_stats: { Args: { pool_uuid: string }; Returns: undefined }
      update_user_account_status: {
        Args: {
          new_status: Database["public"]["Enums"]["account_status"]
          target_user_id: string
        }
        Returns: boolean
      }
      update_user_badge_status: {
        Args: {
          new_user_status: Database["public"]["Enums"]["user_status"]
          target_user_id: string
        }
        Returns: boolean
      }
      update_user_status: {
        Args: { new_status: string; target_user_id: string }
        Returns: boolean
      }
      update_vip_status: { Args: never; Returns: Json }
      update_wallet_balance: {
        Args: {
          amount_change: number
          description: string
          source_type: string
          target_user_id: string
          transaction_type: string
        }
        Returns: boolean
      }
      upsert_ecosystem_app: {
        Args: {
          p_active?: boolean
          p_category?: string
          p_description?: string
          p_embeddable?: boolean
          p_icon?: string
          p_name: string
          p_requires_role?: Database["public"]["Enums"]["app_role"]
          p_slug: string
          p_sort_order?: number
          p_url: string
        }
        Returns: Json
      }
      v2_admin_bulk_delete_requests: {
        Args: { p_ids: string[]; p_reason?: string; p_source: string }
        Returns: Json
      }
      v2_admin_bulk_update_requests: {
        Args: {
          p_ids: string[]
          p_notes?: string
          p_source: string
          p_status: string
        }
        Returns: Json
      }
      v2_admin_delete_request: {
        Args: { p_id: string; p_reason?: string; p_source: string }
        Returns: Json
      }
      v2_admin_fulfill_request: {
        Args: {
          p_from_status: string
          p_id: string
          p_source: string
          p_to_status: string
        }
        Returns: Json
      }
      v2_admin_message_request: {
        Args: {
          p_body: string
          p_id: string
          p_requires_response?: boolean
          p_source: string
          p_subject?: string
          p_user_id: string
        }
        Returns: Json
      }
      v2_admin_update_request: {
        Args: {
          p_id: string
          p_notes?: string
          p_source: string
          p_status: string
        }
        Returns: Json
      }
      v2_apply_profile_update: {
        Args: { p_id: string; p_status: string }
        Returns: undefined
      }
      v2_import_legacy_account: { Args: { p_user_id: string }; Returns: Json }
      v2_import_legacy_account_by_email: {
        Args: { p_email: string }
        Returns: Json
      }
      v2_member_close_ticket: { Args: { p_id: string }; Returns: Json }
      v2_member_message_request: {
        Args: { p_body: string; p_id: string; p_source: string }
        Returns: Json
      }
      v2_member_set_connection: {
        Args: { p_service: string; p_status: string }
        Returns: Json
      }
      v2_review_account: {
        Args: { p_account_id: string; p_notes?: string; p_status: string }
        Returns: Json
      }
      v2_review_asset_claim: {
        Args: {
          p_approve: boolean
          p_claim_id: string
          p_notes?: string
          p_verified_amount?: number
        }
        Returns: Json
      }
      validate_and_sanitize_input: {
        Args: { input_text: string; max_length?: number }
        Returns: string
      }
      validate_founder_access_code: {
        Args: { access_code: string }
        Returns: boolean
      }
      validate_master_password_secure: {
        Args: { client_ip?: unknown; input_password: string }
        Returns: boolean
      }
      validate_position_password: {
        Args: { input_password: string; position_id: string }
        Returns: boolean
      }
      validate_sensitive_data_access: {
        Args: { operation: string; table_name: string }
        Returns: boolean
      }
      validate_sensitive_operation: {
        Args: { ip_address?: unknown; operation_type: string; user_id: string }
        Returns: boolean
      }
      validate_session_security: { Args: never; Returns: boolean }
      validate_user_session: {
        Args: { device_fingerprint_param?: string; session_token_param: string }
        Returns: Json
      }
      validate_wallet_pin: {
        Args: { input_pin: string; user_uuid: string }
        Returns: boolean
      }
      validate_wallet_pin_secure: {
        Args: { client_ip?: unknown; input_pin: string; user_uuid: string }
        Returns: Json
      }
      validate_wallet_pin_secure_fixed: {
        Args: { client_ip?: unknown; input_pin: string; user_uuid: string }
        Returns: Json
      }
      verify_2fa_setup: {
        Args: {
          secret_key: string
          user_uuid: string
          verification_code: string
        }
        Returns: Json
      }
      verify_admin_access: { Args: { check_user_id: string }; Returns: Json }
      verify_admin_with_enhanced_security:
        | {
            Args: {
              admin_user_id: string
              operation_type: string
              risk_level?: string
            }
            Returns: Json
          }
        | { Args: { check_user_id: string }; Returns: Json }
      verify_password: {
        Args: { input_password: string; stored_hash: string }
        Returns: boolean
      }
      verify_pin_secure:
        | { Args: { pin_text: string; stored_hash: string }; Returns: boolean }
        | { Args: { pin_text: string; user_uuid: string }; Returns: Json }
    }
    Enums: {
      account_status: "pending" | "approved" | "suspended" | "closed"
      account_type_enum: "personal" | "business" | "corporate"
      app_role:
        | "admin"
        | "moderator"
        | "user"
        | "support"
        | "marketing"
        | "legal"
        | "arx"
        | "seed_str_admin"
      migration_state: "quarantined" | "under_review" | "approved" | "rejected"
      pool_status: "active" | "paused" | "closed" | "archived"
      reward_curve: "linear" | "tiered" | "exponential"
      user_status: "standard" | "silver" | "gold" | "platinum" | "vip"
    }
    CompositeTypes: {
      ledger_leg: {
        user_id: string | null
        asset: string | null
        bucket: string | null
        amount: number | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      account_status: ["pending", "approved", "suspended", "closed"],
      account_type_enum: ["personal", "business", "corporate"],
      app_role: [
        "admin",
        "moderator",
        "user",
        "support",
        "marketing",
        "legal",
        "arx",
        "seed_str_admin",
      ],
      migration_state: ["quarantined", "under_review", "approved", "rejected"],
      pool_status: ["active", "paused", "closed", "archived"],
      reward_curve: ["linear", "tiered", "exponential"],
      user_status: ["standard", "silver", "gold", "platinum", "vip"],
    },
  },
} as const
