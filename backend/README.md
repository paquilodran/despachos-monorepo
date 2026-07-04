# Backend - Springboot API REST Despacho

## Descripción
API REST para gestionar despachos (servicio backend Spring Boot).

## Contenido
- **Instrucciones de uso**
- **Justificación del tipo de volumen utilizado**
- **Documentación del pipeline (CI/CD)**

## Requisitos
- Java 17+ (o la versión configurada en `pom.xml`)
- Maven (se puede usar el wrapper incluido)
- Docker y Docker Compose (si se desea ejecutar en contenedores)

## Configuración
Colocar las variables de entorno en un fichero `.env` en la raíz del proyecto (ya incluido en el repositorio). Las variables principales que usa la aplicación y `docker-compose` son:

- `DB_NAME` (por defecto `despachos_db`)
- `DB_USERNAME`
- `DB_PASSWORD`

Ejemplo mínimo de `.env`:

DB_NAME=despachos_db
DB_USERNAME=usuario
DB_PASSWORD=secreto

## Ejecutar localmente (desarrollo)

Desde la raíz del proyecto:

Linux / macOS:

```
./mvnw spring-boot:run
```

Windows (PowerShell/CMD):

```
mvnw.cmd spring-boot:run
```

Ejecutar tests:

```
./mvnw test
```

La aplicación expone por defecto el puerto `8081` (puede configurarse en `application.properties`).

## Ejecutar con Docker Compose

Levantar la aplicación y la base de datos usando Docker Compose:

```
docker compose up -d --build
```

Parar y eliminar:

```
docker compose down
```

Ver logs del backend:

```
docker compose logs -f backend-despachos
```

Puertos expuestos por defecto:
- Backend: `8081`
- MySQL: `3306`

## Endpoints principales
Base: `POST/GET/PUT/DELETE /api/v1/despachos`

- `GET /api/v1/despachos` — Obtener todos los despachos
- `GET /api/v1/despachos/{id}` — Obtener despacho por ID
- `POST /api/v1/despachos` — Crear despacho (payload JSON)
- `PUT /api/v1/despachos/{id}` — Actualizar despacho
- `DELETE /api/v1/despachos/{id}` — Eliminar despacho

Ejemplo de payload para `POST /api/v1/despachos`:

```
{
  "fechaDespacho": "2026-05-11",
  "patenteCamion": "ABC123",
  "intento": 1,
  "idCompra": 12345,
  "direccionCompra": "Calle Falsa 123",
  "valorCompra": 10000,
  "despachado": false
}
```

## Justificación del tipo de volumen utilizado

En `docker-compose.yml` se usa un volumen nombrado (`despachos_db_data`) montado en `/var/lib/mysql` (driver `local`). Justificación:

- Persistencia gestionada por Docker: un volumen nombrado asegura que los datos de MySQL persisten aunque el contenedor se destruya o se recree.
- Portabilidad y seguridad: a diferencia de un bind-mount hacia el host, los volúmenes nombrados evitan problemas de permisos y rutas específicas del host, y Docker gestiona la ubicación física.
- Rendimiento y backups: los volúmenes Docker están optimizados para I/O de contenedores y facilitan tareas de backup/restore (`docker volume inspect`, `docker run --rm -v despachos_db_data:/data busybox tar ...`).
- Independencia del entorno de desarrollo: facilita ejecutar la misma configuración en CI, staging o producción sin depender de la estructura de archivos del host.

Si en algún caso se requiere acceso directo a los archivos de la base de datos desde el host (por ejemplo para debugging), se puede cambiar a un bind-mount en `docker-compose.yml`, pero hay que considerar permisos y compatibilidad entre sistemas (Windows vs Linux).

## Documentación del pipeline (CI/CD) — ejemplo

Este repositorio puede integrarse en un pipeline de CI/CD (por ejemplo GitHub Actions, GitLab CI o Azure Pipelines). A continuación se describe un pipeline de ejemplo y los pasos recomendados.

Fases recomendadas:

1. Build
   - Ejecutar `mvn -B -DskipTests package` para compilar y empaquetar el JAR.
2. Test
   - Ejecutar `mvn test` y publicar los resultados de test.
3. Static analysis (opcional)
   - Ejecutar análisis estático (SpotBugs, Checkstyle, PMD) si aplica.
4. Build Docker image
   - Construir la imagen con `docker build --target production -t $REGISTRY/backend-despachos:$TAG .`
5. Push
   - Push de la imagen a un registry privado o Docker Hub `docker push $REGISTRY/backend-despachos:$TAG`.
6. Deploy
   - Desplegar la nueva imagen usando `docker compose pull && docker compose up -d` en el entorno objetivo, o actualizar la imagen en el orquestador correspondiente (Kubernetes, etc.).

Ejemplo (resumen) de job en GitHub Actions:

```yaml
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
      - name: Build and test
        run: ./mvnw -B package
      - name: Build Docker image
        run: docker build --target production -t ${{ secrets.REGISTRY }}/backend-despachos:${{ github.sha }} .
      - name: Push image
        run: |
          echo ${{ secrets.REGISTRY_PASS }} | docker login ${{ secrets.REGISTRY }} -u ${{ secrets.REGISTRY_USER }} --password-stdin
          docker push ${{ secrets.REGISTRY }}/backend-despachos:${{ github.sha }}
```
