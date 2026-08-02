ALTER TABLE "pickups" ADD COLUMN "settings" JSONB NOT NULL DEFAULT '[]'::jsonb;
