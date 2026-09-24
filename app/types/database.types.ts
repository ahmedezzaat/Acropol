// Hand-written to match supabase/migrations/*.sql exactly, in the shape
// `supabase gen types typescript` produces. Regenerate with that command
// instead of hand-editing once Docker (or a project link) is available —
// `supabase gen types typescript --db-url "$SUPABASE_DB_URL" --schema public`
// requires Docker in this CLI version, which wasn't available when this was
// written.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          email: string;
          full_name: string | null;
          role_id: string | null;
          is_admin: boolean;
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          email: string;
          full_name?: string | null;
          role_id?: string | null;
          is_admin?: boolean;
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          email?: string;
          full_name?: string | null;
          role_id?: string | null;
          is_admin?: boolean;
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "profiles_role_id_fkey";
            columns: ["role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["id"];
          },
        ];
      };
      roles: {
        Row: {
          id: string;
          name: string;
          description: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          description?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          description?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      role_permissions: {
        Row: {
          id: string;
          role_id: string;
          module: string;
          action: string;
        };
        Insert: {
          id?: string;
          role_id: string;
          module: string;
          action: string;
        };
        Update: {
          id?: string;
          role_id?: string;
          module?: string;
          action?: string;
        };
        Relationships: [
          {
            foreignKeyName: "role_permissions_role_id_fkey";
            columns: ["role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["id"];
          },
        ];
      };
      customers: {
        Row: {
          id: string;
          name: string;
          company: string | null;
          phone: string | null;
          email: string | null;
          address: string | null;
          converted_from_lead_id: string | null;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          company?: string | null;
          phone?: string | null;
          email?: string | null;
          address?: string | null;
          converted_from_lead_id?: string | null;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          company?: string | null;
          phone?: string | null;
          email?: string | null;
          address?: string | null;
          converted_from_lead_id?: string | null;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "customers_converted_from_lead_fkey";
            columns: ["converted_from_lead_id"];
            isOneToOne: false;
            referencedRelation: "leads";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "customers_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      leads: {
        Row: {
          id: string;
          name: string;
          phone: string | null;
          phone2: string | null;
          email: string | null;
          source: Database["public"]["Enums"]["lead_source"] | null;
          lead_type: Database["public"]["Enums"]["lead_type"];
          company_name: string | null;
          status: Database["public"]["Enums"]["lead_status"];
          notes: string | null;
          assigned_to: string | null;
          created_by: string;
          customer_id: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          phone?: string | null;
          phone2?: string | null;
          email?: string | null;
          source?: Database["public"]["Enums"]["lead_source"] | null;
          lead_type?: Database["public"]["Enums"]["lead_type"];
          company_name?: string | null;
          status?: Database["public"]["Enums"]["lead_status"];
          notes?: string | null;
          assigned_to?: string | null;
          created_by?: string;
          customer_id?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          phone?: string | null;
          phone2?: string | null;
          email?: string | null;
          source?: Database["public"]["Enums"]["lead_source"] | null;
          lead_type?: Database["public"]["Enums"]["lead_type"];
          company_name?: string | null;
          status?: Database["public"]["Enums"]["lead_status"];
          notes?: string | null;
          assigned_to?: string | null;
          created_by?: string;
          customer_id?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "leads_assigned_to_fkey";
            columns: ["assigned_to"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "leads_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
        ];
      };
      deals: {
        Row: {
          id: string;
          customer_id: string;
          lead_id: string | null;
          title: string;
          stage: Database["public"]["Enums"]["deal_stage"];
          value: number | null;
          expected_close_date: string | null;
          assigned_to: string | null;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          customer_id: string;
          lead_id?: string | null;
          title: string;
          stage?: Database["public"]["Enums"]["deal_stage"];
          value?: number | null;
          expected_close_date?: string | null;
          assigned_to?: string | null;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          customer_id?: string;
          lead_id?: string | null;
          title?: string;
          stage?: Database["public"]["Enums"]["deal_stage"];
          value?: number | null;
          expected_close_date?: string | null;
          assigned_to?: string | null;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "deals_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "deals_lead_id_fkey";
            columns: ["lead_id"];
            isOneToOne: false;
            referencedRelation: "leads";
            referencedColumns: ["id"];
          },
        ];
      };
      quotes: {
        Row: {
          id: string;
          deal_id: string;
          customer_id: string;
          quote_number: string;
          status: Database["public"]["Enums"]["quote_status"];
          valid_until: string | null;
          subtotal: number;
          tax: number;
          total: number;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          deal_id: string;
          customer_id: string;
          quote_number?: string;
          status?: Database["public"]["Enums"]["quote_status"];
          valid_until?: string | null;
          subtotal?: number;
          tax?: number;
          total?: number;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          deal_id?: string;
          customer_id?: string;
          quote_number?: string;
          status?: Database["public"]["Enums"]["quote_status"];
          valid_until?: string | null;
          subtotal?: number;
          tax?: number;
          total?: number;
          created_by?: string;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "quotes_deal_id_fkey";
            columns: ["deal_id"];
            isOneToOne: false;
            referencedRelation: "deals";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "quotes_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
        ];
      };
      quote_items: {
        Row: {
          id: string;
          quote_id: string;
          description: string;
          qty: number;
          unit_price: number;
          sort_order: number;
          line_total: number;
        };
        Insert: {
          id?: string;
          quote_id: string;
          description: string;
          qty?: number;
          unit_price?: number;
          sort_order?: number;
        };
        Update: {
          id?: string;
          quote_id?: string;
          description?: string;
          qty?: number;
          unit_price?: number;
          sort_order?: number;
        };
        Relationships: [
          {
            foreignKeyName: "quote_items_quote_id_fkey";
            columns: ["quote_id"];
            isOneToOne: false;
            referencedRelation: "quotes";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: Record<string, never>;
    Functions: {
      has_permission: {
        Args: { p_module: string; p_action: string };
        Returns: boolean;
      };
      has_any_module_permission: {
        Args: { p_module: string };
        Returns: boolean;
      };
      crm_convert_lead: {
        Args: { p_lead_id: string };
        Returns: string;
      };
    };
    Enums: {
      lead_status: "new" | "contacted" | "qualified" | "converted" | "lost";
      lead_type: "individual" | "company";
      lead_source: "facebook" | "instagram" | "meta" | "google" | "website" | "event" | "referral";
      deal_stage: "open" | "proposal" | "negotiation" | "won" | "lost";
      quote_status: "draft" | "sent" | "accepted" | "rejected" | "expired";
    };
    CompositeTypes: Record<string, never>;
  };
};
