#!/bin/bash
# =============================================================
# Script de infraestructura — Despachos Monorepo
# ISY1101 · AWS ECS Fargate + ALB + Autoscaling
# =============================================================

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
CLUSTER_NAME="despachos-cluster-v2"
FRONTEND_REPO="frontend-despacho"
BACKEND_REPO="backend-despachos"
MYSQL_REPO="mysql-despachos"
MONOREPO_DIR="/home/patoq/despachos-monorepo"

echo "============================================"
echo " Ejecutando Infraestructura como Código"
echo "============================================"

# FASE 1 — REPOSITORIOS ECR
echo ">>> FASE 1: Verificando repositorios ECR..."
for REPO in $FRONTEND_REPO $BACKEND_REPO $MYSQL_REPO; do
  aws ecr describe-repositories --repository-names $REPO --region $REGION &>/dev/null || \
  aws ecr create-repository --repository-name $REPO --region $REGION > /dev/null
done

# FASE 2 — COMPILACIÓN Y ENVIÓ DE IMÁGENES
echo ">>> FASE 2: Compilando y subiendo imágenes a ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Frontend
docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FRONTEND_REPO:latest $MONOREPO_DIR/frontend/
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FRONTEND_REPO:latest

# Backend
cd $MONOREPO_DIR/backend
chmod +x mvnw
./mvnw -B -DskipTests package -q
docker build -t $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$BACKEND_REPO:latest $MONOREPO_DIR/backend/
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$BACKEND_REPO:latest

# MySQL
docker pull mysql:5.7 --quiet
docker tag mysql:5.7 $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$MYSQL_REPO:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$MYSQL_REPO:latest

# FASE 3 — CLÚSTER ECS
echo ">>> FASE 3: Asegurando Clúster ECS..."
aws ecs describe-clusters --clusters $CLUSTER_NAME --region $REGION &>/dev/null || \
aws ecs create-cluster --cluster-name $CLUSTER_NAME --capacity-providers FARGATE --region $REGION > /dev/null

# FASE 4 — LEER ENTORNOS DE RED DE AWS
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text --region $REGION)
SUBNET_1=$(echo $SUBNETS | awk '{print $1}')
SUBNET_2=$(echo $SUBNETS | awk '{print $2}')
SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region $REGION)

# FASE 5 — REGISTRO DE MANIFIESTOS DEL REPOSITORIO
echo ">>> FASE 5: Registrando Manifiestos de Despliegue ECS..."
aws ecs register-task-definition --cli-input-json file://$MONOREPO_DIR/infra/ecs-manifests/backend-task-def.json --region $REGION > /dev/null
aws ecs register-task-definition --cli-input-json file://$MONOREPO_DIR/infra/ecs-manifests/frontend-task-def.json --region $REGION > /dev/null

# FASE 6 — APPLICATION LOAD BALANCER
echo ">>> FASE 6: Configurando ALB..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names "despachos-alb" --region $REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "None")
if [ "$ALB_ARN" == "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer --name despachos-alb --subnets $SUBNET_1 $SUBNET_2 --security-groups $SG_ID --scheme internet-facing --region $REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $REGION --query 'LoadBalancers[0].DNSName' --output text)

TG_ARN=$(aws elbv2 describe-target-groups --names "frontend-tg" --region $REGION --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "None")
if [ "$TG_ARN" == "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group --name frontend-tg --protocol HTTP --port 8080 --vpc-id $VPC_ID --target-type ip --health-check-path "/" --region $REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
fi

aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION &>/dev/null || \
aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN --region $REGION > /dev/null

# FASE 7 — SERVICIOS ECS
echo ">>> FASE 7: Creando o actualizando Servicios de Contenedores..."
aws ecs describe-services --cluster $CLUSTER_NAME --services backend-service --region $REGION 2>/dev/null | grep -q "ACTIVE" || \
aws ecs create-service --cluster $CLUSTER_NAME --service-name backend-service --task-definition backend-con-mysql --desired-count 2 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" --region $REGION > /dev/null

aws ecs describe-services --cluster $CLUSTER_NAME --services frontend-service --region $REGION 2>/dev/null | grep -q "ACTIVE" || \
aws ecs create-service --cluster $CLUSTER_NAME --service-name frontend-service --task-definition frontend-despachos --desired-count 2 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" --load-balancers "targetGroupArn=$TG_ARN,containerName=frontend,containerPort=8080" --region $REGION > /dev/null

# FASE 8 — AUTOSCALING (HPA EQUIVALENT)
echo ">>> FASE 8: Aplicando políticas de Auto Scaling..."
for SVC in frontend-service backend-service; do
  aws application-autoscaling register-scalable-target --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SVC --scalable-dimension ecs:service:DesiredCount --min-capacity 2 --max-capacity 5 --region $REGION > /dev/null
  aws application-autoscaling put-scaling-policy --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SVC --scalable-dimension ecs:service:DesiredCount --policy-name "$SVC-cpu" --policy-type TargetTrackingScaling --target-tracking-scaling-policy-configuration '{"TargetValue": 50.0, "PredefinedMetricSpecification": {"PredefinedMetricType": "ECSServiceAverageCPUUtilization"}, "ScaleInCooldown": 300, "ScaleOutCooldown": 300}' --region $REGION > /dev/null
done

echo "============================================"
echo " INFRAESTRUCTURA CONFIGURADA CON SUCESO"
echo " URL ACCESO: http://$ALB_DNS"
echo "============================================"
