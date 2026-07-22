/// Textos legales de la app, en un solo lugar (fuente única de verdad).
///
/// La Política de Privacidad y los Términos viven acá, embebidos, y se muestran
/// in-app desde [LegalScreen]. Las tiendas (Play Store) EXIGEN además una URL
/// pública: cuando exista el sitio, completá [kPrivacyPolicyUrl] / [kTermsUrl]
/// y la ficha de cada tienda debe apuntar a esas URLs (con el mismo contenido).
///
/// IMPORTANTE: estos textos describen lo que el código realmente hace. Si
/// cambiás el flujo de datos (nuevos proveedores, nuevos datos que se suben,
/// nuevas features que comparten info), actualizá el texto acá para que siga
/// siendo veraz. Hoy los datos se guardan en un backend propio (NestJS en
/// Render + Supabase Postgres); ya NO se usa Notion.
///
/// Cambiá el email de contacto o los textos SOLO acá.
library;

/// Email de contacto / soporte / ejercicio de derechos de datos. Debe ser una
/// casilla monitoreada: las tiendas exigen responder reportes de contenido en
/// ≤ 24 h y atender pedidos de datos (acceso / eliminación).
const String kSupportEmail = 'francobusch130@gmail.com';

/// URLs públicas de los documentos legales. Vacías por ahora (no hay sitio):
/// cuando existan, la ficha de cada tienda debe apuntar acá y [LegalScreen]
/// ofrecerá abrirlas. Con string vacío se usa solo la versión in-app.
const String kPrivacyPolicyUrl = '';
const String kTermsUrl = '';

/// Fecha de última actualización de los documentos (mostrada al usuario).
const String kLegalLastUpdated = '22 de julio de 2026';

/// Política de Privacidad (resumen honesto de lo que la app hace hoy).
const String kPrivacyPolicy = '''
Última actualización: $kLegalLastUpdated

1of1 ("la app") es una aplicación para encontrar canchas de básquet y registrar
tus partidos. Esta política explica qué datos usamos y por qué.

QUÉ DATOS RECOLECTAMOS
• Datos de cuenta: nombre, email y, opcionalmente, ciudad y teléfono que cargás
  al registrarte. Tu fecha de nacimiento se guarda para verificar y acreditar
  que cumplís la edad mínima.
• Handle y datos de perfil: apodo público, insignia de clan, foto (si iniciás
  sesión con Google) y tus estadísticas de juego.
• Ubicación: usamos tu ubicación para mostrarte canchas cercanas y para detectar
  cuándo estás jugando en una cancha. Con tu permiso "Siempre", la detección
  funciona con la app cerrada. No almacenamos tus coordenadas en nuestra base:
  solo registramos en qué cancha jugaste. (Ver "Servicios de terceros": para el
  mapa y las rutas, tus coordenadas se envían a Google en el momento.)
• Datos de salud (opcional): si conectás Salud (Health Connect / Apple Health),
  leemos calorías, pulso, pasos y distancia de tus partidos. Estos datos quedan
  SOLO en tu dispositivo y no se suben a nuestros servidores.
• Actividad de juego: historial de partidos (cancha, fecha, duración, puntos).
• Mensajes: el contenido de los chats de pickups que enviás se guarda en nuestro
  servidor para poder mostrárselo a los participantes de ese pickup.

PARA QUÉ LOS USAMOS
Para hacer funcionar la app: ubicarte en el mapa, detectar y puntuar tus
partidos, mostrar tu perfil y rankings, y conectar la comunidad (amigos, pickups
y sus chats).

DÓNDE SE GUARDAN
Los datos de cuenta, juego y mensajes se almacenan en nuestro backend propio,
alojado en Render (Render Services, Inc., servidores en Estados Unidos) sobre una
base de datos Supabase Postgres (Supabase, Inc.). Ambos proveedores actúan como
encargados del tratamiento por nuestra cuenta. Al usar la app aceptás esta
transferencia internacional de datos a Estados Unidos. Los datos de salud no
salen de tu teléfono.

SERVICIOS DE TERCEROS
Usamos servicios de Google para funciones del mapa: Google Maps (mostrar el
mapa), Geocoding (convertir direcciones en coordenadas) y Directions (calcular
rutas a las canchas). Al usar esas funciones, tu ubicación y/o la dirección
consultada se envían a Google. Si iniciás sesión con Google, tu autenticación y
foto de perfil las provee Google Sign-In. El tratamiento que hace Google se rige
por su propia política de privacidad (policies.google.com/privacy).

CUÁNTO TIEMPO LOS CONSERVAMOS
Conservamos tus datos mientras tu cuenta esté activa. Si eliminás tu cuenta, los
borramos de nuestra base; pueden persistir por un tiempo breve en copias de
respaldo antes de eliminarse por completo.

QUÉ VEN OTROS USUARIOS
Otros usuarios pueden ver tu nombre, handle, insignia y estadísticas públicas.
En los chats de pickups, los participantes ven los mensajes que enviás y tu
handle. Tu presencia "jugando", la cancha y el tiempo solo se comparten si
activás esos permisos en Ajustes → Privacidad (todos vienen desactivados por
defecto).

TUS DERECHOS
Podés acceder, rectificar o eliminar tus datos. Desde Ajustes → Eliminar cuenta
borrás tu cuenta y tus datos de nuestra base. También podés escribirnos a
$kSupportEmail para ejercer cualquier derecho (Ley 25.326 de Argentina; y, según
tu jurisdicción, derechos equivalentes como los de CCPA/CPRA en EE.UU.).

MENORES
La app no está dirigida a menores de 13 años y no recolectamos datos de ellos a
sabiendas. Si sos menor de edad, usá la app con autorización de tu representante
legal.

CAMBIOS
Podemos actualizar esta política; avisaremos dentro de la app. Ante dudas,
escribinos a $kSupportEmail.
''';

