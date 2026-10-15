import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Caché en disco de las fotos de las canchas: se bajan una vez y después salen
/// del celu (al reabrir la app, cambiar de pestaña o sin conexión).
///
/// Cachear por URL es seguro: cada foto subida tiene una URL única
/// (`courts/<uuid>.webp`, sin sobrescritura), así que una foto nueva nunca
/// reusa la URL de una vieja.
final CacheManager courtImageCache = CacheManager(
  Config(
    'courtImages',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 300,
  ),
);
