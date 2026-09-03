import fs from 'fs';

let file = fs.readFileSync('app/(app)/products/page.tsx', 'utf-8');

// 1. Add expiration_date to form
file = file.replace(
`    reorder_level: '10',
    status: 'in_stock',
  });`,
`    reorder_level: '10',
    status: 'in_stock',
    expiration_date: '',
  });`
);

// 2. Add expiration_date to export
file = file.replace(
`      Statut: getStatusLabel(p.status),`,
`      Statut: getStatusLabel(p.status),
      'Date péremption': p.expiration_date || '',`
);

// 3. Add to productData in import
file = file.replace(
`              status: mapStatus(row.Statut || row.statut || row.status || 'in_stock'),
            };`,
`              status: mapStatus(row.Statut || row.statut || row.status || 'in_stock'),
              expiration_date: row['Date péremption'] || row.expiration_date || null,
            };`
);

// 4. Move Dialog
const dialogRegex = /<Dialog open={dialogOpen} onOpenChange={setDialogOpen}>[\s\S]*?<\/DialogContent>\s*<\/Dialog>/;
const match = file.match(dialogRegex);
if (match) {
  const dialogContent = match[0];
  // Remove from old place
  file = file.replace(dialogContent, '');
  
  // Update the dialog to add expiration_date in form
  let updatedDialog = dialogContent.replace(
`                <div className="space-y-2">
                  <Label htmlFor="status">Statut</Label>`,
`                <div className="space-y-2">
                  <Label htmlFor="expiration_date">Date de péremption</Label>
                  <Input
                    id="expiration_date"
                    type="date"
                    value={form.expiration_date}
                    onChange={(e) => setForm({ ...form, expiration_date: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="status">Statut</Label>`
  );
  
  // Also add expiration_date to insert logic
  updatedDialog = updatedDialog.replace(
`                            status: form.status,
                          })`,
`                            status: form.status,
                            expiration_date: form.expiration_date || null,
                          })`
  );
  
  updatedDialog = updatedDialog.replace(
`                            status: 'in_stock',
                          });`,
`                            status: 'in_stock',
                            expiration_date: '',
                          });`
  );

  // Find filters block and inject dialog
  const filtersTarget = `<Card>
        <CardContent className="pt-6">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">`;
  
  const filtersReplacement = `<Card>
        <CardContent className="pt-6">
          <div className="flex flex-col md:flex-row gap-4 items-start">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 flex-1 w-full">`;
            
  file = file.replace(filtersTarget, filtersReplacement);
  
  // Close the new flex wrapper after the grid, and add dialog
  file = file.replace(
`              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>`,
`              </SelectContent>
            </Select>
          </div>
          <div className="mt-4 md:mt-0">
            ${updatedDialog}
          </div>
        </div>
        </CardContent>
      </Card>`
  );
}

// 5. Add expiration_date to Edit Dialog
file = file.replace(
`                  <div className="space-y-2">
                    <Label htmlFor="edit-status">Statut</Label>`,
`                  <div className="space-y-2">
                    <Label htmlFor="edit-expiration">Date péremption</Label>
                    <Input
                      id="edit-expiration"
                      type="date"
                      value={editingProduct?.expiration_date || ''}
                      onChange={(e) => setEditingProduct({ ...editingProduct, expiration_date: e.target.value })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="edit-status">Statut</Label>`
);

file = file.replace(
`                              status: editingProduct.status,
                            })`,
`                              status: editingProduct.status,
                              expiration_date: editingProduct.expiration_date || null,
                            })`
);

// 6. Add expiration date column to table
file = file.replace(
`                    <TableHead>Statut</TableHead>
                    <TableHead className="w-10"></TableHead>`,
`                    <TableHead>Statut</TableHead>
                    <TableHead>Péremption</TableHead>
                    <TableHead className="w-10"></TableHead>`
);

file = file.replace(
`                        <TableCell>
                          <Badge className={getStatusColor(product.status)}>
                            {getStatusLabel(product.status)}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-1">`,
`                        <TableCell>
                          <Badge className={getStatusColor(product.status)}>
                            {getStatusLabel(product.status)}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs whitespace-nowrap">
                          {product.expiration_date ? new Date(product.expiration_date).toLocaleDateString() : '-'}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-1">`
);

fs.writeFileSync('app/(app)/products/page.tsx', file);
console.log('Modified products/page.tsx');
