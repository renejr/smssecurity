# Contexto do Projeto: Escudo Anti-Golpes de SMS

## Visão Geral
* **Objetivo:** Desenvolver um aplicativo Android focado em segurança defensiva que intercepta mensagens SMS em tempo real, analisa o conteúdo e alerta o usuário imediatamente sobre possíveis golpes ou fraudes, antes de qualquer interação manual.
* **Foco de Hardware:** O aplicativo DEVE ser altamente otimizado para rodar de forma fluida em smartphones intermediários e antigos (ex: Samsung linha A, com ~4GB de RAM). A gestão de memória (evitar Out Of Memory - OOM) é prioridade máxima.

## Stack Tecnológico e Arquitetura
1.  **Interface e Orquestração (Frontend/Core):** Flutter com Dart.
2.  **Interceptação Nativa (Backend Mobile):** Kotlin/Java. Uso estrito de `BroadcastReceiver` com prioridade máxima e comunicação via `MethodChannel` para enviar os dados brutos do SMS ao Flutter instantaneamente. Não usar bibliotecas genéricas de SMS que rodam em background passivo.
3.  **Banco de Dados (Memória/RAG):** SQLite com extensão vetorial (ex: `sqlite-vss` ou similar via FFI) para armazenar embeddings de golpes conhecidos e realizar buscas por similaridade (cosine similarity).
4.  **Inteligência Artificial (Motor de Decisão):** LLM Local quantizado e de tamanho reduzido (ex: TinyLlama 1.1B, H2O-Danube 1.8B ou Gemma 2b) rodando via `llama.cpp` ou `MLC LLM` no dispositivo.
5.  **Inteligência Externa (Servidor de Alimentação):** Web Scraper em Python (Selenium) varrendo sites como o Reclame Aqui para alimentar uma base de dados central que sincronizará novos padrões de golpes com o SQLite local do app.

## Papel do Agente no Projeto
* **Especialista Mobile e IA:** Fornecer códigos nativos (Kotlin) perfeitamente integrados ao Flutter (Dart).
* **Foco em Performance:** Ao escrever queries para o SQLite ou integrar o LLM local, priorizar a economia de RAM, processamento em Threads separadas (Isolates no Dart) e uso eficiente de recursos do aparelho para não travar a UI.
* **Código Completo:** Ao gerar scripts ou classes, entregue o código pronto para produção, sem omitir partes importantes com comentários do tipo `// adicione sua lógica aqui`.

## Modo Detetive
Antes de criar, refatorar o codigo sempre que tiver duvidas sobre a implementação me pergunte.

## Modelo de Negócios e Monetização (Arquitetura)
* **Estratégia de Retenção (7 Dias Free Trial):** O aplicativo oferece 7 dias iniciais de experiência PREMIUM absoluta. Durante este período, o app DEVE funcionar sem qualquer tipo de anúncio (Ads) e com todas as funções de segurança liberadas.
* **Transição Pós-Trial (Freemium / Paywall):** Após o 7º dia, o aplicativo entra em modo restrito:
  - Exibe uma tela de conversão (Paywall) para a compra da licença definitiva via In-App Purchases (ex: RevenueCat).
  - Ativa a exibição de anúncios (ex: Google AdMob) para os usuários que optarem por continuar na versão gratuita.
* **Gerenciamento de Estado (UI):** O Flutter deve utilizar um gerenciamento de estado global (ex: `isPremium`, `trialDaysLeft`). A interface deve injetar os `AdBannerWidgets` apenas se o usuário não for Premium E o trial tiver expirado.
* **Segurança da Licença:** A contagem dos dias de teste e a validação da compra devem ser protegidas (ex: checagem online ou criptografia local) para impedir que o usuário zere os 7 dias apenas limpando o cache do Android.

## Internacionalização e Escalabilidade Global (i18n / l10n)
* **Interface (UI) Multilíngue:** O Flutter DEVE ser configurado desde o "Dia Zero" para suportar múltiplos idiomas (padrão `intl` / `AppLocalizations`). NENHUMA string de texto deve ser "hardcoded" (chumbada) diretamente nos widgets.
* **Segmentação de Banco de Dados (RAG Regional):** A tabela do SQLite Vetorial DEVE incluir campos de metadados para `region_code` (ex: BR, US, IN) e `language`. A busca de similaridade (cosine similarity) do SMS recebido deve priorizar os vetores da mesma região para evitar falsos positivos com golpes estrangeiros.
* **Motor de IA Adaptativo:** O prompt montado no Dart e enviado para o LLM Local deve instruir o modelo a analisar e, caso necessário, traduzir ou classificar a fraude respeitando o idioma original do SMS interceptado e a localidade do usuário.