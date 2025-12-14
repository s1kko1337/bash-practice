#!/bin/bash

# Скрипт анализа результатов benchmark
# Обрабатывает логи и метрики, выводит итоговый отчёт
#
# Использование: ./analyze_results.sh
# Ожидает файлы: benchmark_test.log, metrics.txt

# Файлы с данными

LOG_FILE="benchmark_test.log"
METRICS_FILE="metrics.txt"

# Раздел 4: Анализ логов приложения

echo ""
echo "### [4] АНАЛИЗ ВЫХОДНЫХ ДАННЫХ"
echo ""

if [ -f "$LOG_FILE" ]; then
    LOG_LINES=$(wc -l < "$LOG_FILE")

    LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)

    CPU_RECORDS=$(grep -c "| CPU$" "$LOG_FILE" || echo "0")
    MEM_RECORDS=$(grep -c "| MEM$" "$LOG_FILE" || echo "0")

    echo "Файл лога:"
    echo "  Всего записей: $LOG_LINES"
    echo "  Размер файла: $LOG_SIZE"
    echo "  CPU записей: $CPU_RECORDS"
    echo "  MEM записей: $MEM_RECORDS"

    echo ""
    echo "Примеры записей (первые 5):"
    head -n 5 "$LOG_FILE" | while read line; do
        echo "  $line"
    done
else
    echo "Файл лога не найден"
    LOG_LINES=0
    LOG_SIZE="0"
    CPU_RECORDS=0
    MEM_RECORDS=0
fi

# Раздел 5: Расчёт метрик производительности

echo ""
echo "### [5] МЕТРИКИ ПРОИЗВОДИТЕЛЬНОСТИ"
echo ""

# -f FILE - файл существует
# -s FILE - файл существует И не пустой (size > 0)
if [ -f "$METRICS_FILE" ] && [ -s "$METRICS_FILE" ]; then

    # Среднее значение CPU (1-я колонка)
    AVG_CPU=$(awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0.00"}' "$METRICS_FILE")

    # Среднее значение MEM (2-я колонка)
    AVG_MEM=$(awk '{sum+=$2; count++} END {if(count>0) printf "%.2f", sum/count; else print "0.00"}' "$METRICS_FILE")

    # Поиск максимума:
    # {if($1>max) max=$1} - если текущее значение больше max, обновляем max
    # max изначально = 0 (автоинициализация awk)
    MAX_CPU=$(awk '{if($1>max) max=$1} END {printf "%.2f", max}' "$METRICS_FILE")
    MAX_MEM=$(awk '{if($2>max) max=$2} END {printf "%.2f", max}' "$METRICS_FILE")

    echo "Использование CPU:"
    echo "  Среднее: ${AVG_CPU}%"
    echo "  Максимум: ${MAX_CPU}%"
    echo ""

    echo "Использование памяти:"
    echo "  Среднее: ${AVG_MEM}%"
    echo "  Максимум: ${MAX_MEM}%"
    echo ""

    # Пропускная способность
    if [ -n "$TEST_DURATION" ] && [ "$TEST_DURATION" -gt 0 ] && [ "$LOG_LINES" -gt 0 ]; then
        THROUGHPUT=$(echo "scale=2; $LOG_LINES / $TEST_DURATION" | bc)
        echo "Производительность:"
        echo "  Записей в секунду: $THROUGHPUT"
        echo ""
    fi
else
    echo "Нет данных для анализа"
    AVG_CPU="0.00"
    MAX_CPU="0.00"
    AVG_MEM="0.00"
    MAX_MEM="0.00"
fi

# Раздел 6: Итоговый отчёт

echo ""
echo "================================"
echo "  ИТОГОВЫЙ ОТЧЕТ"
echo "================================"
echo ""

echo "### РЕЗУЛЬТАТЫ BENCHMARK"
echo ""

# Информация о среде CI 
echo "Тестовая среда:"
if [ -n "$GITHUB_ACTIONS" ]; then
    # $GITHUB_* - переменные окружения GitHub Actions
    echo "  Runner: GitHub Actions"
    echo "  Событие: ${GITHUB_EVENT_NAME:-unknown}"
    echo "  Ветка: ${GITHUB_REF_NAME:-unknown}"
    echo "  Commit: ${GITHUB_SHA:-unknown}"
else
    echo "  Runner: Локальный запуск"
    echo "  Хост: $(hostname)"
fi
echo ""

echo "Производительность приложения:"
echo "  Длительность теста: ${TEST_DURATION:-N/A}с"
echo "  Собрано образцов: ${SAMPLE_COUNT:-N/A}"
echo "  CPU (средн./макс.): ${AVG_CPU}% / ${MAX_CPU}%"
echo "  Память (средн./макс.): ${AVG_MEM}% / ${MAX_MEM}%"
echo ""

echo "Выходные данные:"
echo "  Записей в лог: $LOG_LINES"
echo "  Размер лога: $LOG_SIZE"
echo "  CPU записей: $CPU_RECORDS"
echo "  MEM записей: $MEM_RECORDS"
echo ""

# Оценка производительности

echo "### ОЦЕНКА"
echo ""

AVG_CPU_INT=$(echo "$AVG_CPU" | cut -d. -f1)
AVG_CPU_INT=${AVG_CPU_INT:-0}

if [ "$AVG_CPU_INT" -lt 5 ]; then
    echo "  CPU: Отлично (низкое потребление)"
elif [ "$AVG_CPU_INT" -lt 15 ]; then
    echo "  CPU: Хорошо (умеренное потребление)"
else
    echo "  CPU: Высокое потребление"
fi

AVG_MEM_INT=$(echo "$AVG_MEM" | cut -d. -f1)
AVG_MEM_INT=${AVG_MEM_INT:-0}

if [ "$AVG_MEM_INT" -lt 1 ]; then
    echo "  Память: Отлично (низкое потребление)"
elif [ "$AVG_MEM_INT" -lt 5 ]; then
    echo "  Память: Хорошо (умеренное потребление)"
else
    echo "  Память: Высокое потребление"
fi

echo ""
echo "================================"
echo "  BENCHMARK ЗАВЕРШЕН"
echo "================================"

# Экспорт переменных для GitHub Actions

# Записываем метрики в $GITHUB_ENV для использования в других шагах
if [ -n "$GITHUB_ENV" ]; then
    {
        echo "LOG_LINES=$LOG_LINES"
        echo "LOG_SIZE=$LOG_SIZE"
        echo "CPU_RECORDS=$CPU_RECORDS"
        echo "MEM_RECORDS=$MEM_RECORDS"
        echo "AVG_CPU=$AVG_CPU"
        echo "MAX_CPU=$MAX_CPU"
        echo "AVG_MEM=$AVG_MEM"
        echo "MAX_MEM=$MAX_MEM"
    } >> "$GITHUB_ENV"
fi
