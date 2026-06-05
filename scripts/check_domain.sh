#!/bin/bash

domain=$(echo "$1" | tr -d '"'\')
mode=$(echo "$2" | tr -d '"'\')

if [[ -z "$domain" ]]; then
  echo "Usage: $0 domain.com [expiry|created|age_years|registrar|ns|ns_discovery|checked|lastcheck]"
  exit 1
fi

if [[ -z "$mode" ]]; then
  mode="expiry"
fi

if [[ "$mode" == "checked" || "$mode" == "lastcheck" ]]; then
  date +"%Y-%m-%d %H:%M:%S"
  exit 0
fi

if ! command -v whois >/dev/null; then
  echo "Error: 'whois' package is required but not installed."
  exit 1
fi

whois_raw=$(whois "${domain,,}" 2>/dev/null)

if [[ "$mode" == "created" ]]; then
  created_line=$(echo "$whois_raw" | grep -Ei '(created|creation date|registered):' | head -n 1)
  created_date=$(echo "$created_line" | cut -d':' -f2- | xargs)
  [[ -z "$created_date" ]] && created_date=$(echo "$created_line" | awk '{print $NF}' | xargs)
  if [[ -n "$created_date" && "$created_date" != "null" ]]; then
    date -d "$created_date" +"%Y-%m-%d" 2>/dev/null || echo "$created_date"
  else
    echo "Unknown"
  fi

elif [[ "$mode" == "age_years" ]]; then
  created_line=$(echo "$whois_raw" | grep -Ei '(created|creation date|registered):' | head -n 1)
  created_date=$(echo "$created_line" | cut -d':' -f2- | xargs)
  [[ -z "$created_date" ]] && created_date=$(echo "$created_line" | awk '{print $NF}' | xargs)

  if [[ -n "$created_date" && "$created_date" != "null" ]]; then
    created_timestamp=$(date -d "$created_date" +%s 2>/dev/null)
    if [[ -n "$created_timestamp" ]]; then
      age_years=$(( ($(date +%s) - created_timestamp) / 31536000 ))
      echo "$age_years"
    else
      echo "0"
    fi
  else
    echo "0"
  fi

elif [[ "$mode" == "registrar" ]]; then
  # Ищем регистратора без жесткой привязки к началу строки ^ (актуально для .am)
  registrar=$(echo "$whois_raw" | grep -Ei '(registrar|registrar organization|registrar name):' | head -n 1 | cut -d':' -f2- | xargs)
  if [[ -n "$registrar" ]]; then echo "$registrar"; else echo "Unknown"; fi

elif [[ "$mode" == "ns" ]]; then
  # Пробуем стандартный поиск nserver/name server
  ns_list=$(echo "$whois_raw" | grep -Ei '(nserver|name server):' | cut -d':' -f2- | xargs | tr ' ' ',')
  
  # Если пусто (как в .am), забираем строки после "DNS servers:" до первой пустой строки
  if [[ -z "$ns_list" ]]; then
    ns_list=$(echo "$whois_raw" | awk '/DNS servers:/ {flag=1; next} /^[[:space:]]*$/ {flag=0} flag {print}' | xargs | tr ' ' ',')
  fi
  
  # Очищаем от финальных точек, если они есть
  ns_list=$(echo "${ns_list,,}" | sed 's/\.,/,/g' | sed 's/\.$//')
  
  if [[ -n "$ns_list" ]]; then echo "$ns_list"; else echo "Unknown"; fi

elif [[ "$mode" == "ns_discovery" ]]; then
  # Извлекаем NS-серверы аналогично текстовому режиму
  raw_ns=$(echo "$whois_raw" | grep -Ei '(nserver|name server):' | cut -d':' -f2- | xargs)
  if [[ -z "$raw_ns" ]]; then
    raw_ns=$(echo "$whois_raw" | awk '/DNS servers:/ {flag=1; next} /^[[:space:]]*$/ {flag=0} flag {print}' | xargs)
  fi
  
  # Формируем чистый JSON без точек на конце адресов
  echo "["
  first=true
  for ns in $raw_ns; do
    ns_clean=$(echo "${ns,,}" | sed 's/\.$//')
    if [ "$first" = true ]; then first=false; else echo ","; fi
    echo "  { \"{#NS_SERVER}\": \"$ns_clean\" }"
  done
  echo "]"

else
  # Режим подсчета дней (mode == expiry)
  expiry_line=$(echo "$whois_raw" | grep -Ei '(paid-till|expires|registry expiry date|expiration date)' | head -n 1)
  if echo "$expiry_line" | grep -q ':'; then
    expiry_date=$(echo "$expiry_line" | cut -d':' -f2- | xargs)
  else
    expiry_date=$(echo "$expiry_line" | awk '{print $NF}' | xargs)
  fi
  if [[ -n "$expiry_date" && "$expiry_date" != "null" ]]; then
    expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
    if [[ -n "$expiry_timestamp" ]]; then
      days_remaining=$(( (expiry_timestamp - $(date +%s)) / 86400 ))
      if (( days_remaining < 0 )); then echo "0"; else echo "$days_remaining"; fi
    else
      echo "Error"
    fi
  else
    echo "Error"
  fi
fi
