-- Fix the private_seed_str_applications table to allow report-only applications
-- The investment_amount column should be nullable for report access applications

ALTER TABLE private_seed_str_applications 
ALTER COLUMN investment_amount DROP NOT NULL,
ALTER COLUMN investment_amount SET DEFAULT 0;