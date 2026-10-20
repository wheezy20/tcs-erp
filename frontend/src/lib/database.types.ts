export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          category: string
          code: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          is_active: boolean
          is_postable: boolean
          name: string
          normal_balance: string | null
          subtype: string
          updated_at: string
        }
        Insert: {
          category: string
          code: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          is_active?: boolean
          is_postable?: boolean
          name: string
          normal_balance?: string | null
          subtype: string
          updated_at?: string
        }
        Update: {
          category?: string
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          is_active?: boolean
          is_postable?: boolean
          name?: string
          normal_balance?: string | null
          subtype?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      admissions_academic_years: {
        Row: {
          created_at: string
          is_active: boolean
          label: string
          position: number
        }
        Insert: {
          created_at?: string
          is_active?: boolean
          label: string
          position: number
        }
        Update: {
          created_at?: string
          is_active?: boolean
          label?: string
          position?: number
        }
        Relationships: []
      }
      admissions_campus_grade_rules: {
        Row: {
          branch_id: string
          grade_id: string
        }
        Insert: {
          branch_id: string
          grade_id: string
        }
        Update: {
          branch_id?: string
          grade_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admissions_campus_grade_rules_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admissions_campus_grade_rules_grade_id_fkey"
            columns: ["grade_id"]
            isOneToOne: false
            referencedRelation: "admissions_grades"
            referencedColumns: ["id"]
          },
        ]
      }
      admissions_capacity: {
        Row: {
          academic_year: string
          branch_id: string | null
          capacity: number
          grade_id: string
          id: string
        }
        Insert: {
          academic_year: string
          branch_id?: string | null
          capacity: number
          grade_id: string
          id?: string
        }
        Update: {
          academic_year?: string
          branch_id?: string | null
          capacity?: number
          grade_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admissions_capacity_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admissions_capacity_grade_id_fkey"
            columns: ["grade_id"]
            isOneToOne: false
            referencedRelation: "admissions_grades"
            referencedColumns: ["id"]
          },
        ]
      }
      admissions_email_outbox: {
        Row: {
          application_ids: string[]
          attempts: number
          claim_token: string | null
          claimed_at: string | null
          created_at: string
          event_key: string
          id: string
          kind: string
          last_error_class: string | null
          last_http_status: number | null
          next_attempt_at: string
          params: Json
          provider_message_id: string | null
          recipient_email: string | null
          requeued_at: string | null
          requeued_by: string | null
          sent_at: string | null
          status: string
        }
        Insert: {
          application_ids: string[]
          attempts?: number
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          event_key: string
          id?: string
          kind: string
          last_error_class?: string | null
          last_http_status?: number | null
          next_attempt_at?: string
          params: Json
          provider_message_id?: string | null
          recipient_email?: string | null
          requeued_at?: string | null
          requeued_by?: string | null
          sent_at?: string | null
          status?: string
        }
        Update: {
          application_ids?: string[]
          attempts?: number
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          event_key?: string
          id?: string
          kind?: string
          last_error_class?: string | null
          last_http_status?: number | null
          next_attempt_at?: string
          params?: Json
          provider_message_id?: string | null
          recipient_email?: string | null
          requeued_at?: string | null
          requeued_by?: string | null
          sent_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "admissions_email_outbox_requeued_by_fkey"
            columns: ["requeued_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      admissions_email_worker: {
        Row: {
          ceiling_reached_at: string | null
          id: boolean
          last_run_at: string | null
          last_success_at: string | null
          worker_url: string | null
        }
        Insert: {
          ceiling_reached_at?: string | null
          id?: boolean
          last_run_at?: string | null
          last_success_at?: string | null
          worker_url?: string | null
        }
        Update: {
          ceiling_reached_at?: string | null
          id?: boolean
          last_run_at?: string | null
          last_success_at?: string | null
          worker_url?: string | null
        }
        Relationships: []
      }
      admissions_grades: {
        Row: {
          band: string | null
          classification_code: string | null
          created_at: string
          id: string
          is_active: boolean
          is_preschool_vaccination_required: boolean
          name: string
          position: number
        }
        Insert: {
          band?: string | null
          classification_code?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          is_preschool_vaccination_required?: boolean
          name: string
          position: number
        }
        Update: {
          band?: string | null
          classification_code?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          is_preschool_vaccination_required?: boolean
          name?: string
          position?: number
        }
        Relationships: []
      }
      admissions_reference_counters: {
        Row: {
          key: string
          next_value: number
        }
        Insert: {
          key: string
          next_value?: number
        }
        Update: {
          key?: string
          next_value?: number
        }
        Relationships: []
      }
      admissions_settings: {
        Row: {
          id: number
          offer_ttl_days: number
          public_applications_open: boolean
          public_intake_open: boolean
          updated_at: string
        }
        Insert: {
          id?: number
          offer_ttl_days?: number
          public_applications_open?: boolean
          public_intake_open?: boolean
          updated_at?: string
        }
        Update: {
          id?: number
          offer_ttl_days?: number
          public_applications_open?: boolean
          public_intake_open?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      allowance_types: {
        Row: {
          branch_id: string
          id: string
          name: string
          position: number
          taxable: boolean
        }
        Insert: {
          branch_id: string
          id?: string
          name: string
          position?: number
          taxable?: boolean
        }
        Update: {
          branch_id?: string
          id?: string
          name?: string
          position?: number
          taxable?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "allowance_types_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      application_decisions: {
        Row: {
          application_id: string
          decided_at: string
          decided_by: string | null
          decision_type: string
          id: string
          notes: string
        }
        Insert: {
          application_id: string
          decided_at?: string
          decided_by?: string | null
          decision_type: string
          id?: string
          notes?: string
        }
        Update: {
          application_id?: string
          decided_at?: string
          decided_by?: string | null
          decision_type?: string
          id?: string
          notes?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_decisions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_decisions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_decisions_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      application_documents: {
        Row: {
          application_id: string
          document_type: string
          id: string
          status: string
          storage_path: string | null
          uploaded_at: string | null
        }
        Insert: {
          application_id: string
          document_type: string
          id?: string
          status?: string
          storage_path?: string | null
          uploaded_at?: string | null
        }
        Update: {
          application_id?: string
          document_type?: string
          id?: string
          status?: string
          storage_path?: string | null
          uploaded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "application_documents_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_documents_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_emergency_contacts: {
        Row: {
          application_id: string
          id: string
          name: string
          phone: string
          relationship: string
        }
        Insert: {
          application_id: string
          id?: string
          name: string
          phone: string
          relationship: string
        }
        Update: {
          application_id?: string
          id?: string
          name?: string
          phone?: string
          relationship?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_emergency_contacts_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_emergency_contacts_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_health_info: {
        Row: {
          allergies_dietary_details: string
          application_id: string
          has_allergies_or_dietary_requirements: boolean
          has_learning_or_physical_needs: boolean
          has_medical_conditions: boolean
          id: string
          learning_or_physical_needs_details: string
          medical_conditions_details: string
        }
        Insert: {
          allergies_dietary_details?: string
          application_id: string
          has_allergies_or_dietary_requirements?: boolean
          has_learning_or_physical_needs?: boolean
          has_medical_conditions?: boolean
          id?: string
          learning_or_physical_needs_details?: string
          medical_conditions_details?: string
        }
        Update: {
          allergies_dietary_details?: string
          application_id?: string
          has_allergies_or_dietary_requirements?: boolean
          has_learning_or_physical_needs?: boolean
          has_medical_conditions?: boolean
          id?: string
          learning_or_physical_needs_details?: string
          medical_conditions_details?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_health_info_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_health_info_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_match_flags: {
        Row: {
          application_id: string
          created_at: string
          differences: Json
          family_matched: boolean
          id: string
          matched_application_id: string | null
          outcome: string
          student_matched: boolean
        }
        Insert: {
          application_id: string
          created_at?: string
          differences?: Json
          family_matched: boolean
          id?: string
          matched_application_id?: string | null
          outcome: string
          student_matched: boolean
        }
        Update: {
          application_id?: string
          created_at?: string
          differences?: Json
          family_matched?: boolean
          id?: string
          matched_application_id?: string | null
          outcome?: string
          student_matched?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "application_match_flags_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_match_flags_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_match_flags_matched_application_id_fkey"
            columns: ["matched_application_id"]
            isOneToOne: false
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_match_flags_matched_application_id_fkey"
            columns: ["matched_application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_notes: {
        Row: {
          application_id: string
          author_id: string | null
          content: string
          created_at: string
          edited_at: string | null
          id: string
        }
        Insert: {
          application_id: string
          author_id?: string | null
          content: string
          created_at?: string
          edited_at?: string | null
          id?: string
        }
        Update: {
          application_id?: string
          author_id?: string | null
          content?: string
          created_at?: string
          edited_at?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_notes_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      application_offers: {
        Row: {
          application_id: string
          expires_at: string | null
          id: string
          responded_at: string | null
          response: string
          sent_at: string | null
          token_hash: string
        }
        Insert: {
          application_id: string
          expires_at?: string | null
          id?: string
          responded_at?: string | null
          response?: string
          sent_at?: string | null
          token_hash: string
        }
        Update: {
          application_id?: string
          expires_at?: string | null
          id?: string
          responded_at?: string | null
          response?: string
          sent_at?: string | null
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      application_upload_reservations: {
        Row: {
          cleaned_at: string | null
          cleanup_claimed_at: string | null
          consumed_at: string | null
          created_at: string
          document_type: string
          expires_at: string
          extension: string
          id: string
          session_id: string
          storage_path: string | null
        }
        Insert: {
          cleaned_at?: string | null
          cleanup_claimed_at?: string | null
          consumed_at?: string | null
          created_at?: string
          document_type: string
          expires_at: string
          extension: string
          id?: string
          session_id: string
          storage_path?: string | null
        }
        Update: {
          cleaned_at?: string | null
          cleanup_claimed_at?: string | null
          consumed_at?: string | null
          created_at?: string
          document_type?: string
          expires_at?: string
          extension?: string
          id?: string
          session_id?: string
          storage_path?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "application_upload_reservations_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "application_upload_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      application_upload_sessions: {
        Row: {
          closed_at: string | null
          created_at: string
          expires_at: string
          id: string
          submitted_application_id: string | null
          token_hash: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          submitted_application_id?: string | null
          token_hash: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          submitted_application_id?: string | null
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "application_upload_sessions_submitted_application_id_fkey"
            columns: ["submitted_application_id"]
            isOneToOne: false
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_upload_sessions_submitted_application_id_fkey"
            columns: ["submitted_application_id"]
            isOneToOne: false
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
      applications: {
        Row: {
          academic_year: string
          application_reference: string | null
          branch_id: string | null
          created_at: string
          declaration_agreed: boolean
          declaration_agreed_at: string | null
          declaration_ip_address: unknown
          declaration_signature_name: string
          id: string
          inquiry_reference: string | null
          media_consent_agreed: boolean
          month_of_enrollment: string
          scholarship_interest_details: string
          stage: string
          student_id: string
          updated_at: string
          wants_scholarship_info: boolean
          year_group_applied_for: string
        }
        Insert: {
          academic_year: string
          application_reference?: string | null
          branch_id?: string | null
          created_at?: string
          declaration_agreed?: boolean
          declaration_agreed_at?: string | null
          declaration_ip_address?: unknown
          declaration_signature_name?: string
          id?: string
          inquiry_reference?: string | null
          media_consent_agreed?: boolean
          month_of_enrollment?: string
          scholarship_interest_details?: string
          stage?: string
          student_id: string
          updated_at?: string
          wants_scholarship_info?: boolean
          year_group_applied_for: string
        }
        Update: {
          academic_year?: string
          application_reference?: string | null
          branch_id?: string | null
          created_at?: string
          declaration_agreed?: boolean
          declaration_agreed_at?: string | null
          declaration_ip_address?: unknown
          declaration_signature_name?: string
          id?: string
          inquiry_reference?: string | null
          media_consent_agreed?: boolean
          month_of_enrollment?: string
          scholarship_interest_details?: string
          stage?: string
          student_id?: string
          updated_at?: string
          wants_scholarship_info?: boolean
          year_group_applied_for?: string
        }
        Relationships: [
          {
            foreignKeyName: "applications_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_id: string
          after: Json | null
          before: Json | null
          branch_id: string
          entity_id: string
          entity_table: string
          id: string
          occurred_at: string
        }
        Insert: {
          action: string
          actor_id: string
          after?: Json | null
          before?: Json | null
          branch_id: string
          entity_id: string
          entity_table: string
          id?: string
          occurred_at?: string
        }
        Update: {
          action?: string
          actor_id?: string
          after?: Json | null
          before?: Json | null
          branch_id?: string
          entity_id?: string
          entity_table?: string
          id?: string
          occurred_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_accounts: {
        Row: {
          account_number: string
          created_at: string
          created_by: string
          currency: string
          gl_account_id: string
          id: string
          is_active: boolean
          name: string
          opening_balance: number
          opening_balance_date: string
          updated_at: string
        }
        Insert: {
          account_number: string
          created_at?: string
          created_by?: string
          currency?: string
          gl_account_id: string
          id?: string
          is_active?: boolean
          name: string
          opening_balance?: number
          opening_balance_date: string
          updated_at?: string
        }
        Update: {
          account_number?: string
          created_at?: string
          created_by?: string
          currency?: string
          gl_account_id?: string
          id?: string
          is_active?: boolean
          name?: string
          opening_balance?: number
          opening_balance_date?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_accounts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_accounts_gl_account_id_fkey"
            columns: ["gl_account_id"]
            isOneToOne: true
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_deposits: {
        Row: {
          amount: number
          bank_account_id: string
          branch_id: string
          created_at: string
          date: string
          deposited_by: string
          id: string
          note: string
          reference: string
          source: string
        }
        Insert: {
          amount: number
          bank_account_id: string
          branch_id: string
          created_at?: string
          date: string
          deposited_by?: string
          id?: string
          note?: string
          reference?: string
          source: string
        }
        Update: {
          amount?: number
          bank_account_id?: string
          branch_id?: string
          created_at?: string
          date?: string
          deposited_by?: string
          id?: string
          note?: string
          reference?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_deposits_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_deposits_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_deposits_deposited_by_fkey"
            columns: ["deposited_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_reconciliations: {
        Row: {
          bank_account_id: string
          completed_at: string | null
          completed_by: string | null
          difference: number | null
          id: string
          notes: string
          opening_balance: number
          reconciled_balance: number | null
          started_at: string
          started_by: string
          statement_date: string
          statement_ending_balance: number
        }
        Insert: {
          bank_account_id: string
          completed_at?: string | null
          completed_by?: string | null
          difference?: number | null
          id?: string
          notes?: string
          opening_balance: number
          reconciled_balance?: number | null
          started_at?: string
          started_by?: string
          statement_date: string
          statement_ending_balance: number
        }
        Update: {
          bank_account_id?: string
          completed_at?: string | null
          completed_by?: string | null
          difference?: number | null
          id?: string
          notes?: string
          opening_balance?: number
          reconciled_balance?: number | null
          started_at?: string
          started_by?: string
          statement_date?: string
          statement_ending_balance?: number
        }
        Relationships: [
          {
            foreignKeyName: "bank_reconciliations_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_reconciliations_started_by_fkey"
            columns: ["started_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      bank_statement_lines: {
        Row: {
          amount: number
          bank_account_id: string
          clear_note: string
          created_at: string
          date: string
          description: string
          id: string
          imported_by: string
          matched_at: string | null
          matched_by: string | null
          matched_journal_line_id: string | null
          reconciliation_id: string | null
          reference: string
          status: string
        }
        Insert: {
          amount: number
          bank_account_id: string
          clear_note?: string
          created_at?: string
          date: string
          description: string
          id?: string
          imported_by?: string
          matched_at?: string | null
          matched_by?: string | null
          matched_journal_line_id?: string | null
          reconciliation_id?: string | null
          reference?: string
          status?: string
        }
        Update: {
          amount?: number
          bank_account_id?: string
          clear_note?: string
          created_at?: string
          date?: string
          description?: string
          id?: string
          imported_by?: string
          matched_at?: string | null
          matched_by?: string | null
          matched_journal_line_id?: string | null
          reconciliation_id?: string | null
          reference?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_statement_lines_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_statement_lines_imported_by_fkey"
            columns: ["imported_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_statement_lines_matched_by_fkey"
            columns: ["matched_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_statement_lines_matched_journal_line_id_fkey"
            columns: ["matched_journal_line_id"]
            isOneToOne: true
            referencedRelation: "journal_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bank_statement_lines_reconciliation_id_fkey"
            columns: ["reconciliation_id"]
            isOneToOne: false
            referencedRelation: "bank_reconciliations"
            referencedColumns: ["id"]
          },
        ]
      }
      branches: {
        Row: {
          created_at: string
          default_low_stock_threshold: number
          id: string
          name: string
          public_label: string | null
        }
        Insert: {
          created_at?: string
          default_low_stock_threshold?: number
          id?: string
          name: string
          public_label?: string | null
        }
        Update: {
          created_at?: string
          default_low_stock_threshold?: number
          id?: string
          name?: string
          public_label?: string | null
        }
        Relationships: []
      }
      business_settings: {
        Row: {
          daily_sales_summary_enabled: boolean
          id: number
          low_stock_alerts_enabled: boolean
          overdue_invoice_alerts_enabled: boolean
          session_timeout_minutes: number
          updated_at: string
          vat_rate: number
          wht_rate: number
        }
        Insert: {
          daily_sales_summary_enabled?: boolean
          id?: number
          low_stock_alerts_enabled?: boolean
          overdue_invoice_alerts_enabled?: boolean
          session_timeout_minutes?: number
          updated_at?: string
          vat_rate?: number
          wht_rate?: number
        }
        Update: {
          daily_sales_summary_enabled?: boolean
          id?: number
          low_stock_alerts_enabled?: boolean
          overdue_invoice_alerts_enabled?: boolean
          session_timeout_minutes?: number
          updated_at?: string
          vat_rate?: number
          wht_rate?: number
        }
        Relationships: []
      }
      contract_templates: {
        Row: {
          category: string
          created_at: string
          html_body: string
          id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          category: string
          created_at?: string
          html_body?: string
          id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          category?: string
          created_at?: string
          html_body?: string
          id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contract_templates_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_deposits: {
        Row: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          cancellation_fee: number | null
          cancellation_note: string | null
          cancellation_refund: number | null
          cancelled_at: string | null
          cancelled_by: string | null
          customer_id: string
          customer_name: string
          description: string
          fulfilled_at: string | null
          fulfilled_invoice_id: string | null
          fulfilled_sale_id: string | null
          id: string
          method: string
          status: string
          taken_at: string
          taken_by: string
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          branch_id: string
          cancellation_fee?: number | null
          cancellation_note?: string | null
          cancellation_refund?: number | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          customer_id: string
          customer_name: string
          description?: string
          fulfilled_at?: string | null
          fulfilled_invoice_id?: string | null
          fulfilled_sale_id?: string | null
          id: string
          method: string
          status?: string
          taken_at?: string
          taken_by?: string
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          branch_id?: string
          cancellation_fee?: number | null
          cancellation_note?: string | null
          cancellation_refund?: number | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          customer_id?: string
          customer_name?: string
          description?: string
          fulfilled_at?: string | null
          fulfilled_invoice_id?: string | null
          fulfilled_sale_id?: string | null
          id?: string
          method?: string
          status?: string
          taken_at?: string
          taken_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_deposits_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_fulfilled_invoice_id_fkey"
            columns: ["fulfilled_invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_fulfilled_sale_id_fkey"
            columns: ["fulfilled_sale_id"]
            isOneToOne: false
            referencedRelation: "sales"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_deposits_taken_by_fkey"
            columns: ["taken_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_discounts: {
        Row: {
          active: boolean
          branch_id: string
          created_at: string
          created_by: string
          customer_id: string
          id: string
          label: string
          mode: string
          updated_at: string
          value: number
        }
        Insert: {
          active?: boolean
          branch_id: string
          created_at?: string
          created_by?: string
          customer_id: string
          id?: string
          label: string
          mode: string
          updated_at?: string
          value: number
        }
        Update: {
          active?: boolean
          branch_id?: string
          created_at?: string
          created_by?: string
          customer_id?: string
          id?: string
          label?: string
          mode?: string
          updated_at?: string
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "customer_discounts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_discounts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_discounts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          address: string
          balance: number
          branch_id: string
          created_at: string
          customer_since: string
          customer_type: string
          email: string
          id: string
          lifetime_total: number
          name: string
          phone: string
          store_credit_balance: number
          updated_at: string
        }
        Insert: {
          address?: string
          balance?: number
          branch_id: string
          created_at?: string
          customer_since?: string
          customer_type?: string
          email?: string
          id?: string
          lifetime_total?: number
          name: string
          phone: string
          store_credit_balance?: number
          updated_at?: string
        }
        Update: {
          address?: string
          balance?: number
          branch_id?: string
          created_at?: string
          customer_since?: string
          customer_type?: string
          email?: string
          id?: string
          lifetime_total?: number
          name?: string
          phone?: string
          store_credit_balance?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      day_closes: {
        Row: {
          bank_transfer_sales: number | null
          branch_id: string
          business_date: string
          card_sales: number | null
          cash_deposits: number | null
          cash_expenses: number | null
          cash_refunds: number | null
          cash_sales: number | null
          cash_variance: number | null
          closed_at: string | null
          closed_by: string | null
          counted_cash: number | null
          created_at: string
          discounts_given: number | null
          expected_cash: number | null
          id: string
          invoice_cash_sales: number | null
          invoice_cheque_sales: number | null
          manual_sales_total: number | null
          manual_transaction_count: number | null
          mobile_money_sales: number | null
          notes: string
          opening_confirmed_at: string
          opening_confirmed_by: string
          opening_float: number
          pos_cash_sales: number | null
          system_sales_total: number | null
          system_transaction_count: number | null
          tally_count_variance: number | null
          tally_sales_variance: number | null
          vat_collected: number | null
        }
        Insert: {
          bank_transfer_sales?: number | null
          branch_id: string
          business_date: string
          card_sales?: number | null
          cash_deposits?: number | null
          cash_expenses?: number | null
          cash_refunds?: number | null
          cash_sales?: number | null
          cash_variance?: number | null
          closed_at?: string | null
          closed_by?: string | null
          counted_cash?: number | null
          created_at?: string
          discounts_given?: number | null
          expected_cash?: number | null
          id?: string
          invoice_cash_sales?: number | null
          invoice_cheque_sales?: number | null
          manual_sales_total?: number | null
          manual_transaction_count?: number | null
          mobile_money_sales?: number | null
          notes?: string
          opening_confirmed_at?: string
          opening_confirmed_by?: string
          opening_float: number
          pos_cash_sales?: number | null
          system_sales_total?: number | null
          system_transaction_count?: number | null
          tally_count_variance?: number | null
          tally_sales_variance?: number | null
          vat_collected?: number | null
        }
        Update: {
          bank_transfer_sales?: number | null
          branch_id?: string
          business_date?: string
          card_sales?: number | null
          cash_deposits?: number | null
          cash_expenses?: number | null
          cash_refunds?: number | null
          cash_sales?: number | null
          cash_variance?: number | null
          closed_at?: string | null
          closed_by?: string | null
          counted_cash?: number | null
          created_at?: string
          discounts_given?: number | null
          expected_cash?: number | null
          id?: string
          invoice_cash_sales?: number | null
          invoice_cheque_sales?: number | null
          manual_sales_total?: number | null
          manual_transaction_count?: number | null
          mobile_money_sales?: number | null
          notes?: string
          opening_confirmed_at?: string
          opening_confirmed_by?: string
          opening_float?: number
          pos_cash_sales?: number | null
          system_sales_total?: number | null
          system_transaction_count?: number | null
          tally_count_variance?: number | null
          tally_sales_variance?: number | null
          vat_collected?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "day_closes_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "day_closes_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "day_closes_opening_confirmed_by_fkey"
            columns: ["opening_confirmed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      departments: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          position?: number
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          position?: number
        }
        Relationships: []
      }
      deposit_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      employee_allowances: {
        Row: {
          allowance_type_id: string
          default_amount: number
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
        }
        Insert: {
          allowance_type_id: string
          default_amount: number
          effective_from: string
          effective_to?: string | null
          employee_id: string
          id?: string
        }
        Update: {
          allowance_type_id?: string
          default_amount?: number
          effective_from?: string
          effective_to?: string | null
          employee_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_allowances_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_allowances_allowance_type_id_fkey"
            columns: ["allowance_type_id"]
            isOneToOne: false
            referencedRelation: "allowance_types"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_documents: {
        Row: {
          document_type: string
          employee_id: string
          id: string
          notes: string | null
          storage_path: string
          uploaded_at: string
          uploaded_by: string
        }
        Insert: {
          document_type: string
          employee_id: string
          id?: string
          notes?: string | null
          storage_path: string
          uploaded_at?: string
          uploaded_by?: string
        }
        Update: {
          document_type?: string
          employee_id?: string
          id?: string
          notes?: string | null
          storage_path?: string
          uploaded_at?: string
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_documents_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_generated_documents: {
        Row: {
          acceptance_signature_name: string | null
          accepted_at: string | null
          created_at: string
          created_by: string
          document_kind: string
          employee_id: string
          id: string
          issued_at: string | null
          issued_by: string | null
          merge_data: Json
          status: string
          storage_path: string
          superseded_at: string | null
          version: number
        }
        Insert: {
          acceptance_signature_name?: string | null
          accepted_at?: string | null
          created_at?: string
          created_by?: string
          document_kind: string
          employee_id: string
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          merge_data: Json
          status?: string
          storage_path: string
          superseded_at?: string | null
          version: number
        }
        Update: {
          acceptance_signature_name?: string | null
          accepted_at?: string | null
          created_at?: string
          created_by?: string
          document_kind?: string
          employee_id?: string
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          merge_data?: Json
          status?: string
          storage_path?: string
          superseded_at?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "employee_generated_documents_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_generated_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_generated_documents_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_onboarding_submissions: {
        Row: {
          account_no: string | null
          bank_name: string | null
          contract_accepted: boolean
          date_of_birth: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employee_id: string
          gender: string | null
          id: string
          national_id: string | null
          payment_method: string | null
          personal_email: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          signature_name: string | null
          submitted_at: string
          token_id: string
          uploaded_documents: Json
        }
        Insert: {
          account_no?: string | null
          bank_name?: string | null
          contract_accepted?: boolean
          date_of_birth?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employee_id: string
          gender?: string | null
          id?: string
          national_id?: string | null
          payment_method?: string | null
          personal_email?: string | null
          qualifications?: string[] | null
          rejection_reason?: string | null
          residential_address?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          signature_name?: string | null
          submitted_at?: string
          token_id: string
          uploaded_documents?: Json
        }
        Update: {
          account_no?: string | null
          bank_name?: string | null
          contract_accepted?: boolean
          date_of_birth?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employee_id?: string
          gender?: string | null
          id?: string
          national_id?: string | null
          payment_method?: string | null
          personal_email?: string | null
          qualifications?: string[] | null
          rejection_reason?: string | null
          residential_address?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          signature_name?: string | null
          submitted_at?: string
          token_id?: string
          uploaded_documents?: Json
        }
        Relationships: [
          {
            foreignKeyName: "employee_onboarding_submissions_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_onboarding_submissions_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_onboarding_submissions_token_id_fkey"
            columns: ["token_id"]
            isOneToOne: false
            referencedRelation: "employee_onboarding_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_onboarding_tasks: {
        Row: {
          checklist_item_id: string
          completed: boolean
          completed_at: string | null
          completed_by: string | null
          created_at: string
          employee_id: string
          id: string
          provided_number: string | null
          provided_via: string | null
        }
        Insert: {
          checklist_item_id: string
          completed?: boolean
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          employee_id: string
          id?: string
          provided_number?: string | null
          provided_via?: string | null
        }
        Update: {
          checklist_item_id?: string
          completed?: boolean
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          employee_id?: string
          id?: string
          provided_number?: string | null
          provided_via?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_onboarding_tasks_checklist_item_id_fkey"
            columns: ["checklist_item_id"]
            isOneToOne: false
            referencedRelation: "onboarding_checklist_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_onboarding_tasks_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_onboarding_tasks_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_onboarding_tokens: {
        Row: {
          created_at: string
          created_by: string
          employee_id: string
          expires_at: string
          id: string
          token_hash: string
          used_at: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string
          employee_id: string
          expires_at: string
          id?: string
          token_hash: string
          used_at?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          employee_id?: string
          expires_at?: string
          id?: string
          token_hash?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_onboarding_tokens_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_onboarding_tokens_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_pay_config: {
        Row: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        Insert: {
          account_no?: string | null
          approval_status?: string
          bank?: string | null
          basic_salary: number
          created_at?: string
          effective_from: string
          effective_to?: string | null
          employee_id: string
          id?: string
          payment_method?: string
          pays_paye?: boolean
          pays_ssnit?: boolean
          pays_tier2?: boolean
          proposed_by?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Update: {
          account_no?: string | null
          approval_status?: string
          bank?: string | null
          basic_salary?: number
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          employee_id?: string
          id?: string
          payment_method?: string
          pays_paye?: boolean
          pays_ssnit?: boolean
          pays_tier2?: boolean
          proposed_by?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_pay_config_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_pay_config_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_pay_config_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        Insert: {
          branch_id: string
          church_denomination?: string | null
          contract_end_date?: string | null
          created_at?: string
          date_of_birth?: string | null
          department?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employment_status?: string
          employment_type?: string | null
          gender?: string | null
          id?: string
          name: string
          national_id?: string | null
          onboarding_completed_at?: string | null
          personal_email?: string | null
          phone?: string | null
          position?: string | null
          preferred_name?: string | null
          probation_end_date?: string | null
          proposed_by?: string | null
          qualifications?: string[] | null
          rejection_reason?: string | null
          residential_address?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          school_email?: string | null
          ssnit_number?: string | null
          start_date?: string | null
          tin_number?: string | null
          updated_at?: string
        }
        Update: {
          branch_id?: string
          church_denomination?: string | null
          contract_end_date?: string | null
          created_at?: string
          date_of_birth?: string | null
          department?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employment_status?: string
          employment_type?: string | null
          gender?: string | null
          id?: string
          name?: string
          national_id?: string | null
          onboarding_completed_at?: string | null
          personal_email?: string | null
          phone?: string | null
          position?: string | null
          preferred_name?: string | null
          probation_end_date?: string | null
          proposed_by?: string | null
          qualifications?: string[] | null
          rejection_reason?: string | null
          residential_address?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          school_email?: string | null
          ssnit_number?: string | null
          start_date?: string | null
          tin_number?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employees_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_categories: {
        Row: {
          branch_id: string
          id: string
          name: string
          position: number
        }
        Insert: {
          branch_id: string
          id?: string
          name: string
          position?: number
        }
        Update: {
          branch_id?: string
          id?: string
          name?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "expense_categories_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_category_accounts: {
        Row: {
          account_id: string
          branch_id: string
          category: string
        }
        Insert: {
          account_id: string
          branch_id: string
          category: string
        }
        Update: {
          account_id?: string
          branch_id?: string
          category?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_category_accounts_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_category_accounts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          category: string
          date: string
          description: string
          id: string
          method: string
          receipt_path: string | null
          recorded_at: string
          recorded_by: string
          reference: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          branch_id: string
          category: string
          date: string
          description: string
          id: string
          method: string
          receipt_path?: string | null
          recorded_at?: string
          recorded_by?: string
          reference?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          branch_id?: string
          category?: string
          date?: string
          description?: string
          id?: string
          method?: string
          receipt_path?: string | null
          recorded_at?: string
          recorded_by?: string
          reference?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expenses_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_voided_by_fkey"
            columns: ["voided_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      families: {
        Row: {
          comments: string
          created_at: string
          id: string
          referral_source: string
          referral_source_other: string
        }
        Insert: {
          comments?: string
          created_at?: string
          id?: string
          referral_source?: string
          referral_source_other?: string
        }
        Update: {
          comments?: string
          created_at?: string
          id?: string
          referral_source?: string
          referral_source_other?: string
        }
        Relationships: []
      }
      guardians: {
        Row: {
          address: string
          bulk_email_unsubscribe_token_hash: string | null
          bulk_email_unsubscribed_at: string | null
          email: string
          family_id: string
          first_name: string
          id: string
          phone: string
          relationship: string
          religion: string
          surname: string
          town_city: string
        }
        Insert: {
          address?: string
          bulk_email_unsubscribe_token_hash?: string | null
          bulk_email_unsubscribed_at?: string | null
          email: string
          family_id: string
          first_name?: string
          id?: string
          phone: string
          relationship: string
          religion?: string
          surname?: string
          town_city?: string
        }
        Update: {
          address?: string
          bulk_email_unsubscribe_token_hash?: string | null
          bulk_email_unsubscribed_at?: string | null
          email?: string
          family_id?: string
          first_name?: string
          id?: string
          phone?: string
          relationship?: string
          religion?: string
          surname?: string
          town_city?: string
        }
        Relationships: [
          {
            foreignKeyName: "guardians_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      held_sales: {
        Row: {
          branch_id: string
          created_at: string
          customer_id: string | null
          customer_name: string
          held_by: string
          id: string
          lines: Json
          payments: Json
          sale_discount_mode: string
          sale_discount_value: number
          vat_mode: string
        }
        Insert: {
          branch_id: string
          created_at?: string
          customer_id?: string | null
          customer_name?: string
          held_by?: string
          id?: string
          lines: Json
          payments?: Json
          sale_discount_mode?: string
          sale_discount_value?: number
          vat_mode?: string
        }
        Update: {
          branch_id?: string
          created_at?: string
          customer_id?: string | null
          customer_name?: string
          held_by?: string
          id?: string
          lines?: Json
          payments?: Json
          sale_discount_mode?: string
          sale_discount_value?: number
          vat_mode?: string
        }
        Relationships: [
          {
            foreignKeyName: "held_sales_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "held_sales_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "held_sales_held_by_fkey"
            columns: ["held_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_lines: {
        Row: {
          discount: number
          id: string
          invoice_id: string
          name: string
          position: number
          product_id: string | null
          quantity: number
          unit: string
          unit_price: number
          vat: boolean
        }
        Insert: {
          discount?: number
          id?: string
          invoice_id: string
          name: string
          position?: number
          product_id?: string | null
          quantity: number
          unit: string
          unit_price?: number
          vat?: boolean
        }
        Update: {
          discount?: number
          id?: string
          invoice_id?: string
          name?: string
          position?: number
          product_id?: string | null
          quantity?: number
          unit?: string
          unit_price?: number
          vat?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      invoice_payments: {
        Row: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          id: string
          invoice_id: string
          method: string
          note: string
          paid_at: string
          recorded_by: string
          reference: string
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          branch_id: string
          id?: string
          invoice_id: string
          method: string
          note?: string
          paid_at?: string
          recorded_by?: string
          reference?: string
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          branch_id?: string
          id?: string
          invoice_id?: string
          method?: string
          note?: string
          paid_at?: string
          recorded_by?: string
          reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoice_payments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_payments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_payments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          issued_by: string
          notes: string
          total: number
          updated_at: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
          wht_amount: number
          wht_applied: boolean
          wht_rate: number | null
        }
        Insert: {
          amount_paid?: number
          balance?: number
          branch_id: string
          created_at?: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount?: number
          issued_by?: string
          notes?: string
          total?: number
          updated_at?: string
          vat_rate?: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
          wht_amount?: number
          wht_applied?: boolean
          wht_rate?: number | null
        }
        Update: {
          amount_paid?: number
          balance?: number
          branch_id?: string
          created_at?: string
          customer_id?: string
          customer_name?: string
          date?: string
          due_date?: string
          id?: string
          invoice_discount?: number
          issued_by?: string
          notes?: string
          total?: number
          updated_at?: string
          vat_rate?: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
          wht_amount?: number
          wht_applied?: boolean
          wht_rate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_voided_by_fkey"
            columns: ["voided_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_entries: {
        Row: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        Insert: {
          branch_id: string
          cost_data_incomplete?: boolean
          created_at?: string
          created_by?: string
          description: string
          entry_date: string
          id: string
          reference?: string | null
          reverses_entry_id?: string | null
          source_id?: string | null
          source_table?: string | null
        }
        Update: {
          branch_id?: string
          cost_data_incomplete?: boolean
          created_at?: string
          created_by?: string
          description?: string
          entry_date?: string
          id?: string
          reference?: string | null
          reverses_entry_id?: string | null
          source_id?: string | null
          source_table?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reverses_entry_id_fkey"
            columns: ["reverses_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_entry_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      journal_lines: {
        Row: {
          account_id: string
          created_at: string
          credit: number
          debit: number
          description: string
          entry_id: string
          id: string
          position: number
        }
        Insert: {
          account_id: string
          created_at?: string
          credit?: number
          debit?: number
          description?: string
          entry_id: string
          id?: string
          position?: number
        }
        Update: {
          account_id?: string
          created_at?: string
          credit?: number
          debit?: number
          description?: string
          entry_id?: string
          id?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "journal_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_lines_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      manager_overrides: {
        Row: {
          branch_id: string
          created_at: string
          expires_at: string
          id: string
          manager_id: string
          reason: string
          requested_by: string
          used_at: string | null
        }
        Insert: {
          branch_id: string
          created_at?: string
          expires_at?: string
          id?: string
          manager_id?: string
          reason?: string
          requested_by: string
          used_at?: string | null
        }
        Update: {
          branch_id?: string
          created_at?: string
          expires_at?: string
          id?: string
          manager_id?: string
          reason?: string
          requested_by?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "manager_overrides_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "manager_overrides_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "manager_overrides_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          branch_id: string
          created_at: string
          entity_id: string | null
          entity_table: string | null
          id: string
          link: string | null
          read_at: string | null
          recipient_id: string
          title: string
          type: string
        }
        Insert: {
          body?: string
          branch_id: string
          created_at?: string
          entity_id?: string | null
          entity_table?: string | null
          id?: string
          link?: string | null
          read_at?: string | null
          recipient_id: string
          title: string
          type: string
        }
        Update: {
          body?: string
          branch_id?: string
          created_at?: string
          entity_id?: string | null
          entity_table?: string | null
          id?: string
          link?: string | null
          read_at?: string | null
          recipient_id?: string
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      onboarding_checklist_items: {
        Row: {
          accepts_number_in_lieu: boolean
          created_at: string
          derivation_key: string | null
          id: string
          is_active: boolean
          is_derived: boolean
          name: string
          position: number
          requires_document: boolean
        }
        Insert: {
          accepts_number_in_lieu?: boolean
          created_at?: string
          derivation_key?: string | null
          id?: string
          is_active?: boolean
          is_derived?: boolean
          name: string
          position?: number
          requires_document?: boolean
        }
        Update: {
          accepts_number_in_lieu?: boolean
          created_at?: string
          derivation_key?: string | null
          id?: string
          is_active?: boolean
          is_derived?: boolean
          name?: string
          position?: number
          requires_document?: boolean
        }
        Relationships: []
      }
      overtime_tax_rates: {
        Row: {
          created_at: string
          effective_from: string
          id: string
          overtime_cap_pct_of_basic: number
          qualifying_annual_basic_max: number
          rate_above_cap_pct: number
          rate_within_cap_pct: number
        }
        Insert: {
          created_at?: string
          effective_from: string
          id?: string
          overtime_cap_pct_of_basic: number
          qualifying_annual_basic_max: number
          rate_above_cap_pct: number
          rate_within_cap_pct: number
        }
        Update: {
          created_at?: string
          effective_from?: string
          id?: string
          overtime_cap_pct_of_basic?: number
          qualifying_annual_basic_max?: number
          rate_above_cap_pct?: number
          rate_within_cap_pct?: number
        }
        Relationships: []
      }
      paye_bands: {
        Row: {
          band_order: number
          effective_from: string
          id: string
          lower_bound: number
          rate: number
          upper_bound: number | null
        }
        Insert: {
          band_order: number
          effective_from: string
          id?: string
          lower_bound: number
          rate: number
          upper_bound?: number | null
        }
        Update: {
          band_order?: number
          effective_from?: string
          id?: string
          lower_bound?: number
          rate?: number
          upper_bound?: number | null
        }
        Relationships: []
      }
      payment_providers: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          kind: string
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          kind?: string
          name: string
          position?: number
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          kind?: string
          name?: string
          position?: number
        }
        Relationships: []
      }
      payroll_run_exclusions: {
        Row: {
          employee_id: string
          excluded_at: string
          excluded_by: string | null
          id: string
          payroll_run_id: string
          reason: string | null
        }
        Insert: {
          employee_id: string
          excluded_at?: string
          excluded_by?: string | null
          id?: string
          payroll_run_id: string
          reason?: string | null
        }
        Update: {
          employee_id?: string
          excluded_at?: string
          excluded_by?: string | null
          id?: string
          payroll_run_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payroll_run_exclusions_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_run_exclusions_excluded_by_fkey"
            columns: ["excluded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_run_exclusions_payroll_run_id_fkey"
            columns: ["payroll_run_id"]
            isOneToOne: false
            referencedRelation: "payroll_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_runs: {
        Row: {
          branch_id: string
          created_at: string
          created_by: string | null
          id: string
          month: number
          posted_at: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          year: number
        }
        Insert: {
          branch_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          month: number
          posted_at?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          year: number
        }
        Update: {
          branch_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          month?: number
          posted_at?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "payroll_runs_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_runs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_runs_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_runs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      payslip_allowances: {
        Row: {
          allowance_type_id: string
          amount: number
          id: string
          note: string | null
          payslip_id: string
        }
        Insert: {
          allowance_type_id: string
          amount: number
          id?: string
          note?: string | null
          payslip_id: string
        }
        Update: {
          allowance_type_id?: string
          amount?: number
          id?: string
          note?: string | null
          payslip_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payslip_allowances_allowance_type_id_fkey"
            columns: ["allowance_type_id"]
            isOneToOne: false
            referencedRelation: "allowance_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payslip_allowances_payslip_id_fkey"
            columns: ["payslip_id"]
            isOneToOne: false
            referencedRelation: "payslips"
            referencedColumns: ["id"]
          },
        ]
      }
      payslips: {
        Row: {
          basic_salary: number
          employee_id: string
          employee_pay_config_id: string
          fines: number
          generated_at: string
          gross_salary: number
          id: string
          iou: number
          net_pay: number
          overtime_concession: boolean
          overtime_hours: number
          overtime_pay: number
          overtime_rate: number
          overtime_tax: number
          payroll_run_id: string
          pdf_path: string | null
          ssnit: number
          ssnit_employer: number
          tax: number
          taxable_income: number
          tier2: number
          total_allowances: number
          total_deductions: number
          total_earning: number
        }
        Insert: {
          basic_salary: number
          employee_id: string
          employee_pay_config_id: string
          fines?: number
          generated_at?: string
          gross_salary: number
          id?: string
          iou?: number
          net_pay: number
          overtime_concession?: boolean
          overtime_hours?: number
          overtime_pay?: number
          overtime_rate?: number
          overtime_tax?: number
          payroll_run_id: string
          pdf_path?: string | null
          ssnit?: number
          ssnit_employer?: number
          tax?: number
          taxable_income: number
          tier2?: number
          total_allowances?: number
          total_deductions: number
          total_earning: number
        }
        Update: {
          basic_salary?: number
          employee_id?: string
          employee_pay_config_id?: string
          fines?: number
          generated_at?: string
          gross_salary?: number
          id?: string
          iou?: number
          net_pay?: number
          overtime_concession?: boolean
          overtime_hours?: number
          overtime_pay?: number
          overtime_rate?: number
          overtime_tax?: number
          payroll_run_id?: string
          pdf_path?: string | null
          ssnit?: number
          ssnit_employer?: number
          tax?: number
          taxable_income?: number
          tier2?: number
          total_allowances?: number
          total_deductions?: number
          total_earning?: number
        }
        Relationships: [
          {
            foreignKeyName: "payslips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payslips_employee_pay_config_id_fkey"
            columns: ["employee_pay_config_id"]
            isOneToOne: false
            referencedRelation: "employee_pay_config"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payslips_payroll_run_id_fkey"
            columns: ["payroll_run_id"]
            isOneToOne: false
            referencedRelation: "payroll_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      positions: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          is_teaching: boolean
          name: string
          position: number
          staff_class: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_teaching?: boolean
          name: string
          position?: number
          staff_class?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_teaching?: boolean
          name?: string
          position?: number
          staff_class?: string | null
        }
        Relationships: []
      }
      pro_forma_invoice_lines: {
        Row: {
          discount: number
          id: string
          name: string
          position: number
          pro_forma_invoice_id: string
          product_id: string | null
          quantity: number
          unit: string
          unit_price: number
          vat: boolean
        }
        Insert: {
          discount?: number
          id?: string
          name: string
          position?: number
          pro_forma_invoice_id: string
          product_id?: string | null
          quantity: number
          unit: string
          unit_price?: number
          vat?: boolean
        }
        Update: {
          discount?: number
          id?: string
          name?: string
          position?: number
          pro_forma_invoice_id?: string
          product_id?: string | null
          quantity?: number
          unit?: string
          unit_price?: number
          vat?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "pro_forma_invoice_lines_pro_forma_invoice_id_fkey"
            columns: ["pro_forma_invoice_id"]
            isOneToOne: false
            referencedRelation: "pro_forma_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pro_forma_invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      pro_forma_invoice_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      pro_forma_invoices: {
        Row: {
          branch_id: string
          converted_invoice_id: string | null
          created_at: string
          created_by: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          notes: string
          status: string
          total: number
          vat_rate: number
        }
        Insert: {
          branch_id: string
          converted_invoice_id?: string | null
          created_at?: string
          created_by?: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount?: number
          notes?: string
          status?: string
          total?: number
          vat_rate?: number
        }
        Update: {
          branch_id?: string
          converted_invoice_id?: string | null
          created_at?: string
          created_by?: string
          customer_id?: string
          customer_name?: string
          date?: string
          due_date?: string
          id?: string
          invoice_discount?: number
          notes?: string
          status?: string
          total?: number
          vat_rate?: number
        }
        Relationships: [
          {
            foreignKeyName: "pro_forma_invoices_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pro_forma_invoices_converted_invoice_id_fkey"
            columns: ["converted_invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pro_forma_invoices_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pro_forma_invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          branch_id: string
          category: string
          cost: number | null
          created_at: string
          description: string
          id: string
          low_stock_threshold: number | null
          name: string
          price: number | null
          size: string
          sku: string
          stock: number
          unit: string
          updated_at: string
        }
        Insert: {
          branch_id: string
          category: string
          cost?: number | null
          created_at?: string
          description?: string
          id?: string
          low_stock_threshold?: number | null
          name: string
          price?: number | null
          size?: string
          sku: string
          stock?: number
          unit: string
          updated_at?: string
        }
        Update: {
          branch_id?: string
          category?: string
          cost?: number | null
          created_at?: string
          description?: string
          id?: string
          low_stock_threshold?: number | null
          name?: string
          price?: number | null
          size?: string
          sku?: string
          stock?: number
          unit?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
        ]
      }
      public_rate_limits: {
        Row: {
          bucket: string
          count: number
          key_hash: string
          window_start: string
        }
        Insert: {
          bucket: string
          count?: number
          key_hash: string
          window_start: string
        }
        Update: {
          bucket?: string
          count?: number
          key_hash?: string
          window_start?: string
        }
        Relationships: []
      }
      purchase_order_lines: {
        Row: {
          id: string
          name: string
          position: number
          product_id: string
          purchase_order_id: string
          quantity_ordered: number
          quantity_received: number
          unit: string
          unit_cost: number
        }
        Insert: {
          id?: string
          name: string
          position?: number
          product_id: string
          purchase_order_id: string
          quantity_ordered: number
          quantity_received?: number
          unit: string
          unit_cost: number
        }
        Update: {
          id?: string
          name?: string
          position?: number
          product_id?: string
          purchase_order_id?: string
          quantity_ordered?: number
          quantity_received?: number
          unit?: string
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_order_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      purchase_order_receipt_lines: {
        Row: {
          id: string
          product_id: string
          purchase_order_line_id: string
          quantity: number
          receipt_id: string
          unit_cost: number
        }
        Insert: {
          id?: string
          product_id: string
          purchase_order_line_id: string
          quantity: number
          receipt_id: string
          unit_cost: number
        }
        Update: {
          id?: string
          product_id?: string
          purchase_order_line_id?: string
          quantity?: number
          receipt_id?: string
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_receipt_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_receipt_lines_purchase_order_line_id_fkey"
            columns: ["purchase_order_line_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_receipt_lines_receipt_id_fkey"
            columns: ["receipt_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_receipts"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_order_receipts: {
        Row: {
          branch_id: string
          created_at: string
          id: string
          notes: string
          purchase_order_id: string
          received_by: string
          received_date: string
          total_value: number
        }
        Insert: {
          branch_id: string
          created_at?: string
          id?: string
          notes?: string
          purchase_order_id: string
          received_by?: string
          received_date?: string
          total_value?: number
        }
        Update: {
          branch_id?: string
          created_at?: string
          id?: string
          notes?: string
          purchase_order_id?: string
          received_by?: string
          received_date?: string
          total_value?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_receipts_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_receipts_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_receipts_received_by_fkey"
            columns: ["received_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          created_by: string
          expected_date: string | null
          id: string
          notes: string
          order_date: string
          received_value: number
          status: string
          supplier_id: string
          supplier_name: string
          total: number
          updated_at: string
        }
        Insert: {
          amount_paid?: number
          balance?: number
          branch_id: string
          created_at?: string
          created_by?: string
          expected_date?: string | null
          id: string
          notes?: string
          order_date?: string
          received_value?: number
          status?: string
          supplier_id: string
          supplier_name: string
          total?: number
          updated_at?: string
        }
        Update: {
          amount_paid?: number
          balance?: number
          branch_id?: string
          created_at?: string
          created_by?: string
          expected_date?: string | null
          id?: string
          notes?: string
          order_date?: string
          received_value?: number
          status?: string
          supplier_id?: string
          supplier_name?: string
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      qualifications: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          position?: number
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          position?: number
        }
        Relationships: []
      }
      sale_lines: {
        Row: {
          category: string
          discount_mode: string
          discount_value: number
          id: string
          name: string
          position: number
          product_id: string
          quantity: number
          sale_id: string
          unit: string
          unit_price: number
          vat: boolean
        }
        Insert: {
          category: string
          discount_mode?: string
          discount_value?: number
          id?: string
          name: string
          position?: number
          product_id: string
          quantity: number
          sale_id: string
          unit: string
          unit_price: number
          vat?: boolean
        }
        Update: {
          category?: string
          discount_mode?: string
          discount_value?: number
          id?: string
          name?: string
          position?: number
          product_id?: string
          quantity?: number
          sale_id?: string
          unit?: string
          unit_price?: number
          vat?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "sale_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_lines_sale_id_fkey"
            columns: ["sale_id"]
            isOneToOne: false
            referencedRelation: "sales"
            referencedColumns: ["id"]
          },
        ]
      }
      sale_number_counters: {
        Row: {
          last_number: number
          year_month: string
        }
        Insert: {
          last_number?: number
          year_month: string
        }
        Update: {
          last_number?: number
          year_month?: string
        }
        Relationships: []
      }
      sale_payments: {
        Row: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          id: string
          method: string
          paid_at: string
          reference: string
          sale_id: string
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          branch_id: string
          id?: string
          method: string
          paid_at?: string
          reference?: string
          sale_id: string
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          branch_id?: string
          id?: string
          method?: string
          paid_at?: string
          reference?: string
          sale_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sale_payments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_payments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_payments_sale_id_fkey"
            columns: ["sale_id"]
            isOneToOne: false
            referencedRelation: "sales"
            referencedColumns: ["id"]
          },
        ]
      }
      sale_returns: {
        Row: {
          approval_state: string
          bank_account_id: string | null
          branch_id: string
          customer_id: string | null
          difference: number
          id: string
          payment_method: string | null
          processed_by: string
          reason: string
          replacement_name: string | null
          replacement_product_id: string | null
          replacement_quantity: number | null
          replacement_unit: string | null
          replacement_unit_price: number | null
          resolution: string
          return_group_id: string | null
          returned_at: string
          returned_name: string
          returned_product_id: string
          returned_quantity: number
          returned_sale_line_id: string
          returned_unit: string
          returned_unit_price: number
          sale_id: string
        }
        Insert: {
          approval_state: string
          bank_account_id?: string | null
          branch_id: string
          customer_id?: string | null
          difference: number
          id?: string
          payment_method?: string | null
          processed_by?: string
          reason?: string
          replacement_name?: string | null
          replacement_product_id?: string | null
          replacement_quantity?: number | null
          replacement_unit?: string | null
          replacement_unit_price?: number | null
          resolution: string
          return_group_id?: string | null
          returned_at?: string
          returned_name: string
          returned_product_id: string
          returned_quantity: number
          returned_sale_line_id: string
          returned_unit: string
          returned_unit_price: number
          sale_id: string
        }
        Update: {
          approval_state?: string
          bank_account_id?: string | null
          branch_id?: string
          customer_id?: string | null
          difference?: number
          id?: string
          payment_method?: string | null
          processed_by?: string
          reason?: string
          replacement_name?: string | null
          replacement_product_id?: string | null
          replacement_quantity?: number | null
          replacement_unit?: string | null
          replacement_unit_price?: number | null
          resolution?: string
          return_group_id?: string | null
          returned_at?: string
          returned_name?: string
          returned_product_id?: string
          returned_quantity?: number
          returned_sale_line_id?: string
          returned_unit?: string
          returned_unit_price?: number
          sale_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sale_returns_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_processed_by_fkey"
            columns: ["processed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_replacement_product_id_fkey"
            columns: ["replacement_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_returned_product_id_fkey"
            columns: ["returned_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_returned_sale_line_id_fkey"
            columns: ["returned_sale_line_id"]
            isOneToOne: false
            referencedRelation: "sale_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sale_returns_sale_id_fkey"
            columns: ["sale_id"]
            isOneToOne: false
            referencedRelation: "sales"
            referencedColumns: ["id"]
          },
        ]
      }
      sales: {
        Row: {
          branch_id: string
          cashier: string
          created_at: string
          customer_id: string | null
          customer_name: string
          id: string
          notes: string
          override_authorized_by: string | null
          sale_discount_mode: string
          sale_discount_value: number
          sold_at: string
          total: number
          vat_mode: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          branch_id: string
          cashier?: string
          created_at?: string
          customer_id?: string | null
          customer_name: string
          id: string
          notes?: string
          override_authorized_by?: string | null
          sale_discount_mode?: string
          sale_discount_value?: number
          sold_at?: string
          total: number
          vat_mode?: string
          vat_rate: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          branch_id?: string
          cashier?: string
          created_at?: string
          customer_id?: string | null
          customer_name?: string
          id?: string
          notes?: string
          override_authorized_by?: string | null
          sale_discount_mode?: string
          sale_discount_value?: number
          sold_at?: string
          total?: number
          vat_mode?: string
          vat_rate?: number
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_cashier_fkey"
            columns: ["cashier"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_override_authorized_by_fkey"
            columns: ["override_authorized_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_voided_by_fkey"
            columns: ["voided_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      staff: {
        Row: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
          employee_id: string | null
          id: string
          name: string
          protected: boolean
          role: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          branch_id: string
          created_at?: string
          email: string
          employee_id?: string | null
          id: string
          name: string
          protected?: boolean
          role: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          branch_id?: string
          created_at?: string
          email?: string
          employee_id?: string | null
          id?: string
          name?: string
          protected?: boolean
          role?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_admissions_capabilities: {
        Row: {
          all_grades: boolean
          can_decide: boolean
          can_view_health: boolean
          grade_bands: string[]
          granted_by: string | null
          staff_id: string
          updated_at: string
        }
        Insert: {
          all_grades?: boolean
          can_decide?: boolean
          can_view_health?: boolean
          grade_bands?: string[]
          granted_by?: string | null
          staff_id: string
          updated_at?: string
        }
        Update: {
          all_grades?: boolean
          can_decide?: boolean
          can_view_health?: boolean
          grade_bands?: string[]
          granted_by?: string | null
          staff_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_admissions_capabilities_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_admissions_capabilities_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: true
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_advance_change_requests: {
        Row: {
          advance_id: string
          id: string
          kind: string
          new_instalment: number | null
          proposed_at: string
          proposed_by: string | null
          reason: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        Insert: {
          advance_id: string
          id?: string
          kind: string
          new_instalment?: number | null
          proposed_at?: string
          proposed_by?: string | null
          reason?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Update: {
          advance_id?: string
          id?: string
          kind?: string
          new_instalment?: number | null
          proposed_at?: string
          proposed_by?: string | null
          reason?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_advance_change_requests_advance_id_fkey"
            columns: ["advance_id"]
            isOneToOne: false
            referencedRelation: "staff_advances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advance_change_requests_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advance_change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_advance_repayments: {
        Row: {
          advance_id: string
          amount: number
          created_at: string
          id: string
          instalment_due: number
          payslip_id: string
        }
        Insert: {
          advance_id: string
          amount: number
          created_at?: string
          id?: string
          instalment_due: number
          payslip_id: string
        }
        Update: {
          advance_id?: string
          amount?: number
          created_at?: string
          id?: string
          instalment_due?: number
          payslip_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_advance_repayments_advance_id_fkey"
            columns: ["advance_id"]
            isOneToOne: false
            referencedRelation: "staff_advances"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advance_repayments_payslip_id_fkey"
            columns: ["payslip_id"]
            isOneToOne: false
            referencedRelation: "payslips"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_advances: {
        Row: {
          amount: number
          bank_account_id: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string | null
          proposed_at: string
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id?: string
          instalment: number
          note?: string | null
          proposed_at?: string
          proposed_by?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          disbursed_on?: string
          disbursement_method?: string
          employee_id?: string
          first_repayment_month?: string
          id?: string
          instalment?: number
          note?: string | null
          proposed_at?: string
          proposed_by?: string | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_advances_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advances_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advances_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_advances_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_number_counters: {
        Row: {
          next_roll: number
          year: number
        }
        Insert: {
          next_roll?: number
          year: number
        }
        Update: {
          next_roll?: number
          year?: number
        }
        Relationships: []
      }
      staff_numbers: {
        Row: {
          class_code: string
          employee_id: string
          issued_at: string
          issued_by: string | null
          number: string
          replaced_by: string | null
          retire_reason: string | null
          retired_at: string | null
          retired_by: string | null
          roll: number
          year: number
        }
        Insert: {
          class_code: string
          employee_id: string
          issued_at?: string
          issued_by?: string | null
          number: string
          replaced_by?: string | null
          retire_reason?: string | null
          retired_at?: string | null
          retired_by?: string | null
          roll: number
          year: number
        }
        Update: {
          class_code?: string
          employee_id?: string
          issued_at?: string
          issued_by?: string | null
          number?: string
          replaced_by?: string | null
          retire_reason?: string | null
          retired_at?: string | null
          retired_by?: string | null
          roll?: number
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "staff_numbers_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_numbers_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_numbers_replaced_by_fkey"
            columns: ["replaced_by"]
            isOneToOne: false
            referencedRelation: "staff_numbers"
            referencedColumns: ["number"]
          },
          {
            foreignKeyName: "staff_numbers_retired_by_fkey"
            columns: ["retired_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      statutory_rates: {
        Row: {
          created_at: string
          effective_from: string
          id: string
          ssnit_employee_pct: number
          ssnit_employer_pct: number
          tier2_employee_pct: number
          tier2_employer_pct: number
        }
        Insert: {
          created_at?: string
          effective_from: string
          id?: string
          ssnit_employee_pct: number
          ssnit_employer_pct: number
          tier2_employee_pct: number
          tier2_employer_pct?: number
        }
        Update: {
          created_at?: string
          effective_from?: string
          id?: string
          ssnit_employee_pct?: number
          ssnit_employer_pct?: number
          tier2_employee_pct?: number
          tier2_employer_pct?: number
        }
        Relationships: []
      }
      stock_movements: {
        Row: {
          balance_after: number
          branch_id: string
          change: number
          id: string
          movement_type: string
          occurred_at: string
          performed_by: string
          product_id: string
          reason: string
        }
        Insert: {
          balance_after: number
          branch_id: string
          change: number
          id?: string
          movement_type: string
          occurred_at?: string
          performed_by?: string
          product_id: string
          reason?: string
        }
        Update: {
          balance_after?: number
          branch_id?: string
          change?: number
          id?: string
          movement_type?: string
          occurred_at?: string
          performed_by?: string
          product_id?: string
          reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_movements_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_performed_by_fkey"
            columns: ["performed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      students: {
        Row: {
          address: string
          country: string
          current_grade: string
          current_grade_id: string | null
          current_school: string
          date_of_birth: string | null
          family_id: string
          full_name: string
          gender: string
          id: string
          nationality: string
          postal_code: string
          previous_school_location: string
          prior_schooling: string | null
          student_id: string | null
          town_city: string
        }
        Insert: {
          address?: string
          country?: string
          current_grade?: string
          current_grade_id?: string | null
          current_school?: string
          date_of_birth?: string | null
          family_id: string
          full_name: string
          gender?: string
          id?: string
          nationality?: string
          postal_code?: string
          previous_school_location?: string
          prior_schooling?: string | null
          student_id?: string | null
          town_city?: string
        }
        Update: {
          address?: string
          country?: string
          current_grade?: string
          current_grade_id?: string | null
          current_school?: string
          date_of_birth?: string | null
          family_id?: string
          full_name?: string
          gender?: string
          id?: string
          nationality?: string
          postal_code?: string
          previous_school_location?: string
          prior_schooling?: string | null
          student_id?: string | null
          town_city?: string
        }
        Relationships: [
          {
            foreignKeyName: "students_current_grade_id_fkey"
            columns: ["current_grade_id"]
            isOneToOne: false
            referencedRelation: "admissions_grades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "students_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_payments: {
        Row: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          id: string
          method: string
          note: string
          paid_at: string
          purchase_order_id: string
          recorded_by: string
          reference: string
        }
        Insert: {
          amount: number
          bank_account_id?: string | null
          branch_id: string
          id?: string
          method: string
          note?: string
          paid_at?: string
          purchase_order_id: string
          recorded_by?: string
          reference?: string
        }
        Update: {
          amount?: number
          bank_account_id?: string | null
          branch_id?: string
          id?: string
          method?: string
          note?: string
          paid_at?: string
          purchase_order_id?: string
          recorded_by?: string
          reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "supplier_payments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            isOneToOne: false
            referencedRelation: "bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_payments_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_payments_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_payments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      suppliers: {
        Row: {
          address: string
          balance: number
          branch_id: string
          contact_name: string
          created_at: string
          created_by: string
          email: string
          id: string
          is_active: boolean
          lifetime_total: number
          name: string
          phone: string
          updated_at: string
        }
        Insert: {
          address?: string
          balance?: number
          branch_id: string
          contact_name?: string
          created_at?: string
          created_by?: string
          email?: string
          id?: string
          is_active?: boolean
          lifetime_total?: number
          name: string
          phone?: string
          updated_at?: string
        }
        Update: {
          address?: string
          balance?: number
          branch_id?: string
          contact_name?: string
          created_at?: string
          created_by?: string
          email?: string
          id?: string
          is_active?: boolean
          lifetime_total?: number
          name?: string
          phone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "suppliers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      admissions_application_list: {
        Row: {
          academic_year: string | null
          application_reference: string | null
          branch_id: string | null
          branch_name: string | null
          created_at: string | null
          grade_band: string | null
          grade_name: string | null
          id: string | null
          inquiry_reference: string | null
          month_of_enrollment: string | null
          stage: string | null
          student_full_name: string | null
          student_id: string | null
          updated_at: string | null
          year_group_applied_for: string | null
        }
        Relationships: [
          {
            foreignKeyName: "applications_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "applications_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      application_offer_status: {
        Row: {
          application_id: string | null
          effective_response: string | null
          expires_at: string | null
          id: string | null
          responded_at: string | null
          response: string | null
          sent_at: string | null
        }
        Insert: {
          application_id?: string | null
          effective_response?: never
          expires_at?: string | null
          id?: string | null
          responded_at?: string | null
          response?: string | null
          sent_at?: string | null
        }
        Update: {
          application_id?: string | null
          effective_response?: never
          expires_at?: string | null
          id?: string | null
          responded_at?: string | null
          response?: string | null
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "application_offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "admissions_application_list"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "application_offers_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "applications"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      _admissions_capability_holder_problem: {
        Args: {
          p_all_grades: boolean
          p_can_decide: boolean
          p_grade_bands: string[]
          p_role: string
        }
        Returns: string
      }
      _admissions_capacity_warning: {
        Args: { p_application_id: string; p_reveal_figures: boolean }
        Returns: string
      }
      _admissions_email_max_age: { Args: never; Returns: string }
      _admissions_email_params_ok: {
        Args: { p_kind: string; p_params: Json }
        Returns: boolean
      }
      _admissions_email_retry_delay: {
        Args: { p_attempts: number }
        Returns: string
      }
      _admissions_grade_code: { Args: { p_grade: string }; Returns: string }
      _admissions_grade_id: { Args: { p_grade: string }; Returns: string }
      _admissions_mask_email: { Args: { p_email: string }; Returns: string }
      _admissions_reference_year: { Args: { p_at?: string }; Returns: number }
      _admissions_seed_public_campus_labels: { Args: never; Returns: number }
      _admissions_sequence_text: { Args: { p_seq: number }; Returns: string }
      _admissions_worker_kick: { Args: { p_job: string }; Returns: boolean }
      _application_kind_for_extension: {
        Args: { p_extension: string }
        Returns: string
      }
      _application_required_document_types: {
        Args: { p_grade_id: string }
        Returns: string[]
      }
      _application_upload_capacity_check: { Args: never; Returns: undefined }
      _employee_import_check: { Args: { p_rows: Json }; Returns: Json }
      _employee_import_date: {
        Args: { p_text: string }
        Returns: Record<string, unknown>
      }
      _employee_import_money: {
        Args: { p_text: string }
        Returns: Record<string, unknown>
      }
      _employee_import_yes_no: { Args: { p_text: string }; Returns: boolean }
      _enqueue_admissions_emails: {
        Args: {
          p_application_id: string
          p_event: string
          p_family_id: string
          p_typed_emails: string[]
        }
        Returns: undefined
      }
      _issue_staff_number: {
        Args: { p_employee_id: string; p_year: number }
        Returns: string
      }
      _next_admissions_reference: {
        Args: { p_prefix: string; p_year: number }
        Returns: string
      }
      _next_admissions_sequence: { Args: { p_key: string }; Returns: number }
      _next_admissions_student_id: {
        Args: { p_code: string; p_year: number }
        Returns: string
      }
      _offer_effective_response: {
        Args: { p_expires_at: string; p_response: string }
        Returns: string
      }
      _payroll_run_unaccounted: {
        Args: { p_run_id: string }
        Returns: {
          employee_id: string
          name: string
        }[]
      }
      _post_journal_entry_rows: {
        Args: {
          p_branch_id: string
          p_cost_data_incomplete?: boolean
          p_date: string
          p_description: string
          p_lines: Json
          p_reference: string
          p_source_id: string
          p_source_table: string
        }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _provision_bank_gl_account: {
        Args: { p_bank_name: string; p_created_by?: string }
        Returns: string
      }
      _public_bool: {
        Args: { p_field: string; p_key: string; p_label: string; p_obj: Json }
        Returns: boolean
      }
      _public_invalid: {
        Args: { p_field: string; p_message: string }
        Returns: undefined
      }
      _public_only_keys: {
        Args: {
          p_allowed: string[]
          p_field: string
          p_obj: Json
          p_what: string
        }
        Returns: undefined
      }
      _public_phone_ok: { Args: { p_phone: string }; Returns: boolean }
      _public_rate_limit_hit: {
        Args: { p_bucket: string; p_key_hash: string }
        Returns: boolean
      }
      _public_rate_limit_rule: {
        Args: { p_bucket: string }
        Returns: Record<string, unknown>
      }
      _public_text: {
        Args: {
          p_field: string
          p_key: string
          p_label: string
          p_max: number
          p_obj: Json
          p_required: boolean
        }
        Returns: string
      }
      _require_admissions_decider: {
        Args: never
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
          employee_id: string | null
          id: string
          name: string
          protected: boolean
          role: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "staff"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _require_admissions_writer: {
        Args: never
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
          employee_id: string | null
          id: string
          name: string
          protected: boolean
          role: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "staff"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _require_admissions_year_manager: {
        Args: never
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
          employee_id: string | null
          id: string
          name: string
          protected: boolean
          role: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "staff"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _require_public_service_caller: { Args: never; Returns: undefined }
      _settle_offer_expiry: {
        Args: { p_application_id: string }
        Returns: boolean
      }
      _staff_advance_change_problem: {
        Args: {
          p_advance: Database["public"]["Tables"]["staff_advances"]["Row"]
          p_kind: string
          p_new_instalment: number
        }
        Returns: string
      }
      _staff_class_for_employee: {
        Args: { p_employee_id: string }
        Returns: string
      }
      _take_staff_roll: { Args: { p_year: number }; Returns: number }
      account_id_by_code: { Args: { p_code: string }; Returns: string }
      add_admissions_academic_year: {
        Args: { p_label: string }
        Returns: {
          created_at: string
          is_active: boolean
          label: string
          position: number
        }
        SetofOptions: {
          from: "*"
          to: "admissions_academic_years"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      add_application_note: {
        Args: { p_application_id: string; p_content: string }
        Returns: {
          application_id: string
          author_id: string | null
          content: string
          created_at: string
          edited_at: string | null
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "application_notes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      adjust_product_stock: {
        Args: { p_new_stock: number; p_product_id: string; p_reason: string }
        Returns: {
          balance_after: number
          branch_id: string
          change: number
          id: string
          movement_type: string
          occurred_at: string
          performed_by: string
          product_id: string
          reason: string
        }
        SetofOptions: {
          from: "*"
          to: "stock_movements"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admissions_application_visible: {
        Args: { p_application_id: string }
        Returns: boolean
      }
      admissions_family_visible: {
        Args: { p_family_id: string }
        Returns: boolean
      }
      admissions_grade_band: { Args: { p_grade: string }; Returns: string }
      admissions_grade_name: { Args: { p_grade: string }; Returns: string }
      admissions_grade_visible: { Args: { p_grade: string }; Returns: boolean }
      admissions_student_visible: {
        Args: { p_student_id: string }
        Returns: boolean
      }
      admissions_worker_secret: { Args: never; Returns: string }
      approve_employee: {
        Args: {
          p_account_no?: string
          p_bank?: string
          p_basic_salary?: number
          p_employee_id: string
          p_payment_method?: string
        }
        Returns: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_onboarding_submission: {
        Args: { p_submission_id: string }
        Returns: undefined
      }
      approve_pay_config: {
        Args: {
          p_account_no?: string
          p_bank?: string
          p_basic_salary?: number
          p_config_id: string
          p_payment_method?: string
        }
        Returns: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_pay_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_staff_advance: {
        Args: { p_advance_id: string }
        Returns: {
          amount: number
          bank_account_id: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string | null
          proposed_at: string
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_staff_advance_change: {
        Args: { p_request_id: string }
        Returns: {
          advance_id: string
          id: string
          kind: string
          new_instalment: number | null
          proposed_at: string
          proposed_by: string | null
          reason: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advance_change_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      authorize_manager_override: {
        Args: { p_reason?: string; p_requested_by: string }
        Returns: {
          branch_id: string
          created_at: string
          expires_at: string
          id: string
          manager_id: string
          reason: string
          requested_by: string
          used_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "manager_overrides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      can_read_store: { Args: never; Returns: boolean }
      can_write: { Args: never; Returns: boolean }
      cancel_bank_reconciliation: {
        Args: { p_reconciliation_id: string }
        Returns: undefined
      }
      cancel_customer_deposit: {
        Args: { p_deposit_id: string; p_fee: number; p_note?: string }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          cancellation_fee: number | null
          cancellation_note: string | null
          cancellation_refund: number | null
          cancelled_at: string | null
          cancelled_by: string | null
          customer_id: string
          customer_name: string
          description: string
          fulfilled_at: string | null
          fulfilled_invoice_id: string | null
          fulfilled_sale_id: string | null
          id: string
          method: string
          status: string
          taken_at: string
          taken_by: string
        }
        SetofOptions: {
          from: "*"
          to: "customer_deposits"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancel_purchase_order: {
        Args: { p_purchase_order_id: string }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          created_by: string
          expected_date: string | null
          id: string
          notes: string
          order_date: string
          received_value: number
          status: string
          supplier_id: string
          supplier_name: string
          total: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "purchase_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      change_decision: {
        Args: {
          p_application_id: string
          p_decision_type: string
          p_notes: string
        }
        Returns: Json
      }
      check_public_rate_limit: {
        Args: { p_bucket: string; p_key_hash?: string }
        Returns: boolean
      }
      claim_admissions_emails: {
        Args: { p_daily_ceiling: number; p_limit: number }
        Returns: {
          attempts: number
          claim_token: string
          id: string
          kind: string
          params: Json
          recipient_email: string
        }[]
      }
      claim_expired_application_uploads: {
        Args: { p_limit: number }
        Returns: {
          reservation_id: string
          storage_path: string
        }[]
      }
      clear_statement_line: {
        Args: { p_line_id: string; p_note?: string }
        Returns: {
          amount: number
          bank_account_id: string
          clear_note: string
          created_at: string
          date: string
          description: string
          id: string
          imported_by: string
          matched_at: string | null
          matched_by: string | null
          matched_journal_line_id: string | null
          reconciliation_id: string | null
          reference: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_statement_lines"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      close_day: {
        Args: {
          p_branch_id: string
          p_counted_cash: number
          p_manual_sales_total: number
          p_manual_transaction_count: number
          p_notes?: string
        }
        Returns: {
          bank_transfer_sales: number | null
          branch_id: string
          business_date: string
          card_sales: number | null
          cash_deposits: number | null
          cash_expenses: number | null
          cash_refunds: number | null
          cash_sales: number | null
          cash_variance: number | null
          closed_at: string | null
          closed_by: string | null
          counted_cash: number | null
          created_at: string
          discounts_given: number | null
          expected_cash: number | null
          id: string
          invoice_cash_sales: number | null
          invoice_cheque_sales: number | null
          manual_sales_total: number | null
          manual_transaction_count: number | null
          mobile_money_sales: number | null
          notes: string
          opening_confirmed_at: string
          opening_confirmed_by: string
          opening_float: number
          pos_cash_sales: number | null
          system_sales_total: number | null
          system_transaction_count: number | null
          tally_count_variance: number | null
          tally_sales_variance: number | null
          vat_collected: number | null
        }
        SetofOptions: {
          from: "*"
          to: "day_closes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_bank_reconciliation: {
        Args: { p_reconciliation_id: string }
        Returns: {
          bank_account_id: string
          completed_at: string | null
          completed_by: string | null
          difference: number | null
          id: string
          notes: string
          opening_balance: number
          reconciled_balance: number | null
          started_at: string
          started_by: string
          statement_date: string
          statement_ending_balance: number
        }
        SetofOptions: {
          from: "*"
          to: "bank_reconciliations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      compute_day_totals: {
        Args: { p_branch_id: string; p_business_date: string }
        Returns: {
          bank_transfer_sales: number
          card_sales: number
          cash_deposits: number
          cash_expenses: number
          cash_refunds: number
          cash_sales: number
          discounts_given: number
          invoice_cash_sales: number
          invoice_cheque_sales: number
          mobile_money_sales: number
          pos_cash_sales: number
          system_sales_total: number
          system_transaction_count: number
          vat_collected: number
        }[]
      }
      compute_invoice_posting_amounts: {
        Args: { p_invoice_discount: number; p_lines: Json; p_total: number }
        Returns: {
          discount: number
          subtotal: number
          vat: number
        }[]
      }
      compute_invoice_total: {
        Args: { p_invoice_discount: number; p_lines: Json; p_vat_rate: number }
        Returns: number
      }
      compute_sale_posting_amounts: {
        Args: {
          p_lines: Json
          p_sale_discount_mode: string
          p_sale_discount_value: number
          p_total: number
        }
        Returns: {
          discount: number
          subtotal: number
          vat: number
        }[]
      }
      compute_sale_total: {
        Args: {
          p_lines: Json
          p_sale_discount_mode: string
          p_sale_discount_value: number
          p_vat_mode: string
          p_vat_rate: number
        }
        Returns: number
      }
      consume_manager_override: {
        Args: { p_ticket_id: string }
        Returns: string
      }
      convert_pro_forma_to_invoice: {
        Args: {
          p_due_date: string
          p_pro_forma_invoice_id: string
          p_wht_applied?: boolean
        }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          issued_by: string
          notes: string
          total: number
          updated_at: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
          wht_amount: number
          wht_applied: boolean
          wht_rate: number | null
        }
        SetofOptions: {
          from: "*"
          to: "invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      correct_application_grade: {
        Args: { p_application_id: string; p_grade_id: string }
        Returns: Json
      }
      correct_staff_number: {
        Args: { p_employee_id: string; p_reason: string }
        Returns: string
      }
      create_account: {
        Args: {
          p_category: string
          p_code: string
          p_description?: string
          p_name: string
          p_subtype: string
        }
        Returns: {
          category: string
          code: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          is_active: boolean
          is_postable: boolean
          name: string
          normal_balance: string | null
          subtype: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "accounts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_admissions_capacity: {
        Args: {
          p_academic_year: string
          p_branch_id: string
          p_capacity: number
          p_grade_id: string
        }
        Returns: {
          academic_year: string
          branch_id: string | null
          capacity: number
          grade_id: string
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "admissions_capacity"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_bank_account: {
        Args: {
          p_account_number: string
          p_currency?: string
          p_gl_account_id?: string
          p_name: string
          p_opening_balance: number
          p_opening_balance_date: string
        }
        Returns: {
          account_number: string
          created_at: string
          created_by: string
          currency: string
          gl_account_id: string
          id: string
          is_active: boolean
          name: string
          opening_balance: number
          opening_balance_date: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_accounts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_customer_deposit: {
        Args: {
          p_amount: number
          p_bank_account_id?: string
          p_branch_id: string
          p_customer_id: string
          p_description: string
          p_method: string
        }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          cancellation_fee: number | null
          cancellation_note: string | null
          cancellation_refund: number | null
          cancelled_at: string | null
          cancelled_by: string | null
          customer_id: string
          customer_name: string
          description: string
          fulfilled_at: string | null
          fulfilled_invoice_id: string | null
          fulfilled_sale_id: string | null
          id: string
          method: string
          status: string
          taken_at: string
          taken_by: string
        }
        SetofOptions: {
          from: "*"
          to: "customer_deposits"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_customer_discount: {
        Args: {
          p_customer_id: string
          p_label: string
          p_mode: string
          p_value: number
        }
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          created_by: string
          customer_id: string
          id: string
          label: string
          mode: string
          updated_at: string
          value: number
        }
        SetofOptions: {
          from: "*"
          to: "customer_discounts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_expense: {
        Args: {
          p_amount: number
          p_bank_account_id?: string
          p_branch_id: string
          p_category: string
          p_date: string
          p_description: string
          p_method: string
          p_receipt_path?: string
          p_reference: string
        }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          category: string
          date: string
          description: string
          id: string
          method: string
          receipt_path: string | null
          recorded_at: string
          recorded_by: string
          reference: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "expenses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_invoice: {
        Args: {
          p_branch_id: string
          p_customer_id: string
          p_customer_name: string
          p_date: string
          p_due_date: string
          p_invoice_discount: number
          p_lines: Json
          p_notes: string
          p_wht_applied?: boolean
        }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          issued_by: string
          notes: string
          total: number
          updated_at: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
          wht_amount: number
          wht_applied: boolean
          wht_rate: number | null
        }
        SetofOptions: {
          from: "*"
          to: "invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_payroll_run: {
        Args: { p_branch_id: string; p_month: number; p_year: number }
        Returns: {
          branch_id: string
          created_at: string
          created_by: string | null
          id: string
          month: number
          posted_at: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          year: number
        }
        SetofOptions: {
          from: "*"
          to: "payroll_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_payslip: {
        Args: {
          p_allowances?: Json
          p_employee_id: string
          p_fines?: number
          p_iou?: number
          p_overtime_hours?: number
          p_overtime_rate?: number
          p_payroll_run_id: string
        }
        Returns: {
          basic_salary: number
          employee_id: string
          employee_pay_config_id: string
          fines: number
          generated_at: string
          gross_salary: number
          id: string
          iou: number
          net_pay: number
          overtime_concession: boolean
          overtime_hours: number
          overtime_pay: number
          overtime_rate: number
          overtime_tax: number
          payroll_run_id: string
          pdf_path: string | null
          ssnit: number
          ssnit_employer: number
          tax: number
          taxable_income: number
          tier2: number
          total_allowances: number
          total_deductions: number
          total_earning: number
        }
        SetofOptions: {
          from: "*"
          to: "payslips"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_pro_forma_invoice: {
        Args: {
          p_branch_id: string
          p_customer_id: string
          p_customer_name: string
          p_date: string
          p_due_date: string
          p_invoice_discount: number
          p_lines: Json
          p_notes: string
        }
        Returns: {
          branch_id: string
          converted_invoice_id: string | null
          created_at: string
          created_by: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          notes: string
          status: string
          total: number
          vat_rate: number
        }
        SetofOptions: {
          from: "*"
          to: "pro_forma_invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_purchase_order: {
        Args: {
          p_branch_id: string
          p_expected_date: string
          p_lines: Json
          p_notes: string
          p_order_date: string
          p_supplier_id: string
          p_supplier_name: string
        }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          created_by: string
          expected_date: string | null
          id: string
          notes: string
          order_date: string
          received_value: number
          status: string
          supplier_id: string
          supplier_name: string
          total: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "purchase_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_sale: {
        Args: {
          p_branch_id: string
          p_customer_id: string
          p_customer_name: string
          p_lines: Json
          p_notes?: string
          p_override_ticket?: string
          p_payments: Json
          p_sale_discount_mode: string
          p_sale_discount_value: number
          p_vat_mode: string
        }
        Returns: {
          branch_id: string
          cashier: string
          created_at: string
          customer_id: string | null
          customer_name: string
          id: string
          notes: string
          override_authorized_by: string | null
          sale_discount_mode: string
          sale_discount_value: number
          sold_at: string
          total: number
          vat_mode: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "sales"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_sale_return: {
        Args: {
          p_approval_state: string
          p_bank_account_id?: string
          p_customer_id?: string
          p_payment_method?: string
          p_reason: string
          p_replacement_product_id: string
          p_replacement_quantity: number
          p_resolution: string
          p_returned_quantity: number
          p_returned_sale_line_id: string
          p_sale_id: string
        }
        Returns: {
          approval_state: string
          bank_account_id: string | null
          branch_id: string
          customer_id: string | null
          difference: number
          id: string
          payment_method: string | null
          processed_by: string
          reason: string
          replacement_name: string | null
          replacement_product_id: string | null
          replacement_quantity: number | null
          replacement_unit: string | null
          replacement_unit_price: number | null
          resolution: string
          return_group_id: string | null
          returned_at: string
          returned_name: string
          returned_product_id: string
          returned_quantity: number
          returned_sale_line_id: string
          returned_unit: string
          returned_unit_price: number
          sale_id: string
        }
        SetofOptions: {
          from: "*"
          to: "sale_returns"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_sale_return_batch: {
        Args: {
          p_bank_account_id?: string
          p_customer_id?: string
          p_lines: Json
          p_payment_method?: string
          p_reason: string
          p_refund_choice: string
          p_sale_id: string
        }
        Returns: {
          approval_state: string
          bank_account_id: string | null
          branch_id: string
          customer_id: string | null
          difference: number
          id: string
          payment_method: string | null
          processed_by: string
          reason: string
          replacement_name: string | null
          replacement_product_id: string | null
          replacement_quantity: number | null
          replacement_unit: string | null
          replacement_unit_price: number | null
          resolution: string
          return_group_id: string | null
          returned_at: string
          returned_name: string
          returned_product_id: string
          returned_quantity: number
          returned_sale_line_id: string
          returned_unit: string
          returned_unit_price: number
          sale_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "sale_returns"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      create_supplier: {
        Args: {
          p_address?: string
          p_branch_id: string
          p_contact_name?: string
          p_email?: string
          p_name: string
          p_phone?: string
        }
        Returns: {
          address: string
          balance: number
          branch_id: string
          contact_name: string
          created_at: string
          created_by: string
          email: string
          id: string
          is_active: boolean
          lifetime_total: number
          name: string
          phone: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "suppliers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_admissions_capacity: { Args: { p_id: string }; Returns: undefined }
      delete_payslip: { Args: { p_payslip_id: string }; Returns: undefined }
      delete_product: { Args: { p_id: string }; Returns: undefined }
      discard_draft_document: {
        Args: { p_document_id: string }
        Returns: undefined
      }
      exclude_employee_from_run: {
        Args: { p_employee_id: string; p_reason?: string; p_run_id: string }
        Returns: {
          employee_id: string
          excluded_at: string
          excluded_by: string | null
          id: string
          payroll_run_id: string
          reason: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payroll_run_exclusions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      expense_category_account: {
        Args: { p_branch_id: string; p_category: string }
        Returns: string
      }
      finish_application_upload_cleanup: {
        Args: { p_reservation_ids: string[] }
        Returns: number
      }
      generate_employee_document: {
        Args: {
          p_document_kind: string
          p_employee_id: string
          p_merge_data: Json
          p_storage_path: string
        }
        Returns: {
          acceptance_signature_name: string | null
          accepted_at: string | null
          created_at: string
          created_by: string
          document_kind: string
          employee_id: string
          id: string
          issued_at: string | null
          issued_by: string | null
          merge_data: Json
          status: string
          storage_path: string
          superseded_at: string | null
          version: number
        }
        SetofOptions: {
          from: "*"
          to: "employee_generated_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      generate_offer: { Args: { p_application_id: string }; Returns: Json }
      generate_onboarding_token: {
        Args: { p_employee_id: string; p_ttl_days?: number }
        Returns: {
          expires_at: string
          token: string
        }[]
      }
      get_admissions_email_health: {
        Args: never
        Returns: {
          ceiling_reached_at: string
          config_error: boolean
          expired: number
          failed: number
          last_run_at: string
          last_success_at: string
          suppressed: number
          waiting: number
        }[]
      }
      get_application_email_status: {
        Args: { p_application_id: string }
        Returns: {
          emails: number
          last_sent_at: string
          status: string
        }[]
      }
      get_onboarding_context: {
        Args: { p_token: string }
        Returns: {
          department: string
          employee_name: string
          employee_position: string
          valid: boolean
        }[]
      }
      get_public_admissions_options: { Args: never; Returns: Json }
      get_session_timeout_minutes: { Args: never; Returns: number }
      has_admissions_capability: {
        Args: { p_capability: string }
        Returns: boolean
      }
      has_role: { Args: { p_roles: string[] }; Returns: boolean }
      import_bank_statement_lines: {
        Args: { p_bank_account_id: string; p_lines: Json }
        Returns: {
          amount: number
          bank_account_id: string
          clear_note: string
          created_at: string
          date: string
          description: string
          id: string
          imported_by: string
          matched_at: string | null
          matched_by: string | null
          matched_journal_line_id: string | null
          reconciliation_id: string | null
          reference: string
          status: string
        }[]
        SetofOptions: {
          from: "*"
          to: "bank_statement_lines"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      import_employees: { Args: { p_rows: Json }; Returns: Json }
      include_employee_in_run: {
        Args: { p_employee_id: string; p_run_id: string }
        Returns: undefined
      }
      initialize_onboarding_checklist: {
        Args: { p_employee_id: string }
        Returns: undefined
      }
      initialize_onboarding_tasks: {
        Args: { p_employee_id: string }
        Returns: undefined
      }
      is_active_staff: { Args: never; Returns: boolean }
      is_valid_onboarding_token: { Args: { p_token: string }; Returns: boolean }
      issue_employee_document: {
        Args: { p_document_id: string }
        Returns: undefined
      }
      list_admissions_emails: {
        Args: { p_limit?: number; p_status?: string }
        Returns: {
          application_ids: string[]
          attempts: number
          created_at: string
          id: string
          kind: string
          last_error_class: string
          last_http_status: number
          next_attempt_at: string
          recipient_masked: string
          references: string[]
          requeued_at: string
          sent_at: string
          status: string
        }[]
      }
      list_staff_names: {
        Args: never
        Returns: {
          id: string
          name: string
        }[]
      }
      mark_admissions_email_result: {
        Args: {
          p_claim_token: string
          p_error_class: string
          p_http_status: number
          p_id: string
          p_outcome: string
          p_provider_message_id: string
        }
        Returns: boolean
      }
      mark_enrolled: { Args: { p_application_id: string }; Returns: Json }
      match_statement_line: {
        Args: { p_journal_line_id: string; p_line_id: string }
        Returns: {
          amount: number
          bank_account_id: string
          clear_note: string
          created_at: string
          date: string
          description: string
          id: string
          imported_by: string
          matched_at: string | null
          matched_by: string | null
          matched_journal_line_id: string | null
          reconciliation_id: string | null
          reference: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_statement_lines"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      move_application_to_document_review: {
        Args: { p_application_id: string }
        Returns: {
          academic_year: string
          application_reference: string | null
          branch_id: string | null
          created_at: string
          declaration_agreed: boolean
          declaration_agreed_at: string | null
          declaration_ip_address: unknown
          declaration_signature_name: string
          id: string
          inquiry_reference: string | null
          media_consent_agreed: boolean
          month_of_enrollment: string
          scholarship_interest_details: string
          stage: string
          student_id: string
          updated_at: string
          wants_scholarship_info: boolean
          year_group_applied_for: string
        }
        SetofOptions: {
          from: "*"
          to: "applications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      next_product_skus: {
        Args: { p_count: number; p_prefix: string }
        Returns: string[]
      }
      notify_daily_sales_summary: {
        Args: { p_day_close_id: string }
        Returns: undefined
      }
      notify_managers: {
        Args: {
          p_body: string
          p_branch_id: string
          p_entity_id: string
          p_entity_table: string
          p_link: string
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      notify_overdue_invoices: {
        Args: { p_as_of: string; p_branch_id: string }
        Returns: undefined
      }
      open_application_upload_session: { Args: never; Returns: Json }
      open_day: {
        Args: { p_branch_id: string; p_opening_float: number }
        Returns: {
          bank_transfer_sales: number | null
          branch_id: string
          business_date: string
          card_sales: number | null
          cash_deposits: number | null
          cash_expenses: number | null
          cash_refunds: number | null
          cash_sales: number | null
          cash_variance: number | null
          closed_at: string | null
          closed_by: string | null
          counted_cash: number | null
          created_at: string
          discounts_given: number | null
          expected_cash: number | null
          id: string
          invoice_cash_sales: number | null
          invoice_cheque_sales: number | null
          manual_sales_total: number | null
          manual_transaction_count: number | null
          mobile_money_sales: number | null
          notes: string
          opening_confirmed_at: string
          opening_confirmed_by: string
          opening_float: number
          pos_cash_sales: number | null
          system_sales_total: number | null
          system_transaction_count: number | null
          tally_count_variance: number | null
          tally_sales_variance: number | null
          vat_collected: number | null
        }
        SetofOptions: {
          from: "*"
          to: "day_closes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      payment_method_account: { Args: { p_method: string }; Returns: string }
      place_purchase_order: {
        Args: { p_purchase_order_id: string }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          created_by: string
          expected_date: string | null
          id: string
          notes: string
          order_date: string
          received_value: number
          status: string
          supplier_id: string
          supplier_name: string
          total: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "purchase_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_bank_deposit_journal_entry: {
        Args: { p_deposit_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_customer_deposit_cancellation_journal_entry: {
        Args: { p_deposit_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_customer_deposit_journal_entry: {
        Args: { p_deposit_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_day_close_journal_entry: {
        Args: { p_day_close_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_expense_journal_entry: {
        Args: { p_expense_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_invoice_journal_entry: {
        Args: { p_invoice_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_invoice_payment_journal_entry: {
        Args: { p_payment_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_journal_entry: {
        Args: {
          p_date: string
          p_description: string
          p_lines: Json
          p_reference: string
          p_reverses_entry_id?: string
        }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_payroll_run: {
        Args: { p_run_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_purchase_receipt_journal_entry: {
        Args: { p_receipt_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_sale_journal_entry: {
        Args: { p_sale_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_sale_return_journal_entry: {
        Args: { p_return_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_stock_adjustment_journal_entry: {
        Args: { p_movement_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_supplier_payment_journal_entry: {
        Args: { p_payment_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      preview_employee_import: { Args: { p_rows: Json }; Returns: Json }
      propose_employee: {
        Args: {
          p_account_no?: string
          p_bank?: string
          p_basic_salary?: number
          p_branch_id: string
          p_department?: string
          p_effective_from?: string
          p_name: string
          p_payment_method?: string
          p_pays_paye?: boolean
          p_pays_ssnit?: boolean
          p_pays_tier2?: boolean
          p_phone?: string
          p_position?: string
          p_staff_id?: string
        }
        Returns: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      propose_pay_config_change: {
        Args: {
          p_account_no: string
          p_bank: string
          p_basic_salary: number
          p_effective_from: string
          p_employee_id: string
          p_payment_method?: string
          p_pays_paye: boolean
          p_pays_ssnit: boolean
          p_pays_tier2: boolean
        }
        Returns: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_pay_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      propose_staff_advance: {
        Args: {
          p_amount: number
          p_bank_account_id?: string
          p_disbursed_on: string
          p_employee_id: string
          p_first_repayment_month: string
          p_instalment: number
          p_method: string
          p_note?: string
        }
        Returns: {
          amount: number
          bank_account_id: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string | null
          proposed_at: string
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      propose_staff_advance_change: {
        Args: {
          p_advance_id: string
          p_kind: string
          p_new_instalment?: number
          p_reason?: string
        }
        Returns: {
          advance_id: string
          id: string
          kind: string
          new_instalment: number | null
          proposed_at: string
          proposed_by: string | null
          reason: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advance_change_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      purge_admissions_housekeeping: { Args: never; Returns: Json }
      receive_purchase_order: {
        Args: {
          p_lines: Json
          p_notes: string
          p_purchase_order_id: string
          p_received_date: string
        }
        Returns: {
          branch_id: string
          created_at: string
          id: string
          notes: string
          purchase_order_id: string
          received_by: string
          received_date: string
          total_value: number
        }
        SetofOptions: {
          from: "*"
          to: "purchase_order_receipts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      recompute_derived_onboarding_task: {
        Args: { p_derivation_key: string; p_employee_id: string }
        Returns: undefined
      }
      recompute_onboarding_completion: {
        Args: { p_employee_id: string }
        Returns: undefined
      }
      record_bank_deposit: {
        Args: {
          p_amount: number
          p_bank_account_id: string
          p_branch_id: string
          p_date: string
          p_note?: string
          p_reference?: string
          p_source: string
        }
        Returns: {
          amount: number
          bank_account_id: string
          branch_id: string
          created_at: string
          date: string
          deposited_by: string
          id: string
          note: string
          reference: string
          source: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_deposits"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_decision: {
        Args: {
          p_application_id: string
          p_decision_type: string
          p_notes: string
        }
        Returns: Json
      }
      record_document_acceptance: {
        Args: { p_document_id: string; p_signature_name: string }
        Returns: undefined
      }
      record_invoice_payment: {
        Args: {
          p_amount: number
          p_bank_account_id?: string
          p_deposit_id?: string
          p_invoice_id: string
          p_method: string
          p_note?: string
          p_paid_at?: string
          p_reference: string
        }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          id: string
          invoice_id: string
          method: string
          note: string
          paid_at: string
          recorded_by: string
          reference: string
        }
        SetofOptions: {
          from: "*"
          to: "invoice_payments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_offer_response: {
        Args: { p_application_id: string; p_response: string }
        Returns: Json
      }
      record_supplier_payment: {
        Args: {
          p_amount: number
          p_bank_account_id?: string
          p_method: string
          p_note?: string
          p_paid_at?: string
          p_purchase_order_id: string
          p_reference?: string
        }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          id: string
          method: string
          note: string
          paid_at: string
          purchase_order_id: string
          recorded_by: string
          reference: string
        }
        SetofOptions: {
          from: "*"
          to: "supplier_payments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_employee: {
        Args: { p_employee_id: string; p_reason: string }
        Returns: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_onboarding_submission: {
        Args: { p_reason?: string; p_submission_id: string }
        Returns: undefined
      }
      reject_pay_config: {
        Args: { p_config_id: string; p_reason: string }
        Returns: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_pay_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_payroll_run: {
        Args: { p_reason: string; p_run_id: string }
        Returns: {
          branch_id: string
          created_at: string
          created_by: string | null
          id: string
          month: number
          posted_at: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          year: number
        }
        SetofOptions: {
          from: "*"
          to: "payroll_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_staff_advance: {
        Args: { p_advance_id: string; p_reason: string }
        Returns: {
          amount: number
          bank_account_id: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string | null
          proposed_at: string
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reject_staff_advance_change: {
        Args: { p_reason: string; p_request_id: string }
        Returns: {
          advance_id: string
          id: string
          kind: string
          new_instalment: number | null
          proposed_at: string
          proposed_by: string | null
          reason: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advance_change_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      requeue_admissions_emails: { Args: { p_ids: string[] }; Returns: number }
      require_finance_writer: { Args: never; Returns: undefined }
      require_staff: {
        Args: never
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
          employee_id: string | null
          id: string
          name: string
          protected: boolean
          role: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "staff"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      require_writable_role: { Args: never; Returns: undefined }
      reserve_application_upload: {
        Args: {
          p_document_type: string
          p_extension: string
          p_session_token: string
        }
        Returns: Json
      }
      reset_offer: { Args: { p_application_id: string }; Returns: Json }
      reverse_journal_entry: {
        Args: { p_date?: string; p_description?: string; p_entry_id: string }
        Returns: {
          branch_id: string
          cost_data_incomplete: boolean
          created_at: string
          created_by: string
          description: string
          entry_date: string
          id: string
          reference: string | null
          reverses_entry_id: string | null
          source_id: string | null
          source_table: string | null
        }
        SetofOptions: {
          from: "*"
          to: "journal_entries"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_admissions_academic_year_active: {
        Args: { p_active: boolean; p_label: string }
        Returns: {
          created_at: string
          is_active: boolean
          label: string
          position: number
        }
        SetofOptions: {
          from: "*"
          to: "admissions_academic_years"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_admissions_capabilities: {
        Args: {
          p_all_grades: boolean
          p_can_decide: boolean
          p_can_view_health: boolean
          p_grade_bands: string[]
          p_staff_id: string
        }
        Returns: undefined
      }
      set_admissions_offer_ttl_days: {
        Args: { p_days: number }
        Returns: {
          id: number
          offer_ttl_days: number
          public_applications_open: boolean
          public_intake_open: boolean
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "admissions_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_admissions_public_applications: {
        Args: { p_open: boolean }
        Returns: {
          id: number
          offer_ttl_days: number
          public_applications_open: boolean
          public_intake_open: boolean
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "admissions_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_admissions_public_intake: {
        Args: { p_open: boolean }
        Returns: {
          id: number
          offer_ttl_days: number
          public_applications_open: boolean
          public_intake_open: boolean
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "admissions_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_admissions_worker_url: { Args: { p_url: string }; Returns: undefined }
      set_application_document_status: {
        Args: { p_document_id: string; p_status: string }
        Returns: {
          application_id: string
          document_type: string
          id: string
          status: string
          storage_path: string | null
          uploaded_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "application_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_application_stage: {
        Args: { p_application_id: string; p_stage: string }
        Returns: {
          academic_year: string
          application_reference: string | null
          branch_id: string | null
          created_at: string
          declaration_agreed: boolean
          declaration_agreed_at: string | null
          declaration_ip_address: unknown
          declaration_signature_name: string
          id: string
          inquiry_reference: string | null
          media_consent_agreed: boolean
          month_of_enrollment: string
          scholarship_interest_details: string
          stage: string
          student_id: string
          updated_at: string
          wants_scholarship_info: boolean
          year_group_applied_for: string
        }
        SetofOptions: {
          from: "*"
          to: "applications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_employee_status: {
        Args: { p_employee_id: string; p_status: string }
        Returns: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_expense_categories: {
        Args: { p_branch_id: string; p_categories: string[] }
        Returns: {
          branch_id: string
          id: string
          name: string
          position: number
        }[]
        SetofOptions: {
          from: "*"
          to: "expense_categories"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      set_pay_config_exemptions: {
        Args: {
          p_employee_id: string
          p_pays_paye: boolean
          p_pays_ssnit: boolean
          p_pays_tier2: boolean
        }
        Returns: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_pay_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_position_staff_class: {
        Args: { p_class: string; p_position_id: string }
        Returns: {
          created_at: string
          id: string
          is_active: boolean
          is_teaching: boolean
          name: string
          position: number
          staff_class: string | null
        }
        SetofOptions: {
          from: "*"
          to: "positions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      settle_expired_offers: { Args: never; Returns: number }
      settlement_account: {
        Args: { p_bank_account_id: string; p_method: string }
        Returns: string
      }
      staff_advance_deduction_preview: {
        Args: { p_employee_id: string; p_payroll_run_id: string }
        Returns: {
          advance_id: string
          balance: number
          due: number
          instalment: number
          ord: number
          skip_reason: string
        }[]
      }
      staff_advance_payslip_lines: {
        Args: { p_payslip_id: string }
        Returns: {
          advance_amount: number
          advance_id: string
          amount: number
          balance_after: number
          disbursed_on: string
          instalment_due: number
        }[]
      }
      staff_advance_summary: {
        Args: { p_employee_id?: string }
        Returns: {
          amount: number
          balance: number
          bank_account_id: string
          disbursed_on: string
          disbursement_method: string
          display_status: string
          employee_id: string
          employee_name: string
          employee_status: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string
          proposed_at: string
          proposed_by: string
          rejection_reason: string
          repaid: number
          reviewed_at: string
          reviewed_by: string
          status: string
        }[]
      }
      staff_sign_in_status: {
        Args: never
        Returns: {
          last_sign_in_at: string
          staff_id: string
        }[]
      }
      start_bank_reconciliation: {
        Args: {
          p_bank_account_id: string
          p_statement_date: string
          p_statement_ending_balance: number
        }
        Returns: {
          bank_account_id: string
          completed_at: string | null
          completed_by: string | null
          difference: number | null
          id: string
          notes: string
          opening_balance: number
          reconciled_balance: number | null
          started_at: string
          started_by: string
          statement_date: string
          statement_ending_balance: number
        }
        SetofOptions: {
          from: "*"
          to: "bank_reconciliations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_application: {
        Args: { p_payload: Json; p_session_token: string; p_sniffed: Json }
        Returns: string
      }
      submit_inquiry: { Args: { p_payload: Json }; Returns: string[] }
      submit_onboarding_form: {
        Args: {
          p_account_no?: string
          p_bank_name?: string
          p_contract_accepted?: boolean
          p_date_of_birth?: string
          p_emergency_contact_name?: string
          p_emergency_contact_phone?: string
          p_gender?: string
          p_national_id?: string
          p_payment_method?: string
          p_personal_email?: string
          p_qualifications?: string[]
          p_residential_address?: string
          p_signature_name?: string
          p_token: string
          p_uploaded_documents?: Json
        }
        Returns: string
      }
      submit_payroll_run_for_review: {
        Args: { p_run_id: string }
        Returns: {
          branch_id: string
          created_at: string
          created_by: string | null
          id: string
          month: number
          posted_at: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          year: number
        }
        SetofOptions: {
          from: "*"
          to: "payroll_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      toggle_onboarding_task: {
        Args: {
          p_completed: boolean
          p_provided_number?: string
          p_provided_via?: string
          p_task_id: string
        }
        Returns: undefined
      }
      unmatch_statement_line: {
        Args: { p_line_id: string }
        Returns: {
          amount: number
          bank_account_id: string
          clear_note: string
          created_at: string
          date: string
          description: string
          id: string
          imported_by: string
          matched_at: string | null
          matched_by: string | null
          matched_journal_line_id: string | null
          reconciliation_id: string | null
          reference: string
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_statement_lines"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_admissions_capacity: {
        Args: { p_capacity: number; p_id: string }
        Returns: {
          academic_year: string
          branch_id: string | null
          capacity: number
          grade_id: string
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "admissions_capacity"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_application_note: {
        Args: { p_content: string; p_note_id: string }
        Returns: {
          application_id: string
          author_id: string | null
          content: string
          created_at: string
          edited_at: string | null
          id: string
        }
        SetofOptions: {
          from: "*"
          to: "application_notes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_employee_profile: {
        Args: {
          p_church_denomination?: string
          p_contract_end_date?: string
          p_date_of_birth?: string
          p_department: string
          p_emergency_contact_name?: string
          p_emergency_contact_phone?: string
          p_employee_id: string
          p_employment_type?: string
          p_gender?: string
          p_national_id?: string
          p_personal_email?: string
          p_phone: string
          p_position: string
          p_preferred_name?: string
          p_probation_end_date?: string
          p_qualifications?: string[]
          p_residential_address?: string
          p_school_email?: string
          p_ssnit_number?: string
          p_start_date?: string
          p_tin_number?: string
        }
        Returns: {
          branch_id: string
          church_denomination: string | null
          contract_end_date: string | null
          created_at: string
          date_of_birth: string | null
          department: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employment_status: string
          employment_type: string | null
          gender: string | null
          id: string
          name: string
          national_id: string | null
          onboarding_completed_at: string | null
          personal_email: string | null
          phone: string | null
          position: string | null
          preferred_name: string | null
          probation_end_date: string | null
          proposed_by: string | null
          qualifications: string[] | null
          rejection_reason: string | null
          residential_address: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          school_email: string | null
          ssnit_number: string | null
          start_date: string | null
          tin_number: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "employees"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_invoice: {
        Args: {
          p_branch_id: string
          p_customer_id: string
          p_customer_name: string
          p_date: string
          p_due_date: string
          p_id: string
          p_invoice_discount: number
          p_lines: Json
          p_notes: string
        }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          issued_by: string
          notes: string
          total: number
          updated_at: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
          wht_amount: number
          wht_applied: boolean
          wht_rate: number | null
        }
        SetofOptions: {
          from: "*"
          to: "invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      void_expense: {
        Args: { p_expense_id: string; p_reason: string }
        Returns: {
          amount: number
          bank_account_id: string | null
          branch_id: string
          category: string
          date: string
          description: string
          id: string
          method: string
          receipt_path: string | null
          recorded_at: string
          recorded_by: string
          reference: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "expenses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      void_invoice: {
        Args: { p_invoice_id: string; p_reason: string }
        Returns: {
          amount_paid: number
          balance: number
          branch_id: string
          created_at: string
          customer_id: string
          customer_name: string
          date: string
          due_date: string
          id: string
          invoice_discount: number
          issued_by: string
          notes: string
          total: number
          updated_at: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
          wht_amount: number
          wht_applied: boolean
          wht_rate: number | null
        }
        SetofOptions: {
          from: "*"
          to: "invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      void_sale: {
        Args: { p_reason: string; p_sale_id: string }
        Returns: {
          branch_id: string
          cashier: string
          created_at: string
          customer_id: string | null
          customer_name: string
          id: string
          notes: string
          override_authorized_by: string | null
          sale_discount_mode: string
          sale_discount_value: number
          sold_at: string
          total: number
          vat_mode: string
          vat_rate: number
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "sales"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      withdraw_pay_config_proposal: {
        Args: { p_config_id: string }
        Returns: {
          account_no: string | null
          approval_status: string
          bank: string | null
          basic_salary: number
          created_at: string
          effective_from: string
          effective_to: string | null
          employee_id: string
          id: string
          payment_method: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_pay_config"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      withdraw_staff_advance_change: {
        Args: { p_request_id: string }
        Returns: {
          advance_id: string
          id: string
          kind: string
          new_instalment: number | null
          proposed_at: string
          proposed_by: string | null
          reason: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advance_change_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      withdraw_staff_advance_proposal: {
        Args: { p_advance_id: string }
        Returns: {
          amount: number
          bank_account_id: string | null
          disbursed_on: string
          disbursement_method: string
          employee_id: string
          first_repayment_month: string
          id: string
          instalment: number
          note: string | null
          proposed_at: string
          proposed_by: string | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "staff_advances"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
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
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

