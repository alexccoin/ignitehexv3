-- Update brand domains to have 'brand' domain_type
UPDATE domain_marketplace_listings
SET domain_type = 'brand'
WHERE domain_name IN (
  'apple', 'google', 'microsoft', 'amazon', 'samsung', 'cocacola', 'toyota', 'mercedes', 'mcdonalds', 'disney',
  'nike', 'louisvuitton', 'tesla', 'meta', 'bmw', 'chanel', 'hermes', 'netflix', 'gucci', 'pepsi',
  'intel', 'cisco', 'oracle', 'sap', 'adidas', 'adobe', 'visa', 'mastercard', 'paypal', 'starbucks',
  'ikea', 'zara', 'uber', 'spotify', 'tiktok', 'linkedin', 'snapchat', 'whatsapp', 'instagram', 'youtube',
  'twitter', 'pinterest', 'reddit', 'airbnb', 'booking', 'alibaba', 'tencent', 'huawei', 'sony', 'nintendo',
  'honda', 'ford', 'audi', 'porsche', 'ferrari', 'lamborghini', 'rolex', 'cartier', 'tiffany', 'prada',
  'dior', 'burberry', 'armani', 'versace', 'fendi', 'coach', 'ralphlauren', 'calvinklein', 'levis', 'gap',
  'uniqlo', 'walmart', 'target', 'costco', 'kfc', 'burgerking', 'subway', 'dominos', 'pizzahut', 'dunkin',
  'redbull', 'monster', 'nestle', 'kraft', 'kelloggs', 'pfizer', 'johnson', 'loreal', 'gillette', 'colgate',
  'dove', 'nivea', 'pantene', 'olay', 'lancome', 'esteelauder', 'clinique', 'maybelline', 'revlon', 'sephora'
);