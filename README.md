# Escudo SMS - Radar IA 🛡️

O **Escudo SMS** é um aplicativo de segurança móvel evolutivo que combina Inteligência Artificial local (On-Device) com validação externa para detectar, prevenir e aprender com golpes via SMS em tempo real, focado no contexto brasileiro (PIX, Falsa Central, Phishing).

---

## 🚀 Funcionalidades Principais

### 1. Monitoramento e Proteção
*   **Interceptação Nativa**: Monitoramento de SMS recebidos em tempo real via Android nativo (Kotlin) com `BroadcastReceiver`.
*   **Análise Híbrida Inteligente**:
    *   **IA Semântica (BERT Local)**: Modelo de linguagem `MobileBERT` (TFLite) rodando no dispositivo para entender o contexto da mensagem instantaneamente.
    *   **Validação Externa**: Integração com APIs de reputação para URLs suspeitas.
    *   **Busca Vetorial (RAG)**: Comparação de similaridade com base de dados de ameaças conhecidas usando SQLite com extensão vetorial.
*   **Auto-Aprendizado (Auto-RAG) 🧠**:
    *   O sistema **aprende sozinho**: novas ameaças confirmadas são automaticamente vetorizadas e adicionadas à base de conhecimento local.
*   **Alertas e Social**:
    *   **Notificações de Alta Prioridade**: Alertas imediatos na barra de status.
    *   **Compartilhamento de Alerta**: Envio rápido de avisos para contatos via WhatsApp/Telegram.

### 2. Monetização e Estratégia Comercial 💰
O aplicativo opera em modelo **Freemium** com estratégia de monetização híbrida:

*   **Período de Testes (Trial)**:
    *   7 dias iniciais de uso **Premium Gratuito** (sem anúncios, proteção total).
    *   Controle via servidor backend e `TrialController` local.
*   **Modo Freemium (Pós-Trial)**:
    *   Exibição de **Banners AdMob** no rodapé.
    *   **Paywall** (Bloqueio Visual) no Histórico de Ameaças (efeito Blur + Cadeado).
    *   Anúncios Intersticiais (Tela Cheia) em ações específicas.
*   **Assinatura Premium (RevenueCat)**:
    *   Remoção completa de anúncios.
    *   Desbloqueio do Histórico de Ameaças.
    *   Acesso a funcionalidades avançadas de Telemetria.
    *   **Mock de Pagamento**: Sistema de simulação de compra integrado para testes offline e validação de fluxo UX.

### 3. Ferramentas de Debug e Desenvolvimento 🛠️
*   **Painel de Configurações Avançado**:
    *   **Resetar Premium (Debug Mock)**: Permite voltar ao status Free para re-testar o fluxo de venda.
    *   **Simular Trial Expirado**: Toggle para forçar a exibição de anúncios e Paywall instantaneamente.
*   **Sistema de Logs Interno**:
    *   Captura e persistência de logs críticos (AdMob, Erros, Status) em arquivo `.txt` local.
    *   **Visualizador de Logs**: Tela dedicada para leitura e exportação dos logs via compartilhamento.
*   **Modo Mock Offline**:
    *   O `PaymentService` detecta automaticamente se a API Key do RevenueCat não está configurada e ativa o modo de simulação, prevenindo crashes em ambiente de desenvolvimento.

---

## 🛠️ Stack Tecnológica

*   **Frontend**: Flutter (Dart) com Clean Architecture.
*   **Backend Mobile**: Kotlin (Android Nativo) para interceptação de SMS e serviços de background.
*   **IA On-Device**: TensorFlow Lite (TFLite) com MobileBERT Int8.
*   **Banco de Dados**: SQLite + Vetores (RAG Local).
*   **Monetização**:
    *   `google_mobile_ads` (AdMob).
    *   `purchases_flutter` (RevenueCat) com fallback para Mock.
*   **Gerenciamento de Estado**: Provider (`TrialController`, `ThreatProvider`).

---

## 📦 Estrutura do Projeto

*   `android/`: Código nativo Android (Receiver, MainActivity, Services).
*   `lib/core/`: Serviços globais (IA, Banco de Dados, Isolate, Notificações, AdMob, Logs).
*   `lib/features/`: Módulos funcionais (Análise, Histórico, Configurações, Paywall).
*   `assets/models/`: Modelos TFLite e vocabulários.
*   `backend/`: Código do servidor Python (FastAPI/PostgreSQL) para orquestração global.

---

## 🔧 Instalação e Execução

### 📱 Aplicativo (Flutter)

1.  **Pré-requisitos**:
    *   Flutter SDK instalado.
    *   Dispositivo Android ou Emulador configurado.

2.  **Instalar Dependências**:
    ```bash
    flutter pub get
    ```

3.  **Configuração de Ambiente**:
    *   O arquivo `lib/core/constants/api_constants.dart` controla a URL da API (Dev/Prod).
    *   O arquivo `lib/core/services/admob_service.dart` contém os IDs de teste do AdMob.

4.  **Executar o App**:
    ```bash
    flutter run
    ```
    *   *Nota*: Para testar anúncios reais, gere a build de release: `flutter build apk`.

### 🖥️ Backend (Python)

O servidor de backend está localizado na pasta `backend/`.

1.  **Configuração Automática (Windows)**:
    Execute o script `setup.bat` na pasta `backend`. Ele criará o ambiente virtual e instalará as dependências.
    ```cmd
    cd backend
    setup.bat
    ```

2.  **Configuração Manual (Linux/Mac)**:
    ```bash
    cd backend
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ```

3.  **Executar Servidor**:
    ```bash
    # Com venv ativado:
    python main.py
    ```
    *O servidor rodará em `http://localhost:8000` (ou porta configurada).*

## 🛡️ Permissões

O aplicativo solicitará permissão para ler SMS (`RECEIVE_SMS`, `READ_SMS`) e acesso à rede (`INTERNET`, `ACCESS_NETWORK_STATE`) para validação de licença e anúncios.

## 📄 Licença

Este projeto é um protótipo educacional/demonstrativo desenvolvido pela MDXHQ Desenvolvimento ©.
