# Graph Report - .  (2026-07-14)

## Corpus Check
- Corpus is ~8,314 words - fits in a single context window. You may not need a graph.

## Summary
- 431 nodes · 805 edges · 23 communities (20 shown, 3 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 19 edges (avg confidence: 0.7)
- Token cost: 1,600 input · 3,200 output

## Community Hubs (Navigation)
- Auth: guards y decoradores
- Auth Service (login/Google)
- Courts Service y resenas
- Dependencias NPM
- Cliente Notion (builders/parsers)
- Courts Controller (+admin)
- Auth Controller y DTOs
- package.json
- README: contratos de la API
- Modulos NestJS (wiring)
- tsconfig
- Entidad Pickup + Service
- Modulo Friends
- Config de Notion
- Matches Controller
- Matches Service y ranking
- Refs de build (excludes)
- DTOs de Pickups
- nest-cli
- DTO de Match
- Schema Service (columnas)
- Chats Service
- DTO lote de Matches

## God Nodes (most connected - your core abstractions)
1. `NotionService` - 58 edges
2. `AuthUser` - 24 edges
3. `CurrentUser` - 22 edges
4. `compilerOptions` - 20 edges
5. `ProfilesService` - 17 edges
6. `Profile` - 15 edges
7. `AuthService` - 12 edges
8. `CourtsService` - 12 edges
9. `CourtsController` - 11 edges
10. `RegisterDto` - 10 edges

## Surprising Connections (you probably didn't know these)
- `bootstrap()` --indirect_call--> `AppModule`  [INFERRED]
  src/main.ts → src/app.module.ts

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **API por dominio protegida con JWT** — readme_me_endpoints, readme_profiles_endpoints, readme_courts_reviews_endpoints, readme_friends_endpoints, readme_pickups_chats_endpoints, readme_matches_endpoints [EXTRACTED 1.00]
- **Capa de acceso a Notion (cliente + schema + bases)** — readme_notion_service, readme_schema_service, readme_notion_databases [EXTRACTED 1.00]
- **Compatibilidad con la app existente (port de NotionService, mismo hash, espejo de schema)** — readme_notion_service, readme_schema_service, readme_password_hash_sha256, readme_app_notionservice, readme_app_ensurenotionschema [INFERRED 0.85]

## Communities (23 total, 3 thin omitted)

### Community 0 - "Auth: guards y decoradores"
Cohesion: 0.07
Nodes (34): AdminGuard, Injectable, CurrentUser, JwtAuthGuard, Injectable, AuthUser, ChatsController, CreateChatDto (+26 more)

### Community 1 - "Auth Service (login/Google)"
Cohesion: 0.09
Nodes (19): AuthService, Injectable, normalizeHandle(), validateHandleFormat(), AppUser, appUserFromNotion(), Profile, profileFromNotion() (+11 more)

### Community 2 - "Courts Service y resenas"
Cohesion: 0.11
Nodes (21): CourtsService, Injectable, FriendsService, Injectable, ALLOWED_BADGES, Court, COURT_APPROVAL, courtFromNotion() (+13 more)

### Community 3 - "Dependencias NPM"
Cohesion: 0.07
Nodes (29): axios, class-transformer, class-validator, google-auth-library, @nestjs/common, @nestjs/config, @nestjs/core, @nestjs/jwt (+21 more)

### Community 5 - "Courts Controller (+admin)"
Cohesion: 0.11
Nodes (17): IsNumber, CourtsController, Body, Controller, Delete, Get, Param, Post (+9 more)

### Community 6 - "Auth Controller y DTOs"
Cohesion: 0.15
Nodes (15): MinLength, AuthController, Body, Controller, Post, GoogleAuthDto, LoginDto, RegisterDto (+7 more)

### Community 7 - "package.json"
Cohesion: 0.08
Nodes (23): @nestjs/cli, @nestjs/schematics, description, devDependencies, @nestjs/cli, @nestjs/schematics, @types/express, @types/node (+15 more)

### Community 8 - "README: contratos de la API"
Cohesion: 0.11
Nodes (22): _ensureNotionSchema de la app (espejo del schema.service), NotionService de la app (origen del port), Endpoints públicos de Auth (/auth/login, /auth/register, /auth/google), Backend 1of1 (NestJS Gateway a Notion), Chats: solo metadata, mensajes locales en la app, Endpoints de canchas y reseñas (/courts, /reviews), DELETE /me (archivado de cuenta, requisito de tiendas), Fase A (gateway server-side) (+14 more)

### Community 9 - "Modulos NestJS (wiring)"
Cohesion: 0.12
Nodes (17): AppModule, Module, AuthModule, Module, ChatsModule, Module, CourtsModule, Module (+9 more)

### Community 10 - "tsconfig"
Cohesion: 0.10
Nodes (20): compilerOptions, allowSyntheticDefaultImports, baseUrl, declaration, emitDecoratorMetadata, esModuleInterop, experimentalDecorators, forceConsistentCasingInFileNames (+12 more)

### Community 11 - "Entidad Pickup + Service"
Cohesion: 0.26
Nodes (7): csv(), Pickup, pickupFromNotion(), pickupToNotionProps(), uncsv(), PickupsService, Injectable

### Community 12 - "Modulo Friends"
Cohesion: 0.18
Nodes (7): FriendsController, Body, Controller, Delete, Param, Post, UseGuards

### Community 13 - "Config de Notion"
Cohesion: 0.24
Nodes (6): Global, notionConfig(), NotionDbKey, NotionModule, Module, Props

### Community 14 - "Matches Controller"
Cohesion: 0.20
Nodes (7): MatchesController, Body, Controller, Get, Post, Query, UseGuards

### Community 15 - "Matches Service y ranking"
Cohesion: 0.22
Nodes (3): MatchesService, Injectable, matchFromNotion()

### Community 16 - "Refs de build (excludes)"
Cohesion: 0.25
Nodes (7): dist, node_modules, **/*spec.ts, test, ./tsconfig.json, exclude, extends

### Community 17 - "DTOs de Pickups"
Cohesion: 0.29
Nodes (8): CreatePickupDto, PickupFieldsDto, IsArray, IsInt, IsOptional, IsString, Max, Min

### Community 18 - "nest-cli"
Cohesion: 0.33
Nodes (5): collection, compilerOptions, deleteOutDir, $schema, sourceRoot

### Community 19 - "DTO de Match"
Cohesion: 0.33
Nodes (6): MatchItemDto, IsInt, IsISO8601, IsOptional, IsString, Min

### Community 22 - "DTO lote de Matches"
Cohesion: 0.50
Nodes (4): CreateMatchesDto, IsArray, Type, ValidateNested

## Knowledge Gaps
- **69 isolated node(s):** `$schema`, `collection`, `sourceRoot`, `deleteOutDir`, `name` (+64 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NotionService` connect `Cliente Notion (builders/parsers)` to `Auth: guards y decoradores`, `Auth Service (login/Google)`, `Courts Service y resenas`, `Auth Controller y DTOs`, `Entidad Pickup + Service`, `Config de Notion`, `Matches Service y ranking`, `Schema Service (columnas)`, `Chats Service`?**
  _High betweenness centrality (0.173) - this node is a cross-community bridge._
- **Why does `AuthUser` connect `Auth: guards y decoradores` to `Auth Service (login/Google)`, `Modulo Friends`, `Courts Controller (+admin)`, `Matches Controller`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Why does `CurrentUser` connect `Auth: guards y decoradores` to `Auth Service (login/Google)`, `Modulo Friends`, `Courts Controller (+admin)`, `Matches Controller`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **What connects `$schema`, `collection`, `sourceRoot` to the rest of the system?**
  _69 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Auth: guards y decoradores` be split into smaller, more focused modules?**
  _Cohesion score 0.06818181818181818 - nodes in this community are weakly interconnected._
- **Should `Auth Service (login/Google)` be split into smaller, more focused modules?**
  _Cohesion score 0.08974358974358974 - nodes in this community are weakly interconnected._
- **Should `Courts Service y resenas` be split into smaller, more focused modules?**
  _Cohesion score 0.11363636363636363 - nodes in this community are weakly interconnected._