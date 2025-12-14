#!/bin/bash

# Проверяем наличие файла, если он есть - получаем переменные из него
if [ -f .env ]; then
    source .env
fi

# Задаем пропущенные переменные или все (при отсутствии их в .env) ${переменная из окружения:-дефолтное знаечение}
TOP_CPU_COUNT=${TOP_CPU_COUNT:-5}           # Количество процессов для мониторинга по процессору
TOP_MEM_COUNT=${TOP_MEM_COUNT:-5}           # Количество процессов для мониторинга по памяти
MONITOR_INTERVAL=${MONITOR_INTERVAL:-10}    # Интервал между проверками [сек]
OUTPUT_FILE=${OUTPUT_FILE:-"monitor.log"}   # Имя файла для записи логов
PID_FILE=${PID_FILE:-"/tmp/monitor.pid"}    # Файл для хранения PID при запуске в фоне

# Булевых флаги (меняются при наличии аргументов при запуске): флаг вывода в консоль и флаг фонового режима соответственно
VERBOSE=false
DAEMON=false

# Типовая функция для вывода информации об использовании скрипта
help() {
    # $0 - спец. переменная,хранит путь к текущему скрипту
    echo "Использование: $0 -ОПЦИЯ"
    echo ""
    echo "Опции:"
    echo "  -d, --daemon     Запуск в фоновом режиме"
    echo "  -v, --verbose    Вывод лога в консоль"
    echo "  -s, --stop       Остановить фоновый процесс"
    echo "  -h, --help       Показать справку"
    echo ""
    echo "Переменные окружения:"
    echo "  TOP_CPU_COUNT      Кол-во процессов по CPU (по умолчанию: 5)"
    echo "  TOP_MEM_COUNT      Кол-во процессов по памяти (по умолчанию: 5)"
    echo "  MONITOR_INTERVAL   Интервал в секундах (по умолчанию: 10)"
    echo "  OUTPUT_FILE        Имя файла лога (по умолчанию: monitor.log)"
}

# Функция остановки скрипта при запуске в фоне
stopDaemon() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        
        # kill -0 - проверка существования процесса по его айдишнику, без отправки сигнала. ошибки дропаем
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            echo "Процесс $pid остановлен"
        else
            echo "Процесс $pid не найден"
            rm -f "$PID_FILE"
        fi
    else
        echo "PID-файл не найден. Демон не запущен?"
    fi
    exit 0
}

# логирование - первый аргумент выводим в лог файл, если у нас режим с выводом в консоль, то еще и в нее
logLine() {
    local line="$1"
    echo "$line" >> "$OUTPUT_FILE"
    
    if [ "$VERBOSE" = true ]; then
        echo "$line"
    fi
}

# основная функция для мониторинга 
monitor() {
    while true; do
        currentTime=$(date "+%Y-%m-%d %H:%M:%S")
        
        # топ процессов по нагруженности процессора
        
        # ps aux --no-headers показываем все процессы без строки заголовков
        #   a - процессы всех пользователей
        #   u - user-ориентированный формат
        #   x - фоновые процессы
        #
        # | передаёт stdout одной команды на stdin другой 
        # у нас такой пайплайн: (stdout ps -> stdin sort -> stdout sort -> 
        #                        stdin head -> stdout head -> stdin в цикл,
        #                        считывание строки с разбиением через пробел по переменным искобчая интерпретацию бэкслэша)
        #
        # sort -k3 -n -r сортировка:
        #   -k3 - по 3-й колонке (%CPU)
        #   -n - числовая сортировка
        #   -r - в обратном порядке
        #
        # head -n N - берем то кол-во строк, которое указано в окружении
        # while read -r VAR1 VAR2 VAR3 ... - читает строку и разбивает по пробелам в переменные
        #   -r - отключает интерпретацию /
        #   command - последняя переменная, захватывает всё оставшееся (включая пробелы)
        #
        # Колонки ps aux: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
        ps aux --no-headers | sort -k3 -n -r | head -n "$TOP_CPU_COUNT" | while read -r user pid cpu mem vsz rss tty stat start time command; do
            memoryBytes=$((rss * 1024)) #кб в б
            processName=$(basename "${command%% *}") 
            logLine "$currentTime | $pid | $processName | ${cpu}% | $memoryBytes | CPU"
        done
        
        # топ процессов по оперативной памяти
        # все аналогично, но сортируем по rss (реальному использованию памяти)
        ps aux --no-headers | sort -k6 -n -r | head -n "$TOP_MEM_COUNT" | while read -r user pid cpu mem vsz rss tty stat start time command; do
            memoryBytes=$((rss * 1024)) #кб в б
            processName=$(basename "${command%% *}")
            logLine "$currentTime | $pid | $processName | ${cpu}% | $memoryBytes | MEM"
        done
        
        # sleep N - приостанавливаем выполнение на заданное кол-во секунд
        sleep "$MONITOR_INTERVAL"
    done
}

# парсинг аргументов
# $# - количество аргументов командной строки
# -gt - больше чем
while [[ $# -gt 0 ]]; do
    case $1 in 
        -d|--daemon)
            DAEMON=true
            # shift - сдвигает аргументы: $2 становится $1, $3 становится $2 и т.д.
            # Также уменьшает $# на 1
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--stop)
            stopDaemon
            ;;
        -h|--help)
            help
            exit 0
            ;;
        #аналог default в switch-case
        *)
            echo "Неизвестный параметр: $1"
            help
            exit 1
            ;;
    esac
done

# Непосредственно запуск
if [ "$DAEMON" = true ]; then
    echo "Запуск в фоновом режиме..."

    # Останавливаем старый процесс, если он существует
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        
        if kill -0 "$pid" 2>/dev/null; then
            echo "Останавливаем предыдущий процесс ($pid)..."
            kill "$pid"
        fi
        rm -f "$PID_FILE"
    fi
    # nohup - игнорируем SIGHUP сигнал (закрытие терминала)
    # > /dev/null - перенаправляет stdout в никуда
    # & - запуск в фоне
    nohup "$0" > /dev/null 2>&1 &
    
    echo $! > "$PID_FILE"
    
    echo "PID: $(cat "$PID_FILE")"
    echo "Для остановки: $0 --stop"
else
    monitor
fi
