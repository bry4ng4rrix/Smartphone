import QRCode from 'qrcode';

interface QRCodeOptions {
  sku: string;
  productName: string;
  imageId: string;
  size?: string;
  colorVariant?: string;
}

export async function generateQRCode(options: QRCodeOptions): Promise<string> {
  const {
    sku,
    productName,
    imageId,
    size = 'S',
    colorVariant = 'Default',
  } = options;

  // Create a data string that encodes all important info
  const qrData = JSON.stringify({
    sku,
    productName,
    imageId,
    size,
    colorVariant,
    timestamp: new Date().toISOString(),
  });

  try {
    // Generate QR code as data URL (PNG)
    const qrCodeDataUrl = await QRCode.toDataURL(qrData, {
      errorCorrectionLevel: 'H',
      type: 'image/png',
      quality: 0.95,
      margin: 1,
      width: 300,
    });

    return qrCodeDataUrl;
  } catch (error) {
    console.error('[v0] Error generating QR code:', error);
    throw new Error('Failed to generate QR code');
  }
}

export async function generateSimpleQRCode(text: string): Promise<string> {
  try {
    return await QRCode.toDataURL(text, {
      errorCorrectionLevel: 'M',
      type: 'image/png',
      quality: 0.95,
      margin: 1,
      width: 200,
    });
  } catch (error) {
    console.error('[v0] Error generating simple QR code:', error);
    throw new Error('Failed to generate QR code');
  }
}

// Function to decode QR code data (in practice, this would be done by a QR scanner)
export function parseQRCodeData(qrData: string) {
  try {
    return JSON.parse(qrData);
  } catch {
    return { raw: qrData };
  }
}
