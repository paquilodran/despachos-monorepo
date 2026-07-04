markdown# Despachos — Evaluación Final Transversal ISY1101

Plataforma completa (Frontend + Backend + Base de datos) desplegada en AWS ECS Fargate
con pipeline CI/CD unificado en GitHub Actions.

## Estructura del repositorio

├── frontend/          → React + Vite + Nginx
├── backend/           → Spring Boot + Java 17
├── infra/             → Task Definitions y configuración exportada de AWS
│   └── task-definitions/
├── docker-compose.yml → Orquestación local de los 3 servicios
└── .github/workflows/ → Pipeline CI/CD único


## Arquitectura

Internet → ALB (puerto 80) → frontend-service (ECS Fargate, Nginx:8080)
→ backend-service  (ECS Fargate)
├── backend (Spring Boot:8081)
└── mysql   (MySQL:3306, mismo Task)


## Infraestructura AWS

- **Clúster:** `despachos-cluster` (Fargate, us-east-1)
- **Roles IAM:** `LabRole` (Task Role + Execution Role)
- **Red:** VPC por defecto, subredes multi-AZ
- **Balanceo:** Application Load Balancer internet-facing
- **Registro de imágenes:** Amazon ECR (3 repositorios: frontend, backend, mysql)

Ver configuración exportada real en `/infra/`:
- `cluster-config.json`
- `task-definitions/backend-task-definition.json`
- `task-definitions/frontend-task-definition.json`
- `services-config.json`
- `autoscaling-config.json`

## Autoscaling

- **Tipo:** Target Tracking
- **Métrica:** ECSServiceAverageCPUUtilization
- **Umbral:** 50% CPU
- **Mínimo:** 2 tareas · **Máximo:** 5 tareas
- Configurado en **ambos** servicios (frontend y backend)

## Pipeline CI/CD

Un solo workflow (`.github/workflows/deploy.yml`) con 2 jobs secuenciales:

1. **deploy-backend:** build Maven → build Docker → push ECR → deploy ECS (backend + mysql)
2. **deploy-frontend:** build Docker → push ECR → deploy ECS (frontend), depende de que termine el backend

## Docker Compose (desarrollo local)

```bash
docker compose up -d
```

Levanta frontend (puerto 8080), backend (puerto 8081) y MySQL (puerto 3306) con red interna y healthchecks.

## Gestión de secretos

Credenciales AWS gestionadas exclusivamente vía **GitHub Secrets**:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

Rol `LabRole` aplicado con principio de mínimo privilegio (permisos únicamente para ECS, ECR y CloudWatch).

## Validación funcional

```bash
curl http://<ALB_DNS>                          # Frontend → HTTP 200
curl http://<BACKEND_IP>:8081/api/v1/despachos # Backend → []
```

## Logs

- Frontend: CloudWatch `/ecs/frontend-despachos`
- Backend: CloudWatch `/ecs/backend-despachos`

## Decisiones técnicas

- **ECS Fargate en vez de EKS:** AWS Academy no permite `iam:CreateRole`
- **MySQL en el mismo contenedor que backend:** AWS Academy no permite RDS
- **Monorepo:** unifica app + infraestructura en un solo repositorio versionado

## Problemas encontrados

| Problema | Solución |
|----------|----------|
| EKS requiere permisos IAM no disponibles | Migrar a ECS Fargate |
| RDS no disponible en AWS Academy | MySQL como contenedor en la misma Task |
| Repos separados dificultaban evaluación | Migración a monorepo único |
| Nginx no podía usar puerto 80 sin root | Cambiar a puerto 8080 |
