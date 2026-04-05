// ─── Core Models ────────────────────────────────────────────────────

export interface User {
  id: string;
  email: string;
  display_name: string | null;
  currency: string;
  timezone: string;
  is_active: boolean;
  is_superuser: boolean;
  created_at: string;
}

export interface Category {
  id: string;
  name: string;
  icon: string | null;
  color: string | null;
  sort_order: number;
  is_active: boolean;
  is_hidden: boolean;
  monthly_budget: number | null;
}

export interface Expense {
  id: string;
  category_id: string;
  amount: number;
  tax_amount: number | null;
  currency: string;
  description: string | null;
  merchant_name: string | null;
  expense_date: string;
  receipt_image_path: string | null;
  ocr_method: string | null;
  is_recurring: boolean;
  is_tax_deductible: boolean;
  tags: string[];
  created_at: string;
}

// ─── Debt Models ────────────────────────────────────────────────────

export interface CreditCard {
  id: string;
  card_name: string;
  last_four: string;
  current_balance: number;
  credit_limit: number;
  apr: number;
  minimum_payment: number;
  utilization: number;
  statement_day: number;
  due_day: number;
}

export interface Loan {
  id: string;
  loan_name: string;
  lender: string;
  loan_type: string;
  original_principal: number;
  current_balance: number;
  interest_rate: number;
  minimum_payment: number;
  progress_percent: number;
  due_day: number;
}

export interface DebtPayment {
  id: string;
  debt_type: "credit_card" | "loan";
  debt_id: string;
  amount: number;
  principal_portion: number;
  interest_portion: number;
  payment_date: string;
  is_snowflake: boolean;
}

// ─── Import / Parsing ───────────────────────────────────────────────

export interface ParsedTransaction {
  date: string;
  description: string;
  amount: number;
  is_expense: boolean;
  suggested_category_id: string | null;
  auto_labeled: boolean;
  possible_duplicate: boolean;
  include: boolean;
}

// ─── Strategy / Payoff ──────────────────────────────────────────────

export interface StrategyResult {
  strategy: "avalanche" | "snowball" | "hybrid" | "minimum_only";
  months_to_freedom: number;
  total_interest: number;
  payoff_order: string[];
}

// ─── Friend Debt ────────────────────────────────────────────────────

// ─── Chat Models ────────────────────────────────────────────────────

export interface ChatConversation {
  id: string;
  title: string | null;
  created_at: string;
  updated_at: string;
  last_message_preview: string | null;
}

export interface ChatMessage {
  id: string;
  conversation_id: string;
  role: "user" | "assistant";
  content: string;
  model_used: string | null;
  tokens_used: number | null;
  created_at: string;
}

// ─── Telegram Models ────────────────────────────────────────────────

export interface TelegramLinkCode {
  code: string;
  expires_at: string;
}

export interface TelegramStatus {
  linked: boolean;
  telegram_username: string | null;
  linked_at: string | null;
}

// ─── Friend Debt ────────────────────────────────────────────────────

export interface FriendDebtSummary {
  friend_accumulated: number;
  current_bank_balance: number;
  amount_owed: number;
  external_safety_net: number;
  true_shortfall: number;
  status: "ok" | "warning" | "critical";
}
