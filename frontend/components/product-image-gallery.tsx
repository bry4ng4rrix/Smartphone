'use client';

import { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Download, X, Copy, Check } from 'lucide-react';
import { toast } from 'sonner';
import Image from 'next/image';

interface ProductImage {
  id: string;
  image_url: string;
  qr_code_image?: string;
  size?: string;
  color_variant?: string;
  is_primary: boolean;
}

interface ProductImageGalleryProps {
  images: ProductImage[];
  productName: string;
  productSku: string;
  onDelete?: (imageId: string) => void;
  onSetPrimary?: (imageId: string) => void;
}

export function ProductImageGallery({
  images,
  productName,
  productSku,
  onDelete,
  onSetPrimary,
}: ProductImageGalleryProps) {
  const [selectedImage, setSelectedImage] = useState<ProductImage | null>(
    images.find((img) => img.is_primary) || images[0] || null
  );
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const handleCopyQRData = (imageId: string) => {
    const image = images.find((img) => img.id === imageId);
    if (image) {
      navigator.clipboard.writeText(
        JSON.stringify({
          sku: productSku,
          productName,
          imageId,
          timestamp: new Date().toISOString(),
        })
      );
      setCopiedId(imageId);
      setTimeout(() => setCopiedId(null), 2000);
      toast.success('QR code data copied to clipboard');
    }
  };

  const handleDownloadQRCode = (imageId: string) => {
    const image = images.find((img) => img.id === imageId);
    if (image?.qr_code_image) {
      const link = document.createElement('a');
      link.href = image.qr_code_image;
      link.download = `qrcode-${productSku}-${imageId}.png`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      toast.success('QR code downloaded');
    }
  };

  if (!images || images.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Galerie d&apos;images</CardTitle>
          <CardDescription>Aucune image ajoutée pour ce produit</CardDescription>
        </CardHeader>
        <CardContent className="text-center py-8 text-slate-500">
          Ajoutez des images pour visualiser les photos du produit et leurs codes QR
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Galerie d&apos;images et QR Codes</CardTitle>
        <CardDescription>
          {images.length} image(s) - {productName}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Main Image Display */}
        {selectedImage && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Product Image */}
            <div className="space-y-3">
              <div className="relative w-full aspect-square bg-slate-100 rounded-lg overflow-hidden border border-slate-200">
                <Image
                  src={selectedImage.image_url}
                  alt={`${productName} - ${selectedImage.color_variant || 'Variante'}`}
                  fill
                  className="object-cover"
                />
                {selectedImage.is_primary && (
                  <Badge className="absolute top-2 left-2 bg-blue-500">Principal</Badge>
                )}
              </div>
              <div className="text-sm text-slate-600">
                {selectedImage.size && <p>Taille: <span className="font-semibold">{selectedImage.size}</span></p>}
                {selectedImage.color_variant && <p>Couleur: <span className="font-semibold">{selectedImage.color_variant}</span></p>}
              </div>
            </div>

            {/* QR Code Display */}
            <div className="space-y-3">
              <div className="space-y-2">
                <h4 className="font-semibold text-sm">Code QR d&apos;identification</h4>
                {selectedImage.qr_code_image && (
                  <div className="bg-white p-4 border border-slate-200 rounded-lg inline-block">
                    <Image
                      src={selectedImage.qr_code_image}
                      alt="QR Code"
                      width={200}
                      height={200}
                      className="w-48 h-48"
                    />
                  </div>
                )}
              </div>

              {/* QR Code Actions */}
              <div className="flex gap-2 pt-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleDownloadQRCode(selectedImage.id)}
                  className="gap-2"
                >
                  <Download className="w-4 h-4" />
                  Télécharger
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleCopyQRData(selectedImage.id)}
                  className="gap-2"
                >
                  {copiedId === selectedImage.id ? (
                    <Check className="w-4 h-4" />
                  ) : (
                    <Copy className="w-4 h-4" />
                  )}
                  Copier données
                </Button>
              </div>

              {/* Image Details */}
              <div className="bg-slate-50 p-3 rounded border border-slate-200 text-xs space-y-1">
                <p><strong>SKU:</strong> {productSku}</p>
                <p><strong>ID Image:</strong> {selectedImage.id.slice(0, 8)}...</p>
                <p><strong>Créée:</strong> {new Date().toLocaleDateString()}</p>
              </div>
            </div>
          </div>
        )}

        {/* Thumbnail Gallery */}
        {images.length > 1 && (
          <div className="border-t pt-4">
            <h4 className="text-sm font-semibold mb-3">Toutes les images</h4>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
              {images.map((image) => (
                <div key={image.id} className="space-y-2">
                  <button
                    onClick={() => setSelectedImage(image)}
                    className={`relative w-full aspect-square rounded-lg overflow-hidden border-2 transition-all ${
                      selectedImage?.id === image.id
                        ? 'border-blue-500 ring-2 ring-blue-200'
                        : 'border-slate-200 hover:border-slate-300'
                    }`}
                  >
                    <Image
                      src={image.image_url}
                      alt={image.color_variant || 'Variante'}
                      fill
                      className="object-cover"
                    />
                  </button>
                  <div className="text-xs text-center">
                    {image.size && <p>{image.size}</p>}
                    {image.color_variant && <p className="text-slate-500">{image.color_variant}</p>}
                  </div>
                  <div className="flex gap-1">
                    {onSetPrimary && !image.is_primary && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => onSetPrimary(image.id)}
                        className="flex-1 text-xs"
                      >
                        Principal
                      </Button>
                    )}
                    {onDelete && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => onDelete(image.id)}
                        className="text-red-500 hover:text-red-700"
                      >
                        <X className="w-3 h-3" />
                      </Button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
