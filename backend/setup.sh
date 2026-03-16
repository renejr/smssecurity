#!/bin/bash

echo "[SETUP] Iniciando configuracao do Backend Python (Linux/Mac)..."

# 1. Verifica Python
if ! command -v python3 &> /dev/null
then
    echo "[ERRO] python3 nao encontrado. Instale o Python 3."
    exit 1
fi

# 2. Cria Venv
if [ ! -d "venv" ]; then
    echo "[SETUP] Criando ambiente virtual 'venv'..."
    python3 -m venv venv
else
    echo "[SETUP] Ambiente virtual 'venv' ja existe."
fi

# 3. Instala Dependencias
echo "[SETUP] Ativando venv e instalando dependencias..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "[SUCESSO] Ambiente configurado!"
echo "Para rodar o servidor, execute:"
echo "source venv/bin/activate"
echo "python3 main.py"
echo ""
