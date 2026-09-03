'use client';

import { useCallback, useState } from 'react';
import { Upload, X, Check, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import Image from 'next/image';

interface ImageUploadProps {
  onImageSelect: (file: File) => void;
  maxSize?: number; // in MB
  acceptedFormats?: string[];
  onUploadStart?: () => void;
  onUploadEnd?: () => void;
}

export function ImageUpload({
  onImageSelect,
  maxSize = 5,
  acceptedFormats = ['image/jpeg', 'image/png', 'image/webp'],
  onUploadStart,
  onUploadEnd,
}: ImageUploadProps) {
  const [dragActive, setDragActive] = useState(false);
  const [preview, setPreview] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);

  const validateFile = (file: File): boolean => {
    setError(null);

    // Check size
    if (file.size > maxSize * 1024 * 1024) {
      setError(`Fichier trop volumineux (max ${maxSize}MB)`);
      toast.error(`Fichier trop volumineux (max ${maxSize}MB)`);
      return false;
    }

    // Check format
    if (!acceptedFormats.includes(file.type)) {
      setError('Format d\'image non supporté (JPEG, PNG, WebP)');
      toast.error('Format d\'image non supporté');
      return false;
    }

    return true;
  };

  const handleFile = useCallback(
    (file: File) => {
      if (!validateFile(file)) return;

      setSelectedFile(file);
      onImageSelect(file);

      // Create preview
      const reader = new FileReader();
      reader.onloadend = () => {
        setPreview(reader.result as string);
      };
      reader.readAsDataURL(file);

      toast.success(`Image "${file.name}" sélectionnée`);
    },
    [onImageSelect, maxSize, acceptedFormats]
  );

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === 'dragenter' || e.type === 'dragover') {
      setDragActive(true);
    } else if (e.type === 'dragleave') {
      setDragActive(false);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);

    const files = e.dataTransfer.files;
    if (files && files[0]) {
      handleFile(files[0]);
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files[0]) {
      handleFile(files[0]);
    }
  };

  const clearSelection = () => {
    setSelectedFile(null);
    setPreview(null);
    setError(null);
  };

  return (
    <Card>
      <CardContent className="pt-6">
        {preview ? (
          <div className="space-y-4">
            {/* Preview */}
            <div className="relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border-2 border-blue-200">
              <Image
                src={preview}
                alt="Preview"
                fill
                className="object-cover"
              />
            </div>

            {/* File Info */}
            <div className="bg-slate-50 p-3 rounded border border-slate-200 space-y-2">
              <div className="flex items-center gap-2">
                <Check className="w-4 h-4 text-green-500" />
                <span className="text-sm font-medium text-slate-700">Image sélectionnée</span>
              </div>
              <p className="text-xs text-slate-600 break-all">{selectedFile?.name}</p>
              <p className="text-xs text-slate-500">
                {selectedFile && (selectedFile.size / 1024 / 1024).toFixed(2)} MB
              </p>
            </div>

            {/* Clear Button */}
            <Button
              variant="outline"
              onClick={clearSelection}
              className="w-full gap-2"
            >
              <X className="w-4 h-4" />
              Changer l&apos;image
            </Button>
          </div>
        ) : (
          <div
            onDragEnter={handleDrag}
            onDragLeave={handleDrag}
            onDragOver={handleDrag}
            onDrop={handleDrop}
            className={`border-2 border-dashed rounded-lg p-8 text-center transition-all ${
              dragActive
                ? 'border-blue-500 bg-blue-50'
                : 'border-slate-300 bg-slate-50 hover:border-slate-400'
            }`}
          >
            <Upload className="w-12 h-12 text-slate-400 mx-auto mb-3" />
            <h3 className="font-semibold text-slate-900 mb-1">Déposer l&apos;image ici</h3>
            <p className="text-sm text-slate-600 mb-4">ou cliquez pour parcourir</p>

            {error && (
              <div className="flex items-center gap-2 bg-red-50 text-red-700 px-3 py-2 rounded text-sm mb-4">
                <AlertCircle className="w-4 h-4" />
                {error}
              </div>
            )}

            <input
              type="file"
              onChange={handleChange}
              accept={acceptedFormats.join(',')}
              className="hidden"
              id="image-input"
            />

            <label htmlFor="image-input">
              <Button asChild variant="outline" className="gap-2">
                <span>
                  <Upload className="w-4 h-4" />
                  Sélectionner une image
                </span>
              </Button>
            </label>

            <div className="mt-4 space-y-2 text-xs text-slate-500">
              <p>Format supporté: JPEG, PNG, WebP</p>
              <p>Taille maximum: {maxSize}MB</p>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
