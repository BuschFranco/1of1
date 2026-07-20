-- CreateTable
CREATE TABLE "court_posts" (
    "id" TEXT NOT NULL,
    "court_id" TEXT NOT NULL,
    "user_email" TEXT NOT NULL,
    "user_handle" TEXT NOT NULL DEFAULT '',
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "court_posts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "court_posts_court_id_created_at_idx" ON "court_posts"("court_id", "created_at");

-- CreateIndex
CREATE INDEX "court_posts_user_email_court_id_created_at_idx" ON "court_posts"("user_email", "court_id", "created_at");

-- CreateTable
CREATE TABLE "post_comments" (
    "id" TEXT NOT NULL,
    "post_id" TEXT NOT NULL,
    "user_email" TEXT NOT NULL,
    "user_handle" TEXT NOT NULL DEFAULT '',
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "post_comments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "post_comments_post_id_created_at_idx" ON "post_comments"("post_id", "created_at");
