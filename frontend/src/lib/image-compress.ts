// ─── EXIF orientation ───────────────────────────────────────────────

/**
 * Reads the EXIF orientation tag (tag 0x0112) from the first 64 KB of
 * a JPEG file.  Returns 1 (normal) when no EXIF data is found.
 */
function readExifOrientation(buffer: ArrayBuffer): number {
  const view = new DataView(buffer);

  // JPEG starts with 0xFFD8
  if (view.getUint16(0) !== 0xffd8) return 1;

  let offset = 2;
  while (offset < view.byteLength - 2) {
    const marker = view.getUint16(offset);

    // APP1 marker -- EXIF data
    if (marker === 0xffe1) {
      const exifOffset = offset + 4; // skip marker + length

      // "Exif\0\0"
      if (view.getUint32(exifOffset) !== 0x45786966) return 1;

      const tiffOffset = exifOffset + 6;
      const littleEndian = view.getUint16(tiffOffset) === 0x4949;

      const ifdOffset =
        tiffOffset + view.getUint32(tiffOffset + 4, littleEndian);
      const numEntries = view.getUint16(ifdOffset, littleEndian);

      for (let i = 0; i < numEntries; i++) {
        const entryOffset = ifdOffset + 2 + i * 12;
        if (entryOffset + 12 > view.byteLength) break;

        const tag = view.getUint16(entryOffset, littleEndian);
        if (tag === 0x0112) {
          return view.getUint16(entryOffset + 8, littleEndian);
        }
      }
      return 1;
    }

    // Skip to next marker
    if ((marker & 0xff00) !== 0xff00) break;
    const segmentLength = view.getUint16(offset + 2);
    offset += 2 + segmentLength;
  }

  return 1;
}

// ─── Canvas rotation helper ─────────────────────────────────────────

/**
 * Draws an image onto a canvas, applying the EXIF orientation transform
 * so the result is always upright.
 */
function applyOrientation(
  canvas: HTMLCanvasElement,
  ctx: CanvasRenderingContext2D,
  img: HTMLImageElement,
  orientation: number,
): void {
  const w = img.naturalWidth;
  const h = img.naturalHeight;

  // Orientations 5-8 swap width/height.
  if (orientation >= 5 && orientation <= 8) {
    canvas.width = h;
    canvas.height = w;
  } else {
    canvas.width = w;
    canvas.height = h;
  }

  switch (orientation) {
    case 2:
      ctx.transform(-1, 0, 0, 1, w, 0);
      break;
    case 3:
      ctx.transform(-1, 0, 0, -1, w, h);
      break;
    case 4:
      ctx.transform(1, 0, 0, -1, 0, h);
      break;
    case 5:
      ctx.transform(0, 1, 1, 0, 0, 0);
      break;
    case 6:
      ctx.transform(0, 1, -1, 0, h, 0);
      break;
    case 7:
      ctx.transform(0, -1, -1, 0, h, w);
      break;
    case 8:
      ctx.transform(0, -1, 1, 0, 0, w);
      break;
    default:
      break; // orientation 1 -- no transform needed
  }

  ctx.drawImage(img, 0, 0);
}

// ─── Public API ─────────────────────────────────────────────────────

/**
 * Compress an image file to a JPEG blob that is smaller than
 * `maxSizeKB` (default 200 KB).
 *
 * Steps:
 *  1. Read EXIF orientation from the raw bytes.
 *  2. Draw the image onto a canvas with the orientation applied.
 *  3. Iteratively lower JPEG quality until the output is within budget.
 */
export async function compressImage(
  file: File,
  maxSizeKB: number = 200,
): Promise<Blob> {
  const arrayBuffer = await file.arrayBuffer();
  const orientation = readExifOrientation(arrayBuffer);

  // Decode image
  const img = await new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = (e) => reject(e);
    image.src = URL.createObjectURL(file);
  });

  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Could not get canvas 2D context");

  applyOrientation(canvas, ctx, img, orientation);

  // Scale down if the image is very large (max dimension 2048 px)
  const MAX_DIM = 2048;
  if (canvas.width > MAX_DIM || canvas.height > MAX_DIM) {
    const scale = MAX_DIM / Math.max(canvas.width, canvas.height);
    const scaledW = Math.round(canvas.width * scale);
    const scaledH = Math.round(canvas.height * scale);

    // Copy current canvas content to a temporary canvas
    const tmp = document.createElement("canvas");
    tmp.width = canvas.width;
    tmp.height = canvas.height;
    const tmpCtx = tmp.getContext("2d")!;
    tmpCtx.drawImage(canvas, 0, 0);

    canvas.width = scaledW;
    canvas.height = scaledH;
    ctx.drawImage(tmp, 0, 0, scaledW, scaledH);
  }

  // Iteratively reduce quality
  const maxBytes = maxSizeKB * 1024;
  let quality = 0.92;
  const QUALITY_STEP = 0.05;
  const MIN_QUALITY = 0.1;

  let blob = await canvasToBlob(canvas, quality);

  while (blob.size > maxBytes && quality > MIN_QUALITY) {
    quality -= QUALITY_STEP;
    blob = await canvasToBlob(canvas, Math.max(quality, MIN_QUALITY));
  }

  // Free the object URL created for the image element
  URL.revokeObjectURL(img.src);

  return blob;
}

function canvasToBlob(
  canvas: HTMLCanvasElement,
  quality: number,
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => {
        if (b) resolve(b);
        else reject(new Error("Canvas toBlob returned null"));
      },
      "image/jpeg",
      quality,
    );
  });
}

/**
 * Convert a Blob (or File) to a Base64-encoded data URL string.
 */
export function fileToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}
