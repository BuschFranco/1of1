-- Respaldo del historial de sesiones de juego y de las listas chicas del usuario.
-- Tablas nuevas e independientes: no se tocan `matches` ni `profiles`, asi que no
-- hay locks sobre tablas que ya tienen datos.

-- CreateTable
CREATE TABLE "play_sessions" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "ended_at_ms" BIGINT NOT NULL,
    "data" JSONB NOT NULL,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "play_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_data" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_data_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "play_sessions_email_ended_at_ms_key" ON "play_sessions"("email", "ended_at_ms");

-- CreateIndex
CREATE UNIQUE INDEX "user_data_email_kind_key" ON "user_data"("email", "kind");

-- Mismo patron que 20260718170000_enable_rls: el backend entra como dueño y se
-- salta RLS; sin politicas, la Data API de Supabase queda bloqueada.
ALTER TABLE "play_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "user_data" ENABLE ROW LEVEL SECURITY;
