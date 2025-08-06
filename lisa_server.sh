#!/bin/bash

#---------------------------------------------------
# Script: LisaServer.com
# Versión: 5.7 (Lógica de consumo y menú definitivos)
# Finalidad: Monitorización y gestión del servidor.
#---------------------------------------------------

# --- Definición de Colores y Emoticonos ---
NC='\033[0m'       # Sin Color
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'

# --- Función para comprobar e instalar dependencias ---
check_dependencies() {
    echo -e "${CYAN}Verificando las dependencias necesarias...${NC}"
    local missing_apt=()

    for pkg in wget vnstat neofetch; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_apt+=("$pkg")
        fi
    done

    if [ ${#missing_apt[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ Todas las dependencias están en orden.${NC}"
        sleep 1
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  Se requiere instalar el siguiente software: ${missing_apt[*]}.${NC}"
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Para continuar, por favor ejecuta el script con sudo:${NC}"
        echo -e "   sudo $0"
        exit 1
    fi
    
    read -p "¿Deseas que el script realice la instalación ahora? (s/n): " choice
    if [[ "$choice" != "s" && "$choice" != "S" ]]; then
        echo "Instalación omitida."
        return 1
    fi

    echo "Instalando paquetes APT: ${missing_apt[*]}..."
    apt-get update &> /dev/null
    if ! apt-get install -y "${missing_apt[@]}"; then
         echo -e "${RED}❌ Error instalando paquetes con APT.${NC}"
    else
        echo -e "${GREEN}✅ Paquetes instalados correctamente.${NC}"
    fi
}

# --- FUNCIONES DE ADMINISTRACIÓN ---

change_hostname(){
    read -p "Introduce el nuevo nombre de host: " new_hostname
    if [ -z "$new_hostname" ]; then
        echo -e "${RED}El nombre no puede estar vacío.${NC}"
        return
    fi
    hostnamectl set-hostname "$new_hostname"
    echo -e "${GREEN}✅ Nombre de host cambiado a '${BOLD}$new_hostname${GREEN}'.${NC}"
    echo -e "${YELLOW}Necesitas reiniciar o volver a iniciar sesión para ver el cambio en todas partes.${NC}"
}

change_root_password(){
    echo -e "${YELLOW}A continuación, se te pedirá que introduzcas y confirmes la nueva contraseña para el usuario 'root'.${NC}"
    passwd root
}

create_myuser(){
    echo -e "${YELLOW}Este comando creará el usuario 'myuser' con contraseña 'lisa25' y permisos de sudo sin contraseña.${NC}"
    read -p "¿Estás seguro de que quieres continuar? (s/n): " confirm
    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
        echo "Ejecutando el comando de creación de usuario..."
        useradd -s /bin/bash myuser && echo 'myuser:lisa25' | chpasswd && usermod -aG sudo myuser && echo 'myuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/myuser && chmod 440 /etc/sudoers.d/myuser && history -c && cat /dev/null > ~/.bash_history && unset HISTFILE && rm -f /root/.bash_history /home/myuser/.bash_history /var/log/wtmp /var/log/btmp
        echo -e "${GREEN}✅ Proceso completado.${NC}"
    else
        echo "Operación cancelada."
    fi
}

reboot_server() {
    read -p "$(echo -e "${RED}${BOLD}¿ESTÁS COMPLETAMENTE SEGURO DE QUE QUIERES REINICIAR EL SERVIDOR? (s/n): ${NC}")" confirm
    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
        echo -e "${YELLOW}Reiniciando el servidor en 3 segundos...${NC}"
        sleep 3
        reboot
    else
        echo "Reinicio cancelado."
    fi
}

# --- FUNCIONES DE MONITORIZACIÓN ---

get_download_speed() {
    echo -e "\n${CYAN}--- 📥 Probando Velocidad de Descarga ---${NC}"
    wget -O /dev/null http://ipv4.download.thinkbroadband.com/100MB.zip
}

get_data_usage() {
    if ! command -v vnstat &> /dev/null; then
        echo -e "\n${RED}🚫 'vnstat' no está instalado.${NC}"; return;
    fi
    echo -e "\n${CYAN}--- 📊 Resumen de Consumo de Datos ---${NC}"
    local interface
    interface=$(ip route | grep default | sed -e 's/^.*dev.//' -e 's/.proto.*//' | head -n1 || echo "eth0")
    echo -e "Mostrando estadísticas para la interfaz: ${YELLOW}${interface}${NC}\n"

    local vnstat_raw_output
    vnstat_raw_output=$(vnstat -i "$interface")
    if [ -z "$vnstat_raw_output" ]; then
        echo -e "${YELLOW}No se pudieron obtener datos de 'vnstat'. ¿El servicio está en ejecución y ha recolectado datos?${NC}"
        return
    fi

    print_data_line() {
        local emoji=$1 label=$2 line=$3 color=$4
        if [ -n "$line" ]; then
            local rx_data tx_data total_data
            rx_data=$(echo "$line" | awk '{print $2, $3}')
            tx_data=$(echo "$line" | awk '{print $5, $6}')
            total_data=$(echo "$line" | awk '{print $8, $9}')
            printf "${emoji}  %-20s | ${GREEN}%-17s${NC} | ${CYAN}%-17s${NC} | ${color}%-17s${NC}\n" "$label" "$rx_data" "$tx_data" "$total_data"
        fi
    }

    printf "${BOLD}%-22s | %-17s | %-17s | %-17s${NC}\n" "PERIODO" "RECIBIDO (↓)" "ENVIADO (↑)" "TOTAL"
    echo "------------------------------------------------------------------------------------"

    # --- LÓGICA DE EXTRACCIÓN DEFINITIVA v5.7 ---
    local today_line=$(echo "$vnstat_raw_output" | grep -E "hoy|today")
    
    # Extraer SÓLO las líneas de datos de meses (contienen una comilla y un año de 2 dígitos)
    local all_monthly_lines=$(echo "$vnstat_raw_output" | grep -E "\w{3,4} '[0-9]{2}")

    local current_month_line=$(echo "$all_monthly_lines" | tail -n 1)
    
    local previous_month_line=""
    if [ "$(echo "$all_monthly_lines" | wc -l)" -gt 1 ]; then
        previous_month_line=$(echo "$all_monthly_lines" | tail -n 2 | head -n 1)
    fi
    
    # El total de los últimos 30 días es la línea de resumen de la sección diaria
    local daily_total_line=$(echo "$vnstat_raw_output" | awk '/daily/,0' | grep -A 1 -- '------------------------' | tail -n 1)

    print_data_line "☀️" "Hoy" "$today_line" "${BOLD}${YELLOW}"
    print_data_line "📅" "Mes Actual" "$current_month_line" "${BOLD}${GREEN}"
    print_data_line "⏮️" "Mes Pasado" "$previous_month_line" "${BOLD}${CYAN}"
    print_data_line "🗓️" "Últimos 30 días" "$daily_total_line" "${BOLD}${MAGENTA}"
}

get_server_specs() {
    echo -e "\n${CYAN}--- 💻 Características del Servidor (con Neofetch) ---${NC}"
    neofetch
}

# --- Inicio del Script ---
clear
check_dependencies || read -p "Presiona Enter para continuar con funcionalidad limitada..."

# Bucle infinito que muestra el menú principal
while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo "    +------------------------------------------------------+"
    echo "    |                    LisaServer.com                    |"
    echo "    |       Panel de Gestión y Monitorización v5.7         |"
    echo "    +------------------------------------------------------+"
    echo -e "${NC}"
    echo -e "${MAGENTA}--- Administración ---${NC}"
    echo -e "   ${GREEN}1.${NC}${CYAN} Cambiar Nombre de Host"
    echo -e "   ${GREEN}2.${NC}${CYAN} Cambiar Contraseña de Root"
    echo -e "   ${GREEN}3.${NC}${YELLOW} Crear Usuario 'myuser'"
    echo -e "${MAGENTA}--- Monitorización ---${NC}"
    echo -e "   ${GREEN}4.${NC}${CYAN} Probar Velocidad de Descarga"
    echo -e "   ${GREEN}5.${NC}${CYAN} Consultar Consumo de Datos"
    echo -e "   ${GREEN}6.${NC}${CYAN} Características del Servidor"
    echo -e "${MAGENTA}--- Sistema ---${NC}"
    echo -e "   ${CYAN}20.${NC}${RED} Reiniciar Servidor"
    echo -e "   ${CYAN}0.${NC}${RED} Salir"
    echo ""

    read -p "$(echo -e "${YELLOW}Selecciona una opción: ${NC}")" choice

    case $choice in
        1) change_hostname ;;
        2) change_root_password ;;
        3) create_myuser ;;
        4) get_download_speed ;;
        5) get_data_usage ;;
        6) get_server_specs ;;
        20) reboot_server ;;
        0)
            echo -e "\n${MAGENTA}Saliendo del script. ¡Hasta luego! ✨${NC}\n"
            exit 0 ;;
        *)
            echo -e "\n${RED}Opción no válida.${NC}" ;;
    esac
    read -p "$(echo -e "\n${YELLOW}Presiona Enter para volver al menú...${NC}")"
done