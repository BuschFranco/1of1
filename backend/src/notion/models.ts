import { NotionService as N } from './notion.service';

/** Credenciales (base Usuarios). */
export interface AppUser {
  pageId: string;
  email: string;
  passwordHash: string;
  profileId: string;
}

export function appUserFromNotion(page: any): AppUser {
  const p = page.properties;
  return {
    pageId: page.id?.toString() ?? '',
    email: N.readTitle(p, 'Email'),
    passwordHash: N.readText(p, 'PasswordHash'),
    profileId: N.readText(p, 'ProfileId'),
  };
}

/** Perfil público del jugador (base Perfiles). Espejo del modelo de la app. */
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
  /** Fecha (ISO) en que el usuario entró a su clan actual. Gate del chat de clan. */
  clanJoinedAt: string;
}

export function profileFromNotion(page: any): Profile {
  const p = page.properties;
  return {
    pageId: page.id?.toString() ?? '',
    name: N.readTitle(p, 'Name'),
    handle: N.readText(p, 'Handle'),
    phone: N.readPhone(p, 'Phone'),
    city: N.readText(p, 'City'),
    lat: N.readNumber(p, 'Lat'),
    lng: N.readNumber(p, 'Lng'),
    avatar: N.readUrl(p, 'Avatar'),
    position: N.readSelect(p, 'Position'),
    height: N.readNumber(p, 'Height'),
    games: N.readInt(p, 'Games'),
    courts: N.readInt(p, 'Courts'),
    streak: N.readInt(p, 'Streak'),
    points: N.readInt(p, 'Points'),
    rating: N.readNumber(p, 'Rating'),
    userEmail: N.readText(p, 'UserEmail'),
    clan: N.readText(p, 'Clan'),
    avatarColor: N.readText(p, 'AvatarColor'),
    clanTextColor: N.readText(p, 'ClanTextColor'),
    clanFont: N.readText(p, 'ClanFont'),
    avatarFrame: N.readText(p, 'AvatarFrame'),
    title: N.readText(p, 'EquippedTitle'),
    level: N.readText(p, 'Level'),
    unlockedBadges: N.readMultiSelect(p, 'UnlockedBadges'),
    playSeconds: N.readInt(p, 'PlaySeconds'),
    playTimeByCourt: N.readText(p, 'PlayTimeByCourt'),
    shareStatus: N.readCheckbox(p, 'ShareStatus'),
    shareCourt: N.readCheckbox(p, 'ShareCourt'),
    shareTime: N.readCheckbox(p, 'ShareTime'),
    playing: N.readCheckbox(p, 'Playing'),
    playingCourtId: N.readText(p, 'PlayingCourtId'),
    playingSince: N.readDate(p, 'PlayingSince') ?? '',
    lastPlayedCourtId: N.readText(p, 'LastPlayedCourtId'),
    lastPlayedAt: N.readDate(p, 'LastPlayedAt') ?? '',
    showLastPlayed: N.readCheckbox(p, 'ShowLastPlayed'),
    clanJoinedAt: N.readDate(p, 'ClanJoinedAt') ?? '',
  };
}

/** Propiedades Notion para crear/actualizar un perfil (subconjunto editable). */
export function profileToNotionProps(pr: Partial<Profile>): Record<string, any> {
  const out: Record<string, any> = {};
  const set = (k: string, v: any) => {
    if (v !== undefined) out[k] = v;
  };
  set('Name', pr.name !== undefined ? N.title(pr.name) : undefined);
  set('Handle', pr.handle !== undefined ? N.richText(pr.handle) : undefined);
  set('Phone', pr.phone !== undefined ? N.phone(pr.phone) : undefined);
  set('City', pr.city !== undefined ? N.richText(pr.city) : undefined);
  set('Lat', pr.lat !== undefined ? N.number(pr.lat) : undefined);
  set('Lng', pr.lng !== undefined ? N.number(pr.lng) : undefined);
  set('Avatar', pr.avatar !== undefined ? N.url(pr.avatar) : undefined);
  set('Position', pr.position !== undefined ? N.select(pr.position) : undefined);
  set('Height', pr.height !== undefined ? N.number(pr.height) : undefined);
  set('Games', pr.games !== undefined ? N.number(pr.games) : undefined);
  set('Courts', pr.courts !== undefined ? N.number(pr.courts) : undefined);
  set('Streak', pr.streak !== undefined ? N.number(pr.streak) : undefined);
  set('Points', pr.points !== undefined ? N.number(pr.points) : undefined);
  set('Rating', pr.rating !== undefined ? N.number(pr.rating) : undefined);
  set('UserEmail', pr.userEmail !== undefined ? N.richText(pr.userEmail) : undefined);
  set('Clan', pr.clan !== undefined ? N.richText(pr.clan) : undefined);
  set('AvatarColor', pr.avatarColor !== undefined ? N.richText(pr.avatarColor) : undefined);
  set('ClanTextColor', pr.clanTextColor !== undefined ? N.richText(pr.clanTextColor) : undefined);
  set('ClanFont', pr.clanFont !== undefined ? N.richText(pr.clanFont) : undefined);
  set('AvatarFrame', pr.avatarFrame !== undefined ? N.richText(pr.avatarFrame) : undefined);
  set('EquippedTitle', pr.title !== undefined ? N.richText(pr.title) : undefined);
  set('Level', pr.level !== undefined ? N.richText(pr.level) : undefined);
  set('UnlockedBadges', pr.unlockedBadges !== undefined ? N.multiSelect(pr.unlockedBadges) : undefined);
  set('PlaySeconds', pr.playSeconds !== undefined ? N.number(pr.playSeconds) : undefined);
  set('PlayTimeByCourt', pr.playTimeByCourt !== undefined ? N.richText(pr.playTimeByCourt) : undefined);
  set('ShareStatus', pr.shareStatus !== undefined ? N.checkbox(pr.shareStatus) : undefined);
  set('ShareCourt', pr.shareCourt !== undefined ? N.checkbox(pr.shareCourt) : undefined);
  set('ShareTime', pr.shareTime !== undefined ? N.checkbox(pr.shareTime) : undefined);
  set('Playing', pr.playing !== undefined ? N.checkbox(pr.playing) : undefined);
  set('PlayingCourtId', pr.playingCourtId !== undefined ? N.richText(pr.playingCourtId) : undefined);
  set('PlayingSince', pr.playingSince !== undefined ? N.date(pr.playingSince || null) : undefined);
  set('LastPlayedCourtId', pr.lastPlayedCourtId !== undefined ? N.richText(pr.lastPlayedCourtId) : undefined);
  set('LastPlayedAt', pr.lastPlayedAt !== undefined ? N.date(pr.lastPlayedAt || null) : undefined);
  set('ShowLastPlayed', pr.showLastPlayed !== undefined ? N.checkbox(pr.showLastPlayed) : undefined);
  set('ClanJoinedAt', pr.clanJoinedAt !== undefined ? N.date(pr.clanJoinedAt || null) : undefined);
  return out;
}
