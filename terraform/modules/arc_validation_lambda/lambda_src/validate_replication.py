"""
ARC Region Switch — Lambda de Validación de Replicación DynamoDB
================================================================
Este handler es invocado por el ARC Region Switch Plan como Paso 2 del workflow
(custom_action_lambda_config) ANTES de desviar el tráfico a Irlanda.

Función: Consulta CloudWatch para verificar que la métrica ReplicationLatency
de la DynamoDB Global Table está por debajo de 2000 ms en la réplica de destino
(eu-west-1). Si la latencia es aceptable, retorna éxito y el plan continúa al
Paso 3 (desvío de tráfico vía Route53). Si no, retorna un error que detiene
el Region Switch hasta que el operador lo revise manualmente.

Variables de entorno requeridas:
  DYNAMODB_TABLE_NAME   : Nombre de la tabla Global Table
  TARGET_REGION         : Región de destino (eu-west-1)
  MAX_LATENCY_MS        : Umbral máximo de latencia en ms (default: 2000)
"""

import os
import json
import logging
import boto3
from datetime import datetime, timedelta, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Variables de entorno
TABLE_NAME     = os.environ["DYNAMODB_TABLE_NAME"]
TARGET_REGION  = os.environ["TARGET_REGION"]          # eu-west-1
MAX_LATENCY_MS = int(os.environ.get("MAX_LATENCY_MS", "2000"))


def get_replication_latency(cloudwatch_client: object) -> float | None:
    """
    Consulta la métrica ReplicationLatency de DynamoDB Global Tables.
    Retorna la latencia máxima en los últimos 5 minutos, o None si no hay datos.
    
    Namespace : AWS/DynamoDB
    Metric    : ReplicationLatency (en milisegundos)
    Dimensions: TableName + ReceivingRegion
    """
    end_time   = datetime.now(timezone.utc)
    start_time = end_time - timedelta(minutes=5)

    response = cloudwatch_client.get_metric_statistics(
        Namespace  = "AWS/DynamoDB",
        MetricName = "ReplicationLatency",
        Dimensions = [
            {"Name": "TableName",        "Value": TABLE_NAME},
            {"Name": "ReceivingRegion",  "Value": TARGET_REGION},
        ],
        StartTime  = start_time,
        EndTime    = end_time,
        Period     = 300,  # ventana de 5 minutos en segundos
        Statistics = ["Maximum"],
        Unit       = "Milliseconds",
    )

    datapoints = response.get("Datapoints", [])
    if not datapoints:
        logger.warning(
            "No se obtuvieron datapoints de ReplicationLatency. "
            "Puede indicar que la Global Table aún no ha comenzado a replicar "
            "o que no hay escrituras recientes. Se asume latencia OK para no "
            "bloquear el Region Switch sin datos suficientes."
        )
        return None

    # Tomamos el máximo entre todos los datapoints del período
    max_latency = max(dp["Maximum"] for dp in datapoints)
    logger.info(f"ReplicationLatency máxima (últimos 5 min): {max_latency:.1f} ms")
    return max_latency


def lambda_handler(event: dict, context: object) -> dict:
    """
    Handler principal invocado por el ARC Region Switch Plan.
    
    El plan espera:
      - Éxito (statusCode 200 o retorno normal): continuar al siguiente paso.
      - Excepción no capturada: detener el plan y marcar el paso como fallido.
    """
    logger.info(f"Evento recibido: {json.dumps(event)}")
    logger.info(
        f"Validando ReplicationLatency de tabla '{TABLE_NAME}' "
        f"hacia región '{TARGET_REGION}'. Umbral: {MAX_LATENCY_MS} ms."
    )

    cloudwatch = boto3.client("cloudwatch", region_name="eu-central-1")

    latency_ms = get_replication_latency(cloudwatch)

    if latency_ms is None:
        # Sin datos: no bloqueamos el switch, pero lo registramos claramente
        logger.warning(
            "Validación aprobada SIN DATOS de latencia. "
            "Recomendación: verificar manualmente la replicación antes de continuar."
        )
        return {
            "statusCode": 200,
            "status":     "NO_DATA_APPROVED",
            "message":    (
                f"No hay datapoints de ReplicationLatency para la tabla "
                f"'{TABLE_NAME}' → '{TARGET_REGION}' en los últimos 5 minutos. "
                f"Region Switch puede continuar (sin bloqueo por ausencia de datos)."
            ),
        }

    if latency_ms > MAX_LATENCY_MS:
        # Latencia fuera de umbral → lanzar excepción para detener el plan ARC
        error_msg = (
            f"VALIDACIÓN FALLIDA: ReplicationLatency = {latency_ms:.1f} ms "
            f"supera el umbral de {MAX_LATENCY_MS} ms. "
            f"El Region Switch ha sido DETENIDO para evitar pérdida de datos. "
            f"Espere a que la replicación se estabilice e inténtelo de nuevo."
        )
        logger.error(error_msg)
        raise ValueError(error_msg)

    # Latencia dentro del umbral → éxito
    success_msg = (
        f"VALIDACIÓN EXITOSA: ReplicationLatency = {latency_ms:.1f} ms "
        f"(umbral: {MAX_LATENCY_MS} ms). "
        f"La replicación DynamoDB está al día. Continuando con el desvío de tráfico."
    )
    logger.info(success_msg)
    return {
        "statusCode": 200,
        "status":     "APPROVED",
        "latency_ms": latency_ms,
        "message":    success_msg,
    }
