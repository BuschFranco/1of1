# Backend — 1of1

En construcción. Acá va a vivir el backend de la app 1of1.

Hoy la app habla directo con Notion como backend (token embebido en el cliente).
La idea de este servicio es mover esa lógica al servidor: auth real, proxy de
Notion (para no exponer el token en el cliente), y la API que consuma la app.

## TODO

- [ ] Elegir stack (Node/Express, Python/FastAPI, Dart/Shelf, …)
- [ ] Auth (reemplazar el hash prototipo del cliente)
- [ ] Proxy/abstracción de Notion (ocultar el token del cliente)
- [ ] Endpoints: perfiles, canchas, amigos, presencia
