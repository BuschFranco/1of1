import { NotionService as N } from './notion.service';

/** Badges válidos en la base Canchas (se filtran al escribir). */
export const ALLOWED_BADGES = new Set<string>([
  'Iluminada', 'Gratis', 'Popular', 'Techada', 'Reserva', 'Torneos',
  'Vestuarios', 'Estacionamiento', 'Bebedero',
]);

export const COURT_APPROVAL = {
  pending: 'Sin definir',
  approved: 'Aprobado',
  rejected: 'Desaprobado',
} as const;

// ── Court (base Canchas) ───────────────────────────────────────────────────

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
  /** Horario estructurado "HH:mm" (vacío = desconocido). */
  openTime: string;
  closeTime: string;
  badges: string[];
  desc: string;
  lat: number;
  lng: number;
  proposedBy: string;
  proposedByClan: string;
  proposedByEmail: string;
  /** Estado de moderación (select "Aprobacion"). Vacío si no está seteado. */
  approval: string;
}

function statusFromString(s: string): Court['status'] {
  return s === 'busy' ? 'busy' : s === 'closed' ? 'closed' : 'open';
}

export function courtFromNotion(page: any): Court {
  const p = page.properties;
  return {
    id: page.id?.toString() ?? '',
    name: N.readTitle(p, 'Name'),
    area: N.readText(p, 'Area'),
    dist: N.readText(p, 'Dist'),
    img: N.readUrl(p, 'Img'),
    rating: N.readNumber(p, 'Rating'),
    reviews: N.readInt(p, 'Reviews'),
    type: N.readSelect(p, 'Type', 'Exterior'),
    free: N.readCheckbox(p, 'Free'),
    lit: N.readCheckbox(p, 'Lit'),
    hoops: N.readInt(p, 'Hoops', 1),
    surface: N.readSelect(p, 'Surface', 'Asfalto'),
    status: statusFromString(N.readSelect(p, 'Status', 'open')),
    players: N.readInt(p, 'Players'),
    vibe: N.readSelect(p, 'Vibe', 'Casual'),
    hours: N.readText(p, 'Hours'),
    openTime: N.readText(p, 'OpenTime'),
    closeTime: N.readText(p, 'CloseTime'),
    badges: N.readMultiSelect(p, 'Badges'),
    desc: N.readText(p, 'Desc'),
    lat: N.readNumber(p, 'Lat'),
    lng: N.readNumber(p, 'Lng'),
    proposedBy: N.readText(p, 'CreatedBy'),
    proposedByClan: N.readText(p, 'CreatedByClan'),
    proposedByEmail: N.readText(p, 'CreatedByEmail'),
    approval: N.readSelect(p, 'Aprobacion', ''),
  };
}

/** Propuesta de cancha: entra como "Sin definir" (pendiente de moderación). */
export function courtToNotionProps(
  c: Partial<Court>,
  meta: { createdBy?: string; createdByClan?: string; createdByEmail?: string } = {},
): Record<string, any> {
  const out: Record<string, any> = {
    Name: N.title(c.name ?? ''),
    Area: N.richText(c.area ?? ''),
    Dist: N.richText(c.dist ?? ''),
    Img: N.url(c.img ?? ''),
    Rating: N.number(c.rating ?? 0),
    Reviews: N.number(c.reviews ?? 0),
    Type: N.select(c.type ?? 'Exterior'),
    Free: N.checkbox(c.free ?? false),
    Lit: N.checkbox(c.lit ?? false),
    Hoops: N.number(c.hoops ?? 1),
    Surface: N.select(c.surface ?? 'Asfalto'),
    Status: N.select(c.status ?? 'open'),
    Players: N.number(c.players ?? 0),
    Vibe: N.select(c.vibe ?? 'Casual'),
    Hours: N.richText(c.hours ?? ''),
    OpenTime: N.richText(c.openTime ?? ''),
    CloseTime: N.richText(c.closeTime ?? ''),
    Badges: N.multiSelect((c.badges ?? []).filter((b) => ALLOWED_BADGES.has(b))),
    Desc: N.richText(c.desc ?? ''),
    Lat: N.number(c.lat ?? 0),
    Lng: N.number(c.lng ?? 0),
    Aprobacion: N.select(COURT_APPROVAL.pending),
  };
  if (meta.createdBy !== undefined) out.CreatedBy = N.richText(meta.createdBy);
  if (meta.createdByClan !== undefined) out.CreatedByClan = N.richText(meta.createdByClan);
  if (meta.createdByEmail !== undefined) out.CreatedByEmail = N.richText(meta.createdByEmail);
  return out;
}

// ── Review (base Reseñas) ───────────────────────────────────────────────────

export interface Review {
  pageId: string;
  courtId: string;
  userEmail: string;
  userHandle: string;
  rating: number;
  comment: string;
  createdAt: string | null;
}

export function reviewFromNotion(page: any): Review {
  const p = page.properties;
  return {
    pageId: page.id?.toString() ?? '',
    courtId: N.readText(p, 'CourtId'),
    userEmail: N.readText(p, 'UserEmail'),
    userHandle: N.readText(p, 'UserHandle'),
    rating: N.readNumber(p, 'Rating'),
    comment: N.readText(p, 'Comment'),
    createdAt: N.readDate(p, 'CreatedAt'),
  };
}

export function reviewToNotionProps(r: Omit<Review, 'pageId'>): Record<string, any> {
  return {
    Title: N.title(`${r.userEmail} → ${r.courtId}`),
    CourtId: N.richText(r.courtId),
    UserEmail: N.richText(r.userEmail),
    UserHandle: N.richText(r.userHandle),
    Rating: N.number(r.rating),
    Comment: N.richText(r.comment),
    CreatedAt: N.date(r.createdAt ?? new Date().toISOString()),
  };
}

