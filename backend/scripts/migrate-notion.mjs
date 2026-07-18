// One-off: migra TODOS los datos de las bases de Notion a Postgres (Supabase),
// preservando los pageId de Notion como PK (los JWT y los ids cacheados en la
// app siguen válidos). Idempotente: upsert por id, se puede correr más de una
// vez. Notion no devuelve páginas archivadas, así que solo migra lo vivo.
//
// Uso:  node scripts/migrate-notion.mjs   (desde backend/, con .env completo:
//       NOTION_TOKEN + DATABASE_URL/DIRECT_URL)
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// ── .env manual (el script corre fuera de Nest) ─────────────────────────────
const root = dirname(dirname(fileURLToPath(import.meta.url)));
for (const line of readFileSync(join(root, '.env'), 'utf8').split(/\r?\n/)) {
  const i = line.indexOf('=');
  if (i > 0 && !line.trim().startsWith('#')) {
    const k = line.slice(0, i).trim();
    if (!(k in process.env)) process.env[k] = line.slice(i + 1).trim();
  }
}

const { PrismaClient } = await import('@prisma/client');
const prisma = new PrismaClient();

const TOKEN = process.env.NOTION_TOKEN;
if (!TOKEN) throw new Error('NOTION_TOKEN vacío en backend/.env');
const DB = {
  users: process.env.NOTION_DB_USERS ?? '42c859d28f854f2cb004a8a68fd7b374',
  profiles: process.env.NOTION_DB_PROFILES ?? '38505f6959d44e968b537afe66459657',
  courts: process.env.NOTION_DB_COURTS ?? 'bda471e99e2f420887a0ca441ae68488',
  reviews: process.env.NOTION_DB_REVIEWS ?? 'a878279779174b7baecb13a8c1fbf9dc',
  pickups: process.env.NOTION_DB_PICKUPS ?? 'e4e76d276ec34012be0b36ba1f5ed133',
  friends: process.env.NOTION_DB_FRIENDS ?? 'a83f5d37fae54973ae106698c83545fa',
  matches: process.env.NOTION_DB_MATCHES ?? '39952fcd7ece81408da4f331c0979c77',
  chats: process.env.NOTION_DB_CHATS ?? '',
};

const H = {
  Authorization: `Bearer ${TOKEN}`,
  'Notion-Version': '2022-06-28',
  'Content-Type': 'application/json',
};

async function queryAll(db) {
  const out = [];
  let cursor;
  do {
    const res = await fetch(`https://api.notion.com/v1/databases/${db}/query`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify({ page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) }),
    });
    const j = await res.json();
    if (!res.ok) throw new Error(`Notion query ${db}: ${JSON.stringify(j)}`);
    out.push(...j.results);
    cursor = j.has_more ? j.next_cursor : undefined;
  } while (cursor);
  return out;
}

// ── Parsers (mismas semánticas que el gateway) ──────────────────────────────
const title = (p, n) => (p?.[n]?.title ?? []).map((t) => t.plain_text).join('');
const text = (p, n) => (p?.[n]?.rich_text ?? []).map((t) => t.plain_text).join('');
const num = (p, n, d = 0) => p?.[n]?.number ?? d;
const int = (p, n, d = 0) => Math.round(p?.[n]?.number ?? d);
const check = (p, n) => p?.[n]?.checkbox ?? false;
const sel = (p, n, d = '') => p?.[n]?.select?.name ?? d;
const multi = (p, n) => (p?.[n]?.multi_select ?? []).map((o) => o.name);
const url = (p, n) => p?.[n]?.url ?? '';
const phone = (p, n) => p?.[n]?.phone_number ?? '';
const date = (p, n) => {
  const s = p?.[n]?.date?.start ?? null;
  if (!s) return null;
  const d = new Date(/(?:Z|[+-]\d{2}:?\d{2})$/i.test(s) ? s : `${s}Z`);
  return isNaN(d.getTime()) ? null : d;
};
const csv = (s) => (s.length === 0 ? [] : s.split(',').filter((e) => e.length > 0));

// ── Migración por tabla ─────────────────────────────────────────────────────
const counts = {};

async function migrate(name, dbId, mapRow, upsert) {
  if (!dbId) {
    counts[name] = 'omitida (DB no configurada)';
    return;
  }
  const pages = await queryAll(dbId);
  let n = 0;
  for (const page of pages) {
    const id = page.id?.toString();
    if (!id) continue;
    const data = mapRow(page.properties);
    await upsert(id, data);
    n++;
  }
  counts[name] = `${n}/${pages.length}`;
}

