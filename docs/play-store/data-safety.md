# Formulario "Seguridad de los datos" (Data Safety) — Play Console

Guía para completar el cuestionario de Play Console (Política de la app →
Seguridad de los datos), basada en lo que la app realmente recopila (revisé el
código: permisos declarados, endpoints del backend, campos del perfil).

**Importante:** este formulario lo completa Google directamente en Play
Console con un wizard de preguntas — acá te dejo las respuestas ya resueltas
para que las tipees ahí. Nadie más que vos puede enviarlo (queda asociado a tu
cuenta de desarrollador).

## ¿Recopila o comparte datos del usuario?

**Sí.**

## Cifrado en tránsito

**Sí** — todo el tráfico va por HTTPS (backend en Render con TLS).

## ¿El usuario puede pedir que se borren sus datos?

**Sí** — botón "Eliminar cuenta" dentro de la app (Perfil → Ajustes), borra
perfil, historial de partidos, amistades, reseñas y mensajes.

## Tipos de datos a declarar

| Categoría | Dato | ¿Se recopila? | ¿Opcional? | ¿Se comparte con terceros? | Propósito declarado |
|---|---|---|---|---|---|
| Ubicación | Ubicación aproximada | Sí | No (necesaria para el mapa) | No | Funcionalidad de la app |
| Ubicación | Ubicación precisa | Sí | No (para detección de partido) | No | Funcionalidad de la app |
| Información personal | Nombre | Sí | No | No | Funcionalidad de la app |
| Información personal | Dirección de email | Sí | No | No | Funcionalidad de la app, Autenticación |
| Información personal | Número de teléfono | Sí | Sí | No | Funcionalidad de la app |
| Información personal | Otra info (fecha de nacimiento, ciudad) | Sí | Sí | No | Funcionalidad de la app |
| Fotos y videos | Fotos | Sí (avatar y fotos de cancha) | Sí | No | Funcionalidad de la app |
| Mensajes | Otros mensajes en la app | Sí (chat de pickups) | No (si usás esa función) | No | Funcionalidad de la app |
| Actividad en la app | Interacciones en la app | Sí (partidos, reseñas, logros) | No | No | Funcionalidad de la app, Analítica |
| Salud y fitness | Información de salud (Health Connect: pulso, calorías, pasos, distancia, ejercicio) | Sí, SOLO si el usuario lo activa | **Sí, opt-in explícito** | No | Funcionalidad de la app |

**Sobre "compartir con terceros":** usamos Supabase (base de datos/almacenamiento)
y Google (Maps, Sign-In) como **proveedores de servicio** para operar la app,
no como terceros a quienes se "comparten" los datos con fines propios de ellos
— esa es la distinción que hace el formulario de Google. Si tenés dudas al
completarlo, la guía oficial lo aclara: un proveedor que solo procesa datos en
tu nombre no cuenta como "compartir datos" en el sentido del formulario.

## Nota sobre datos de salud (Health Connect)

Google tiene requisitos EXTRA para apps que leen Health Connect: hay que
declarar explícitamente el uso en la sección correspondiente del formulario y
puede pedir una **declaración de política de datos de salud** aparte. Como es
opt-in y no es el corazón de la app (es un enriquecimiento opcional del
historial), destacá eso al completar esa sección.

## Nota sobre ubicación en segundo plano

Google audita fuerte el permiso `ACCESS_BACKGROUND_LOCATION`. En la sección de
permisos de la Play Console Declaration Form vas a tener que:
1. Justificar por qué la app necesita ubicación en background (nuestra
   respuesta: "detecta automáticamente el inicio y fin de partidos de básquet
   sin que el usuario tenga que abrir la app").
2. Puede pedir un **video corto** mostrando el flujo (activar el permiso →
   la app detectando un partido). Si llega a pedirlo, avisame y lo preparamos.
