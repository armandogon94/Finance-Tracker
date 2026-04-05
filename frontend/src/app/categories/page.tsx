"use client";

import React, { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  TouchSensor,
  KeyboardSensor,
  useSensors,
  useSensor,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  GripVertical,
  Plus,
  Pencil,
  Archive,
  Check,
  X,
  Loader2,
  Grid3X3,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import Navigation from "@/components/Navigation";
import type { Category } from "@/types";

// ─── Helpers ────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
  });
}

const DEFAULT_COLORS = [
  "#3B82F6",
  "#10B981",
  "#F59E0B",
  "#EF4444",
  "#8B5CF6",
  "#EC4899",
  "#14B8A6",
  "#F97316",
  "#6366F1",
  "#84CC16",
];

const DEFAULT_ICONS = [
  "🍔", "🛒", "🚗", "🏠", "💊", "🎮", "✈️", "📚", "👕", "💡",
  "🎬", "🏋️", "☕", "🎁", "📱",
];

// ─── Sortable Row ───────────────────────────────────────────────────

interface SortableRowProps {
  category: Category;
  onEdit: (cat: Category) => void;
  onArchive: (id: string) => void;
}

function SortableCategoryRow({ category, onEdit, onArchive }: SortableRowProps) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: category.id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="flex items-center gap-3 px-4 py-3 bg-white"
    >
      {/* Drag handle */}
      <button
        className="touch-none text-gray-300 hover:text-gray-500 flex-shrink-0 cursor-grab active:cursor-grabbing"
        {...attributes}
        {...listeners}
      >
        <GripVertical className="h-4 w-4" />
      </button>

      {/* Color + icon */}
      <div
        className="h-9 w-9 rounded-full flex items-center justify-center text-base flex-shrink-0"
        style={{
          backgroundColor: (category.color ?? "#94A3B8") + "20",
        }}
      >
        {category.icon ?? (
          <span
            className="h-3 w-3 rounded-full"
            style={{ backgroundColor: category.color ?? "#94A3B8" }}
          />
        )}
      </div>

      {/* Name + budget */}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-gray-800 truncate">
          {category.name}
        </p>
        {category.monthly_budget != null && (
          <p className="text-xs text-gray-400">
            Budget: {fmt(category.monthly_budget)}/mo
          </p>
        )}
      </div>

      {/* Actions */}
      <button
        onClick={() => onEdit(category)}
        className="h-8 w-8 rounded-lg flex items-center justify-center text-gray-400
                   hover:bg-gray-50 hover:text-gray-600 transition-colors flex-shrink-0"
      >
        <Pencil className="h-3.5 w-3.5" />
      </button>
      <button
        onClick={() => onArchive(category.id)}
        className="h-8 w-8 rounded-lg flex items-center justify-center text-gray-400
                   hover:bg-red-50 hover:text-red-500 transition-colors flex-shrink-0"
      >
        <Archive className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

// ─── Inline Form ────────────────────────────────────────────────────

interface CategoryFormData {
  name: string;
  icon: string;
  color: string;
  monthly_budget: string;
}

