-- CreateTable
CREATE TABLE "messages" (
    "id" TEXT NOT NULL,
    "pickup_id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "messages_pickup_id_created_at_idx" ON "messages"("pickup_id", "created_at");
