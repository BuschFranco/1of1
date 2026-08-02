ALTER TABLE "pickups" ADD COLUMN "rewards" JSONB NOT NULL DEFAULT '[]'::jsonb;
