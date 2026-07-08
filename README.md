# Despachos Monorepo — ISY1101
## Evaluación Final Transversal · Introducción a Herramientas DevOps
### Automatización CI/CD: Frontend + Backend + MySQL en AWS ECS Fargate

**Repositorio:** https://github.com/paquilodran/despachos-monorepo  
**Estudiante:** Patricio Quilodrán  
**Año:** 2025

---

## Descripción del proyecto

Plataforma completa de gestión de despachos con automatización total del ciclo CI/CD. Cada push a la rama `main` dispara automáticamente el pipeline de GitHub Actions que compila, empaqueta, publica y despliega los tres componentes (Frontend, Backend, MySQL) en AWS ECS Fargate sin intervención manual.

---

## Estructura del repositorio

```
despachos-monorepo/
├── frontend/                    → Aplicación React + Vite servida con Nginx
│   ├── Dockerfile               → Build multietapa (node:20-alpine → nginx:1.25-alpine)
│   ├── .dockerignore
│   ├── nginx.conf               → Nginx configurado en puerto 8080 (usuario no-root)
│   └── src/
├── backend/                     → API REST Spring Boot + Java 17
│   ├── Dockerfile               → Imagen basada en Eclipse Temurin JRE
│   ├── .dockerignore
│   ├── mvnw                     → Maven wrapper
│   └── src/
├── infra/
│   ├── scripts/
│   │   └── setup-infra.sh       → Script Bash que crea toda la infraestructura AWS
│   └── task-definitions/
│       ├── backend-task-definition.json   → Task Definition ECS backend + MySQL
│       └── frontend-task-definition.json  → Task Definition ECS frontend
├── docker-compose.yml           → Orquestación local (desarrollo)
├── .github/
│   └── workflows/
│       └── deploy.yml           → Pipeline CI/CD unificado (backend + frontend)
└── README.md
```

---

## Arquitectura del sistema

```
Internet
    │
    ▼
Application Load Balancer (despachos-alb)
internet-facing · HTTP:80 · us-east-1
    │
    ▼
ECS Cluster: despachos-cluster (Fargate, us-east-1)
    │
    ├── frontend-service (Task Def: frontend-despachos)
    │       └── Contenedor: frontend (Nginx, puerto 8080)
    │           Min: 2 tareas · Max: 5 tareas (HPA CPU 50%)
    │
    └── backend-service (Task Def: backend-con-mysql)
            ├── Contenedor: backend (Spring Boot, puerto 8081)
            └── Contenedor: mysql   (MySQL 5.7, puerto 3306)
                comunicación interna por localhost
                Min: 2 tareas · Max: 5 tareas (HPA CPU 50%)

Registro de imágenes: Amazon ECR
  ├── 599461371730.dkr.ecr.us-east-1.amazonaws.com/frontend-despacho
  ├── 599461371730.dkr.ecr.us-east-1.amazonaws.com/backend-despachos
  └── 599461371730.dkr.ecr.us-east-1.amazonaws.com/mysql-despachos

Observabilidad: Amazon CloudWatch
  ├── /ecs/frontend-despachos
  └── /ecs/backend-con-mysql

IAM: LabRole (Task Role + Execution Role) — mínimo privilegio
VPC: default · Subredes multi-AZ (us-east-1a, us-east-1d)
```

---

## Método de integración del sistema

| Componente | Tecnología | Puerto | Comunicación |
|------------|------------|--------|--------------|
| Frontend | React + Vite + Nginx | 8080 | Recibe tráfico del ALB |
| Backend | Spring Boot + Java 17 | 8081 | Expuesto internamente |
| MySQL | MySQL 5.7 | 3306 | Solo por localhost (mismo Task) |

- El **Frontend** recibe tráfico público a través del ALB y consume la API del Backend
- El **Backend** se conecta a **MySQL** por `localhost` ya que ambos corren en el mismo Task Definition de Fargate — comparten el mismo namespace de red
- En desarrollo local (docker-compose), el Backend se conecta a MySQL por nombre de servicio (`mysql`) a través de la red bridge `despachos-network`

---

## Contenedorización

### Frontend — Dockerfile multietapa

```dockerfile
# Etapa 1: Build de React con Node.js
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --frozen-lockfile
COPY . .
RUN npm run build

# Etapa 2: Producción con Nginx Alpine
FROM nginx:1.25-alpine AS production
RUN addgroup -g 1001 -S appgroup && adduser -u 1001 -S appuser -G appgroup
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
USER appuser
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

**Decisiones:**
- **Multietapa:** imagen final ~25MB vs ~1GB con Node completo
- **Alpine:** distribución minimalista, menos superficie de ataque
- **Usuario no-root:** seguridad — por eso Nginx corre en puerto 8080 y no 80

### Backend — Dockerfile

```dockerfile
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8081
CMD ["java", "-jar", "app.jar"]
```

### Docker Compose — Entorno local

```bash
# Levantar entorno completo localmente
docker compose up -d

