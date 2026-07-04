# ============================================================
# STAGE 1: BUILD - Compila el JAR con Maven
# Usa imagen completa con JDK 17 y Maven
# ============================================================
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /app


COPY pom.xml .
RUN mvn dependency:go-offline -B

# Ahora copiar el codigo fuente y compilar
COPY src ./src
RUN mvn clean package -DskipTests -B

# ============================================================
# STAGE 2: PRODUCCION - Solo el JRE (sin Maven, sin codigo fuente)
# Imagen mucho mas liviana: ~200MB vs ~800MB
# ============================================================
FROM eclipse-temurin:17-jre-alpine AS production

# Crear grupo y usuario sin privilegios root (seguridad)
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copiar solo el JAR desde el stage de build
COPY --from=builder /app/target/*.jar app.jar

# Dar permisos al usuario no-root
RUN chown appuser:appgroup app.jar

# Cambiar al usuario sin privilegios
USER appuser

# Puerto 8081 segun application.properties
EXPOSE 8081

# Variables de entorno (se sobreescriben en docker-compose o en EC2)
ENV DB_ENDPOINT=localhost \
    DB_PORT=3306 \
    DB_NAME=despachos_db \
    DB_USERNAME=root \
    DB_PASSWORD=changeme

# Opciones de JVM optimizadas para contenedores
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport"

# Comando de inicio
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
