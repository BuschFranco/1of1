# Graph Report - .  (2026-07-14)

## Corpus Check
- 24 files · ~150,831 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2606 nodes · 3679 edges · 172 communities (105 shown, 67 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 15 edges (avg confidence: 0.71)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Play Session Service
- Profile Screen
- Home Screen
- Models
- Session Alarms
- Add Court Screen
- Auth Screen
- Notion Service
- Session
- Courts
- Pickup Create Screen
- Main Shell
- Permissions Modal
- Achievements
- App Theme
- Pop Panel
- Crew Screen
- App Tab Bar
- Auth.service
- Pickup Chat Screen
- Notion.service
- App Permissions
- Cosmetics
- Notifications Service
- CLAUDE
- Main
- Match Detail Screen
- Profiles.controller
- Notifications Screen
- Dart Plugin Registrant
- Detail Screen
- Sync Coordinator
- Basketball Graffiti
- Profile Screen (2)
- Profile Screen (3)
- Notion.config
- Profiles.service
- List Screen
- Health Service
- Courts.controller
- Pickups Provider
- Entities
- Tsconfig
- Create Screen
- AppDelegate
- Friends.module
- App Fx
- Legal Content
- Courts Provider
- Geofence Service
- Reward Banner
- Court Marker Icon
- Reveal On Scroll
- Filters Screen
- Pressable Widget
- Detail Screen (2)
- Handle Setup Screen
- Court Image
- Slide Up On Scroll
- Pop Button
- Notion Config
- Legal Screen
- Package
- Under Construction
- Package (2)
- Onboarding Screen
- Blocked Provider
- Route Service
- Court Rating Service
- Favorites Provider
- Local Chat Service
- Location Service
- Session Alarms (2)
- Match Detail Screen (2)
- Friends Service
- Dart Build Result
- Dart Build Result (2)
- Dart Build Result (3)
- Dart Build Result (4)
- Dart Build Result (5)
- Detail Screen (3)
- Geocoding Service
- App Loader
- Tsconfig.build
- GeneratedPluginRegistrant
- Home Screen (2)
- App Loading State
- Pickups.module
- Models.freezed
- README
- GeneratedPluginRegistrant (2)
- Flutter Lldb Helper
- Status Dot
- README (2)
- Nest Cli
- Package (3)
- Pickups.module (2)
- Gradlew
- Package (4)
- Profiles.controller (2)
- Widget Test
- Build.gradle
- Pubspec
- Friends.module (2)
- CLAUDE (2)
- Flutter Export Environment
- Config.template
- Add Court Screen (2)
- Auth Screen (2)
- Auth Screen (3)
- Notion Service (2)
- Play Session Service (2)
- README (3)
- Package (5)
- Package (6)
- Package (7)
- Package (8)
- Package (9)
- Package (10)
- CLAUDE (3)
- Ic Launcher Foreground
- Ic Launcher Foreground (2)
- Ic Launcher Foreground (3)
- Ic Launcher Foreground (4)
- Ic Launcher
- Ic Launcher (2)
- Ic Launcher (3)
- Icon Foreground
- Icon Legacy
- Logo 1of1
- Logo 1of1 (2)
- Stdout
- Icon App 1024x1024@1x
- Icon App 20x20@1x
- Icon App 20x20@2x
- Icon App 20x20@3x
- Icon App 29x29@1x
- Icon App 29x29@2x
- Icon App 29x29@3x
- Icon App 40x40@1x
- Icon App 40x40@2x
- Icon App 40x40@3x
- Icon App 60x60@2x
- Icon App 60x60@3x
- Icon App 76x76@1x
- Icon App 76x76@2x
- Icon App 83.5x83.5@2x
- LaunchImage
- LaunchImage@2x
- LaunchImage@3x
- Models.freezed (2)
- Models.freezed (3)
- Models.freezed (4)
- Models.freezed (5)
- Models.freezed (6)
- Models.freezed (7)
- Pubspec (2)
- Pubspec (3)
- Pubspec (4)
- README (4)
- README (5)
- README (6)
- README (7)
- CLAUDE (4)
- CLAUDE (5)
- CLAUDE (6)
- CLAUDE (7)
- CLAUDE (8)
- CLAUDE (9)
- Concept Cluster

## God Nodes (most connected - your core abstractions)
1. `PlaySessionService` - 61 edges
2. `NotionService` - 47 edges
3. `Session` - 37 edges
4. `PickupsProvider` - 22 edges
5. `compilerOptions` - 20 edges
6. `CourtsProvider` - 17 edges
7. `ProfilesService` - 17 edges
8. `LocationService` - 17 edges
9. `AuthUser` - 15 edges
10. `ProfilesProvider` - 14 edges

## Surprising Connections (you probably didn't know these)
- `app/analysis_options.yaml` --conceptually_related_to--> `app/ (Flutter mobile app)`  [INFERRED]
  app/analysis_options.yaml → README.md
- `iOS LaunchImage Assets README` --conceptually_related_to--> `app/ (Flutter mobile app)`  [INFERRED]
  app/ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md → README.md
- `_save` --references--> `Session`  [EXTRACTED]
  app/lib/screens/handle_setup_screen.dart → app/lib/services/session.dart
- `build` --references--> `Session`  [EXTRACTED]
  app/lib/screens/handle_setup_screen.dart → app/lib/services/session.dart
- `initState` --references--> `PlaySessionService`  [EXTRACTED]
  app/lib/screens/notifications_screen.dart → app/lib/services/play_session_service.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Capa de abstracción Notion-as-backend** — lib_services_notion_service, lib_notion_notion_config, lib_data_models, app_claude_notion_backend_pattern [INFERRED 0.85]
- **Flujo de detección de partido en background** — lib_services_play_session_service, lib_services_session_alarms, app_claude_background_detection, app_pubspec_android_alarm_manager_plus [INFERRED 0.85]
- **Patrón de sincronización batch/dirty-flag a Notion** — lib_services_session, lib_services_play_session_service, app_claude_batch_sync, app_readme_batch_sync_rationale [INFERRED 0.85]

## Communities (172 total, 67 thin omitted)

### Community 0 - "Play Session Service"
Cohesion: 0.01
Nodes (216): _accrued, achievement, acknowledgeReward, addChatNotification, AppNotification, atMillis, _atSnoozedCourt, avgHr (+208 more)

### Community 1 - "Profile Screen"
Cohesion: 0.02
Nodes (113): _achievementsSection, activeTab, _add, _adding, _avatar, _background, _ClanBadgeDialog, _ClanBadgeDialogState (+105 more)

### Community 2 - "Home Screen"
Cohesion: 0.02
Nodes (110): _activeFilters, _applyFilters, _autoSelectedCourtId, _autoSelectNearCourt, _bottomSwipe, _cardBtn, _circles, _clearWaypoint (+102 more)

### Community 3 - "Models"
Cohesion: 0.03
Nodes (79): acceptedMembers, AppUser, comment, copyWith, courtId, createdAt, createdAtMillis, createdBy (+71 more)

### Community 4 - "Session Alarms"
Cohesion: 0.03
Nodes (77): a, activeKey, activeRaw, at, atMillis, best, bestDist, cancel (+69 more)

### Community 5 - "Add Court Screen"
Cohesion: 0.03
Nodes (69): _amenities, _amenitiesGrid, _amenityOptions, _areaCtrl, _areaEdited, _areaLookupBusy, build, _buildBadges (+61 more)

### Community 6 - "Auth Screen"
Cohesion: 0.03
Nodes (65): _acceptedTerms, action, _ageFrom, autofillHints, _birthdate, _birthdateField, _brand, build (+57 more)

### Community 7 - "Notion Service"
Cohesion: 0.04
Nodes (45): archivePage, _base, body, checkbox, createPage, date, deleteCourt, _ensureOk (+37 more)

### Community 8 - "Session"
Cohesion: 0.04
Nodes (44): _defaultTab, deleteAccount, _dirty, _email, flush, _flushing, googleSignIn, _hash (+36 more)

### Community 9 - "Courts"
Cohesion: 0.05
Nodes (43): approved, area, badges, closeTime, closeTod, Court, CourtApproval, desc (+35 more)

### Community 10 - "Pickup Create Screen"
Cohesion: 0.05
Nodes (43): _bgColor, build, _chip, _colorCircle, _colorRow, _courtDropdown, _courts, _courtSlots (+35 more)

### Community 11 - "Main Shell"
Cohesion: 0.05
Nodes (41): _bgForTab, _closeDetail, _closeFilters, createState, crewActivityNotifier, _detailCourtId, dispose, _filtersOpen (+33 more)

### Community 12 - "Permissions Modal"
Cohesion: 0.06
Nodes (40): _dwellBanner, _manualStartBanner, _playingBanner, _syncMockMode, _toggleMockMode, _askResult, _achievementRow, _editClanBadge (+32 more)

### Community 13 - "Achievements"
Cohesion: 0.05
Nodes (39): Achievement, achievementById, AchievementMetric, canchas, color, desc, entrenamientos, GameTitle (+31 more)

### Community 14 - "App Theme"
Cohesion: 0.05
Nodes (38): accent, accentAmber, accentDark, AppColors, AppShape, AppText, archivo, bg (+30 more)

### Community 15 - "Pop Panel"
Cohesion: 0.06
Nodes (35): active, AppChip, build, color, icon, label, onTap, background (+27 more)

### Community 16 - "Crew Screen"
Cohesion: 0.07
Nodes (34): _onTap, _badge, build, createState, CrewScreen, _CrewScreenState, _dateLabel, _emptyState (+26 more)

### Community 17 - "App Tab Bar"
Cohesion: 0.06
Nodes (34): active, AppTab, AppTabBar, _AppTabBarState, build, color, createState, crewHasActivity (+26 more)

### Community 18 - "Auth.service"
Cohesion: 0.10
Nodes (16): AuthController, Body, Controller, Post, AuthService, Injectable, LoginDto, RegisterDto (+8 more)

### Community 19 - "Pickup Chat Screen"
Cohesion: 0.07
Nodes (31): build, _respond, build, _busy, _chatPlaceholder, _clanInsignia, _confirmDelete, _confirmLeave (+23 more)

### Community 20 - "Notion.service"
Cohesion: 0.07
Nodes (6): pickupFromNotion(), pickupToNotionProps(), NotionService, Injectable, PickupsService, Injectable

### Community 21 - "App Permissions"
Cohesion: 0.07
Nodes (27): FlutterEngine, MainActivity, alarm, _alarmChannel, allGranted, AppPerm, background, battery (+19 more)

### Community 22 - "Cosmetics"
Cohesion: 0.07
Nodes (29): AvatarFrame, clanColor, clanFontStyle, clanTextColor, color, CosmeticColor, CosmeticFont, fam (+21 more)

### Community 23 - "Notifications Service"
Cohesion: 0.07
Nodes (29): cancelSession, _channel, init, instance, isEnabled, kDeclineAction, kPauseAction, kStartNowAction (+21 more)

### Community 24 - "CLAUDE"
Cohesion: 0.08
Nodes (29): Arquitectura en 30 segundos (Notion-Providers-UI), Detección de partido en background (alarmas + isolates), Patrón batch/dirty flag (stageStats + flush), Codegen freezed / json_serializable, Notion-as-swappable-backend pattern, Checklist de rebranding (nombre/colores/identidad), Definición de Temporada = semestre calendario, android_alarm_manager_plus ^4.0.4 (+21 more)

### Community 25 - "Main"
Cohesion: 0.07
Nodes (28): _authMode, _bootstrap, _bootstrapping, createState, _ensureNotionSchema, _goAuth, initState, _leaveOnboarding (+20 more)

### Community 26 - "Match Detail Screen"
Cohesion: 0.07
Nodes (28): _brandFooter, color, court, _courtButton, createState, ended, _fmtDate, _healthPill (+20 more)

### Community 27 - "Profiles.controller"
Cohesion: 0.16
Nodes (14): CurrentUser, JwtAuthGuard, Injectable, AuthUser, Get, MeController, ProfilesController, Body (+6 more)

### Community 28 - "Notifications Screen"
Cohesion: 0.08
Nodes (26): _ago, createState, _dateLabel, _empty, _iconBtn, initState, _inviteCard, _myEmail (+18 more)

### Community 29 - "Dart Plugin Registrant"
Cohesion: 0.07
Nodes (26): dart:io, package:battery_plus/battery_plus.dart, package:device_info_plus/device_info_plus.dart, package:file_selector_linux/file_selector_linux.dart, package:file_selector_macos/file_selector_macos.dart, package:file_selector_windows/file_selector_windows.dart, package:flutter_local_notifications/flutter_local_notifications.dart, package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart (+18 more)

### Community 30 - "Detail Screen"
Cohesion: 0.08
Nodes (25): _activityChart, _adminDeleteCourt, courtId, courts, createState, _deleteReview, _fetch, _future (+17 more)

### Community 31 - "Sync Coordinator"
Cohesion: 0.08
Nodes (25): _blocked, _courtNameById, _courts, dispose, _favorites, _flushPendingMatches, _geofencedCount, _onSessionChanged (+17 more)

### Community 32 - "Basketball Graffiti"
Cohesion: 0.08
Nodes (23): _MapCornerPainter, _GoogleLogoPainter, BasketballGraffiti, build, color, _drawBall, _drawHoop, _drawSpeedLines (+15 more)

### Community 33 - "Profile Screen (2)"
Cohesion: 0.13
Nodes (25): HomeScreen, _HomeScreenState, _LivePoints, _LivePointsState, ListScreen, _ListScreenState, _ColorPicker, _ColorPickerState (+17 more)

### Community 34 - "Profile Screen (3)"
Cohesion: 0.11
Nodes (25): _courtName, _courtName, _memberName, _profileFor, initState, _blockFriend, build, _favoriteCard (+17 more)

### Community 35 - "Notion.config"
Cohesion: 0.10
Nodes (19): AppModule, Module, AuthModule, Module, CourtsModule, Module, FriendsModule, Module (+11 more)

### Community 36 - "Profiles.service"
Cohesion: 0.18
Nodes (8): normalizeHandle(), validateHandleFormat(), AppUser, Profile, profileFromNotion(), profileToNotionProps(), ProfilesService, Injectable

### Community 37 - "List Screen"
Cohesion: 0.09
Nodes (22): court, courts, createState, _divider, enterDir, _introPlayed, _miniBadge, onSelectCourt (+14 more)

### Community 38 - "Health Service"
Cohesion: 0.09
Nodes (22): avgHr, calories, _configured, diagnose, distance, _ensureConfigured, hasData, hasPermissions (+14 more)

### Community 39 - "Courts.controller"
Cohesion: 0.12
Nodes (16): CourtsController, Body, Controller, Get, Param, Post, UseGuards, AddReviewDto (+8 more)

### Community 40 - "Pickups Provider"
Cohesion: 0.10
Nodes (20): accept, _archiveInNotion, byId, _cleanupExpired, clearForLogout, decline, deletePickup, _email (+12 more)

### Community 41 - "Entities"
Cohesion: 0.19
Nodes (12): CourtsService, Injectable, ALLOWED_BADGES, Court, COURT_APPROVAL, courtFromNotion(), courtToNotionProps(), Pickup (+4 more)

### Community 42 - "Tsconfig"
Cohesion: 0.10
Nodes (20): compilerOptions, allowSyntheticDefaultImports, baseUrl, declaration, emitDecoratorMetadata, esModuleInterop, experimentalDecorators, forceConsistentCasingInFileNames (+12 more)

### Community 43 - "Create Screen"
Cohesion: 0.11
Nodes (17): add_court_screen.dart, build, CreateScreen, _options, _wip, AppLogo, build, height (+9 more)

### Community 44 - "AppDelegate"
Cohesion: 0.11
Nodes (14): Any, AppDelegate, SceneDelegate, RunnerTests, Bool, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge (+6 more)

### Community 45 - "Friends.module"
Cohesion: 0.12
Nodes (12): FriendsController, FriendsService, Body, Controller, Injectable, Param, Post, UseGuards (+4 more)

### Community 46 - "App Fx"
Cohesion: 0.11
Nodes (18): accentGradient, AppFx, build, child, elevatedShadow, fill, glow, glowElevated (+10 more)

### Community 47 - "Legal Content"
Cohesion: 0.11
Nodes (17): APP, CAMBIOS, CONDUCTA, DERECHOS, kLegalLastUpdated, kPrivacyPolicy, kPrivacyPolicyUrl, kSupportEmail (+9 more)

### Community 48 - "Courts Provider"
Cohesion: 0.12
Nodes (16): addCourt, _courts, _fromNotion, load, _loading, _notion, all, _byEmail (+8 more)

### Community 49 - "Geofence Service"
Cohesion: 0.11
Nodes (17): clear, GeofenceService, ids, init, instance, kCourtGeofenceRadius, kGeofencePortName, _port (+9 more)

### Community 50 - "Reward Banner"
Cohesion: 0.11
Nodes (17): RewardEvent, _anim, build, _card, createState, _ctrl, _current, didUpdateWidget (+9 more)

### Community 51 - "Court Marker Icon"
Cohesion: 0.11
Nodes (17): buildCourtMarker, bytes, canvas, center, d, fill, glyph, h (+9 more)

### Community 52 - "Reveal On Scroll"
Cohesion: 0.11
Nodes (17): _attach, begin, build, child, createState, _ctrl, dispose, duration (+9 more)

### Community 53 - "Filters Screen"
Cohesion: 0.12
Nodes (16): _amenities, _bottomBar, build, _chipRow, createState, _distance, FiltersScreen, _FiltersScreenState (+8 more)

### Community 54 - "Pressable Widget"
Cohesion: 0.12
Nodes (16): _anim, build, child, createState, _ctrl, dispose, duration, initState (+8 more)

### Community 55 - "Detail Screen (2)"
Cohesion: 0.17
Nodes (16): _googleLogin, _submit, _openReviewDialog, _playingNow, _reportReview, _reviewCard, build, _CourtSwipeCard (+8 more)

### Community 56 - "Handle Setup Screen"
Cohesion: 0.13
Nodes (15): build, createState, _ctrl, dispose, _error, _errorBox, _handleField, HandleSetupScreen (+7 more)

### Community 57 - "Court Image"
Cohesion: 0.12
Nodes (14): borderRadius, build, CourtImage, height, _placeholder, url, width, build (+6 more)

### Community 58 - "Slide Up On Scroll"
Cohesion: 0.14
Nodes (14): Animation, build, child, createState, _ctrl, dispose, duration, _fadeAnim (+6 more)

### Community 59 - "Pop Button"
Cohesion: 0.13
Nodes (14): AnimationController, _anim, build, createState, _ctrl, dispose, expand, height (+6 more)

### Community 60 - "Notion Config"
Cohesion: 0.13
Nodes (14): apiVersion, dbChats, dbCourts, dbFriends, dbMatches, dbPickups, dbProfiles, dbReviews (+6 more)

### Community 61 - "Legal Screen"
Cohesion: 0.14
Nodes (13): body, build, LegalScreen, privacy, terms, title, url, _encodeQuery (+5 more)

### Community 62 - "Package"
Cohesion: 0.13
Nodes (15): axios, dependencies, axios, @nestjs/core, @nestjs/jwt, @nestjs/passport, passport-jwt, reflect-metadata (+7 more)

### Community 63 - "Under Construction"
Cohesion: 0.15
Nodes (13): _Splash, _ShareCard, GradientRing, _TabCircle, GlassCard, PopBackground, PopPanel, build (+5 more)

### Community 64 - "Package (2)"
Cohesion: 0.15
Nodes (13): devDependencies, @nestjs/cli, @nestjs/schematics, @types/express, @types/node, @types/passport-jwt, typescript, @nestjs/cli (+5 more)

### Community 65 - "Onboarding Screen"
Cohesion: 0.17
Nodes (11): _brand, build, _cta, _headline, OnboardingScreen, onLogin, onStart, _stats (+3 more)

### Community 66 - "Blocked Provider"
Cohesion: 0.17
Nodes (11): block, _blocked, clearForLogout, isBlocked, _kBase, _key, loadForUser, _norm (+3 more)

### Community 67 - "Route Service"
Cohesion: 0.17
Nodes (11): _decodePolyline, distText, durationText, fetchRoute, _kApiKey, points, RouteResult, RouteService (+3 more)

### Community 68 - "Court Rating Service"
Cohesion: 0.18
Nodes (10): average, _cache, count, CourtRating, hasRating, invalidate, _notion, ratingFor (+2 more)

### Community 69 - "Favorites Provider"
Cohesion: 0.18
Nodes (10): clearForLogout, _ids, isFavorite, _key, load, setUser, toggle, _userKey (+2 more)

### Community 70 - "Local Chat Service"
Cohesion: 0.18
Nodes (10): deleteChat, _expiryHours, getChats, _kChats, _key, LocalChatService, saveChat, _userKey (+2 more)

### Community 71 - "Location Service"
Cohesion: 0.18
Nodes (10): distanceBetween, formatDist, km, _last, metersTo, update, warmUp, package:geolocator/geolocator.dart (+2 more)

### Community 72 - "Session Alarms (2)"
Cohesion: 0.20
Nodes (10): @pragma, _PluginRegistrant, register, geofenceTriggered, notificationBackgroundHandler, alarmBatteryCallback, alarmEndCallback, alarmRadarCallback (+2 more)

### Community 73 - "Match Detail Screen (2)"
Cohesion: 0.22
Nodes (10): _submit, build, MainShell, _MainShellState, build, _captureAndShare, MatchDetailScreen, _MatchDetailScreenState (+2 more)

### Community 74 - "Friends Service"
Cohesion: 0.20
Nodes (9): addFriend, FriendsService, isConfigured, listFriends, normalizeHandle, _notion, removeFriend, searchByHandle (+1 more)

### Community 75 - "Dart Build Result"
Cohesion: 0.22
Nodes (8): build_end, build_start, code_assets, data_assets, dependencies, file:///C:/ProyectosF/1of1/app/.dart_tool/package_config.json, file:///C:/ProyectosF/1of1/app/pubspec.yaml, file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version

### Community 76 - "Dart Build Result (2)"
Cohesion: 0.22
Nodes (8): build_end, build_start, code_assets, data_assets, dependencies, file:///C:/ProyectosF/1of1/app/.dart_tool/package_config.json, file:///C:/ProyectosF/1of1/app/pubspec.yaml, file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version

### Community 77 - "Dart Build Result (3)"
Cohesion: 0.22
Nodes (8): build_end, build_start, code_assets, data_assets, dependencies, file:///C:/ProyectosF/1of1/app/.dart_tool/package_config.json, file:///C:/ProyectosF/1of1/app/pubspec.yaml, file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version

### Community 78 - "Dart Build Result (4)"
Cohesion: 0.22
Nodes (8): build_end, build_start, code_assets, data_assets, dependencies, file:///C:/ProyectosF/triplesapp/app/.dart_tool/package_config.json, file:///C:/ProyectosF/triplesapp/app/pubspec.yaml, file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version

### Community 79 - "Dart Build Result (5)"
Cohesion: 0.22
Nodes (8): build_end, build_start, code_assets, data_assets, dependencies, file:///C:/ProyectosF/triplesapp/app/.dart_tool/package_config.json, file:///C:/ProyectosF/triplesapp/app/pubspec.yaml, file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version

### Community 80 - "Detail Screen (3)"
Cohesion: 0.28
Nodes (9): build, OneOfOneApp, _blockReviewer, _bottomCta, build, DetailScreen, BlockedProvider, FavoritesProvider (+1 more)

### Community 81 - "Geocoding Service"
Cohesion: 0.22
Nodes (8): areaFromLatLng, cityFromLatLng, _components, _first, GeocodingService, _kApiKey, dart:convert, package:http/http.dart

### Community 82 - "App Loader"
Cohesion: 0.25
Nodes (8): AppLoader, _AppLoaderState, build, createState, _gone, visible, app_logo.dart, pop_background.dart

### Community 83 - "Tsconfig.build"
Cohesion: 0.25
Nodes (7): exclude, extends, dist, node_modules, **/*spec.ts, test, ./tsconfig.json

### Community 84 - "GeneratedPluginRegistrant"
Cohesion: 0.33
Nodes (4): GeneratedPluginRegistrant, +registerWithRegistry, Health, NSObject

### Community 85 - "Home Screen (2)"
Cohesion: 0.29
Nodes (7): _ensureUserPosition, _goToMyLocation, _loadInitialPosition, _onMockTap, _startLocationUpdates, _distMeters, LocationService

### Community 86 - "App Loading State"
Cohesion: 0.29
Nodes (6): _gpsReady, _mapReady, markGpsReady, markMapReady, bool get, package:flutter/foundation.dart

### Community 87 - "Pickups.module"
Cohesion: 0.29
Nodes (5): PickupsController, Body, Controller, Post, UseGuards

### Community 88 - "Models.freezed"
Cohesion: 0.33
Nodes (6): @freezed, @JsonSerializable, Profile, _Profile, ProfilePatterns, Profile?

### Community 89 - "README"
Cohesion: 0.33
Nodes (6): app/ (Flutter mobile app), app/analysis_options.yaml, iOS LaunchImage Assets README, backend/ (backend service, TBD), backend/README.md, 1of1 Monorepo README

### Community 90 - "GeneratedPluginRegistrant (2)"
Cohesion: 0.47
Nodes (4): GeneratedPluginRegistrant, FlutterEngine, FlutterLocalNotificationsPlugin, Keep

### Community 91 - "Flutter Lldb Helper"
Cohesion: 0.33
Nodes (5): handle_new_rx_page(), __lldb_init_module(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., SBDebugger, SBFrame

### Community 92 - "Status Dot"
Cohesion: 0.33
Nodes (5): CourtStatus, build, status, StatusDot, ../data/courts.dart

### Community 93 - "README (2)"
Cohesion: 0.40
Nodes (6): google_sign_in ^6.2.2, Cumplimiento legal / lanzamiento en tiendas, lib/data/legal_content.dart, lib/screens/legal_screen.dart, lib/services/blocked_provider.dart, lib/services/report_service.dart

### Community 94 - "Nest Cli"
Cohesion: 0.33
Nodes (5): collection, compilerOptions, deleteOutDir, $schema, sourceRoot

### Community 95 - "Package (3)"
Cohesion: 0.33
Nodes (6): scripts, build, lint, start, start:dev, start:prod

### Community 96 - "Pickups.module (2)"
Cohesion: 0.33
Nodes (6): CreatePickupDto, IsOptional, IsString, Max, Min, IsInt

### Community 97 - "Gradlew"
Cohesion: 0.60
Nodes (3): gradlew script, die(), warn()

### Community 98 - "Package (4)"
Cohesion: 0.40
Nodes (4): description, name, private, version

### Community 99 - "Profiles.controller (2)"
Cohesion: 0.40
Nodes (5): SetHandleDto, SetPresenceDto, IsBoolean, IsOptional, IsString

### Community 100 - "Widget Test"
Cohesion: 0.50
Nodes (3): main, package:flutter_test/flutter_test.dart, package:triplesapp/main.dart

### Community 102 - "Pubspec"
Cohesion: 0.67
Nodes (3): Convenciones y gotchas (§6), google_maps_flutter ^2.10.0, google_maps_flutter_android pineado a 2.19.7

### Community 103 - "Friends.module (2)"
Cohesion: 0.67
Nodes (3): AddFriendDto, IsEmail, IsString

## Ambiguous Edges - Review These
- `Definición de Temporada = semestre calendario` → `Notion DB: Partidos (pickups)`  [AMBIGUOUS]
  app/CLAUDE.md · relation: references

## Knowledge Gaps
- **1721 isolated node(s):** `build_start`, `build_end`, `file:///C:/ProyectosF/1of1/app/.dart_tool/package_config.json`, `file:///C:/ProyectosF/1of1/app/pubspec.yaml`, `file:///C:/Users/yochi/Flutter/bin/cache/dart-sdk/version` (+1716 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **67 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Definición de Temporada = semestre calendario` and `Notion DB: Partidos (pickups)`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **Why does `PlaySessionService` connect `Permissions Modal` to `Play Session Service`, `Profile Screen (2)`, `Home Screen`, `Profile Screen`, `Profile Screen (3)`, `Match Detail Screen (2)`, `Pickup Create Screen`, `Main Shell`, `Detail Screen (3)`, `Crew Screen`, `Pickup Chat Screen`, `Home Screen (2)`, `Detail Screen (2)`, `Main`, `Match Detail Screen`, `Notifications Screen`, `Detail Screen`, `Sync Coordinator`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Why does `Session` connect `Crew Screen` to `Profile Screen`, `Profile Screen (3)`, `Session`, `Pickup Create Screen`, `Pickup Chat Screen`, `Handle Setup Screen`, `Notifications Screen`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **What connects `build_start`, `build_end`, `file:///C:/ProyectosF/1of1/app/.dart_tool/package_config.json` to the rest of the system?**
  _1721 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Play Session Service` be split into smaller, more focused modules?**
  _Cohesion score 0.009216589861751152 - nodes in this community are weakly interconnected._
- **Should `Profile Screen` be split into smaller, more focused modules?**
  _Cohesion score 0.01785437043937277 - nodes in this community are weakly interconnected._
- **Should `Home Screen` be split into smaller, more focused modules?**
  _Cohesion score 0.018018018018018018 - nodes in this community are weakly interconnected._