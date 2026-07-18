-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL DEFAULT '',
    "profile_id" TEXT NOT NULL,
    "is_admin" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "profiles" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL DEFAULT '',
    "handle" TEXT NOT NULL DEFAULT '',
    "phone" TEXT NOT NULL DEFAULT '',
    "city" TEXT NOT NULL DEFAULT '',
    "lat" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "lng" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "avatar" TEXT NOT NULL DEFAULT '',
    "position" TEXT NOT NULL DEFAULT '',
    "height" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "games" INTEGER NOT NULL DEFAULT 0,
    "courts" INTEGER NOT NULL DEFAULT 0,
    "streak" INTEGER NOT NULL DEFAULT 0,
    "points" INTEGER NOT NULL DEFAULT 0,
    "rating" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "user_email" TEXT NOT NULL DEFAULT '',
    "birthdate" TIMESTAMP(3),
    "clan" TEXT NOT NULL DEFAULT '',
    "avatar_color" TEXT NOT NULL DEFAULT '',
    "clan_text_color" TEXT NOT NULL DEFAULT '',
    "clan_font" TEXT NOT NULL DEFAULT '',
    "avatar_frame" TEXT NOT NULL DEFAULT '',
    "equipped_title" TEXT NOT NULL DEFAULT '',
    "level" TEXT NOT NULL DEFAULT '',
    "unlocked_badges" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "play_seconds" INTEGER NOT NULL DEFAULT 0,
    "play_time_by_court" TEXT NOT NULL DEFAULT '',
    "share_status" BOOLEAN NOT NULL DEFAULT false,
    "share_court" BOOLEAN NOT NULL DEFAULT false,
    "share_time" BOOLEAN NOT NULL DEFAULT false,
    "playing" BOOLEAN NOT NULL DEFAULT false,
    "playing_court_id" TEXT NOT NULL DEFAULT '',
    "playing_since" TIMESTAMP(3),
    "last_played_court_id" TEXT NOT NULL DEFAULT '',
    "last_played_at" TIMESTAMP(3),
    "show_last_played" BOOLEAN NOT NULL DEFAULT false,
    "clan_joined_at" TIMESTAMP(3),
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "courts" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL DEFAULT '',
    "area" TEXT NOT NULL DEFAULT '',
    "dist" TEXT NOT NULL DEFAULT '',
    "img" TEXT NOT NULL DEFAULT '',
    "rating" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "reviews" INTEGER NOT NULL DEFAULT 0,
    "type" TEXT NOT NULL DEFAULT 'Exterior',
    "free" BOOLEAN NOT NULL DEFAULT false,
    "lit" BOOLEAN NOT NULL DEFAULT false,
    "hoops" INTEGER NOT NULL DEFAULT 1,
    "surface" TEXT NOT NULL DEFAULT 'Asfalto',
    "status" TEXT NOT NULL DEFAULT 'open',
    "players" INTEGER NOT NULL DEFAULT 0,
    "vibe" TEXT NOT NULL DEFAULT 'Casual',
    "hours" TEXT NOT NULL DEFAULT '',
    "open_time" TEXT NOT NULL DEFAULT '',
    "close_time" TEXT NOT NULL DEFAULT '',
    "badges" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "desc" TEXT NOT NULL DEFAULT '',
    "lat" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "lng" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "created_by" TEXT NOT NULL DEFAULT '',
    "created_by_clan" TEXT NOT NULL DEFAULT '',
    "created_by_email" TEXT NOT NULL DEFAULT '',
    "approval" TEXT NOT NULL DEFAULT '',
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "courts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "reviews" (
    "id" TEXT NOT NULL,
    "court_id" TEXT NOT NULL,
    "user_email" TEXT NOT NULL,
    "user_handle" TEXT NOT NULL DEFAULT '',
    "rating" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "comment" TEXT NOT NULL DEFAULT '',
    "created_at" TIMESTAMP(3),
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "reviews_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pickups" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "court_id" TEXT NOT NULL DEFAULT '',
    "created_by" TEXT NOT NULL DEFAULT '',
    "date_time" TIMESTAMP(3),
    "max_players" INTEGER NOT NULL DEFAULT 10,
    "vibe" TEXT NOT NULL DEFAULT 'Casual',
    "notes" TEXT NOT NULL DEFAULT '',
    "team_size" INTEGER NOT NULL DEFAULT 3,
    "team_a_name" TEXT NOT NULL DEFAULT 'Equipo A',
    "team_b_name" TEXT NOT NULL DEFAULT 'Equipo B',
    "team_a_color" TEXT NOT NULL DEFAULT '#FF6B1A',
    "team_b_color" TEXT NOT NULL DEFAULT '#3B82F6',
    "team_a_members" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "team_b_members" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "target_score" INTEGER NOT NULL DEFAULT 21,
    "accepted_members" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "declined_members" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "invite_code" TEXT NOT NULL DEFAULT '',
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "pickups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friends" (
    "id" TEXT NOT NULL,
    "owner_email" TEXT NOT NULL,
    "friend_handle" TEXT NOT NULL DEFAULT '',
    "friend_name" TEXT NOT NULL DEFAULT '',
    "friend_email" TEXT NOT NULL DEFAULT '',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "friends_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "matches" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "points" INTEGER NOT NULL DEFAULT 0,
    "ended_at" TIMESTAMP(3) NOT NULL,
    "court_id" TEXT NOT NULL DEFAULT '',
    "court_name" TEXT NOT NULL DEFAULT '',
    "result" TEXT NOT NULL DEFAULT '',
    "seconds" INTEGER NOT NULL DEFAULT 0,
    "clan" TEXT NOT NULL DEFAULT '',
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "matches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chats" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL DEFAULT '',
    "pickup_id" TEXT NOT NULL DEFAULT '',
    "created_by" TEXT NOT NULL DEFAULT '',
    "date" TIMESTAMP(3),
    "team_a_name" TEXT NOT NULL DEFAULT 'Equipo A',
    "team_b_name" TEXT NOT NULL DEFAULT 'Equipo B',
    "team_a_color" TEXT NOT NULL DEFAULT '#FF6B1A',
    "team_b_color" TEXT NOT NULL DEFAULT '#3B82F6',
    "last_message" TEXT NOT NULL DEFAULT '',
    "archived" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "chats_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "profiles_user_email_idx" ON "profiles"("user_email");

-- CreateIndex
CREATE INDEX "profiles_handle_idx" ON "profiles"("handle");

-- CreateIndex
CREATE INDEX "profiles_clan_idx" ON "profiles"("clan");

-- CreateIndex
CREATE INDEX "courts_approval_idx" ON "courts"("approval");

-- CreateIndex
CREATE INDEX "courts_created_by_email_idx" ON "courts"("created_by_email");

-- CreateIndex
CREATE INDEX "reviews_court_id_idx" ON "reviews"("court_id");

-- CreateIndex
CREATE INDEX "reviews_user_email_idx" ON "reviews"("user_email");

-- CreateIndex
CREATE INDEX "pickups_invite_code_idx" ON "pickups"("invite_code");

-- CreateIndex
CREATE INDEX "pickups_created_by_idx" ON "pickups"("created_by");

-- CreateIndex
CREATE INDEX "friends_owner_email_idx" ON "friends"("owner_email");

-- CreateIndex
CREATE INDEX "matches_email_idx" ON "matches"("email");

-- CreateIndex
CREATE INDEX "matches_court_id_ended_at_idx" ON "matches"("court_id", "ended_at");

-- CreateIndex
CREATE INDEX "matches_ended_at_idx" ON "matches"("ended_at");

-- CreateIndex
CREATE INDEX "matches_clan_idx" ON "matches"("clan");

-- CreateIndex
CREATE INDEX "chats_pickup_id_idx" ON "chats"("pickup_id");
