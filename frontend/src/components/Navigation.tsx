"use client";

import React, { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Home,
  Receipt,
  Camera,
  TrendingDown,
  MessageCircle,
  MoreHorizontal,
  BarChart3,
  Grid3X3,
  Upload,
  FileText,
  Settings,
  Users,
  Shield,
  EyeOff,
  X,
} from "lucide-react";
import { useAuth } from "@/contexts/AuthContext";
import { useFeatureFlag } from "@/contexts/FeatureFlagsContext";

// ─── Types ──────────────────────────────────────────────────────────

interface NavItem {
  href: string;
  label: string;
  icon: React.ReactNode;
}

// ─── Component ──────────────────────────────────────────────────────

export default function Navigation() {
  const pathname = usePathname();
  const { user } = useAuth();
  const friendDebtEnabled = useFeatureFlag("friend_debt_calculator");
  const hiddenCategoriesEnabled = useFeatureFlag("hidden_categories");

  const [moreOpen, setMoreOpen] = useState(false);

  // ── Primary nav items ─────────────────────────────────────────────

  const primaryItems: NavItem[] = [
    { href: "/", label: "Home", icon: <Home className="h-5 w-5" /> },
    {
      href: "/expenses",
      label: "Expenses",
      icon: <Receipt className="h-5 w-5" />,
    },
    { href: "/scan", label: "Scan", icon: <Camera className="h-5 w-5" /> },
    {
      href: "/debt",
      label: "Debt",
      icon: <TrendingDown className="h-5 w-5" />,
    },
    {
      href: "/chat",
      label: "Chat",
      icon: <MessageCircle className="h-5 w-5" />,
    },
  ];

  // ── "More" menu items ─────────────────────────────────────────────

  const moreItems: NavItem[] = [
    {
      href: "/analytics",
      label: "Analytics",
      icon: <BarChart3 className="h-5 w-5" />,
    },
    {
      href: "/categories",
      label: "Categories",
      icon: <Grid3X3 className="h-5 w-5" />,
    },
    {
      href: "/import",
      label: "Import",
      icon: <Upload className="h-5 w-5" />,
    },
    {
      href: "/receipts",
      label: "Receipts",
      icon: <FileText className="h-5 w-5" />,
    },
    {
      href: "/settings",
      label: "Settings",
      icon: <Settings className="h-5 w-5" />,
    },
  ];

  // Conditionally add feature-flagged items
  if (friendDebtEnabled) {
    moreItems.push({
      href: "/friend-debt",
      label: "Friend Debt",
      icon: <Users className="h-5 w-5" />,
    });
  }

  if (hiddenCategoriesEnabled) {
    moreItems.push({
      href: "/hidden",
      label: "Hidden",
      icon: <EyeOff className="h-5 w-5" />,
    });
  }

  // Admin link for superusers
  if (user?.is_superuser) {
    moreItems.push({
      href: "/admin",
      label: "Admin",
      icon: <Shield className="h-5 w-5" />,
    });
  }

  // ── Active check ──────────────────────────────────────────────────

  const isActive = (href: string) => {
    if (href === "/") return pathname === "/";
    return pathname.startsWith(href);
  };

  const isMoreActive = moreItems.some((item) => isActive(item.href));

  return (
    <>
      {/* Slide-up "More" menu overlay */}
      {moreOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/30 backdrop-blur-sm"
          onClick={() => setMoreOpen(false)}
        >
          <div
            className="absolute bottom-16 left-0 right-0 bg-white rounded-t-3xl shadow-xl
                       max-h-[60vh] overflow-y-auto pb-safe"
            onClick={(e) => e.stopPropagation()}
            style={{
              animation: "slideUp 0.25s ease-out",
            }}
          >
            {/* Handle bar */}
            <div className="flex justify-center pt-3 pb-1">
              <div className="h-1 w-8 rounded-full bg-gray-300" />
            </div>

            {/* Close button */}
            <div className="flex justify-end px-4 pb-1">
              <button
                onClick={() => setMoreOpen(false)}
                className="h-8 w-8 rounded-full bg-gray-100 flex items-center justify-center
                           text-gray-500 hover:bg-gray-200 transition-colors"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {/* Grid of items */}
            <div className="grid grid-cols-3 gap-1 px-4 pb-6">
              {moreItems.map((item) => {
                const active = isActive(item.href);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    onClick={() => setMoreOpen(false)}
                    className={`flex flex-col items-center gap-1.5 py-3 px-2 rounded-xl
                               transition-colors
                               ${
                                 active
                                   ? "bg-primary-50 text-primary-500"
                                   : "text-gray-500 hover:bg-gray-50"
                               }`}
                  >
                    {item.icon}
                    <span className="text-[11px] font-medium">
                      {item.label}
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Bottom navigation bar */}
      <nav
        className="fixed bottom-0 left-0 right-0 z-30 bg-white border-t border-gray-100
                    pb-safe"
      >
        <div className="flex items-center justify-around max-w-lg mx-auto h-16">
          {primaryItems.map((item) => {
            const active = isActive(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex flex-col items-center gap-0.5 px-3 py-1.5 rounded-xl
                           transition-colors min-w-[56px]
                           ${
                             active
                               ? "text-primary-500"
                               : "text-gray-400 hover:text-gray-600"
                           }`}
              >
                {item.icon}
                <span
                  className={`text-[10px] font-medium ${
                    active ? "text-primary-500" : "text-gray-400"
                  }`}
                >
                  {item.label}
                </span>
              </Link>
            );
          })}

          {/* More button */}
          <button
            onClick={() => setMoreOpen((o) => !o)}
            className={`flex flex-col items-center gap-0.5 px-3 py-1.5 rounded-xl
                       transition-colors min-w-[56px]
                       ${
                         isMoreActive || moreOpen
                           ? "text-primary-500"
                           : "text-gray-400 hover:text-gray-600"
                       }`}
          >
            <MoreHorizontal className="h-5 w-5" />
            <span
              className={`text-[10px] font-medium ${
                isMoreActive || moreOpen
                  ? "text-primary-500"
                  : "text-gray-400"
              }`}
            >
              More
            </span>
          </button>
        </div>
      </nav>

      {/* Slide-up animation */}
      <style jsx>{`
        @keyframes slideUp {
          from {
            transform: translateY(100%);
          }
          to {
            transform: translateY(0);
          }
        }
      `}</style>
    </>
  );
}
