---
name: native_android_sms
description: Quando o usuário solicitar código Android nativo (Kotlin/Java), interceptação de mensagens, BroadcastReceiver, permissões de manifesto ou comunicação bridge via MethodChannel.
---

# native_android_sms

## Diretrizes de Arquitetura
- NUNCA utilize plugins Flutter de alto nível para leitura passiva de SMS.
- SEMPRE implemente a captura reativa via `BroadcastReceiver` nativo com `android:priority="999"`.
- Extraia os dados brutos utilizando `SmsMessage.createFromPdu`.

## Foco em Performance
- O código Kotlin DEVE ser extremamente leve e otimizado para evitar ANR (Application Not Responding) em aparelhos de baixo custo (ex: 4GB RAM).

## Comunicação (Bridge)
- Envie os dados interceptados imediatamente para a camada Flutter utilizando `MethodChannel`.
- Ao gerar a resposta, forneça sempre o código completo do Kotlin e a assinatura correspondente esperada no lado do Dart.

# flutter_dart_rag

## Gerenciamento de Recursos
- O app tem como alvo dispositivos intermediários antigos (~4GB RAM). O consumo de memória deve ser monitorado de perto.
- Concorrência Obrigatória: QUALQUER processamento pesado (geração de embeddings, busca vetorial no banco, inferência no LLM) DEVE rodar em uma `Isolate` separada para não causar "jank" ou travar a UI (Main Thread).

## Banco de Dados e RAG
- Utilize integração via FFI para comunicação com extensões C/C++ do SQLite (como `sqlite-vss` ou `sqlite-vec`).

## Padrão de Código
- Entregue código modular, com tipagem forte e null-safety rigoroso.
- Escreva código pronto para produção; não omita lógicas importantes com comentários do tipo `// insira seu código aqui`.

# python_stealth_scraper

## Ferramentas Mandatórias
- Utilize `Playwright` ou `Selenium`, operando preferencialmente em modo Headless.

## Técnicas de Evasão (Stealth)
- O script DEVE implementar táticas para contornar proteções e WAFs:
  - Rotação dinâmica e realista de `User-Agent`.
  - Injeção de atrasos randômicos (`time.sleep` com valores variáveis) entre as requisições.
  - Simulação de comportamento humano (ex: rolagem de página).

## Processamento e Saída
- Limpe os dados extraídos, removendo lixo HTML e ruídos.
- Estruture a saída final em um formato JSON padronizado e limpo, pronto para ser consumido e vetorizado pelo aplicativo Flutter.