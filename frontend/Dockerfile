# ============================================================
# STAGE 1: BUILD - Compila React con Node.js
# ============================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copiar dependencias primero (cache de capas)
COPY package*.json ./
RUN npm ci --frozen-lockfile

# Copiar codigo fuente y compilar
COPY . .
RUN npm run build

# ============================================================
# STAGE 2: PRODUCCION - Nginx sirve los archivos estaticos
# Imagen final: ~25MB vs ~1GB con Node completo
# ============================================================
FROM nginx:1.25-alpine AS production

# Usuario sin privilegios root
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copiar archivos compilados desde el stage anterior
COPY --from=builder /app/dist /usr/share/nginx/html

# Configuracion de Nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Permisos para usuario no-root
RUN chown -R appuser:appgroup /usr/share/nginx/html && \
    chown -R appuser:appgroup /var/cache/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown appuser:appgroup /var/run/nginx.pid

USER appuser
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
