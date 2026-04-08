import csv
import re
import time
from datetime import datetime

import requests

# --- CONFIGURACION ---
# Se mantiene el dominio publico como objetivo por defecto.
ALB_URL = "http://dontpushthis.link"
TIEMPO_ESPERA = 0.5
TIMEOUT_REQUEST = 2

# --- VARIABLES DE TELEMETRIA ---
registro_peticiones = []
inicio_fallo = None
fin_fallo = None
rto_calculado = None


def extraer_zona_o_region(html: str) -> str:
    """
    Extrae la zona o la region desde el HTML renderizado por la capa web.

    La sonda sigue siendo compatible con variantes antiguas del HTML que
    mostraban "Web Region" en lugar de "Availability Zone".
    """
    match = re.search(r"<td>Availability Zone</td><td>(.*?)</td>", html)
    if not match:
        match = re.search(r"<td>Web Region</td><td>(.*?)</td>", html)
    return match.group(1) if match else "Desconocida"


def registrar_muestra(timestamp_actual: datetime, estado: str, codigo: int, region: str) -> None:
    registro_peticiones.append(
        {
            "timestamp": timestamp_actual.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
            "estado": estado,
            "codigo_http": codigo,
            "zona_region": region,
        }
    )


def imprimir_resumen() -> None:
    total_peticiones = len(registro_peticiones)
    exitosas = sum(1 for peticion in registro_peticiones if peticion["estado"] == "OK")
    fallidas = total_peticiones - exitosas

    print("\n" + "=" * 60)
    print("INFORME DEL EXPERIMENTO (CAOS ENGINEERING)")
    print("=" * 60)
    print(f"Total peticiones enviadas: {total_peticiones}")
    print(f"Peticiones exitosas (200): {exitosas} ({round((exitosas / total_peticiones) * 100, 2)}%)")
    print(f"Peticiones fallidas (5XX): {fallidas} ({round((fallidas / total_peticiones) * 100, 2)}%)")

    if rto_calculado:
        print(f"\nMetrica de Resiliencia (RTO): {round(rto_calculado, 2)} segundos")
    else:
        print("\nMetrica de Resiliencia (RTO): No se detecto una caida y recuperacion completa.")


def exportar_csv(nombre_archivo: str = "resultados_experimento.csv") -> None:
    with open(nombre_archivo, mode="w", newline="") as archivo_csv:
        writer = csv.DictWriter(
            archivo_csv,
            fieldnames=["timestamp", "estado", "codigo_http", "zona_region"],
        )
        writer.writeheader()
        writer.writerows(registro_peticiones)

    print(f"\nRegistro completo exportado a: {nombre_archivo}")


print("Iniciando sonda de telemetria... (Pulsa Ctrl+C para detener y generar el informe)")
print("-" * 60)

try:
    while True:
        timestamp_actual = datetime.now()
        estado = "DESCONOCIDO"
        codigo = 0
        region = "Desconocida"

        try:
            respuesta = requests.get(ALB_URL, timeout=TIMEOUT_REQUEST)
            codigo = respuesta.status_code
            region = extraer_zona_o_region(respuesta.text)

            if codigo == 200:
                estado = "OK"
                print(f"[  OK  ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | HTTP 200 | Zona: {region}")

                # Si venimos de un fallo y llega el primer 200 OK, el sistema se ha recuperado.
                if inicio_fallo is not None and fin_fallo is None:
                    fin_fallo = timestamp_actual
                    rto_calculado = (fin_fallo - inicio_fallo).total_seconds()
                    print(f"\n[!] SISTEMA RECUPERADO! Tiempo de caida (RTO): {rto_calculado} segundos\n")

            elif codigo >= 500:
                estado = "FAIL"
                print(f"[ FAIL ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | HTTP {codigo} | Zona: {region}")

                if inicio_fallo is None:
                    inicio_fallo = timestamp_actual

        except requests.exceptions.RequestException:
            estado = "TIMEOUT"
            print(f"[ TIMEOUT ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | Error de conexion")
            if inicio_fallo is None:
                inicio_fallo = timestamp_actual

        registrar_muestra(timestamp_actual, estado, codigo, region)
        time.sleep(TIEMPO_ESPERA)

except KeyboardInterrupt:
    imprimir_resumen()
    exportar_csv()
    print("=" * 60)
