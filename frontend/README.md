# Frontend - Aplicación de Despacho

**Resumen**
- **Descripción:** Aplicación frontend construida con React y Vite para gestionar despachos y compras.
- **Propósito:** Interfaz del sistema de despacho; consume datos locales/servicio mock (`db.json`) y se sirve con Nginx en producción.

**Tecnologías principales**
- **Framework:** React (JSX) + Vite
- **Estilos:** Tailwind CSS
- **Servidor estático / proxy:** Nginx
- **Contenedores:** Docker + Docker Compose

**Estructura del proyecto**
- **Raíz:** contiene [Dockerfile](Dockerfile) y [docker-compose.yml](docker-compose.yml)
- **Configuración Nginx:** [nginx.conf](nginx.conf)
- **Configuración Vite:** [vite.config.js](vite.config.js)
- **Tailwind:** [tailwind.config.js](tailwind.config.js)
- **Entradas principales:** [index.html](index.html), [src/main.jsx](src/main.jsx)
- **Componentes:** [src/componentes](src/componentes)

**Requisitos previos**
- **Instalar:** `node` (>=16), `npm` o `pnpm`, `docker`, `docker-compose`

**Modo desarrollo (local)**
1. Instala dependencias:

```bash
npm install
```

2. Ejecuta servidor de desarrollo (Vite HMR):

```bash
npm run dev
# Por defecto Vite sirve en http://localhost:5173
```

**Construcción y ejecución con Docker (producción)**
- El repositorio incluye un `Dockerfile` multi-stage para construir la app y servirla con Nginx.
- `docker-compose.yml` orquesta el contenedor frontend (Nginx) y puede incluir servicios adicionales si se necesita.

Construir la imagen y levantar el contenedor:

```bash
docker-compose up --build -d
```

Ver logs:

```bash
docker-compose logs -f
```

Parar y eliminar contenedores:

```bash
docker-compose down
```

Si prefieres construir la imagen manualmente:

```bash
docker build -t frontend-despacho:latest .
docker run -p 80:80 frontend-despacho:latest
```

**Decisiones técnicas y motivos**
- **Vite:** arranque rápido y HMR, menos configuración comparado con CRA.
- **Tailwind CSS:** utilidades atómicas que aceleran el desarrollo de UI y mantienen consistencia visual.
- **Nginx como servidor estático y proxy:** eficiente para servir assets optimizados y fácil de configurar con `nginx.conf`.
- **Docker multi-stage build:** separa la fase de build (node) de la fase de runtime (nginx), reduciendo tamaño de imagen y atacando seguridad.
- **db.json (mock):** permite pruebas locales sin backend real; útil para demo y pruebas rápidas.

**Archivos clave**
- **[Dockerfile](Dockerfile):** define la build multi-stage y cómo servir la app con Nginx.
- **[docker-compose.yml](docker-compose.yml):** levanta la app y otros servicios locales si se agregan.
- **[nginx.conf](nginx.conf):** configuración de Nginx (caching, rutas, SPA fallback).
- **[src/main.jsx](src/main.jsx):** punto de entrada React.

**Buenas prácticas y recomendaciones**
- Para producción, habilitar `NODE_ENV=production` y revisar headers de seguridad en `nginx.conf`.
- Añadir una imagen de captura en `public/` y actualizar la ruta en la sección de arriba.
- Versionar imágenes Docker con tags (ej. `v1.0.0`) y subir a registro para CI/CD.

**Solución de problemas comunes**
- Si no ves cambios en producción, limpiar caché del navegador y reconstruir la imagen con `--no-cache`:

```bash
docker-compose build --no-cache
docker-compose up -d
```

- Si Vite no arranca en local, comprobar versión de Node y permisos.
---

