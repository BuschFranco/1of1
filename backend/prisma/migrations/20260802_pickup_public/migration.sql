-- Agrega "is_public" a pickups: marca los pickup games abiertos, visibles en
-- el detalle de la cancha y con unión SIN código de invitación. El índice
-- compuesto es el que pide @@index([courtId, isPublic]) del schema.
ALTER TABLE "pickups" ADD COLUMN "is_public" BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX "pickups_court_id_is_public_idx" ON "pickups"("court_id", "is_public");