# Verificar servicios
docker compose ps

# Ver logs
docker compose logs -f backend

# Apagar
docker compose down
```

Los servicios se comunican por la red bridge `despachos-network`. MySQL tiene healthcheck con `mysqladmin ping` y el backend espera que esté saludable antes de arrancar (`depends_on: condition: service_healthy`).

---

## Infraestructura en la nube (AWS)

### Crear toda la infraestructura desde cero

```bash
# 1. Configurar credenciales AWS Academy
nano ~/.aws/credentials
# Pegar las 3 líneas de AWS Details → Show

# 2. Verificar credenciales
aws sts get-caller-identity

# 3. Ejecutar script de infraestructura
chmod +x infra/scripts/setup-infra.sh
bash infra/scripts/setup-infra.sh
```

El script `setup-infra.sh` crea automáticamente:
- Repositorios ECR (frontend, backend, mysql)
- Build y push de imágenes Docker a ECR
- Clúster ECS Fargate (`despachos-cluster`)
- Task Definitions (backend-con-mysql, frontend-despachos)
- Application Load Balancer internet-facing
- Target Group con health check en `/`
- Servicios ECS (frontend-service, backend-service)
- Autoscaling Target Tracking CPU 50% en ambos servicios

### Componentes AWS

| Componente | Nombre | Configuración |
|------------|--------|---------------|
| Clúster ECS | `despachos-cluster` | Fargate, us-east-1 |
| Servicio frontend | `frontend-service` | 2-5 tareas, ALB |
| Servicio backend | `backend-service` | 2-5 tareas, IP pública |
| Load Balancer | `despachos-alb` | Internet-facing, HTTP:80 |
| Target Group | `frontend-tg` | IP, puerto 8080 |
| Task Def backend | `backend-con-mysql` | 2 vCPU, 4GB RAM |
| Task Def frontend | `frontend-despachos` | 0.25 vCPU, 512MB RAM |
| Registro imágenes | Amazon ECR | 3 repositorios |
| Logs | CloudWatch | /ecs/frontend-despachos, /ecs/backend-con-mysql |
| Roles IAM | `LabRole` | Task Role + Execution Role |

Los manifiestos JSON de las Task Definitions están en `infra/task-definitions/`.

---

## Registro de imágenes (Amazon ECR)

Las imágenes se publican automáticamente con el pipeline CI/CD. Cada imagen tiene dos tags:
- `latest` → siempre apunta a la versión más reciente
- `SHA del commit` → permite trazabilidad exacta de qué versión está en producción

```bash
# Ver imágenes en ECR
aws ecr describe-images \
  --repository-name frontend-despacho \
  --region us-east-1 \
  --query 'imageDetails[*].{Tag:imageTags[0],Fecha:imagePushedAt}' \
  --output table
```

---

## Pipeline CI/CD (GitHub Actions)

Archivo: `.github/workflows/deploy.yml`

### Flujo completo

```
Push a rama main
      │
      ├─► JOB 1: deploy-backend
      │     ├─ Checkout código
      │     ├─ Setup JDK 17
      │     ├─ chmod +x mvnw
      │     ├─ ./mvnw -B -DskipTests package
      │     ├─ Configurar credenciales AWS (GitHub Secrets)
      │     ├─ Login a Amazon ECR
      │     ├─ docker build + push (tags: SHA + latest)
      │     ├─ Descargar Task Definition actual
      │     ├─ Actualizar imagen en Task Definition
      │     └─ Deploy en ECS (backend-service) ✅
      │
      └─► JOB 2: deploy-frontend (depende de JOB 1)
            ├─ Checkout código
            ├─ Configurar credenciales AWS (GitHub Secrets)
            ├─ Login a Amazon ECR
            ├─ docker build + push (tags: SHA + latest)
            ├─ Descargar Task Definition actual
            ├─ Actualizar imagen en Task Definition
            └─ Deploy en ECS (frontend-service) ✅