/// Términos y Condiciones (uso aceptable, responsabilidad, UGC).
const String kTermsAndConditions = '''
Última actualización: $kLegalLastUpdated

Al crear una cuenta y usar 1of1 aceptás estos términos.

USO DE LA APP
1of1 te ayuda a encontrar canchas y registrar partidos. Sos responsable de la
información que cargás (canchas, reseñas, handle, nombre) y de jugar de forma
segura: la app no supervisa ni garantiza el estado de las canchas.

CONTENIDO Y CONDUCTA
Sos responsable del contenido que publicás, incluidas reseñas de canchas y los
mensajes que enviás en los chats de pickups. No se permite contenido ofensivo,
ilegal, spam, acoso ni suplantación de identidad. Podés reportar contenido o
usuarios inapropiados desde la app, y bloquear a otros usuarios. Revisamos los
reportes y podemos eliminar contenido o suspender cuentas que violen estas
reglas. No toleramos contenido abusivo.

UBICACIÓN Y SEGUNDO PLANO
La detección de partidos usa tu ubicación, incluso en segundo plano si lo
autorizás. Podés desactivarla cuando quieras desde Ajustes → Privacidad o desde
los permisos del sistema.

DATOS DE SALUD
Las métricas de salud son informativas y no constituyen consejo médico.

RESPONSABILIDAD
La app se ofrece "tal cual". No nos responsabilizamos por lesiones, pérdidas o
daños derivados del uso de la app o de la asistencia a las canchas.

BAJA
Podés eliminar tu cuenta en cualquier momento desde Ajustes → Eliminar cuenta.

LEY APLICABLE Y JURISDICCIÓN
Estos términos se rigen por las leyes de la República Argentina. Cualquier
controversia se someterá a los tribunales ordinarios competentes de la Ciudad
Autónoma de Buenos Aires, sin perjuicio de los derechos que la ley de tu país de
residencia te reconozca como consumidor.

CONTACTO
$kSupportEmail
''';
