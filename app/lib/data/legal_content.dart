/// Textos legales de la app, en un solo lugar (fuente única de verdad).
///
/// La app NO tiene backend propio todavía (ver README §"Deuda legal / backend"):
/// mientras tanto la Política de Privacidad y los Términos viven acá, embebidos,
/// y se muestran in-app desde [LegalScreen]. Cuando exista un sitio público,
/// completá [kPrivacyPolicyUrl] / [kTermsUrl] y las tiendas linkearán a esas URLs.
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
const String kLegalLastUpdated = '12 de julio de 2026';

/// Política de Privacidad (resumen honesto de lo que la app hace hoy).
const String kPrivacyPolicy = '''
Última actualización: $kLegalLastUpdated

1of1 ("la app") es una aplicación para encontrar canchas de básquet y registrar
tus partidos. Esta política explica qué datos usamos y por qué.

QUÉ DATOS RECOLECTAMOS
• Datos de cuenta: nombre, email y, opcionalmente, ciudad y teléfono que cargás
  al registrarte. Tu fecha de nacimiento se usa solo para verificar tu edad.
• Handle y datos de perfil: apodo público, insignia de clan, foto (si iniciás
  sesión con Google) y tus estadísticas de juego.
• Ubicación: usamos tu ubicación para mostrarte canchas cercanas y para detectar
  cuándo estás jugando en una cancha. Con tu permiso "Siempre", la detección
  funciona con la app cerrada. No guardamos tus coordenadas: solo registramos en
  qué cancha jugaste.
• Datos de salud (opcional): si conectás Salud (Health Connect / Apple Health),
  leemos calorías, pulso, pasos y distancia de tus partidos. Estos datos quedan
  SOLO en tu dispositivo y no se suben a nuestros servidores.
• Actividad de juego: historial de partidos (cancha, fecha, duración, puntos).

PARA QUÉ LOS USAMOS
Para hacer funcionar la app: ubicarte en el mapa, detectar y puntuar tus
partidos, mostrar tu perfil y rankings, y conectar la comunidad (amigos, pickups).

DÓNDE SE GUARDAN
Los datos de cuenta y juego se almacenan en Notion (Notion Labs, Inc., con
servidores en Estados Unidos), que actúa como nuestro proveedor de base de
datos. Al usar la app aceptás esta transferencia internacional. Los datos de
salud no salen de tu teléfono.

QUÉ VEN OTROS USUARIOS
Otros usuarios pueden ver tu nombre, handle, insignia y estadísticas públicas.
Tu presencia "jugando", la cancha y el tiempo solo se comparten si activás esos
permisos en Ajustes → Privacidad (todos vienen desactivados por defecto).

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
No se permite contenido ofensivo, ilegal, spam, acoso ni suplantación de
identidad. Podés reportar contenido o usuarios inapropiados desde la app, y
bloquear a otros usuarios. Revisamos los reportes y podemos eliminar contenido o
suspender cuentas que violen estas reglas. No toleramos contenido abusivo.

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

CONTACTO
$kSupportEmail
''';
