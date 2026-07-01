/**
 * IDs de las bases de Notion + versión de API. El token va por env
 * (NOTION_TOKEN) y vive solo en el servidor. Los IDs tienen default embebido
 * (no son secretos) y se pueden sobreescribir por env.
 */
export const notionConfig = () => ({
  token: process.env.NOTION_TOKEN ?? '',
  apiVersion: '2022-06-28',
  db: {
    users: process.env.NOTION_DB_USERS ?? '42c859d28f854f2cb004a8a68fd7b374',
    profiles:
      process.env.NOTION_DB_PROFILES ?? '38505f6959d44e968b537afe66459657',
    courts: process.env.NOTION_DB_COURTS ?? 'bda471e99e2f420887a0ca441ae68488',
    reviews:
      process.env.NOTION_DB_REVIEWS ?? 'a878279779174b7baecb13a8c1fbf9dc',
    pickups:
      process.env.NOTION_DB_PICKUPS ?? 'e4e76d276ec34012be0b36ba1f5ed133',
    friends:
      process.env.NOTION_DB_FRIENDS ?? 'a83f5d37fae54973ae106698c83545fa',
  },
});

export type NotionDbKey = keyof ReturnType<typeof notionConfig>['db'];