```

### Gestión de secretos

Las credenciales AWS se almacenan en **GitHub Secrets** y nunca aparecen en el código:

| Secret | Uso |
|--------|-----|
| `AWS_ACCESS_KEY_ID` | Autenticación AWS |
| `AWS_SECRET_ACCESS_KEY` | Autenticación AWS |
| `AWS_SESSION_TOKEN` | Token temporal (AWS Academy) |

---

## Autoscaling

Configurado con **Target Tracking** en ambos servicios:

| Parámetro | Valor |
|-----------|-------|
| Tipo | Target Tracking |
| Métrica | ECSServiceAverageCPUUtilization |
| Umbral | 50% CPU |
| Mínimo | 2 tareas |
| Máximo | 5 tareas |
| Scale-out cooldown | 300 segundos |
| Scale-in cooldown | 300 segundos |

Si el promedio de CPU supera 50%, ECS lanza nuevas tareas automáticamente. Si baja, reduce hasta el mínimo de 2.

---

## Seguridad

| Práctica | Implementación |
|----------|----------------|
| Imágenes minimalistas | node:20-alpine, nginx:1.25-alpine, mysql:5.7 |
| Usuario no-root | `appuser` (UID 1001) en contenedor frontend |
| Puertos mínimos | 8080 (frontend), 8081 (backend), MySQL solo por localhost |
| Mínimo privilegio IAM | `LabRole` preexistente, sin crear roles adicionales |
| Credenciales seguras | GitHub Secrets, nunca en el código |
| Red privada | MySQL no expone puertos fuera del contenedor |

---

## Observabilidad

Los logs de todos los contenedores se envían automáticamente a **Amazon CloudWatch**:

```bash
# Ver logs del backend en tiempo real
aws logs tail /ecs/backend-con-mysql --region us-east-1 --since 30m

# Ver logs del frontend
aws logs tail /ecs/frontend-despachos --region us-east-1 --since 30m

# Ver estado de los servicios
aws ecs describe-services \
  --cluster despachos-cluster \
  --services frontend-service backend-service \
  --query 'services[*].{Servicio:serviceName,Corriendo:runningCount,Deseado:desiredCount}' \
  --region us-east-1
```

---

## Validación funcional

```bash
# Obtener URL del frontend
aws elbv2 describe-load-balancers \
  --names despachos-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region us-east-1

# Verificar frontend (HTTP 200)
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://<ALB_DNS>

# Obtener IP del backend y verificar API
TASK=$(aws ecs list-tasks --cluster despachos-cluster \
  --service-name backend-service --query 'taskArns[0]' --output text)
ENI=$(aws ecs describe-tasks --cluster despachos-cluster --tasks $TASK \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)
IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
curl -s http://$IP:8081/api/v1/despachos
```

---

## Decisiones técnicas

| Decisión | Razón |
|----------|-------|
| ECS Fargate vs EKS | AWS Academy deniega `iam:CreateRole` (requerido por eksctl) |
| MySQL en contenedor vs RDS | AWS Academy deniega `rds:CreateDBInstance` |
| MySQL por localhost | Contenedores del mismo Task en Fargate comparten namespace de red |
| Nginx puerto 8080 vs 80 | Usuario no-root no puede usar puertos < 1024 en Linux |
| MySQL 5.7 vs 8.0 | MySQL 8.0 causa OOM (exit code 137) con los recursos disponibles |
| Monorepo único | Rúbrica exige "un repositorio" + simplifica el pipeline CI/CD |
| Script Bash para infraestructura | Permite recrear toda la infraestructura desde cero con un solo comando |

---

## Problemas encontrados y soluciones

| Problema | Causa | Solución |
|----------|-------|----------|
| `iam:CreateRole` denegado | AWS Academy restringe permisos IAM | Migrar de EKS a ECS Fargate usando `LabRole` |
| `rds:CreateDBInstance` denegado | AWS Academy restringe RDS | MySQL como contenedor en la misma Task Definition |
| `mysql-service: Name does not resolve` | Service Discovery no disponible en Academy | Comunicación por `localhost` (mismo Task) |
| Nginx: `Permission denied` en puerto 80 | Usuario no-root no puede usar puertos < 1024 | Configurar Nginx en puerto 8080 |
| `./mvnw: Permission denied` en CI | Falta de permisos en el runner de GitHub | Agregar `chmod +x mvnw` en el workflow |
| MySQL 8.0 OOM (exit code 137) | MySQL 8.0 consume demasiada RAM | Migrar a MySQL 5.7 |
| Credenciales AWS expiran cada ~4h | Sesiones temporales de AWS Academy | Renovar en `~/.aws/credentials` y GitHub Secrets |

---

## Comandos útiles

```bash
# Verificar infraestructura completa
aws ecs describe-clusters --clusters despachos-cluster --region us-east-1
aws ecs describe-services --cluster despachos-cluster \
  --services frontend-service backend-service --region us-east-1
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs --region us-east-1

# Forzar nuevo deploy
aws ecs update-service --cluster despachos-cluster \
  --service frontend-service --force-new-deployment --region us-east-1

# Eliminar infraestructura (después de entregar)
aws ecs update-service --cluster despachos-cluster --service frontend-service --desired-count 0
aws ecs update-service --cluster despachos-cluster --service backend-service --desired-count 0
aws ecs delete-service --cluster despachos-cluster --service frontend-service --force
aws ecs delete-service --cluster despachos-cluster --service backend-service --force
aws ecs delete-cluster --cluster despachos-cluster
```
