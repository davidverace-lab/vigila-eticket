#!/bin/bash
# Versión para GitHub Actions: vigila el evento de eticket.mx y manda push al iPhone (app ntfy)
# cuando aparezca un 2x1 o cambie cualquier boleto/precio.

IDEVENTO=35978
URL="https://www.eticket.mx/masinformacion.aspx?idevento=$IDEVENTO"
TOPIC="eticket-2x1-3tnx0ock34"       # tema en ntfy.sh (suscríbete a este tema en la app ntfy del iPhone)
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

export LC_ALL=C
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
mkdir -p estado
log(){ echo "$(date -u '+%Y-%m-%d %H:%M:%S') $*"; }

avisar(){ # $1 = título, $2 = mensaje
  local t="$1" m="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -H "Title: $t" -H "Priority: high" -H "Tags: tada,ticket" -H "Click: $URL" \
    -d "$m" "https://ntfy.sh/$TOPIC")
  log "ntfy push: HTTP $code"
  log "AVISO: $t | $m"
}

# 1) Token de invitado (igual que lo hace la página)
TOKEN=$(curl -s --max-time 30 -A "$UA" -X POST -H "Referer: $URL" \
  "https://www.eticket.mx/webRequests/Access/Auth.ashx?action=getGuestToken" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
[ -z "$TOKEN" ] && log "ERROR: no se pudo obtener token"

# 2) Precios/boletos desde la API
PRECIOS=""
if [ -n "$TOKEN" ]; then
  PRECIOS=$(curl -s --max-time 30 -A "$UA" -H "Authorization: Bearer $TOKEN" \
    -H "Origin: https://www.eticket.mx" -H "Referer: $URL" \
    "https://api.eticket.com.mx/v2/event/prices/$IDEVENTO" | python3 "$DIR/precios.py" 2>/dev/null)
  [ -z "$PRECIOS" ] && log "ERROR: la API de precios no respondió"
fi

# 3) Texto visible de la página (por si el 2x1 lo ponen como banner o leyenda)
HTML_TXT=$(curl -s --max-time 30 -A "$UA" "$URL" | perl -0pe 's/<script.*?<\/script>//gs; s/<!--.*?-->//gs; s/<[^>]+>/ /g; s/\s+/ /g')
[ -z "$HTML_TXT" ] && log "ERROR: no se pudo descargar la página"

# --- Detección de 2x1 (en precios o en la página) ---
if printf '%s\n%s' "$PRECIOS" "$HTML_TXT" | grep -qiE '(^|[^0-9])2 ?x ?1([^0-9]|$)'; then
  if [ ! -f estado/avisado_2x1 ]; then
    avisar "¡2x1 en Destino Dos Equis (eticket)!" "Apareció el 2x1. Boletos ahora: $(printf '%s' "$PRECIOS" | tr '\n' ';') -> $URL"
    touch estado/avisado_2x1
  fi
else
  rm -f estado/avisado_2x1
fi

# --- Detección de cualquier cambio en boletos/precios (nuevo tipo, nueva zona, precio distinto) ---
if [ -n "$PRECIOS" ]; then
  if [ -f estado/precios_actual.txt ] && ! diff -q estado/precios_actual.txt <(printf '%s\n' "$PRECIOS") >/dev/null; then
    avisar "Cambiaron los boletos de Destino Dos Equis" "ANTES: $(tr '\n' ';' < estado/precios_actual.txt) || AHORA: $(printf '%s' "$PRECIOS" | tr '\n' ';') -> $URL"
  fi
  printf '%s\n' "$PRECIOS" > estado/precios_actual.txt
fi

log "OK: $(printf '%s' "$PRECIOS" | tr '\n' ';')"
