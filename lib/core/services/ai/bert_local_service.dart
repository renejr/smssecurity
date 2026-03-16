import 'dart:io';

import 'package:smssecurity/core/services/ai/bert_tokenizer.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart'; // Para ler o arquivo copiado

class BertLocalService {
  Interpreter? _interpreter;
  BertTokenizer? _tokenizer;
  bool _isInitialized = false;

  // Dimensões do modelo BERT-Tiny padrão (MobileBERT pode variar)
  static const int maxLen = 128;
  static int outputSize = 512; // MobileBERT Float32 (TFHub) tem output 512. Ajustado.

  Future<void> init({String? vocabContent, String? modelPath}) async {
    if (_isInitialized) return;

    try {
      // 1. Carrega o Vocabulário
      // Prioridade: Conteúdo injetado > Arquivo Físico Local > Asset (Fallback instável)
      
      if (vocabContent != null) {
        _tokenizer = BertTokenizer.fromString(vocabContent, maxLen: maxLen);
      } else {
        // Tenta ler do arquivo físico copiado pelo main()
        try {
           final dir = await getApplicationDocumentsDirectory();
           final vocabFile = File('${dir.path}/vocab.txt');
           if (await vocabFile.exists()) {
             final content = await vocabFile.readAsString();
             _tokenizer = BertTokenizer.fromString(content, maxLen: maxLen);
             print("📖 Vocab carregado de arquivo local (Bypass rootBundle).");
           } else {
             throw Exception("vocab.txt não existe localmente.");
           }
        } catch (e) {
           print("⚠️ Falha ao ler vocab local: $e. Tentando asset (pode falhar em background)...");
           // Último recurso: Asset
           try {
              _tokenizer = await BertTokenizer.fromAsset('assets/models/vocab.txt', maxLen: maxLen);
           } catch (e2) {
              print("❌ Falha fatal no vocab: $e2. Usando tokenizer vazio.");
              _tokenizer = BertTokenizer.fromString("", maxLen: maxLen); 
           }
        }
      }
      
      // Tenta carregar o modelo. Se falhar (arquivo não existe), segue sem crashar.
      try {
        final options = InterpreterOptions();
        
        if (modelPath != null) {
          // Carrega de arquivo (ideal para Isolates)
          _interpreter = await Interpreter.fromFile(File(modelPath), options: options);
        } else {
          // Fallback para asset (funciona na Main Thread, pode falhar em Isolate antigo)
          _interpreter = await Interpreter.fromAsset('assets/models/bert_tiny.tflite', options: options);
        }
        
        // Ajusta outputSize dinamicamente baseado no shape real do modelo carregado
        if (_interpreter != null) {
           final outputTensor = _interpreter!.getOutputTensor(0);
           print('🧠 IA Real (BERT-Tiny) carregada. Output Shape Real: ${outputTensor.shape}');
           
           if (outputTensor.shape.length == 2) {
              // Ex: [1, 512] ou [1, 2]
              outputSize = outputTensor.shape[1];
              
              if (outputSize == 2) {
                print("⚠️ O modelo carregado parece ser um classificador binário (logits [1, 2]), não um feature extractor.");
                print("⚠️ Usaremos a saída do classificador como 'pseudo-embedding' (não ideal, mas funcional para teste).");
                // TODO: Recomendar baixar o modelo correto (MobileBERT Feature Extractor)
              }
           }
        }

      } catch (e) {
        print('Aviso: Erro ao carregar .tflite (Path: $modelPath). O app usará embeddings simulados. Erro: $e');
      }
      
      _isInitialized = true;
    } catch (e) {
      print('Erro fatal no BERT Service: $e');
    }
  }

  /// Gera o embedding para o texto fornecido.
  /// Retorna List<double> com dimensão [outputSize].
  Future<List<double>> getEmbedding(String text) async {
    // Se o modelo não carregou, retorna vetor dummy determinístico (para testes de fluxo)
    if (_interpreter == null || _tokenizer == null) {
      // Simulação baseada em hash para manter consistência sem o arquivo binário
      final seed = text.codeUnits.fold(0, (prev, element) => prev + element);
      // Gera vetor aleatório mas determinístico para o mesmo texto
      return List.generate(outputSize, (i) => (seed % (i + 1)) / 1000.0);
    }

    try {
      // 1. Tokenização
      final inputIds = _tokenizer!.tokenize(text);
      
      // 2. Preparação de Inputs
      // A maioria dos modelos BERT exportados para TFLite espera [batch, seq_len] int32
      // Alguns exigem 3 inputs (ids, mask, types). Vamos tentar o padrão simples (1 input).
      // Se falhar, o catch captura e loga.
      
      var input = [inputIds]; // Shape: [1, 128]
      
      // 3. Preparação de Output
      // O MobileBERT geralmente retorna [1, 512] se for output simples, ou [1, 128, 512] se for sequência.
      // Vamos tentar alocar [1, outputSize] primeiro.
      // Se falhar, o catch vai capturar e podemos ajustar no futuro.
      var output = List.filled(1 * outputSize, 0.0).reshape([1, outputSize]);

      // 4. Inferência
      // MobileBERT pode exigir 3 inputs: [input_ids, input_mask, segment_ids]
      // Se tivermos apenas 1 input no modelo, run() funciona.
      // Se o modelo baixado exigir 3, precisamos criar buffers zerados para mask/segment.
      
      final inputTensors = _interpreter!.getInputTensors();
      
      if (inputTensors.length == 3) {
         // Cria inputs adicionais dummy (tudo 0 ou 1)
         var inputMask = [List.filled(maxLen, 1)]; // 1 = token válido
         var segmentIds = [List.filled(maxLen, 0)]; // 0 = sentença A
         
         // A ordem dos inputs depende do modelo. Geralmente ids, mask, segment.
         // Mas precisamos passar LISTA DE OBJETOS para runForMultipleInputs se for positional,
         // ou MAP se for por nome. A API do tflite_flutter usa List para inputs posicionais.
         
         // Tentativa 1: Assumir ordem [ids, mask, segment]
         var inputs = [input, inputMask, segmentIds];
         var outputs = {0: output}; // Output tensor index 0
         
         try {
            _interpreter!.runForMultipleInputs(inputs, outputs);
         } catch (e) {
            // Se falhar, tenta só com 1 input mesmo que tenha 3 tensores (alguns sao opcionais?)
            // Ou tenta ordem diferente?
            print("Tentativa de inferência multi-input falhou: $e");
            // Fallback para single input
            _interpreter!.run(input, output);
         }
      } else {
         // Caso simples (1 input)
         _interpreter!.run(input, output);
      }
      
      // 5. Extração
      return List<double>.from(output[0]);
    } catch (e) {
      print('Erro na inferência do modelo: $e');
      // Fallback seguro
      return List.filled(outputSize, 0.0);
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
