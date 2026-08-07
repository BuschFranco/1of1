import type {
  Chat as DbChat,
  Court as DbCourt,
  Friend as DbFriend,
  Pickup as DbPickup,
  Profile as DbProfile,
  Review as DbReview,
} from '@prisma/client';

// Formato "wire" de la API: EXACTAMENTE las mismas formas JSON que devolvía el
// gateway de Notion (la app Flutter las parsea tal cual). Los mappers traducen
// filas de Prisma → wire. No cambiar nombres ni semántica de vacíos.

/** Regla heredada de fechas: la app manda ISO local SIN offset y Notion lo
 * trataba como UTC (+00:00). Mantener: sin offset ⇒ se interpreta como UTC.
 * '' / null ⇒ null. */
export function parseUtc(s: string | null | undefined): Date | null {
  const v = (s ?? '').trim();
  if (!v) return null;
  const hasOffset = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(v);
  const d = new Date(hasOffset ? v : `${v}Z`);
  return isNaN(d.getTime()) ? null : d;
}

/** Serializa una fecha al wire: ISO UTC (mismos primeros 16 chars que el
 * reloj de pared original). null ⇒ fallback. */
export function isoOr<T>(d: Date | null, fallback: T): string | T {
  return d ? d.toISOString() : fallback;
}

// ── Court ────────────────────────────────────────────────────────────────────

export const ALLOWED_BADGES = new Set<string>([
  'Iluminada', 'Gratis', 'Popular', 'Techada', 'Reserva', 'Torneos',
  'Vestuarios', 'Estacionamiento', 'Bebedero',
]);

export const COURT_APPROVAL = {
  pending: 'Sin definir',
  approved: 'Aprobado',
  rejected: 'Desaprobado',
} as const;

export interface Court {
  id: string;
  name: string;
  area: string;
  dist: string;
  img: string;
  rating: number;
  reviews: number;
  type: string;
  free: boolean;
  lit: boolean;
  hoops: number;
  surface: string;
  status: 'open' | 'busy' | 'closed';
  players: number;
  vibe: string;
  hours: string;
  openTime: string;
  closeTime: string;
  badges: string[];
  desc: string;
  lat: number;
  lng: number;
  proposedBy: string;
  proposedByClan: string;
  proposedByEmail: string;
  approval: string;
}

export function courtWire(c: DbCourt): Court {
  const status =
    c.status === 'busy' ? 'busy' : c.status === 'closed' ? 'closed' : 'open';
  return {
    id: c.id,
    name: c.name,
    area: c.area,
    dist: c.dist,
    img: c.img,
    rating: c.rating,
    reviews: c.reviews,
    type: c.type || 'Exterior',
    free: c.free,
    lit: c.lit,
    hoops: c.hoops,
    surface: c.surface || 'Asfalto',
    status,
    players: c.players,
    vibe: c.vibe || 'Casual',
    hours: c.hours,
    openTime: c.openTime,
    closeTime: c.closeTime,
    badges: c.badges,
    desc: c.desc,
    lat: c.lat,
    lng: c.lng,
    proposedBy: c.proposedBy,
    proposedByClan: c.proposedByClan,
    proposedByEmail: c.proposedByEmail,
    approval: c.approval,
  };
}

// ── Profile ──────────────────────────────────────────────────────────────────

export interface Profile {
  pageId: string;
  name: string;
  handle: string;
  phone: string;
  city: string;
  lat: number;
  lng: number;
  avatar: string;
  position: string;
  height: number;
  games: number;
  courts: number;
  streak: number;
  points: number;
  rating: number;
  userEmail: string;
  birthdate: string;
  clan: string;
  avatarColor: string;
  clanTextColor: string;
  clanFont: string;
  avatarFrame: string;
  title: string;
  level: string;
  unlockedBadges: string[];
  playSeconds: number;
  playTimeByCourt: string;
  shareStatus: boolean;
  shareCourt: boolean;
  shareTime: boolean;
  playing: boolean;
  playingCourtId: string;
  playingSince: string;
  lastPlayedCourtId: string;
  lastPlayedAt: string;
  showLastPlayed: boolean;
  clanJoinedAt: string;
}

