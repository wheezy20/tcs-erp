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
        }
        Insert: {
          created_at?: string
          default_low_stock_threshold?: number
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          default_low_stock_threshold?: number
          id?: string
          name?: string
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
      payroll_runs: {
        Row: {
          branch_id: string
          created_at: string
          created_by: string | null
          id: string
          month: number
          posted_at: string | null
          status: string
          year: number
        }
        Insert: {
          branch_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          month: number
          posted_at?: string | null
          status?: string
          year: number
        }
        Update: {
          branch_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          month?: number
          posted_at?: string | null
          status?: string
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
          fines: number
          generated_at: string
          gross_salary: number
          id: string
          iou: number
          net_pay: number
          overtime_hours: number
          overtime_pay: number
          overtime_rate: number
          payroll_run_id: string
          pdf_path: string | null
          ssnit: number
          staff_id: string
          staff_pay_config_id: string
          tax: number
          taxable_income: number
          tier2: number
          total_allowances: number
          total_deductions: number
          total_earning: number
        }
        Insert: {
          basic_salary: number
          fines?: number
          generated_at?: string
          gross_salary: number
          id?: string
          iou?: number
          net_pay: number
          overtime_hours?: number
          overtime_pay?: number
          overtime_rate?: number
          payroll_run_id: string
          pdf_path?: string | null
          ssnit?: number
          staff_id: string
          staff_pay_config_id: string
          tax?: number
          taxable_income: number
          tier2?: number
          total_allowances?: number
          total_deductions: number
          total_earning: number
        }
        Update: {
          basic_salary?: number
          fines?: number
          generated_at?: string
          gross_salary?: number
          id?: string
          iou?: number
          net_pay?: number
          overtime_hours?: number
          overtime_pay?: number
          overtime_rate?: number
          payroll_run_id?: string
          pdf_path?: string | null
          ssnit?: number
          staff_id?: string
          staff_pay_config_id?: string
          tax?: number
          taxable_income?: number
          tier2?: number
          total_allowances?: number
          total_deductions?: number
          total_earning?: number
        }
        Relationships: [
          {
            foreignKeyName: "payslips_payroll_run_id_fkey"
            columns: ["payroll_run_id"]
            isOneToOne: false
            referencedRelation: "payroll_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payslips_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payslips_staff_pay_config_id_fkey"
            columns: ["staff_pay_config_id"]
            isOneToOne: false
            referencedRelation: "staff_pay_config"
            referencedColumns: ["id"]
          },
        ]
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
        ]
      }
      staff_allowances: {
        Row: {
          allowance_type_id: string
          default_amount: number
          effective_from: string
          effective_to: string | null
          id: string
          staff_id: string
        }
        Insert: {
          allowance_type_id: string
          default_amount: number
          effective_from: string
          effective_to?: string | null
          id?: string
          staff_id: string
        }
        Update: {
          allowance_type_id?: string
          default_amount?: number
          effective_from?: string
          effective_to?: string | null
          id?: string
          staff_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_allowances_allowance_type_id_fkey"
            columns: ["allowance_type_id"]
            isOneToOne: false
            referencedRelation: "allowance_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_allowances_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      staff_pay_config: {
        Row: {
          account_no: string | null
          bank: string | null
          basic_salary: number
          created_at: string
          department: string | null
          effective_from: string
          effective_to: string | null
          id: string
          pays_paye: boolean
          pays_ssnit: boolean
          pays_tier2: boolean
          position: string | null
          staff_id: string
        }
        Insert: {
          account_no?: string | null
          bank?: string | null
          basic_salary: number
          created_at?: string
          department?: string | null
          effective_from: string
          effective_to?: string | null
          id?: string
          pays_paye?: boolean
          pays_ssnit?: boolean
          pays_tier2?: boolean
          position?: string | null
          staff_id: string
        }
        Update: {
          account_no?: string | null
          bank?: string | null
          basic_salary?: number
          created_at?: string
          department?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          pays_paye?: boolean
          pays_ssnit?: boolean
          pays_tier2?: boolean
          position?: string | null
          staff_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_pay_config_staff_id_fkey"
            columns: ["staff_id"]
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
      [_ in never]: never
    }
    Functions: {
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
      account_id_by_code: { Args: { p_code: string }; Returns: string }
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
          status: string
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
          p_fines?: number
          p_iou?: number
          p_overtime_hours?: number
          p_overtime_rate?: number
          p_payroll_run_id: string
          p_staff_id: string
        }
        Returns: {
          basic_salary: number
          fines: number
          generated_at: string
          gross_salary: number
          id: string
          iou: number
          net_pay: number
          overtime_hours: number
          overtime_pay: number
          overtime_rate: number
          payroll_run_id: string
          pdf_path: string | null
          ssnit: number
          staff_id: string
          staff_pay_config_id: string
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
      delete_payslip: { Args: { p_payslip_id: string }; Returns: undefined }
      delete_product: { Args: { p_id: string }; Returns: undefined }
      expense_category_account: {
        Args: { p_branch_id: string; p_category: string }
        Returns: string
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
      is_active_staff: { Args: never; Returns: boolean }
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
      require_finance_writer: { Args: never; Returns: undefined }
      require_staff: {
        Args: never
        Returns: {
          active: boolean
          branch_id: string
          created_at: string
          email: string
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
      settlement_account: {
        Args: { p_bank_account_id: string; p_method: string }
        Returns: string
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
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