function CategoryForm({
  initial,
  onSave,
  onCancel,
  saving,
}: {
  initial?: Partial<Category>;
  onSave: (data: CategoryFormData) => void;
  onCancel: () => void;
  saving: boolean;
}) {
  const [form, setForm] = useState<CategoryFormData>({
    name: initial?.name ?? "",
    icon: initial?.icon ?? "",
    color: initial?.color ?? DEFAULT_COLORS[0],
    monthly_budget: initial?.monthly_budget != null ? String(initial.monthly_budget) : "",
  });

  return (
    <div className="bg-white rounded-2xl shadow-sm p-4 space-y-3">
      {/* Name */}
      <div>
        <label className="block text-[11px] font-medium text-gray-500 mb-1">
          Name
        </label>
        <input
          type="text"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          placeholder="Category name"
          className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                     text-sm text-gray-800 focus:outline-none focus:ring-2
                     focus:ring-primary-500"
        />
      </div>

      {/* Icon picker */}
      <div>
        <label className="block text-[11px] font-medium text-gray-500 mb-1">
          Icon
        </label>
        <div className="flex flex-wrap gap-1.5">
          {DEFAULT_ICONS.map((icon) => (
            <button
              key={icon}
              type="button"
              onClick={() => setForm({ ...form, icon })}
              className={`h-9 w-9 rounded-lg flex items-center justify-center text-base
                         transition-colors border
                         ${
                           form.icon === icon
                             ? "border-primary-500 bg-primary-50"
                             : "border-gray-100 hover:bg-gray-50"
                         }`}
            >
              {icon}
            </button>
          ))}
        </div>
      </div>

      {/* Color picker */}
      <div>
        <label className="block text-[11px] font-medium text-gray-500 mb-1">
          Color
        </label>
        <div className="flex flex-wrap gap-2">
          {DEFAULT_COLORS.map((color) => (
            <button
              key={color}
              type="button"
              onClick={() => setForm({ ...form, color })}
              className={`h-8 w-8 rounded-full transition-all ${
                form.color === color
                  ? "ring-2 ring-offset-2 ring-primary-500 scale-110"
                  : "hover:scale-105"
              }`}
              style={{ backgroundColor: color }}
            />
          ))}
        </div>
      </div>

      {/* Monthly budget */}
      <div>
        <label className="block text-[11px] font-medium text-gray-500 mb-1">
          Monthly Budget (optional)
        </label>
        <input
          type="number"
          min="0"
          step="1"
          value={form.monthly_budget}
          onChange={(e) => setForm({ ...form, monthly_budget: e.target.value })}
          placeholder="0"
          className="w-full rounded-lg border border-gray-200 bg-gray-50 px-3 py-2
                     text-sm text-gray-800 focus:outline-none focus:ring-2
                     focus:ring-primary-500"
        />
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2 pt-1">
        <button
          onClick={() => onSave(form)}
          disabled={saving || !form.name.trim()}
          className="flex-1 flex items-center justify-center gap-2 rounded-xl bg-primary-500
                     py-2.5 text-sm font-semibold text-white
                     hover:bg-primary-600 transition-colors
                     disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {saving ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Check className="h-4 w-4" />
          )}
          Save
        </button>
        <button
          onClick={onCancel}
          className="h-10 w-10 rounded-xl border border-gray-200 flex items-center justify-center
                     text-gray-500 hover:bg-gray-50 transition-colors"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────

export default function CategoriesPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading: authLoading } = useAuth();

  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  // Form state
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);

  // ── DnD sensors ─────────────────────────────────────────────────

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, {
      activationConstraint: { delay: 200, tolerance: 5 },
    }),
    useSensor(KeyboardSensor)
  );

  // ── Fetch categories ────────────────────────────────────────────

  const fetchCategories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const res = await api.getCategories();
      const cats: Category[] = Array.isArray(res) ? res : [];
      setCategories(cats.filter((c) => c.is_active).sort((a, b) => a.sort_order - b.sort_order));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load categories");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    fetchCategories();
  }, [isAuthenticated, authLoading, router, fetchCategories]);

  // ── Drag end ────────────────────────────────────────────────────

  const handleDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = categories.findIndex((c) => c.id === active.id);
    const newIndex = categories.findIndex((c) => c.id === over.id);

    const reordered = arrayMove(categories, oldIndex, newIndex);
    setCategories(reordered);

    try {
      await api.reorderCategories(reordered.map((c) => c.id));
    } catch {
      // Revert on failure
      fetchCategories();
    }
  };

  // ── Create category ─────────────────────────────────────────────

  const handleCreate = async (data: CategoryFormData) => {
    setSaving(true);
    try {
      await api.createCategory({
        name: data.name.trim(),
        icon: data.icon || null,
        color: data.color,
        monthly_budget: data.monthly_budget ? parseFloat(data.monthly_budget) : null,
      });
      setShowAddForm(false);
      fetchCategories();
    } catch {
      // ignore
    } finally {
      setSaving(false);
    }
  };

  // ── Update category ─────────────────────────────────────────────

  const handleUpdate = async (data: CategoryFormData) => {
    if (!editingCategory) return;
    setSaving(true);
    try {
      // The API client doesn't have an updateCategory method explicitly,
      // so we assume a PUT/PATCH to /api/v1/categories/:id
      const token = localStorage.getItem("access_token");
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/categories/${editingCategory.id}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify({
            name: data.name.trim(),
            icon: data.icon || null,
            color: data.color,
            monthly_budget: data.monthly_budget ? parseFloat(data.monthly_budget) : null,
          }),
        }
      );
      if (!res.ok) throw new Error("Update failed");
      setEditingCategory(null);
      fetchCategories();
    } catch {
      // ignore
    } finally {
      setSaving(false);
    }
  };

  // ── Archive (soft delete) ───────────────────────────────────────

  const handleArchive = async (id: string) => {
    try {
      const token = localStorage.getItem("access_token");
      await fetch(
        `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8002"}/api/v1/categories/${id}`,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
          },
          body: JSON.stringify({ is_active: false }),
        }
      );
      setCategories((prev) => prev.filter((c) => c.id !== id));
    } catch {
      // ignore
    }
  };

  // ── Auth guard ────────────────────────────────────────────────────

  if (authLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  // ── Render ──────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <header className="bg-primary-500 text-white px-4 pt-6 pb-8 rounded-b-3xl">
        <div className="flex items-center gap-2 mb-1">
          <Grid3X3 className="h-5 w-5" />
          <h1 className="text-lg font-semibold">Categories</h1>
        </div>
        <p className="text-primary-50 text-sm">
          Drag to reorder, tap to edit
        </p>
      </header>

      <div className="px-4 -mt-4 space-y-4">
        {/* Category list */}
        {loading ? (
          <div className="flex justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-gray-300" />
          </div>
        ) : error ? (
          <div className="bg-white rounded-2xl shadow-sm p-6 text-center">
            <p className="text-sm text-red-500">{error}</p>
            <button
              onClick={fetchCategories}
              className="mt-3 text-sm text-primary-500 font-medium"
            >
              Try again
            </button>
          </div>
        ) : categories.length === 0 ? (
          <div className="bg-white rounded-2xl shadow-sm p-8 text-center">
            <Grid3X3 className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <p className="text-sm text-gray-500 font-medium">No categories yet</p>
            <p className="text-xs text-gray-400 mt-1">
              Add one below to start organizing your expenses
            </p>
          </div>
        ) : (
          <div className="bg-white rounded-2xl shadow-sm divide-y divide-gray-100 overflow-hidden">
            <DndContext
              sensors={sensors}
              collisionDetection={closestCenter}
              onDragEnd={handleDragEnd}
            >
              <SortableContext
                items={categories.map((c) => c.id)}
                strategy={verticalListSortingStrategy}
              >
                {categories.map((cat) =>
                  editingCategory?.id === cat.id ? (
                    <div key={cat.id} className="p-4">
                      <CategoryForm
                        initial={editingCategory}
                        onSave={handleUpdate}
                        onCancel={() => setEditingCategory(null)}
                        saving={saving}
                      />
                    </div>
                  ) : (
                    <SortableCategoryRow
                      key={cat.id}
                      category={cat}
                      onEdit={setEditingCategory}
                      onArchive={handleArchive}
                    />
                  )
                )}
              </SortableContext>
            </DndContext>
          </div>
        )}

        {/* Add category form / button */}
        {showAddForm ? (
          <CategoryForm
            onSave={handleCreate}
            onCancel={() => setShowAddForm(false)}
            saving={saving}
          />
        ) : (
          <button
            onClick={() => setShowAddForm(true)}
            className="w-full flex items-center justify-center gap-2 py-3 bg-white rounded-2xl
                       shadow-sm text-sm font-medium text-primary-500
                       hover:bg-primary-50 transition-colors"
          >
            <Plus className="h-4 w-4" />
            Add Category
          </button>
        )}
      </div>

      <Navigation />
    </div>
  );
}