export function profileWire(p: DbProfile): Profile {
  return {
    pageId: p.id,
    name: p.name,
    handle: p.handle,
    phone: p.phone,
    city: p.city,
    lat: p.lat,
    lng: p.lng,
    avatar: p.avatar,
    position: p.position,
    height: p.height,
    games: p.games,
    courts: p.courts,
    streak: p.streak,
    points: p.exp, // clave JSON "points" (compat app) desde la columna "exp"
    rating: p.rating,
    userEmail: p.userEmail,
    birthdate: isoOr(p.birthdate, ''),
    clan: p.clan,
    avatarColor: p.avatarColor,
    clanTextColor: p.clanTextColor,
    clanFont: p.clanFont,
    avatarFrame: p.avatarFrame,
    title: p.title,
    level: p.level,
    unlockedBadges: p.unlockedBadges,
    playSeconds: p.playSeconds,
    playTimeByCourt: p.playTimeByCourt,
    shareStatus: p.shareStatus,
    shareCourt: p.shareCourt,
    shareTime: p.shareTime,
    playing: p.playing,
    playingCourtId: p.playingCourtId,
    playingSince: isoOr(p.playingSince, ''),
    lastPlayedCourtId: p.lastPlayedCourtId,
    lastPlayedAt: isoOr(p.lastPlayedAt, ''),
    showLastPlayed: p.showLastPlayed,
    clanJoinedAt: isoOr(p.clanJoinedAt, ''),
  };
}

/** Patch de PATCH /me (Partial<Profile> del wire) → data de Prisma. Whitelist
 * explícita (como hacía profileToNotionProps): campos desconocidos se ignoran
 * y pageId/userEmail no son editables por acá. */
export function profilePatchToData(pr: Record<string, any>): Record<string, any> {
  const out: Record<string, any> = {};
  const str = (k: string, col = k) => {
    if (typeof pr[k] === 'string') out[col] = pr[k];
  };
  const num = (k: string) => {
    if (typeof pr[k] === 'number' && isFinite(pr[k])) out[k] = pr[k];
  };
  const int = (k: string, col = k) => {
    if (typeof pr[k] === 'number' && isFinite(pr[k])) out[col] = Math.round(pr[k]);
  };
  const bool = (k: string) => {
    if (typeof pr[k] === 'boolean') out[k] = pr[k];
  };
  const date = (k: string) => {
    if (pr[k] !== undefined) out[k] = parseUtc(pr[k]);
  };
  str('name');
  str('handle');
  str('phone');
  str('city');
  num('lat');
  num('lng');
  str('avatar');
  str('position');
  num('height');
  int('games');
  int('courts');
  int('streak');
  int('points', 'exp'); // wire "points" -> columna "exp"
  num('rating');
  date('birthdate');
  str('clan');
  str('avatarColor');
  str('clanTextColor');
  str('clanFont');
  str('avatarFrame');
  str('title');
  str('level');
  if (Array.isArray(pr.unlockedBadges)) {
    out.unlockedBadges = pr.unlockedBadges.filter(
      (b: any) => typeof b === 'string',
    );
  }
  int('playSeconds');
  str('playTimeByCourt');
  bool('shareStatus');
  bool('shareCourt');
  bool('shareTime');
  bool('playing');
  str('playingCourtId');
  date('playingSince');
  str('lastPlayedCourtId');
  date('lastPlayedAt');
  bool('showLastPlayed');
  date('clanJoinedAt');
  return out;
}

// ── Review ───────────────────────────────────────────────────────────────────

export interface Review {
  pageId: string;
  courtId: string;
  userEmail: string;
  userHandle: string;
  rating: number;
  comment: string;
  createdAt: string | null;
}

export function reviewWire(r: DbReview): Review {
  return {
    pageId: r.id,
    courtId: r.courtId,
    userEmail: r.userEmail,
    userHandle: r.userHandle,
    rating: r.rating,
    comment: r.comment,
    createdAt: isoOr(r.createdAt, null),
  };
}

// ── Pickup / Chat ────────────────────────────────────────────────────────────

/** Tipos de recompensa soportados. Extensible: agregar un string acá (y en el
 *  DTO de pickups) alcanza para que el resto del pipeline lo trate igual. */
export const PICKUP_REWARD_TYPES = [
  'monetaria',
  'indumentaria',
  'accesorios',
  'otro',
];

export interface PickupReward {
  /** 'monetaria' (amount) | 'indumentaria' | 'accesorios' (detail). */
  type: string;
  /** Solo monetaria: monto en pesos (ARS), entero > 0. */
  amount?: number;
  /** Solo indumentaria/accesorios: qué es (remera, muñequeras, …). */
  detail?: string;
}

