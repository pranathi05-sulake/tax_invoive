/**
 * TaxInvoice AI - Client-Side Web Invoice OCR Engine & HTML5 Canvas Preprocessing Pipeline
 * 100% Browser Local Processing via Tesseract.js & Canvas API (No External Cloud APIs / No Uploads)
 */

async function processWebInvoiceOcr(imageSource) {
  try {
    console.log('[Web OCR Pipeline] Step 1: Loading invoice image source...');
    const img = await loadInvoiceImage(imageSource);
    
    console.log(`[Web OCR Pipeline] Step 2 & 3: Upscaling & Image Resizing (${img.width}x${img.height})...`);
    // Preprocessing Variant A: Grayscale + Histogram Stretch (Contrast Normalization) + High Contrast Binarization
    const canvasPreprocessed = preprocessInvoiceCanvas(img, { binarize: true });
    
    // Preprocessing Variant B: Grayscale + Smooth Contrast (for low-contrast scans)
    const canvasGrayscale = preprocessInvoiceCanvas(img, { binarize: false });

    console.log('[Web OCR Pipeline] Step 9: Running Tesseract.js multi-pass OCR on preprocessed variants...');
    
    if (typeof Tesseract === 'undefined') {
      throw new Error('Tesseract.js library not initialized in browser environment.');
    }

    // Execute Pass 1 on Variant A (Binarized High Contrast)
    const worker = await Tesseract.createWorker('eng');
    await worker.setParameters({
      tessedit_char_whitelist: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz./-:%&,()#@ ₹INRRs',
      tessedit_pageseg_mode: Tesseract.PSM.AUTO,
    });

    const resA = await worker.recognize(canvasPreprocessed);
    let bestResult = resA;

    // Execute Pass 2 if Pass 1 confidence is below 70%
    if (resA.data.confidence < 70) {
      console.log('[Web OCR Pipeline] Pass 1 confidence < 70%. Running Pass 2 on Grayscale Variant B...');
      const resB = await worker.recognize(canvasGrayscale);
      if (resB.data.confidence > resA.data.confidence) {
        bestResult = resB;
      }
    }

    await worker.terminate();

    const fullText = bestResult.data.text || '';
    const confidence = bestResult.data.confidence || 0.0;
    const lines = fullText
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.length > 0);

    console.log(`[Web OCR Pipeline] Step 12: OCR Complete. Extracted ${lines.length} lines with ${confidence.toFixed(1)}% confidence.`);

    return {
      success: true,
      fullText: fullText,
      lines: lines,
      confidence: confidence
    };
  } catch (err) {
    console.error('[Web OCR Pipeline] Exception during Web OCR execution:', err);
    return {
      success: false,
      error: err.toString(),
      fullText: '',
      lines: [],
      confidence: 0.0
    };
  }
}

function loadInvoiceImage(source) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'Anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Failed to load invoice image element in browser.'));
    
    if (typeof source === 'string') {
      img.src = source;
    } else if (source instanceof Blob || source instanceof File) {
      img.src = URL.createObjectURL(source);
    } else {
      reject(new Error('Unsupported image source type for Web OCR engine.'));
    }
  });
}

function preprocessInvoiceCanvas(img, options = { binarize: true }) {
  // Step 3: Resolution Upscaling (Target width 1800px - 2400px for optimal OCR DPI)
  let scale = 1.0;
  if (img.width < 1800) {
    scale = 1800 / img.width;
  } else if (img.width > 3000) {
    scale = 2400 / img.width;
  }

  const targetWidth = Math.round(img.width * scale);
  const targetHeight = Math.round(img.height * scale);

  const canvas = document.createElement('canvas');
  canvas.width = targetWidth;
  canvas.height = targetHeight;
  const ctx = canvas.getContext('2d');

  // Draw initial scaled image
  ctx.drawImage(img, 0, 0, targetWidth, targetHeight);

  // Read pixel data
  const imageData = ctx.getImageData(0, 0, targetWidth, targetHeight);
  const data = imageData.data;
  const len = data.length;

  // Step 5: Grayscale Conversion & Intensity Histogram Min/Max
  let minLum = 255;
  let maxLum = 0;
  const lum = new Uint8ClampedArray(len / 4);

  for (let i = 0, j = 0; i < len; i += 4, j++) {
    // Rec. 709 Luminance formula
    const y = Math.round(0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]);
    lum[j] = y;
    if (y < minLum) minLum = y;
    if (y > maxLum) maxLum = y;
  }

  // Step 6: Contrast Normalization / Histogram Stretching
  const range = maxLum - minLum || 1;
  for (let i = 0, j = 0; i < len; i += 4, j++) {
    const normalized = Math.round(((lum[j] - minLum) / range) * 255);
    
    let finalVal = normalized;
    // Step 8: Adaptive Thresholding / Binarization (if enabled)
    if (options.binarize) {
      finalVal = normalized < 145 ? 0 : 255;
    }

    data[i] = finalVal;     // R
    data[i + 1] = finalVal; // G
    data[i + 2] = finalVal; // B
    // Alpha remains unchanged
  }

  ctx.putImageData(imageData, 0, 0);
  return canvas;
}

window.processWebInvoiceOcr = processWebInvoiceOcr;
