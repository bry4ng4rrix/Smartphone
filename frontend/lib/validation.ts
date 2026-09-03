import { z } from 'zod';

// Product validation schema
export const productSchema = z.object({
  sku: z
    .string()
    .min(2, 'SKU minimum 2 caractères')
    .max(50, 'SKU maximum 50 caractères')
    .regex(/^[A-Z0-9\-_]+$/, 'SKU doit contenir seulement des majuscules, chiffres, tirets et underscores'),
  name: z
    .string()
    .min(3, 'Nom minimum 3 caractères')
    .max(200, 'Nom maximum 200 caractères'),
  description: z.string().max(500, 'Description maximum 500 caractères').optional(),
  category_id: z.string().uuid('Catégorie invalide').optional(),
  supplier_id: z.string().uuid('Fournisseur invalide').optional(),
  location: z.string().max(100, 'Localisation maximum 100 caractères').optional(),
  unit_price: z
    .number()
    .min(0, 'Prix doit être positif')
    .max(99999, 'Prix trop élevé'),
  color: z.string().max(50, 'Couleur maximum 50 caractères').optional(),
  material: z.string().max(100, 'Matière maximum 100 caractères').optional(),
  status: z.enum(['in_stock', 'low', 'out_of_stock']).optional(),
});

// Product size validation
export const productSizeSchema = z.object({
  size: z.enum(['S', 'M', 'XL', 'XXL'], {
    errorMap: () => ({ message: 'Taille invalide' }),
  }),
  quantity: z.number().min(0, 'Quantité doit être positive').int('Quantité doit être un entier'),
  reorder_level: z.number().min(0, 'Limite doit être positive').int('Limite doit être un entier'),
});

// Stock movement validation
export const stockMovementSchema = z.object({
  product_id: z.string().uuid('Produit invalide'),
  product_size_id: z.string().uuid('Taille invalide').optional(),
  size: z.enum(['S', 'M', 'XL', 'XXL']).optional(),
  type: z.enum(['entry', 'exit'], {
    errorMap: () => ({ message: 'Type de mouvement invalide' }),
  }),
  quantity: z
    .number()
    .min(1, 'Quantité minimum 1')
    .max(10000, 'Quantité maximum 10000')
    .int('Quantité doit être un entier'),
  notes: z.string().max(500, 'Notes maximum 500 caractères').optional(),
});

// Product image validation
export const productImageSchema = z.object({
  image_url: z.string().url('URL image invalide'),
  size: z.enum(['S', 'M', 'XL', 'XXL']).optional(),
  color_variant: z.string().max(50, 'Variante couleur maximum 50 caractères').optional(),
  is_primary: z.boolean().optional(),
});

// Supplier validation
export const supplierSchema = z.object({
  name: z.string().min(2, 'Nom minimum 2 caractères').max(200, 'Nom maximum 200 caractères'),
  email: z.string().email('Email invalide').optional(),
  phone: z.string().max(20, 'Téléphone maximum 20 caractères').optional(),
  address: z.string().max(500, 'Adresse maximum 500 caractères').optional(),
  city: z.string().max(100, 'Ville maximum 100 caractères').optional(),
  country: z.string().max(100, 'Pays maximum 100 caractères').optional(),
  payment_terms: z.string().max(200, 'Conditions maximum 200 caractères').optional(),
});

// Excel import validation
export const excelImportRowSchema = z.object({
  SKU: z.string().min(2, 'SKU requis'),
  'Nom du produit': z.string().min(3, 'Nom requis'),
  Catégorie: z.string().optional(),
  'Couleur': z.string().optional(),
  'Matière': z.string().optional(),
  'Prix unitaire': z.number().positive('Prix doit être positif'),
  'Taille S': z.number().nonnegative('Quantité non négative').optional(),
  'Taille M': z.number().nonnegative('Quantité non négative').optional(),
  'Taille XL': z.number().nonnegative('Quantité non négative').optional(),
  'Taille XXL': z.number().nonnegative('Quantité non négative').optional(),
});

// Utility functions
export function validateProduct(data: unknown) {
  return productSchema.safeParse(data);
}

export function validateProductSize(data: unknown) {
  return productSizeSchema.safeParse(data);
}

export function validateStockMovement(data: unknown) {
  return stockMovementSchema.safeParse(data);
}

export function validateProductImage(data: unknown) {
  return productImageSchema.safeParse(data);
}

export function validateSupplier(data: unknown) {
  return supplierSchema.safeParse(data);
}

export function validateExcelImportRow(data: unknown) {
  return excelImportRowSchema.safeParse(data);
}

// Format error messages
export function formatValidationErrors(errors: Record<string, any>): string[] {
  const messages: string[] = [];
  
  const flattenErrors = (obj: any, prefix = '') => {
    Object.keys(obj).forEach((key) => {
      const fullKey = prefix ? `${prefix}.${key}` : key;
      if (obj[key].message) {
        messages.push(`${fullKey}: ${obj[key].message}`);
      } else if (typeof obj[key] === 'object') {
        flattenErrors(obj[key], fullKey);
      }
    });
  };

  flattenErrors(errors);
  return messages;
}
