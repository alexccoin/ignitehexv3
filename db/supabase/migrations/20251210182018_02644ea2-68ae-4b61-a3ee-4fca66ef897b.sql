-- Insert top 100 global brand domains at $9,999 each
INSERT INTO domain_marketplace_listings (domain_name, domain_type, listing_type, seller_id, buy_now_price, currency, status, is_admin_listing, description)
SELECT 
  brand,
  'business',
  'buy_now',
  (SELECT id FROM auth.users LIMIT 1),
  9999,
  'USD',
  'active',
  true,
  'Premium global brand domain'
FROM (VALUES
  ('apple'), ('google'), ('microsoft'), ('amazon'), ('samsung'), ('cocacola'), ('toyota'), ('mercedes'), ('mcdonalds'), ('disney'),
  ('nike'), ('louisvuitton'), ('tesla'), ('meta'), ('bmw'), ('chanel'), ('hermes'), ('netflix'), ('gucci'), ('pepsi'),
  ('intel'), ('cisco'), ('oracle'), ('sap'), ('adidas'), ('adobe'), ('visa'), ('mastercard'), ('paypal'), ('starbucks'),
  ('ikea'), ('zara'), ('uber'), ('spotify'), ('tiktok'), ('linkedin'), ('snapchat'), ('whatsapp'), ('instagram'), ('youtube'),
  ('twitter'), ('pinterest'), ('reddit'), ('airbnb'), ('booking'), ('alibaba'), ('tencent'), ('huawei'), ('sony'), ('nintendo'),
  ('honda'), ('ford'), ('audi'), ('porsche'), ('ferrari'), ('lamborghini'), ('rolex'), ('cartier'), ('tiffany'), ('prada'),
  ('dior'), ('burberry'), ('armani'), ('versace'), ('fendi'), ('coach'), ('ralphlauren'), ('calvinklein'), ('levis'), ('gap'),
  ('uniqlo'), ('walmart'), ('target'), ('costco'), ('kfc'), ('burgerking'), ('subway'), ('dominos'), ('pizzahut'), ('dunkin'),
  ('redbull'), ('monster'), ('nestle'), ('kraft'), ('kelloggs'), ('pfizer'), ('johnson'), ('loreal'), ('gillette'), ('colgate'),
  ('dove'), ('nivea'), ('pantene'), ('olay'), ('lancome'), ('esteelauder'), ('clinique'), ('maybelline'), ('revlon'), ('sephora')
) AS brands(brand)
ON CONFLICT DO NOTHING;

-- Insert premium numeric domains str.1 to str.100 at $4,999 each
INSERT INTO domain_marketplace_listings (domain_name, domain_type, listing_type, seller_id, buy_now_price, currency, status, is_admin_listing, description)
SELECT 
  num::text,
  'premium',
  'buy_now',
  (SELECT id FROM auth.users LIMIT 1),
  4999,
  'USD',
  'active',
  true,
  'Ultra-rare single/double digit premium domain'
FROM generate_series(1, 100) AS num
ON CONFLICT DO NOTHING;