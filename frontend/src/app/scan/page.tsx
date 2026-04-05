"use client";

import React, { useState, useRef, useCallback, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  Camera,
  Loader2,
  Check,
  X,
  Upload,
  ArrowLeft,
  Clock,
  Trash2,
  ImageIcon,
} from "lucide-react";
import { api } from "@/lib/api";
import { useAuth } from "@/contexts/AuthContext";
import { compressImage } from "@/lib/image-compress";
import Navigation from "@/components/Navigation";

interface PendingReceipt {
  id: string;
  status: string;
  thumbnail_path: string | null;
  created_at: string;
  ocr_data: any | null;
  error_message: string | null;
}

type PageView = "camera" | "uploading" | "queued" | "queue-list";

export default function ScanPage() {
  const router = useRouter();
  const { user, loading: authLoading } = useAuth();

  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [view, setView] = useState<PageView>("camera");
  const [error, setError] = useState<string | null>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const [capturedImage, setCapturedImage] = useState<string | null>(null);
  const [pendingReceipts, setPendingReceipts] = useState<PendingReceipt[]>([]);
  const [queueCount, setQueueCount] = useState(0);

  // ── Auth guard ────────────────────────────────────────────────────
  useEffect(() => {
    if (!authLoading && !user) router.replace("/");
  }, [authLoading, user, router]);

  // ── Load pending receipts count on mount ──────────────────────────
  useEffect(() => {
    if (user) {
      api.getPendingReceipts().then((items) => {
        setPendingReceipts(items);
        setQueueCount(items.length);
      }).catch(() => {});
    }
  }, [user]);

  // ── Start webcam ──────────────────────────────────────────────────
  const startCamera = useCallback(async () => {
    try {
      setError(null);
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1920 }, height: { ideal: 1080 } },
        audio: false,
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.onloadedmetadata = () => setCameraReady(true);
      }
    } catch {
      setError("Camera access denied. You can upload a photo instead.");
    }
  }, []);

  const stopCamera = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setCameraReady(false);
  }, []);

  useEffect(() => {
    if (view === "camera") startCamera();
    return () => stopCamera();
  }, [view, startCamera, stopCamera]);

  // ── Capture from webcam → queue ───────────────────────────────────
  const capturePhoto = useCallback(async () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas) return;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(video, 0, 0);

    const dataUrl = canvas.toDataURL("image/jpeg", 0.85);
    setCapturedImage(dataUrl);
    stopCamera();
    await queueImage(dataUrl);
  }, [stopCamera]);

  // ── Upload file → queue ───────────────────────────────────────────
  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    stopCamera();

    const reader = new FileReader();
    reader.onload = async () => {
      setCapturedImage(reader.result as string);
      await queueImageFile(file);
    };
    reader.readAsDataURL(file);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  // ── Queue image (from webcam capture) ─────────────────────────────
  const queueImage = async (dataUrl: string) => {
    setView("uploading");
    setError(null);

    try {
      const res = await fetch(dataUrl);
      const blob = await res.blob();
      const file = new File([blob], "receipt.jpg", { type: "image/jpeg" });
      const compressed = await compressImage(file);
      const compressedFile = new File([compressed], "receipt.jpg", { type: "image/jpeg" });

      await api.queueReceipt(compressedFile);
      setQueueCount((c) => c + 1);
      setView("queued");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to save receipt");
      setView("camera");
      setCapturedImage(null);
    }
  };

  // ── Queue image (from file upload) ────────────────────────────────
  const queueImageFile = async (file: File) => {
    setView("uploading");
    setError(null);

    try {
      const compressed = await compressImage(file);
      const compressedFile = new File([compressed], file.name, { type: "image/jpeg" });

      await api.queueReceipt(compressedFile);
      setQueueCount((c) => c + 1);
      setView("queued");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to save receipt");
      setView("camera");
      setCapturedImage(null);
    }
  };

  // ── Scan another ──────────────────────────────────────────────────
  const scanAnother = () => {
    setView("camera");
    setCapturedImage(null);
    setError(null);
  };

  // ── Show queue list ───────────────────────────────────────────────
  const showQueueList = async () => {
    setView("queue-list");
    try {
      const items = await api.getPendingReceipts();
      setPendingReceipts(items);
      setQueueCount(items.length);
    } catch {
      setError("Failed to load pending receipts");
    }
  };

  // ── Delete pending receipt ────────────────────────────────────────
  const deletePending = async (id: string) => {
    try {
      await api.deletePendingReceipt(id);
      setPendingReceipts((prev) => prev.filter((r) => r.id !== id));
      setQueueCount((c) => Math.max(0, c - 1));
    } catch {
      setError("Failed to delete receipt");
    }
  };

  // ── Time ago helper ───────────────────────────────────────────────
  const timeAgo = (iso: string) => {
    const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 60) return "just now";
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
  };

  if (authLoading) return null;

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      {/* Header */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => router.back()} className="p-1 -ml-1 text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <h1 className="text-lg font-semibold text-gray-800">Scan Receipt</h1>
        </div>
        {/* Queue badge */}
        <button
          onClick={showQueueList}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-full
                     bg-amber-50 text-amber-700 text-sm font-medium
                     hover:bg-amber-100 transition-colors"
        >
          <Clock className="h-3.5 w-3.5" />
          {queueCount} pending
        </button>
      </div>

      <div className="max-w-lg mx-auto px-4 pt-4">
        {/* Error banner */}
        {error && (
          <div className="mb-4 rounded-xl bg-red-50 text-red-600 text-sm p-3 flex items-start gap-2">
            <X className="h-4 w-4 mt-0.5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* ── Camera view ─────────────────────────────────────────── */}
        {view === "camera" && (
          <div className="space-y-4">
            <div className="relative rounded-2xl overflow-hidden bg-black aspect-[3/4]">
              <video
                ref={videoRef}
                autoPlay
                playsInline
                muted
                className="w-full h-full object-cover"
              />
              {!cameraReady && !error && (
                <div className="absolute inset-0 flex items-center justify-center bg-gray-900">
                  <Loader2 className="h-8 w-8 animate-spin text-white/60" />
                </div>
              )}
              {cameraReady && (
                <div className="absolute inset-4 border-2 border-white/30 rounded-xl pointer-events-none" />
              )}
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex-1 h-12 rounded-xl border border-gray-200 bg-white text-gray-700
                           font-medium text-sm flex items-center justify-center gap-2
                           hover:bg-gray-50 active:scale-[0.98] transition-all"
              >
                <Upload className="h-4 w-4" />
                Upload Photo
              </button>
              <button
                onClick={capturePhoto}
                disabled={!cameraReady}
                className="flex-1 h-12 rounded-xl bg-blue-600 text-white font-medium text-sm
                           flex items-center justify-center gap-2
                           hover:bg-blue-700 active:scale-[0.98] transition-all
                           disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <Camera className="h-5 w-5" />
                Capture
              </button>
            </div>

            <p className="text-xs text-center text-gray-400">
              Receipt will be saved and analyzed later when OCR is available
            </p>

            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              onChange={handleFileUpload}
              className="hidden"
            />
          </div>
        )}

        {/* ── Uploading ───────────────────────────────────────────── */}
        {view === "uploading" && (
          <div className="space-y-4">
            {capturedImage && (
              <div className="rounded-2xl overflow-hidden aspect-[3/4]">
                <img src={capturedImage} alt="Captured receipt" className="w-full h-full object-cover" />
              </div>
            )}
            <div className="flex flex-col items-center gap-3 py-6">
              <Loader2 className="h-10 w-10 animate-spin text-blue-500" />
              <p className="text-sm font-medium text-gray-600">Saving receipt...</p>
            </div>
          </div>
        )}

        {/* ── Queued success ──────────────────────────────────────── */}
        {view === "queued" && (
          <div className="space-y-6">
            {capturedImage && (
              <div className="rounded-2xl overflow-hidden max-h-64">
                <img src={capturedImage} alt="Receipt" className="w-full object-cover" />
              </div>
            )}

            <div className="flex flex-col items-center gap-3 py-4">
              <div className="h-14 w-14 rounded-full bg-green-100 flex items-center justify-center">
                <Check className="h-7 w-7 text-green-600" />
              </div>
              <p className="text-base font-semibold text-gray-800">Receipt saved!</p>
              <p className="text-sm text-gray-500 text-center max-w-xs">
                Added to your pending queue. You&apos;ll be notified once it&apos;s analyzed.
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={showQueueList}
                className="flex-1 h-11 rounded-xl border border-gray-200 text-gray-600 font-medium
                           text-sm flex items-center justify-center gap-1.5
                           hover:bg-gray-50 active:scale-[0.98] transition-all"
              >
                <Clock className="h-4 w-4" />
                View Queue ({queueCount})
              </button>
              <button
                onClick={scanAnother}
                className="flex-1 h-11 rounded-xl bg-blue-600 text-white font-medium
                           text-sm flex items-center justify-center gap-1.5
                           hover:bg-blue-700 active:scale-[0.98] transition-all"
              >
                <Camera className="h-4 w-4" />
                Scan Another
              </button>
            </div>
          </div>
        )}

        {/* ── Queue list ──────────────────────────────────────────── */}
        {view === "queue-list" && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-semibold text-gray-800">
                Pending Receipts ({pendingReceipts.length})
              </h2>
              <button
                onClick={scanAnother}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg
                           bg-blue-600 text-white text-sm font-medium
                           hover:bg-blue-700 active:scale-[0.98] transition-all"
              >
                <Camera className="h-3.5 w-3.5" />
                Scan
              </button>
            </div>

            {pendingReceipts.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-12 text-gray-400">
                <ImageIcon className="h-12 w-12" />
                <p className="text-sm">No pending receipts</p>
                <button
                  onClick={scanAnother}
                  className="mt-2 text-sm text-blue-600 font-medium hover:underline"
                >
                  Scan your first receipt
                </button>
              </div>
            ) : (
              <div className="space-y-3">
                {pendingReceipts.map((receipt) => (
                  <div
                    key={receipt.id}
                    className="flex items-center gap-3 p-3 bg-white rounded-xl border border-gray-100"
                  >
                    {/* Thumbnail */}
                    <div className="h-16 w-16 rounded-lg bg-gray-100 overflow-hidden flex-shrink-0">
                      {receipt.thumbnail_path ? (
                        <img
                          src={`/api/v1/receipts/pending/${receipt.id}/image?thumbnail=true`}
                          alt="Receipt"
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center">
                          <ImageIcon className="h-6 w-6 text-gray-300" />
                        </div>
                      )}
                    </div>

                    {/* Info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span
                          className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${
                            receipt.status === "pending"
                              ? "bg-amber-50 text-amber-700"
                              : receipt.status === "analyzed"
                              ? "bg-green-50 text-green-700"
                              : "bg-red-50 text-red-700"
                          }`}
                        >
                          {receipt.status === "pending" && <Clock className="h-3 w-3" />}
                          {receipt.status === "analyzed" && <Check className="h-3 w-3" />}
                          {receipt.status === "failed" && <X className="h-3 w-3" />}
                          {receipt.status}
                        </span>
                      </div>
                      <p className="text-xs text-gray-400 mt-1">
                        {receipt.created_at ? timeAgo(receipt.created_at) : ""}
                      </p>
                      {receipt.error_message && (
                        <p className="text-xs text-red-500 mt-0.5 truncate">
                          {receipt.error_message}
                        </p>
                      )}
                    </div>

                    {/* Delete */}
                    <button
                      onClick={() => deletePending(receipt.id)}
                      className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-50
                                 rounded-lg transition-colors"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Hidden canvas for capture */}
      <canvas ref={canvasRef} className="hidden" />

      <Navigation />
    </div>
  );
}
