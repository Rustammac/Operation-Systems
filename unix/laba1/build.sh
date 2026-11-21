
#!/bin/sh

set -u

# 1. Проверка аргументов
usage() {
    echo "Usage: $0 <source-file>" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

srcfile=$1

if [ ! -f "$srcfile" ]; then
    echo "$0: '$srcfile' is not a regular file" >&2
    exit 1
fi

if [ ! -r "$srcfile" ]; then
    echo "$0: '$srcfile' is not readable" >&2
    exit 1
fi

# 2. Сохранение начальной директории
startdir=$(pwd) || {
    echo "$0: failed to determine current directory" >&2
    exit 7
}

# 3. Получение абсолютного пути к исходному файлу
case "$srcfile" in
    /*)
        srcabs=$srcfile
        ;;
    *)
        srcabs=$startdir/$srcfile
        ;;
esac

srcbase=${srcfile##*/}

# 4. Поиск имени выходного файла в комментарии
outname=$(
    awk '
    {
        if (match($0, /^[[:space:]]*(\/\/|#|%)[[:space:]]*Output:[[:space:]]*[^[:space:]]+/)) {
            result = substr($0, RSTART, RLENGTH)
            sub(/^[[:space:]]*(\/\/|#|%)[[:space:]]*Output:[[:space:]]*/, "", result)
            print result
            exit
        }

        if (match($0, /\/\*[[:space:]]*Output:[[:space:]]*[^[:space:]]+/)) {
            result = substr($0, RSTART, RLENGTH)
            sub(/^\/\*[[:space:]]*Output:[[:space:]]*/, "", result)
            print result
            exit
        }
    }
    ' "$srcabs"
) || {
    echo "$0: failed to read output filename" >&2
    exit 3
}

if [ -z "$outname" ]; then
    echo "$0: Output comment not found in '$srcfile'" >&2
    exit 3
fi

# 5. Проверка имени выходного файла
case "$outname" in
    */*|.|..)
        echo "$0: invalid output filename '$outname'" >&2
        exit 3
        ;;
esac

case "$outname" in
    *[!a-zA-Z0-9._-]*)
        echo "$0: invalid characters in output filename" >&2
        exit 3
        ;;
esac

if [ "$outname" = "$srcbase" ]; then
    echo "$0: output filename must differ from source filename" >&2
    exit 3
fi

# 6. Создание временной директории
tmpdir=$(mktemp -d) || {
    echo "$0: failed to create temporary directory" >&2
    exit 5
}

# 7. Функция очистки
cleanup() {
    result=$?
    trap - 0
    rm -rf "$tmpdir"
    exit "$result"
}

# Установка ловушки сразу после создания временной директории
trap cleanup 0

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 141' PIPE
trap 'exit 143' TERM

# 8. Переход во временную директорию
cd "$tmpdir" || {
    echo "$0: failed to enter temporary directory" >&2
    exit 7
}

# 9. Направление временных файлов компилятора в нашу директорию
TMPDIR=$tmpdir
export TMPDIR

# 10. Компиляция
case "$srcbase" in

    *.c)
        if ! gcc -Wall -Wextra -O2 \
            -o "$outname" \
            "$srcabs" 2>build.log
        then
            cat build.log >&2
            exit 2
        fi
        ;;

    *.cpp|*.cc|*.cxx)
        if ! g++ -Wall -Wextra -O2 \
            -o "$outname" \
            "$srcabs" 2>build.log
        then
            cat build.log >&2
            exit 2
        fi
        ;;

    *.tex)
        if ! pdflatex -interaction=nonstopmode -halt-on-error \
            -output-directory "$tmpdir" \
            "$srcabs" >build.log 2>&1
        then
            cat build.log >&2
            exit 2
        fi

        texbase=${srcbase%.tex}

        if [ ! -s "$texbase.pdf" ]; then
            cat build.log >&2
            exit 2
        fi

        if [ "$texbase.pdf" != "$outname" ]; then
            mv "$texbase.pdf" "$outname" || {
                echo "$0: failed to rename PDF file" >&2
                exit 2
            }
        fi
        ;;

    *)
        echo "$0: unsupported source file type '$srcbase'" >&2
        exit 4
        ;;

esac

# 11. Копирование результата в начальную директорию
if ! cp "$outname" "$startdir/$outname"; then
    echo "$0: failed to copy output file" >&2
    exit 6
fi

echo "Build successful: $startdir/$outname"