await migrate('users', DB.users, (p) => ({
  email: title(p, 'Email').trim().toLowerCase(),
  passwordHash: text(p, 'PasswordHash'),
  profileId: text(p, 'ProfileId'),
  isAdmin: check(p, 'Adm'),
  createdAt: date(p, 'CreatedAt') ?? new Date(),
}), (id, data) => prisma.user.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('profiles', DB.profiles, (p) => ({
  name: title(p, 'Name'),
  handle: text(p, 'Handle'),
  phone: phone(p, 'Phone'),
  city: text(p, 'City'),
  lat: num(p, 'Lat'),
  lng: num(p, 'Lng'),
  avatar: url(p, 'Avatar'),
  position: sel(p, 'Position'),
  height: num(p, 'Height'),
  games: int(p, 'Games'),
  courts: int(p, 'Courts'),
  streak: int(p, 'Streak'),
  points: int(p, 'Points'),
  rating: num(p, 'Rating'),
  userEmail: text(p, 'UserEmail').trim().toLowerCase(),
  birthdate: date(p, 'Birthdate'),
  clan: text(p, 'Clan'),
  avatarColor: text(p, 'AvatarColor'),
  clanTextColor: text(p, 'ClanTextColor'),
  clanFont: text(p, 'ClanFont'),
  avatarFrame: text(p, 'AvatarFrame'),
  title: text(p, 'EquippedTitle'),
  level: text(p, 'Level'),
  unlockedBadges: multi(p, 'UnlockedBadges'),
  playSeconds: int(p, 'PlaySeconds'),
  playTimeByCourt: text(p, 'PlayTimeByCourt'),
  shareStatus: check(p, 'ShareStatus'),
  shareCourt: check(p, 'ShareCourt'),
  shareTime: check(p, 'ShareTime'),
  playing: check(p, 'Playing'),
  playingCourtId: text(p, 'PlayingCourtId'),
  playingSince: date(p, 'PlayingSince'),
  lastPlayedCourtId: text(p, 'LastPlayedCourtId'),
  lastPlayedAt: date(p, 'LastPlayedAt'),
  showLastPlayed: check(p, 'ShowLastPlayed'),
  clanJoinedAt: date(p, 'ClanJoinedAt'),
}), (id, data) => prisma.profile.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('courts', DB.courts, (p) => ({
  name: title(p, 'Name'),
  area: text(p, 'Area'),
  dist: text(p, 'Dist'),
  img: url(p, 'Img'),
  rating: num(p, 'Rating'),
  reviews: int(p, 'Reviews'),
  type: sel(p, 'Type', 'Exterior'),
  free: check(p, 'Free'),
  lit: check(p, 'Lit'),
  hoops: int(p, 'Hoops', 1),
  surface: sel(p, 'Surface', 'Asfalto'),
  status: sel(p, 'Status', 'open'),
  players: int(p, 'Players'),
  vibe: sel(p, 'Vibe', 'Casual'),
  hours: text(p, 'Hours'),
  openTime: text(p, 'OpenTime'),
  closeTime: text(p, 'CloseTime'),
  badges: multi(p, 'Badges'),
  desc: text(p, 'Desc'),
  lat: num(p, 'Lat'),
  lng: num(p, 'Lng'),
  proposedBy: text(p, 'CreatedBy'),
  proposedByClan: text(p, 'CreatedByClan'),
  proposedByEmail: text(p, 'CreatedByEmail'),
  approval: sel(p, 'Aprobacion', ''),
}), (id, data) => prisma.court.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('reviews', DB.reviews, (p) => ({
  courtId: text(p, 'CourtId'),
  userEmail: text(p, 'UserEmail'),
  userHandle: text(p, 'UserHandle'),
  rating: num(p, 'Rating'),
  comment: text(p, 'Comment'),
  createdAt: date(p, 'CreatedAt'),
}), (id, data) => prisma.review.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('pickups', DB.pickups, (p) => ({
  title: title(p, 'Title'),
  courtId: text(p, 'CourtId'),
  createdBy: text(p, 'CreatedBy'),
  dateTime: date(p, 'DateTime'),
  maxPlayers: int(p, 'MaxPlayers', 10),
  vibe: sel(p, 'Vibe', 'Casual'),
  notes: text(p, 'Notes'),
  teamSize: int(p, 'TeamSize', 3),
  teamAName: text(p, 'TeamAName') || 'Equipo A',
  teamBName: text(p, 'TeamBName') || 'Equipo B',
  teamAColor: text(p, 'TeamAColor') || '#FF6B1A',
  teamBColor: text(p, 'TeamBColor') || '#3B82F6',
  teamAMembers: csv(text(p, 'TeamAMembers')),
  teamBMembers: csv(text(p, 'TeamBMembers')),
  targetScore: int(p, 'TargetScore', 21),
  acceptedMembers: csv(text(p, 'AcceptedMembers')),
  declinedMembers: csv(text(p, 'DeclinedMembers')),
  inviteCode: text(p, 'InviteCode'),
}), (id, data) => prisma.pickup.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('friends', DB.friends, (p) => ({
  ownerEmail: text(p, 'OwnerEmail'),
  friendHandle: text(p, 'FriendHandle'),
  friendName: text(p, 'FriendName'),
  friendEmail: text(p, 'FriendEmail'),
  createdAt: date(p, 'CreatedAt') ?? new Date(),
}), (id, data) => prisma.friend.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('matches', DB.matches, (p) => ({
  email: title(p, 'Email').trim().toLowerCase(),
  points: int(p, 'Points'),
  endedAt: date(p, 'EndedAt') ?? new Date(0),
  courtId: text(p, 'CourtId'),
  courtName: text(p, 'CourtName'),
  result: sel(p, 'Result', ''),
  seconds: int(p, 'Seconds'),
  clan: text(p, 'Clan').trim().toUpperCase(),
}), (id, data) => prisma.match.upsert({ where: { id }, create: { id, ...data }, update: data }));

await migrate('chats', DB.chats, (p) => ({
  name: title(p, 'Name'),
  pickupId: text(p, 'PickupId'),
  createdBy: text(p, 'CreatedBy'),
  date: date(p, 'Date'),
  teamAName: text(p, 'TeamAName') || 'Equipo A',
  teamBName: text(p, 'TeamBName') || 'Equipo B',
  teamAColor: text(p, 'TeamAColor') || '#FF6B1A',
  teamBColor: text(p, 'TeamBColor') || '#3B82F6',
  lastMessage: text(p, 'LastMessage'),
}), (id, data) => prisma.chat.upsert({ where: { id }, create: { id, ...data }, update: data }));

console.log('Migración completada (migrados/en Notion):');
for (const [k, v] of Object.entries(counts)) console.log(`  ${k}: ${v}`);
await prisma.$disconnect();
