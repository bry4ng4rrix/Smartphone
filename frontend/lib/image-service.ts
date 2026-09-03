// Image management service
// This handles image uploads, storage, and retrieval

export interface ImageUploadResult {
  url: string;
  filename: string;
  size: number;
}

/**
 * Upload an image file and return its URL
 * In production, this would upload to a service like Vercel Blob, AWS S3, etc.
 * For now, we'll convert to base64 data URL for demo purposes
 */
export async function uploadImage(file: File): Promise<ImageUploadResult> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();

    reader.onload = () => {
      try {
        const dataUrl = reader.result as string;
        const filename = `${Date.now()}-${file.name}`;

        resolve({
          url: dataUrl,
          filename,
          size: file.size,
        });
      } catch (error) {
        reject(new Error('Failed to process image'));
      }
    };

    reader.onerror = () => {
      reject(new Error('Failed to read image file'));
    };

    reader.readAsDataURL(file);
  });
}

/**
 * Upload image to Django backend (when integrated)
 * This is for future implementation with proper backend storage
 */
export async function uploadImageToBackend(
  file: File,
  productId: string
): Promise<ImageUploadResult> {
  try {
    const formData = new FormData();
    formData.append('image', file);
    formData.append('product_id', productId);

    const response = await fetch('/api/upload', {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      throw new Error('Failed to upload image');
    }

    const data = await response.json();
    
    return {
      url: data.url,
      filename: data.filename,
      size: file.size,
    };
  } catch (error) {
    console.error('[v0] Error uploading image to backend:', error);
    throw new Error('Failed to upload image to backend storage');
  }
}

/**
 * Get optimized image URL with size parameters
 */
export function getOptimizedImageUrl(
  url: string,
  width?: number,
  height?: number,
  quality?: number
): string {
  // If it's a data URL, return as-is (for local images)
  if (url.startsWith('data:')) {
    return url;
  }

  // For cloud-hosted images, you can add query parameters
  // Example for Supabase storage with transformation
  const params = new URLSearchParams();
  if (width) params.append('width', width.toString());
  if (height) params.append('height', height.toString());
  if (quality) params.append('quality', quality.toString());

  const separator = url.includes('?') ? '&' : '?';
  return params.toString() ? `${url}${separator}${params.toString()}` : url;
}

/**
 * Validate image file
 */
export function validateImageFile(
  file: File,
  maxSizeMB: number = 5,
  acceptedFormats: string[] = ['image/jpeg', 'image/png', 'image/webp']
): { valid: boolean; error?: string } {
  // Check file size
  if (file.size > maxSizeMB * 1024 * 1024) {
    return {
      valid: false,
      error: `File size exceeds ${maxSizeMB}MB limit`,
    };
  }

  // Check file type
  if (!acceptedFormats.includes(file.type)) {
    return {
      valid: false,
      error: 'File format not supported. Use JPEG, PNG, or WebP',
    };
  }

  return { valid: true };
}

/**
 * Get image dimensions
 */
export function getImageDimensions(imageUrl: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';

    img.onload = () => {
      resolve({
        width: img.width,
        height: img.height,
      });
    };

    img.onerror = () => {
      reject(new Error('Failed to load image'));
    };

    img.src = imageUrl;
  });
}

/**
 * Delete image from storage
 */
export async function deleteImage(imagePath: string): Promise<void> {
  try {
    const response = await fetch(`/api/upload?path=${imagePath}`, {
      method: 'DELETE',
    });

    if (!response.ok) {
      throw new Error('Failed to delete image');
    }
  } catch (error) {
    console.error('[v0] Error deleting image:', error);
    throw new Error('Failed to delete image');
  }
}

/**
 * Batch upload multiple images
 */
export async function batchUploadImages(
  files: File[],
  productId: string,
  onProgress?: (current: number, total: number) => void
): Promise<ImageUploadResult[]> {
  const results: ImageUploadResult[] = [];

  for (let i = 0; i < files.length; i++) {
    try {
      const result = await uploadImage(files[i]);
      results.push(result);
      onProgress?.(i + 1, files.length);
    } catch (error) {
      console.error(`[v0] Error uploading file ${i + 1}:`, error);
      // Continue with next file on error
    }
  }

  return results;
}
