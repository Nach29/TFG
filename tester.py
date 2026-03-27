import requests
import time
import re
import csv
from datetime import datetime

# --- CONFIGURACIÓN ---
# Sustituye esto por la URL de tu balanceador
ALB_URL = "http://TU-BALANCEADOR-AQUI.elb.amazonaws.com"
TIEMPO_ESPERA = 0.5 # Medio segundo entre peticiones

# --- VARIABLES DE TELEMETRÍA ---
registro_peticiones = []
inicio_fallo = None
fin_fallo = None
rto_calculado = None

print("Iniciando sonda de telemetría... (Pulsa Ctrl+C para detener y generar el informe)")
print("-" * 60)

try:
    while True:
        timestamp_actual = datetime.now()
        estado = "DESCONOCIDO"
        codigo = 0
        region = "Desconocida"
        
        try:
            respuesta = requests.get(ALB_URL, timeout=2)
            codigo = respuesta.status_code
            
            # Buscar la zona o región en el HTML
            match = re.search(r'<td>Availability Zone</td><td>(.*?)</td>', respuesta.text)
            if not match:
                match = re.search(r'<td>Web Region</td><td>(.*?)</td>', respuesta.text)
            region = match.group(1) if match else "Desconocida"

            if codigo == 200:
                estado = "OK"
                print(f"[\033[92m  OK  \033[0m] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | HTTP 200 | Zona: {region}")
                
                # Lógica para calcular el RTO (Si venimos de un fallo y de repente hay un OK)
                if inicio_fallo is not None and fin_fallo is None:
                    fin_fallo = timestamp_actual
                    rto_calculado = (fin_fallo - inicio_fallo).total_seconds()
                    print(f"\n\033[93m[!] ¡SISTEMA RECUPERADO! Tiempo de caída (RTO): {rto_calculado} segundos\033[0m\n")
                    
            elif codigo >= 500:
                estado = "FAIL"
                print(f"[\033[91m FAIL \033[0m] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | HTTP {codigo} | Zona: {region}")
                
                # Registrar el momento exacto en el que empieza el desastre
                if inicio_fallo is None:
                    inicio_fallo = timestamp_actual

        except requests.exceptions.RequestException as e:
            estado = "TIMEOUT"
            print(f"[\033[91m TIMEOUT \033[0m] {timestamp_actual.strftime('%H:%M:%S.%f')[:-3]} | Error de conexión")
            if inicio_fallo is None:
                inicio_fallo = timestamp_actual

        # Guardar en el registro para el CSV final
        registro_peticiones.append({
            "timestamp": timestamp_actual.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
            "estado": estado,
            "codigo_http": codigo,
            "zona_region": region
        })
        
        time.sleep(TIEMPO_ESPERA)

except KeyboardInterrupt:
    # Cuando pulsas Ctrl+C, se genera el informe
    print("\n" + "=" * 60)
    print("📊 INFORME DEL EXPERIMENTO (CAOS ENGINEERING)")
    print("=" * 60)
    
    total_peticiones = len(registro_peticiones)
    exitosas = sum(1 for p in registro_peticiones if p["estado"] == "OK")
    fallidas = total_peticiones - exitosas
    
    print(f"Total peticiones enviadas: {total_peticiones}")
    print(f"Peticiones exitosas (200): {exitosas} ({round((exitosas/total_peticiones)*100, 2)}%)")
    print(f"Peticiones fallidas (5XX): {fallidas} ({round((fallidas/total_peticiones)*100, 2)}%)")
    
    if rto_calculado:
        print(f"\n⏱️  Métrica de Resiliencia (RTO): {round(rto_calculado, 2)} segundos")
    else:
        print("\n⏱️  Métrica de Resiliencia (RTO): No se detectó una caída y recuperación completa.")

    # Exportar a CSV
    nombre_archivo = "resultados_experimento.csv"
    with open(nombre_archivo, mode='w', newline='') as archivo_csv:
        writer = csv.DictWriter(archivo_csv, fieldnames=["timestamp", "estado", "codigo_http", "zona_region"])
        writer.writeheader()
        writer.writerows(registro_peticiones)
    
    print(f"\n💾 Registro completo exportado a: {nombre_archivo}")
    print("=" * 60)