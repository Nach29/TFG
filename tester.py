import urllib.request
import urllib.error
import time
import re

ALB_URL = "http://tfg-student-icolasma-tfg-alb-233782545.eu-central-1.elb.amazonaws.com/"

print(f"Iniciando inyección de tráfico hacia: {ALB_URL}")
print("Esperando respuestas...")
print("-" * 60)

while True:
    try:
        req = urllib.request.urlopen(ALB_URL, timeout=3)
        html = req.read().decode('utf-8')
        status_code = req.getcode()
    except urllib.error.HTTPError as e:
        html = e.read().decode('utf-8')
        status_code = e.code
    except Exception as e:
        print(f"[\033[93m ALERTA \033[0m] ALB Inaccesible: {e}")
        time.sleep(1)
        continue

    az_match = re.search(r'<td>Web AZ</td><td>(.*?)</td>', html)
    web_az = az_match.group(1) if az_match else "Desconocida"

    if status_code >= 500:
        print(f"[\033[91m FAIL \033[0m] HTTP {status_code} | Zona: {web_az} | ¡Fallo de Backend detectado!")
    else:
        print(f"[\033[92m  OK  \033[0m] HTTP {status_code} | Zona: {web_az} | Funcionamiento normal")

    time.sleep(0.5)