/** Normaliza el JSON de la columna `rewards` (puede venir de clientes viejos
 * como null o con formas inválidas): devuelve solo rewards bien formados,
 * 1 por tipo (el primero gana). */
export function rewardsFromDb(raw: unknown): PickupReward[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: PickupReward[] = [];
  for (const r of raw) {
    if (!r || typeof r !== 'object') continue;
    const rec = r as Record<string, unknown>;
    const type = typeof rec.type === 'string' ? rec.type : '';
    if (!PICKUP_REWARD_TYPES.includes(type) || seen.has(type)) continue;
    const reward: PickupReward = { type };
    if (type === 'monetaria') {
      const amount = Number(rec.amount);
      if (!Number.isInteger(amount) || amount < 1) continue;
      reward.amount = amount;
    } else {
      const detail = typeof rec.detail === 'string' ? rec.detail.trim() : '';
      if (!detail) continue;
      reward.detail = detail.slice(0, 40);
    }
    seen.add(type);
    out.push(reward);
  }
  return out;
}

/** Tipos de configuración personalizada soportados. Extensible: agregar un
 * string acá (y en el DTO de pickups) alcanza para el resto del pipeline. */
export const PICKUP_SETTING_TYPES = [
  'edad',
  'altura',
  'peso',
  'nivel',
  'modalidad',
  'marca',
  'precio_entrada',
];

export interface PickupSetting {
  /** 'edad' (min años) | 'altura' (minCm) | 'peso' (maxKg) | 'nivel'
   *  (value: profesional|amateur) | 'modalidad' (value: competencia|casual) |
   *  'marca' (brand, useKit) | 'precio_entrada' (min = monto en ARS). */
  type: string;
  /** Edad mínima (años), altura mínima (cm), peso máximo (kg) o monto de
   *  entrada (ARS) para precio_entrada. */
  min?: number;
  minCm?: number;
  maxKg?: number;
  /** Solo nivel/modalidad: la variante elegida. */
  value?: string;
  /** Solo marca: nombre de la marca que arma el partido. */
  brand?: string;
  /** Solo marca: el partido se juega con la indumentaria de la marca. */
  useKit?: boolean;
}

/** Normaliza el JSON de la columna `settings` (mismo criterio que rewards):
 * solo configs bien formadas, 1 por tipo (el primero gana). Los requisitos
 * numéricos se clampen a rangos físicamente razonables. */
export function settingsFromDb(raw: unknown): PickupSetting[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: PickupSetting[] = [];
  for (const s of raw) {
    if (!s || typeof s !== 'object') continue;
    const rec = s as Record<string, unknown>;
    const type = typeof rec.type === 'string' ? rec.type : '';
    if (!PICKUP_SETTING_TYPES.includes(type) || seen.has(type)) continue;
    const int = (k: string): number | undefined => {
      const n = Number(rec[k]);
      if (!Number.isInteger(n)) return undefined;
      return n;
    };
    const setting: PickupSetting = { type };
    if (type === 'edad') {
      const min = int('min') ?? int('value');
      if (min === undefined || min < 1 || min > 120) continue;
      setting.min = min;
    } else if (type === 'altura') {
      const minCm = int('minCm') ?? int('min') ?? int('value');
      if (minCm === undefined || minCm < 100 || minCm > 260) continue;
      setting.minCm = minCm;
    } else if (type === 'peso') {
      const maxKg = int('maxKg') ?? int('max') ?? int('value');
      if (maxKg === undefined || maxKg < 35 || maxKg > 250) continue;
      setting.maxKg = maxKg;
    } else if (type === 'nivel' || type === 'modalidad') {
      const value =
        typeof rec.value === 'string' ? rec.value : '';
      const allowed =
        type === 'nivel'
          ? ['profesional', 'amateur']
          : ['competencia', 'casual'];
      if (!allowed.includes(value)) continue;
      setting.value = value;
    } else if (type === 'precio_entrada') {
      const min = int('min') ?? int('value');
      if (min === undefined || min < 1 || min > 100000) continue;
      setting.min = min;
    } else {
      // marca
      const brand =
        typeof rec.brand === 'string' ? rec.brand.trim() : '';
      if (!brand) continue;
      setting.brand = brand.slice(0, 40);
      setting.useKit = rec.useKit === true;
    }
    seen.add(type);
    out.push(setting);
  }
  return out;
}

