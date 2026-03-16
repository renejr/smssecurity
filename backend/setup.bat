@echo off
echo [SETUP] Iniciando configuracao do Backend Python...

:: 1. Verifica se o Python esta instalado
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Python nao encontrado. Instale o Python 3.10+ e adicione ao PATH.
    pause
    exit /b
)

:: 2. Cria o Ambiente Virtual (venv) se nao existir
if not exist "venv" (
    echo [SETUP] Criando ambiente virtual 'venv'...
    python -m venv venv
) else (
    echo [SETUP] Ambiente virtual 'venv' ja existe.
)

:: 3. Ativa o venv e instala dependencias
echo [SETUP] Ativando venv e instalando dependencias...
call venv\Scripts\activate
pip install --upgrade pip
pip install -r requirements.txt

echo.
echo [SUCESSO] Ambiente configurado!
echo Para rodar o servidor, execute:
echo call venv\Scripts\activate
echo python main.py
echo.
pause
