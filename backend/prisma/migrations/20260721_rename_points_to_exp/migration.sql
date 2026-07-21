-- Renombra la columna de progresión "points" -> "exp" (nivel/ranking).
-- RENAME COLUMN preserva los datos existentes; no toca los índices (van sobre
-- otras columnas) ni las claves JSON de la API (que siguen llamándose "points").
ALTER TABLE "matches" RENAME COLUMN "points" TO "exp";
ALTER TABLE "profiles" RENAME COLUMN "points" TO "exp";
