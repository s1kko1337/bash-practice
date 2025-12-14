#!/bin/bash

# Скрипт запуска benchmark и сбора метрик производительности
# Запускает monitor.sh, собирает CPU/MEM метрики, сохраняет в файлы
#
# Использование: ./run_benchmark.sh [длительность_сек]

# Параметры
# ${1:-30} - первый аргумент скрипта, если не задан - используем 30
TEST_DURATION=${1:-30}

# Файлы для результатов
LOG_FILE="benchmark_test.log"
METRICS_FILE="metrics.txt"

echo "### [2] ПАРАМЕТРЫ ТЕСТИРОВАНИЯ"
echo ""
echo "  Длительность теста: ${TEST_DURATION}с"
echo "  Интервал мониторинга: 2с"
echo "  Процессов по CPU: 3"
echo "  Процессов по памяти: 3"
echo "  Файл лога: $LOG_FILE"
echo ""

# Подготовка окружения для monitor.sh

echo "### [3] ЗАПУСК ПРИЛОЖЕНИЯ"
echo ""

export TOP_CPU_COUNT=10           # Количество топ-процессов по CPU
export TOP_MEM_COUNT=10         # Количество топ-процессов по памяти
export MONITOR_INTERVAL=1       # Интервал между проверками [сек]
export OUTPUT_FILE="$LOG_FILE"   # Файл для записи логов

rm -f "$LOG_FILE"

echo "Запуск monitor.sh..."

# Запуск monitor.sh в фоновом режиме

./monitor.sh &

# $! - спец. переменная bash содержит PID последнего запущенного фонового процесса
MONITOR_PID=$!

echo "  PID процесса: $MONITOR_PID"

sleep 3

if ! kill -0 $MONITOR_PID 2>/dev/null; then
    echo "Ошибка: процесс не запустился"
    exit 1
fi

echo "  Статус: Запущен"
echo ""

# Сбор метрик производительности

echo "Сбор метрик производительности..."

> "$METRICS_FILE"

# Счётчик успешно собранных образцов
SAMPLE_COUNT=0

for i in $(seq 1 $TEST_DURATION); do
    # Проверяем, что процесс всё ещё работает
    if kill -0 $MONITOR_PID 2>/dev/null; then

        # pgrep -P PID - находит дочерние процессы с родителем PID
        # tr '\n' ',' - заменяет переводы строк на запятые
        # sed 's/,$//' - удаляет последнюю запятую
        #   s/,$//' - substitute, запятая в конце строки ($) на пустоту
        ALL_PIDS=$(pgrep -P $MONITOR_PID 2>/dev/null | tr '\n' ',' | sed 's/,$//')

        # -n "$VAR" - проверка что строка НЕ пустая
        if [ -n "$ALL_PIDS" ]; then
            # Объединяем родительский PID со списком дочерних
            ALL_PIDS="$MONITOR_PID,$ALL_PIDS"
        else
            ALL_PIDS="$MONITOR_PID"
        fi

        # ps -p "PIDS" - показывает информацию о процессах с указанными PID
        #   -o %cpu= - выводит только колонку CPU без заголовка (= убирает заголовок)
        #
        # awk '{sum+=$1} END {...}' - суммирование всех значений:
        #   {sum+=$1} - на каждой строке добавляем первое поле к sum
        #   END {...} - выполняется после обработки всех строк
        #   NR - количество обработанных строк
        #   printf "%.2f" - вывод с 2 знаками после запятой
        CPU=$(ps -p "$ALL_PIDS" -o %cpu= 2>/dev/null | awk '{sum+=$1} END {if(NR>0) printf "%.2f", sum; else print "0.00"}')
        MEM=$(ps -p "$ALL_PIDS" -o %mem= 2>/dev/null | awk '{sum+=$1} END {if(NR>0) printf "%.2f", sum; else print "0.00"}')

        # Защита от пустых значений
        CPU=${CPU:-0.00}
        MEM=${MEM:-0.00}
        # -z "$VAR" - проверка что строка пустая
        [ -z "$CPU" ] && CPU="0.00"
        [ -z "$MEM" ] && MEM="0.00"

        echo "$CPU $MEM" >> "$METRICS_FILE"

        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

        if [ $((i % 5)) -eq 0 ]; then
            echo "  Прогресс: $i/${TEST_DURATION}с (CPU: ${CPU}%, MEM: ${MEM}%)"
        fi
    else
        echo "  Процесс завершился досрочно на ${i}с"
        break
    fi

    sleep 1
done

# Остановка мониторинга

if kill -0 $MONITOR_PID 2>/dev/null; then
    kill $MONITOR_PID 2>/dev/null
    wait $MONITOR_PID 2>/dev/null || true
fi

sleep 2

echo ""
echo "Сбор метрик завершен"
echo "Собрано образцов: $SAMPLE_COUNT"

# Экспорт переменных для GitHub Actions

# $GITHUB_ENV - спец. файл GitHub Actions для передачи переменных между шагами
if [ -n "$GITHUB_ENV" ]; then
    echo "SAMPLE_COUNT=$SAMPLE_COUNT" >> "$GITHUB_ENV"
    echo "TEST_DURATION=$TEST_DURATION" >> "$GITHUB_ENV"
fi
