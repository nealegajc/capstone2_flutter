#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

# Free port 8000 if another process is still holding it
fuser -k 8000/tcp 2>/dev/null || true

if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi

echo "=========================================================="
echo " Starting Otto Scents Vision Backend (YOLO + PaddleOCR)   "
echo " Host: http://127.0.0.1:8000                              "
echo " Docs: http://127.0.0.1:8000/docs                         "
echo "=========================================================="

exec uvicorn main:app --host 127.0.0.1 --port 8000