export interface Pickup {
  pageId: string;
  title: string;
  courtId: string;
  createdBy: string;
  dateTime: string | null;
  maxPlayers: number;
  vibe: string;
  notes: string;
  teamSize: number;
  teamAName: string;
  teamBName: string;
  teamAColor: string;
  teamBColor: string;
  teamAMembers: string[];
  teamBMembers: string[];
  targetScore: number;
  acceptedMembers: string[];
  declinedMembers: string[];
  inviteCode: string;
  isPublic: boolean;
  rewards: PickupReward[];
  settings: PickupSetting[];
}

export function pickupWire(p: DbPickup): Pickup {
  return {
    pageId: p.id,
    title: p.title,
    courtId: p.courtId,
    createdBy: p.createdBy,
    dateTime: isoOr(p.dateTime, null),
    maxPlayers: p.maxPlayers,
    vibe: p.vibe || 'Casual',
    notes: p.notes,
    teamSize: p.teamSize,
    teamAName: p.teamAName || 'Equipo A',
    teamBName: p.teamBName || 'Equipo B',
    teamAColor: p.teamAColor || '#FF6B1A',
    teamBColor: p.teamBColor || '#3B82F6',
    teamAMembers: p.teamAMembers,
    teamBMembers: p.teamBMembers,
    targetScore: p.targetScore,
    acceptedMembers: p.acceptedMembers,
    declinedMembers: p.declinedMembers,
    inviteCode: p.inviteCode,
    isPublic: p.isPublic,
    rewards: rewardsFromDb(p.rewards),
    settings: settingsFromDb(p.settings),
  };
}

export interface CrewChat {
  pageId: string;
  name: string;
  pickupId: string;
  createdBy: string;
  date: string | null;
  teamAName: string;
  teamBName: string;
  teamAColor: string;
  teamBColor: string;
  lastMessage: string;
}

export function chatWire(c: DbChat): CrewChat {
  return {
    pageId: c.id,
    name: c.name,
    pickupId: c.pickupId,
    createdBy: c.createdBy,
    date: isoOr(c.date, null),
    teamAName: c.teamAName,
    teamBName: c.teamBName,
    teamAColor: c.teamAColor,
    teamBColor: c.teamBColor,
    lastMessage: c.lastMessage,
  };
}

// ── Friend ───────────────────────────────────────────────────────────────────

export interface Friend {
  pageId: string;
  ownerEmail: string;
  friendHandle: string;
  friendName: string;
  friendEmail: string;
}

export function friendWire(f: DbFriend): Friend {
  return {
    pageId: f.id,
    ownerEmail: f.ownerEmail,
    friendHandle: f.friendHandle,
    friendName: f.friendName,
    friendEmail: f.friendEmail,
  };
}

// ── Court Post / Comment ────────────────────────────────────────────────────

export interface CourtPost {
  pageId: string;
  courtId: string;
  userEmail: string;
  userHandle: string;
  content: string;
  createdAt: string | null;
  likeCount: number;
  likedByMe: boolean;
  comments?: PostComment[];
}

export function courtPostWire(
  p: { id: string; courtId: string; userEmail: string; userHandle: string; content: string; createdAt: Date | null },
  likeCount: number,
  likedByMe: boolean,
  comments?: PostComment[],
): CourtPost {
  return {
    pageId: p.id,
    courtId: p.courtId,
    userEmail: p.userEmail,
    userHandle: p.userHandle,
    content: p.content,
    createdAt: isoOr(p.createdAt, null),
    likeCount,
    likedByMe,
    ...(comments !== undefined ? { comments } : {}),
  };
}

export interface PostComment {
  pageId: string;
  postId: string;
  userEmail: string;
  userHandle: string;
  content: string;
  createdAt: string | null;
  likeCount: number;
  likedByMe: boolean;
}

export function postCommentWire(
  c: { id: string; postId: string; userEmail: string; userHandle: string; content: string; createdAt: Date | null },
  likeCount: number,
  likedByMe: boolean,
): PostComment {
  return {
    pageId: c.id,
    postId: c.postId,
    userEmail: c.userEmail,
    userHandle: c.userHandle,
    content: c.content,
    createdAt: isoOr(c.createdAt, null),
    likeCount,
    likedByMe,
  };
}