// ── Pickup (base Partidos) ──────────────────────────────────────────────────

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
}

/** Lista de emails guardada como CSV en un rich_text (mismo formato que la app). */
function csvToList(raw: string): string[] {
  return raw.length === 0 ? [] : raw.split(',').filter((e) => e.length > 0);
}

export function pickupFromNotion(page: any): Pickup {
  const p = page.properties;
  const aName = N.readText(p, 'TeamAName');
  const bName = N.readText(p, 'TeamBName');
  const aColor = N.readText(p, 'TeamAColor');
  const bColor = N.readText(p, 'TeamBColor');
  return {
    pageId: page.id?.toString() ?? '',
    title: N.readTitle(p, 'Title'),
    courtId: N.readText(p, 'CourtId'),
    createdBy: N.readText(p, 'CreatedBy'),
    dateTime: N.readDate(p, 'DateTime'),
    maxPlayers: N.readInt(p, 'MaxPlayers', 10),
    vibe: N.readSelect(p, 'Vibe', 'Casual'),
    notes: N.readText(p, 'Notes'),
    teamSize: N.readInt(p, 'TeamSize', 3),
    teamAName: aName.length ? aName : 'Equipo A',
    teamBName: bName.length ? bName : 'Equipo B',
    teamAColor: aColor.length ? aColor : '#FF6B1A',
    teamBColor: bColor.length ? bColor : '#3B82F6',
    teamAMembers: csvToList(N.readText(p, 'TeamAMembers')),
    teamBMembers: csvToList(N.readText(p, 'TeamBMembers')),
    targetScore: N.readInt(p, 'TargetScore', 21),
    acceptedMembers: csvToList(N.readText(p, 'AcceptedMembers')),
    declinedMembers: csvToList(N.readText(p, 'DeclinedMembers')),
    inviteCode: N.readText(p, 'InviteCode'),
  };
}

export function pickupToNotionProps(p: Omit<Pickup, 'pageId'>): Record<string, any> {
  return {
    Title: N.title(p.title),
    CourtId: N.richText(p.courtId),
    CreatedBy: N.richText(p.createdBy),
    DateTime: N.date(p.dateTime),
    MaxPlayers: N.number(p.maxPlayers),
    Vibe: N.select(p.vibe),
    Notes: N.richText(p.notes),
    TeamSize: N.number(p.teamSize),
    TeamAName: N.richText(p.teamAName),
    TeamBName: N.richText(p.teamBName),
    TeamAColor: N.richText(p.teamAColor),
    TeamBColor: N.richText(p.teamBColor),
    TeamAMembers: N.richText(p.teamAMembers.join(',')),
    TeamBMembers: N.richText(p.teamBMembers.join(',')),
    TargetScore: N.number(p.targetScore),
    AcceptedMembers: N.richText(p.acceptedMembers.join(',')),
    DeclinedMembers: N.richText(p.declinedMembers.join(',')),
    InviteCode: N.richText(p.inviteCode),
  };
}

// ── CrewChat (base Chats, opcional) ─────────────────────────────────────────

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

export function chatFromNotion(page: any): CrewChat {
  const p = page.properties;
  return {
    pageId: page.id?.toString() ?? '',
    name: N.readTitle(p, 'Name'),
    pickupId: N.readText(p, 'PickupId'),
    createdBy: N.readText(p, 'CreatedBy'),
    date: N.readDate(p, 'Date'),
    teamAName: N.readText(p, 'TeamAName'),
    teamBName: N.readText(p, 'TeamBName'),
    teamAColor: N.readText(p, 'TeamAColor'),
    teamBColor: N.readText(p, 'TeamBColor'),
    lastMessage: N.readText(p, 'LastMessage'),
  };
}

export function chatToNotionProps(c: Omit<CrewChat, 'pageId'>): Record<string, any> {
  return {
    Name: N.title(c.name),
    PickupId: N.richText(c.pickupId),
    CreatedBy: N.richText(c.createdBy),
    Date: N.date(c.date),
    TeamAName: N.richText(c.teamAName),
    TeamBName: N.richText(c.teamBName),
    TeamAColor: N.richText(c.teamAColor),
    TeamBColor: N.richText(c.teamBColor),
    LastMessage: N.richText(c.lastMessage),
  };
}

// ── Friend (base Amistades) ─────────────────────────────────────────────────

export interface Friend {
  pageId: string;
  ownerEmail: string;
  friendHandle: string;
  friendName: string;
  friendEmail: string;
}

export function friendFromNotion(page: any): Friend {
  const p = page.properties;
  return {
    pageId: page.id?.toString() ?? '',
    ownerEmail: N.readText(p, 'OwnerEmail'),
    friendHandle: N.readText(p, 'FriendHandle'),
    friendName: N.readText(p, 'FriendName'),
    friendEmail: N.readText(p, 'FriendEmail'),
  };
}

export function friendToNotionProps(f: Omit<Friend, 'pageId'>): Record<string, any> {
  return {
    Title: N.title(`${f.ownerEmail} → ${f.friendHandle}`),
    OwnerEmail: N.richText(f.ownerEmail),
    FriendHandle: N.richText(f.friendHandle),
    FriendName: N.richText(f.friendName),
    FriendEmail: N.richText(f.friendEmail),
    CreatedAt: N.date(new Date().toISOString()),
  };
}
