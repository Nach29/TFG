import argparse
import csv
import re
import time
from collections import Counter
from datetime import datetime
from typing import Optional

import requests

DEFAULT_URL = "http://dontpushthis.link"
DEFAULT_INTERVAL = 0.5
DEFAULT_TIMEOUT = 2.0
DEFAULT_CSV = "resultados_experimento.csv"

registro_peticiones = []
inicio_fallo = None
fin_fallo = None
rto_calculado = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sonda de telemetria para validar Zonal Shift (Fase 1)."
    )
    parser.add_argument("--url", default=DEFAULT_URL, help="URL publica a sondear")
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Segundos entre peticiones",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help="Timeout HTTP por peticion en segundos",
    )
    parser.add_argument(
        "--csv",
        default=DEFAULT_CSV,
        help="Ruta del CSV de salida",
    )
    parser.add_argument(
        "--affected-az",
        help="Availability Zone que se degrada durante la prueba, por ejemplo eu-central-1a",
    )
    return parser.parse_args()


def extraer_campo_tabla(html: str, etiqueta: str) -> Optional[str]:
    patron = rf"<td>{re.escape(etiqueta)}</td><td>(.*?)</td>"
    match = re.search(patron, html, re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    valor = re.sub(r"<.*?>", "", match.group(1))
    return valor.strip()


def extraer_metricas_respuesta(html: str) -> dict:
    web_az = extraer_campo_tabla(html, "Availability Zone")
    if not web_az:
        web_az = extraer_campo_tabla(html, "Web Region")

    return {
        "web_az": web_az or "Desconocida",
        "region": extraer_campo_tabla(html, "Region") or "Desconocida",
        "app_az": extraer_campo_tabla(html, "App AZ") or "Desconocida",
        "app_status": extraer_campo_tabla(html, "App Tier Status") or "Desconocido",
    }


def registrar_muestra(
    timestamp_actual: datetime,
    estado: str,
    codigo: int,
    web_az: str,
    region: str,
    app_az: str,
    app_status: str,
) -> None:
    registro_peticiones.append(
        {
            "timestamp": timestamp_actual.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
            "estado": estado,
            "codigo_http": codigo,
            "web_az": web_az,
            "region": region,
            "app_az": app_az,
            "app_status": app_status,
        }
    )


def contar_valores_ok(campo: str) -> Counter:
    return Counter(
        peticion[campo]
        for peticion in registro_peticiones
        if peticion["estado"] == "OK" and peticion[campo] not in {"Desconocida", "Desconocido"}
    )


def imprimir_contador(titulo: str, contador: Counter) -> None:
    print(f"\n{titulo}")
    if not contador:
        print("  Sin datos suficientes")
        return
    for clave, valor in sorted(contador.items()):
        print(f"  - {clave}: {valor}")


def imprimir_resumen(affected_az: Optional[str]) -> None:
    total_peticiones = len(registro_peticiones)
    exitosas = sum(1 for peticion in registro_peticiones if peticion["estado"] == "OK")
    fallidas = total_peticiones - exitosas

    print("\n" + "=" * 60)
    print("INFORME DEL EXPERIMENTO (FASE 1 - ZONAL SHIFT)")
    print("=" * 60)
    print(f"Total peticiones enviadas: {total_peticiones}")

    if total_peticiones > 0:
        print(f"Peticiones exitosas: {exitosas} ({round((exitosas / total_peticiones) * 100, 2)}%)")
        print(f"Peticiones no exitosas: {fallidas} ({round((fallidas / total_peticiones) * 100, 2)}%)")
    else:
        print("Peticiones exitosas: 0 (0%)")
        print("Peticiones no exitosas: 0 (0%)")

    if rto_calculado is not None:
        print(f"RTO observado: {round(rto_calculado, 2)} segundos")
    else:
        print("RTO observado: no se detecto una caida y recuperacion completa")

    imprimir_contador("Distribucion de respuestas OK por Web AZ", contar_valores_ok("web_az"))
    imprimir_contador("Distribucion de respuestas OK por App AZ", contar_valores_ok("app_az"))
    imprimir_contador("Distribucion de respuestas OK por Region", contar_valores_ok("region"))

    if affected_az:
        muestras_ok_afectada = [
            peticion for peticion in registro_peticiones
            if peticion["estado"] == "OK" and peticion["web_az"] == affected_az
        ]
        muestras_ok_post_recuperacion = [
            peticion for peticion in registro_peticiones
            if fin_fallo is not None
            and peticion["estado"] == "OK"
            and peticion["web_az"] == affected_az
            and datetime.strptime(peticion["timestamp"], "%Y-%m-%d %H:%M:%S.%f") > fin_fallo
        ]

        print(f"\nAZ degradada declarada: {affected_az}")
        print(f"Respuestas OK servidas desde la AZ degradada: {len(muestras_ok_afectada)}")

        if fin_fallo is None:
            print("Veredicto Fase 1: no se pudo comprobar el aislamiento porque no hubo recuperacion observable.")
        elif muestras_ok_post_recuperacion:
            print("Veredicto Fase 1: el trafico volvio a la AZ degradada tras la recuperacion; revisa el Zonal Shift.")
        else:
            print("Veredicto Fase 1: tras la recuperacion, no se observaron respuestas OK desde la AZ degradada.")


def exportar_csv(nombre_archivo: str) -> None:
    with open(nombre_archivo, mode="w", newline="", encoding="utf-8") as archivo_csv:
        writer = csv.DictWriter(
            archivo_csv,
            fieldnames=[
                "timestamp",
                "estado",
                "codigo_http",
                "web_az",
                "region",
                "app_az",
                "app_status",
            ],
        )
        writer.writeheader()
        writer.writerows(registro_peticiones)

    print(f"\nRegistro completo exportado a: {nombre_archivo}")


def main() -> None:
    global inicio_fallo, fin_fallo, rto_calculado

    args = parse_args()

    print("Iniciando sonda de telemetria para Zonal Shift... (Ctrl+C para detener)")
    print(f"URL objetivo: {args.url}")
    if args.affected_az:
        print(f"AZ degradada esperada: {args.affected_az}")
    print("-" * 60)

    try:
        while True:
            timestamp_actual = datetime.now()
            estado = "DESCONOCIDO"
            codigo = 0
            web_az = "Desconocida"
            region = "Desconocida"
            app_az = "Desconocida"
            app_status = "Desconocido"

            try:
                respuesta = requests.get(args.url, timeout=args.timeout)
                codigo = respuesta.status_code

                metricas = extraer_metricas_respuesta(respuesta.text)
                web_az = metricas["web_az"]
                region = metricas["region"]
                app_az = metricas["app_az"]
                app_status = metricas["app_status"]

                if codigo == 200:
                    estado = "OK"
                    print(
                        f"[  OK  ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | "
                        f"HTTP 200 | Web AZ: {web_az} | App AZ: {app_az} | Region: {region}"
                    )

                    if inicio_fallo is not None and fin_fallo is None:
                        fin_fallo = timestamp_actual
                        rto_calculado = (fin_fallo - inicio_fallo).total_seconds()
                        print(f"\n[!] SISTEMA RECUPERADO. RTO observado: {round(rto_calculado, 2)} segundos\n")

                elif codigo >= 500:
                    estado = "FAIL"
                    print(
                        f"[ FAIL ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | "
                        f"HTTP {codigo} | Web AZ: {web_az} | App AZ: {app_az} | App Status: {app_status}"
                    )
                    if inicio_fallo is None:
                        inicio_fallo = timestamp_actual
                else:
                    estado = "WARN"
                    print(
                        f"[ WARN ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | "
                        f"HTTP {codigo} | Web AZ: {web_az} | App AZ: {app_az} | Region: {region}"
                    )

            except requests.exceptions.RequestException as exc:
                estado = "TIMEOUT"
                print(f"[ TIMEOUT ] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | Error de conexion: {exc}")
                if inicio_fallo is None:
                    inicio_fallo = timestamp_actual

            registrar_muestra(timestamp_actual, estado, codigo, web_az, region, app_az, app_status)
            time.sleep(args.interval)

    except KeyboardInterrupt:
        imprimir_resumen(args.affected_az)
        exportar_csv(args.csv)
        print("=" * 60)


if __name__ == "__main__":
    main()