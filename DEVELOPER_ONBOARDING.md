# EnviroTrack — Guia de Onboarding para Desenvolvedores

> **Para quem é este documento:** desenvolvedor que está assumindo o projeto sem conhecimento prévio do domínio de monitoramento ambiental nem das regras de negócio do sistema. Leia do início ao fim antes de tocar em qualquer código.

---

## 1. O que é este sistema e por que ele existe

Empresas de consultoria ambiental (como WALM, Arcadis, Geo etc.) são contratadas por grandes indústrias (Vale, Petrobras, BASF, Cubatão S.A.) para monitorar o estado de recursos hídricos próximos às operações dessas indústrias. Essa obrigação é, muitas vezes, imposta por licenças ambientais emitidas por órgãos como IBAMA, CETESB ou SEMAD.

O monitoramento funciona assim: periodicamente (mensal, trimestral, semestral), técnicos ambientais vão a campo com equipamentos de medição portáteis e visitam pontos físicos pré-cadastrados — nascentes, drenos, piezômetros, vertedouros — onde coletam parâmetros físico-químicos da água, tiram fotos, registram GPS e anotam observações. Tudo isso é depois consolidado em relatórios técnicos entregues ao cliente e aos órgãos reguladores.

**O EnviroTrack é o sistema digital que substitui planilhas, papel e câmera separada nesse processo.** Ele tem duas peças:

| Peça | Repositório | Stack | Propósito |
|------|-------------|-------|-----------|
| **App mobile** | `ETx_mobile_web` | Flutter (Android/iOS) | Uso em campo pelo técnico, offline-first |
| **Protótipo web** | `ETx` | HTML/CSS/JS puro | Mockup funcional de referência para UX |

Este documento cobre os dois, mas o app mobile é o produto de produção. O protótipo web serve como referência visual e de comportamento.

---

## 2. Vocabulário do domínio (glossário obrigatório)

Antes de qualquer coisa, memorize estes termos. Eles aparecem em todo o código.

| Termo | O que é |
|-------|---------|
| **Campanha** | Evento de campo com data, cliente e lista de pontos a coletar. Ex: "Vale Carajás — Campanha Março 2026". Uma campanha pode ter dezenas de pontos. |
| **Ponto de coleta** | Local físico cadastrado permanentemente no sistema com código único (ex: `NAS-001`). O código nunca muda, mesmo que o ponto fique inativo. |
| **Coleta / Registro** | O ato de visitar um ponto durante uma campanha e registrar os dados (parâmetros, fotos, GPS, obs). |
| **NC (Não Coletado)** | Quando o técnico chega ao ponto mas não consegue coletar — acesso negado, ponto seco, equipamento quebrado. Deve ser registrado com justificativa obrigatória. |
| **Parâmetros** | Medições físico-químicas da água: pH, temperatura, condutividade elétrica (CE), oxigênio dissolvido (OD), potencial redox (ORP), turbidez, vazão, nível d'água, profundidade. |
| **Estabilização** | Processo obrigatório para piezômetros e coletas de qualidade. O técnico aguarda os parâmetros estabilizarem (variação < critério) antes de registrar o valor final. O sistema acompanha e valida isso. |
| **Evidência / Foto** | Registro fotográfico obrigatório em campo (mínimo 3 fotos por ponto). Armazenado localmente, enviado ao S3 quando houver conexão. |
| **OS (Ordem de Serviço)** | Sinônimo de campanha no contexto operacional. Cada campanha tem um número de OS (ex: `#2.01.03.51042`). |
| **CC (Centro de Custo)** | Código financeiro interno que identifica o projeto contratante. Ex: `CC-2024-VALE-PA`. |
| **Nascente (NAS)** | Afloramento natural de água subterrânea. Parâmetros: pH, temperatura, CE, OD, ORP, turbidez, vazão. |
| **Drenagem (DRN)** | Canal artificial ou natural de escoamento. Parâmetros: vazão, nível, turbidez. |
| **Vertedouro (VRT)** | Estrutura de controle de fluxo (barragem, SUMP). Parâmetros: vazão, nível, turbidez. |
| **Piezômetro (PZ / inst)** | Instrumento para medir nível d'água subterrânea. Parâmetros primários: nível, profundidade. Parâmetros opcionais: físico-químicos completos (quando há água suficiente). |
| **SMEWW** | Standard Methods for the Examination of Water and Wastewater — norma americana que define como cada parâmetro deve ser medido. Aparece nos relatórios como referência de método (ex: `SMEWW 4500H+ B` para pH). |
| **Relatório F.057.03** | Formulário interno de relatório de ensaio. Cada coleta gera um desse, com cabeçalho, tabela de parâmetros, galeria de fotos, assinaturas e código de auditoria. |

---

## 3. Arquitetura geral

### 3.1 Visão macro

```
┌─────────────────────────────────────────────────┐
│              App Mobile (Flutter)               │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  SQLite  │  │  Camera  │  │  Geolocator  │  │
│  │ (sqflite)│  │ (picker) │  │     GPS      │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │              │               │           │
│  ┌────▼──────────────▼───────────────▼───────┐  │
│  │              DatabaseHelper               │  │
│  │          (fonte da verdade local)         │  │
│  └────────────────────┬──────────────────────┘  │
│                       │                         │
│  ┌────────────────────▼──────────────────────┐  │
│  │              SyncQueue (SQLite)           │  │
│  │    fila persistente de operações          │  │
│  └────────────────────┬──────────────────────┘  │
│                       │                         │
│  ┌────────────────────▼──────────────────────┐  │
│  │              SyncService                  │  │
│  │   push batch → pull updates               │  │
│  │   + EvidenceUploader (S3)                 │  │
│  └────────────────────┬──────────────────────┘  │
└───────────────────────┼─────────────────────────┘
                        │  REST (HTTPS/JSON)
                        │
┌───────────────────────▼─────────────────────────┐
│           Backend NestJS (API v1)               │
│  POST /api/v1/mobile/sync/batch  (push)         │
│  GET  /api/v1/mobile/sync/pull   (pull)         │
│  POST /api/v1/mobile/evidences/upload-url       │
│  POST /api/v1/mobile/evidences/:id/confirm      │
└─────────────────────────────────────────────────┘
```

### 3.2 Princípio offline-first

O app funciona **100% sem internet**. O técnico vai a campo em áreas remotas onde não há sinal. A regra é:

1. Todo dado é salvo primeiro no SQLite local.
2. Uma fila (`sync_queue`) registra cada operação que precisa ir ao servidor.
3. Quando há conexão, o `SyncService` processa a fila em background.
4. O servidor responde com atualizações que são aplicadas ao SQLite local.

Nunca salve dados exclusivamente na memória ou num estado volátil que se perde ao fechar o app.

### 3.3 Segurança

- **JWT + Refresh Token**: armazenados no `FlutterSecureStorage` (iOS Keychain / Android Keystore AES-256). Nunca em `SharedPreferences`.
- **Chave usada**: `ecoflow.v2.auth_session` (diferente da v1 para evitar leitura de dados não criptografados de versões antigas).

---

## 4. Banco de dados (SQLite local)

### 4.1 Tabelas principais

| Tabela | Propósito |
|--------|-----------|
| `campaigns` | Campanhas recebidas do servidor ou criadas localmente |
| `field_points` | Pontos de coleta, um por linha, vinculados a uma campanha |
| `collection_records` | Registro de coleta por ponto (parâmetros, estabilização, obs) |
| `collection_evidences` | Metadados de cada foto (caminho local, status de upload, S3 key) |
| `sync_queue` | Fila de operações pendentes de envio ao servidor |
| `sync_log` | Histórico das sessões de sincronização (para diagnóstico) |

### 4.2 Versionamento do schema

O schema é migrado via `onUpgrade` no `DatabaseHelper`. A versão atual é **4**.

| Versão | O que foi adicionado |
|--------|----------------------|
| v1 | Schema inicial |
| v2 | `sync_queue`, `sync_log` |
| v3 | `collection_evidences`, colunas de estabilização em `field_points` |
| v4 | `weather_conditions_json`, `checklist_pop_json`, `obs_tags_json`, `observations_text` em `field_points` |

**Regra de ouro:** nunca altere o schema sem incrementar `_dbVersion` e adicionar o `ALTER TABLE` correspondente em `onUpgrade`. Jamais use `DROP TABLE` em upgrade — o SQLite local do usuário contém dados reais de campo.

---

## 5. Tipos de pontos e parâmetros por tipo

Cada tipo de ponto tem um conjunto específico de parâmetros que devem ser coletados. O código usa a enum `CollectionType`:

| Código | Tipo | Parâmetros obrigatórios | Parâmetros opcionais |
|--------|------|------------------------|----------------------|
| `nasc` | Nascente | pH, Temperatura, CE, OD, ORP, Turbidez, Vazão | — |
| `dren` | Drenagem | Vazão, Nível d'água, Turbidez | — |
| `vert` | Vertedouro | Vazão, Nível d'água, Turbidez | — |
| `inst` | Piezômetro | Nível d'água, Profundidade | pH, Temperatura, CE, OD, ORP, Turbidez (apenas se houver água suficiente) |
| `fq` | Físico-Químico | pH, Temperatura, CE, OD, ORP | — |

Parâmetros de piezômetro têm duas seções na tela de coleta: instrumentais (obrigatórios) e físico-químicos (opcionais, o técnico pode marcar "não monitorar" com justificativa).

---

## 6. Regras de negócio críticas

### 6.1 Código de ponto é permanente

O código de um ponto (`NAS-001`, `DRN-007`, `PZ-004`) é gerado uma única vez na criação e nunca reutilizado, mesmo que o ponto seja desativado ou o técnico registre uma NC. Isso é fundamental para rastreabilidade — o órgão regulador pode cruzar relatórios de anos diferentes pelo mesmo código.

### 6.2 NC (Não Coletado) não é erro

Quando o técnico não consegue coletar um ponto, ele registra uma NC com:
- Motivo selecionado (lista pré-definida: acesso negado, ponto seco, clima adverso, equipamento com defeito, risco de segurança, coordenada incorreta, outro)
- Descrição livre (obrigatória)
- Foto de evidência (obrigatória)
- GPS do local da tentativa

NC é um status válido e esperado. O ponto continua na base, o código é preservado, e o evento é sincronizado com o servidor normalmente.

### 6.3 Estabilização obrigatória para piezômetros

Para coletas do tipo `inst` (piezômetro) e `fq`, existe um processo de **estabilização** antes de registrar os valores finais:

1. O técnico insere leituras sequencialmente (mínimo 3).
2. O sistema calcula a variação entre leituras consecutivas.
3. Critérios (configurados em `StabilizationConfig`):
   - pH: variação absoluta < 0,1
   - Temperatura: variação absoluta < 0,2 °C
   - OD: variação absoluta < 0,2 mg/L
   - Condutividade: variação percentual < 5%
4. Quando todos os parâmetros requeridos estabilizaram, o sistema considera a coleta pronta.
5. Se o tempo máximo operacional for excedido sem estabilizar, o técnico pode registrar uma **exceção de estabilização** com motivo e notas.

Os valores finais enviados ao servidor são os da **última leitura após estabilização** (`StabFinalStrategy.lastReading`).

### 6.4 Upload de fotos em 3 etapas (S3)

O upload de uma foto ao servidor é um processo de 3 etapas para garantir atomicidade:

```
1. App → Backend: solicitar URL pré-assinada
   POST /api/v1/mobile/evidences/upload-url
   { external_id, record_external_id, point_external_id, mime_type, size_bytes }
   ← { upload_url, file_key }

2. App → S3: fazer PUT direto na URL pré-assinada
   PUT {upload_url} [binary image data]

3. App → Backend: confirmar upload
   POST /api/v1/mobile/evidences/{external_id}/confirm
   { file_key, size_bytes, captured_at, gps_lat, gps_lng, caption }
```

Se o app fechar entre as etapas, o `EvidenceUploader.retryFailedUploads()` é chamado ao retomar. Itens `pending` há mais de 30 segundos com zero tentativas são promovidos a `failed` e reentraram no fluxo de retry.

### 6.5 Ordem de sincronização

Os itens na `sync_queue` devem chegar ao servidor em ordem de dependência. O servidor não aceita um ponto sem a campanha já existir. A fila é sempre processada nesta ordem:

```
1. mobile_campaign   (campanhas)
2. collection_point  (pontos)
3. collection_record (registros de coleta)
4. collection_evidence (evidências/fotos)
```

### 6.6 Backoff exponencial e quarentena

Quando uma operação de sync falha (timeout, erro de rede, 4xx/5xx):

- O item fica em status `failed` com `attempts++`
- Tempo de espera antes de nova tentativa: `2^attempts` minutos (máximo 60 min)
  - 1ª falha → espera 1 min
  - 2ª falha → espera 2 min
  - 3ª falha → espera 4 min
  - 4ª falha → espera 8 min
  - 5ª falha → item é **quarentenado** (não tentado mais automaticamente)
- Quarentenados exigem ação do usuário: o `SyncDiagnosticsScreen` mostra quais estão quarentenados e permite "Tentar novamente" (`retryFailed(reset: true)`)

### 6.7 Resolução de conflito

Quando o servidor retorna `conflict` para um item de sync, o app aplica o `server_payload` recebido ao registro local — servidor vence. Isso acontece quando o mesmo ponto foi editado em dois dispositivos diferentes ou o analista editou via web antes do técnico sincronizar.

### 6.8 Relatórios seguem o formulário F.057.03

O relatório gerado (seja pelo app ou pelo protótipo web) deve seguir o layout formal:
- Cabeçalho: logo EnviroTrack + "Sistema de Gestão Integrada" + número do formulário
- Identificação do ponto: código, nome, tipo, data/hora, coordenadas, status
- Grid de metadados: cliente, projeto, gerente, CC, campanha, técnico
- Tabela de parâmetros: nome, resultado (mono verde), unidade, método SMEWW
- Dados de campo: coordenadas+precisão GPS, tags de observação, texto livre
- Galeria fotográfica: 6 slots (3×2), legendas específicas por tipo de ponto
- Assinaturas: técnico + analista/gerente
- Rodapé: aviso de reprodução restrita + código+data do relatório

---

## 7. Fluxo completo de uma campanha (do início ao sync)

```
Plataforma web (analista)
  └─ cria campanha com lista de pontos
  └─ atribui ao técnico

App mobile (técnico)
  └─ login → JWT salvo em FlutterSecureStorage
  └─ pull de updates → campanha aparece na tela
  └─ abre campanha → vê lista de pontos com status pending/done/nc

Para cada ponto:
  └─ captura GPS (Geolocator, precisão alta, timeout 20s)
  └─ seleciona clima e condições
  └─ preenche parâmetros físico-químicos
  │   └─ (piezômetros) processo de estabilização com leituras sequenciais
  └─ tira fotos (mínimo 3, máximo 6 por ponto)
  │   └─ cada foto → blob local → EvidenceUploader enfileira upload
  └─ seleciona tags de observação + texto livre
  └─ salva (markDone) → status muda para done no SQLite
  └─ SyncQueue recebe upsert de collection_point + collection_record

  Se não conseguiu coletar:
  └─ registra NC com motivo + foto de evidência
  └─ status muda para nc no SQLite
  └─ SyncQueue recebe upsert com ncReported:true

Ao final de todos os pontos:
  └─ tela de encerramento de campo (finish)
  └─ gera relatório PDF local (window.print no web, ou visualização no app)
  └─ envia dados → SyncService.syncNow()

SyncService (background, também disparado a cada 2 minutos se online):
  └─ recoverStaleInFlight() → itens in_flight há > 5min voltam a pending
  └─ fetchPendingBatch() → ordena por entidade (campaign → point → record → evidence)
  └─ POST /api/v1/mobile/sync/batch com até 80 itens
  └─ processa respostas:
      └─ success → markProcessed
      └─ conflict → aplica server_payload local → markProcessed
      └─ error → markFailed → backoff
  └─ EvidenceUploader.retryFailedUploads() para fotos pendentes
  └─ pullUpdates() → GET /api/v1/mobile/sync/pull (cursor-based, 50 itens/página)
      └─ aplica atualizações do servidor ao SQLite local
```

---

## 8. Estrutura de arquivos do app Flutter

```
lib/
├── main.dart                    # Ponto de entrada; guard kIsWeb; rotas
├── models.dart                  # Entidades de domínio (Campaign, FieldPoint, Parameter)
├── app_state.dart               # Estado global (ValueNotifier)
│
├── api/
│   ├── api_config.dart          # URLs, timeouts, limites de batch
│   ├── api_client.dart          # HTTP client com retry e refresh de token
│   ├── api_exceptions.dart      # Tipos de erro da API
│   ├── auth_service.dart        # Login, logout, refresh; usa FlutterSecureStorage
│   └── sync_mappers.dart        # Converte linhas do SQLite → payloads da API
│
├── database/
│   └── database_helper.dart     # Singleton SQLite; todas as queries; migrações
│
├── sync/
│   ├── sync_queue.dart          # Fila SQLite; backoff; quarentena; kMaxAttempts=5
│   ├── sync_service.dart        # Orchestrador push/pull; agendamento automático
│   ├── evidence_uploader.dart   # Upload 3 etapas ao S3; retry de pendentes
│   ├── photo_capture_service.dart # ImagePicker; resize 1920px; qualidade 85%
│   └── device_info.dart         # device_id único para identificar o aparelho
│
├── stabilization/
│   ├── stabilization_config.dart  # Regras de critério por parâmetro (editável)
│   ├── stabilization_models.dart  # StabilizationRule, StabCriterionType etc
│   ├── stabilization_repository.dart # Persistência de leituras no SQLite
│   └── stabilization_service.dart   # Lógica de avaliação de critérios
│
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart          # Banner de sync falho; link para diagnóstico
│   ├── campaigns_screen.dart
│   ├── os_detail_screen.dart     # Detalhe da campanha + lista de pontos
│   ├── collect_screen.dart       # Tela principal de coleta (GPS, params, fotos, obs)
│   ├── finish_screen.dart        # Encerramento de campo
│   ├── reports_screen.dart
│   ├── sync_diagnostics_screen.dart  # Itens quarentenados + log de sync
│   ├── calendar_screen.dart
│   ├── profile_screen.dart
│   ├── notifications_screen.dart
│   ├── new_camp_screen.dart
│   └── edit_profile_screen.dart
│
├── providers/
│   └── collect_provider.dart    # Provider de estado da tela de coleta
│
├── theme/
│   └── app_theme.dart           # Tokens de cor e tipografia
│
└── widgets/
    └── common.dart              # Widgets reutilizáveis
```

---

## 9. API — contrato com o backend

Todos os endpoints têm prefixo `/api/v1`. O app envia o header `X-Schema-Version: 1` em toda requisição. Se o backend retornar `426 Upgrade Required`, o app precisa ser atualizado.

### Push (enviado pelo app)

```
POST /api/v1/mobile/sync/batch
Authorization: Bearer {jwt}
Content-Type: application/json

{
  "device_id": "uuid-do-aparelho",
  "items": [
    {
      "entity_type": "mobile_campaign" | "collection_point" | "collection_record" | "collection_evidence",
      "operation": "upsert" | "soft_delete",
      "external_id": "uuid-gerado-no-app",
      "client_version": 3,
      "client_updated_at": "2026-03-21T09:14:00.000Z",
      "payload": { ... depende da entidade ... }
    }
  ]
}
```

Respostas por item: `"success"`, `"conflict"` (vem com `server_payload`), `"duplicate"` (já foi processado antes — idempotente), `"error"`.

### Pull (recebe do servidor)

```
GET /api/v1/mobile/sync/pull?limit=50&cursor={opaque_cursor}
Authorization: Bearer {jwt}

← {
    "items": [ { "type": "...", "payload": {...} } ],
    "next_cursor": "..." | null
  }
```

O pull é paginado por cursor. O app continua até `next_cursor === null` ou `items.length < 50`.

### Payloads por entidade (em `sync_mappers.dart`)

**Campanha (`mobile_campaign`):**
```json
{
  "name": "Vale Carajás",
  "code": "CAM-2026-03",
  "client": "Vale S.A.",
  "responsible": "Rafael Borges",
  "deadline": "2026-03-28",
  "total_points": 18,
  "done_points": 5,
  "status": "in_progress",  // nova→pending, emCampo→in_progress, concluida→completed
  "assigned_user_external_id": "uuid-do-tecnico",
  "finished_at": null
}
```

**Ponto (`collection_point`):**
```json
{
  "campaign_external_id": "uuid-da-campanha",
  "code": "NAS-001",
  "name": "Afloramento N-01",
  "point_type": "spring",  // nasc→spring, dren→drainage, vert→weir, inst→instrument
  "status": "done" | "nc" | "pending" | "justified_exception",
  "latitude": -6.0012,
  "longitude": -50.1468,
  "coord_source": "gps" | null,
  "nc_reported": false,
  "nc_motive": null
}
```

**Registro de coleta (`collection_record`):**
```json
{
  "campaign_external_id": "...",
  "point_external_id": "...",
  "technician_external_id": "...",
  "technician_name": "Carlos Almeida",
  "status": "done" | "nc" | "justified_exception",
  "final_parameter_values": { "pH": 6.9, "temp": 26.4, ... },
  "stabilization_status": "stabilized" | "exception" | null,
  "stabilization_summary": { ... },
  "weather": ["ensolarado", "vento fraco"],
  "checklist_pop": [{ "label": "EPI", "checked": true }],
  "obs_tags": ["odor", "coloração"],
  "observations": "Afloramento em boas condições.",
  "nc": { "reported": true, "motive": "Acesso negado" }
}
```

---

## 10. Protótipo web (ETx/index.html)

O arquivo `ETx/index.html` é um mockup funcional de ~2200 linhas em HTML/CSS/JS puro. Não tem build step — abra diretamente no browser.

**Propósito:** referência de UX/UI e comportamento, base para testar geração de relatórios sem precisar do app mobile.

**Dados mock no arquivo:**
- `POINTS_DB` — 39 pontos de coleta com coordenadas e valores anteriores
- `CAMPAIGNS` — 3 campanhas (vale, cubatao, paulinia)
- `TYPE_PARAMS` — parâmetros por tipo de ponto
- `PARAM_META` — metadados de cada parâmetro (ícone, label, unidade, min, max)
- `REP_MOCK` — 10 registros de coleta fictícios para tela de relatórios
- `collected{}` — dicionário global que é populado quando o técnico "salva" um ponto na simulação

**Funcionalidades implementadas no protótipo:**
- Navegação completa entre todas as telas
- Fluxo de coleta: GPS simulado, entrada de parâmetros, captura de foto real (via `<input type="file">`)
- `markDone()` persiste snapshot em `collected{}`
- Geração de relatório A4 imprimível via `window.print()`
- Relatório consolidado por campanha (multi-página)
- `@media print` que oculta toda a phone-shell e mostra só o documento

**Design system:**
- Tokens: `--bg:#0F172A`, `--acc:#3DBC78`, `--neon:#00FFB2`, `--sky:#0EA5E9`
- Fontes: Syne (headings 700–800), DM Sans (corpo), Space Mono (dados/códigos)
- Phone shell 390×844px com `border-radius:52px` — nunca quebre este container

---

## 11. Pontos de atenção e armadilhas conhecidas

1. **`kIsWeb` guard no main.dart:** o app mostra uma tela de "plataforma não suportada" quando rodado no Flutter Web. Isso é intencional — o app é exclusivamente mobile. Não remova esse guard.

2. **`sqflite` não funciona em testes sem FFI:** testes que precisam do banco de dados usam `sqflite_common_ffi` com banco em memória. Ver `test/sync_queue_test.dart`.

3. **`preferFrontCamera` não existe no `image_picker`:** já foi removido uma vez por erro. Não tente adicioná-lo de novo.

4. **Null assertions desnecessários no `database_helper.dart`:** o retorno de queries já é nullable — não force `!` onde o tipo já é correto.

5. **`unawaited()` requer `dart:async`:** ao disparar uploads em background com `unawaited(...)`, certifique-se que o import está presente.

6. **Android `minSdk = 23`:** foi elevado de `flutter.minSdkVersion` para 23 para suportar `FlutterSecureStorage`. Não baixe esse valor.

7. **iOS Info.plist:** as chaves de permissão de câmera, galeria e GPS já estão declaradas em português. Qualquer novo uso de plataforma que exija permissão deve ter a descrição adicionada aqui antes de tudo.

8. **Sync queue e `windows/`:** os arquivos `windows/flutter/generated_plugin_registrant.cc` e `generated_plugins.cmake` foram alterados automaticamente pelo Flutter ao adicionar os pacotes nativos. Não edite manualmente.

9. **Relatório F.057.03:** o layout do relatório PDF tem estrutura formal obrigatória definida pelo processo interno da consultoria. Não altere as seções, a ordem ou o cabeçalho sem alinhamento explícito com o responsável pelo produto.

10. **Conflito de versão no schema de sync:** `X-Schema-Version` no header é `1`. Se o payload mudar de forma incompatível com versões anteriores do app em produção, incremente esse número e garanta que o backend trate a migração antes de publicar o app novo.

---

## 12. Configuração do ambiente de desenvolvimento

```bash
# Flutter SDK >= 3.3.0 requerido
flutter --version

# Instalar dependências
flutter pub get

# Rodar no Android (emulador ou device)
flutter run

# Rodar com URL de backend custom
flutter run --dart-define=API_BASE_URL=https://api.envirotrack.com

# Padrão local (emulador Android aponta para localhost do host)
# API_BASE_URL default: http://10.0.2.2:4000

# Rodar testes
flutter test

# O arquivo ETx/index.html não precisa de build — abra direto no Chrome
```

### Dependências principais e por que estão aqui

| Pacote | Motivo |
|--------|--------|
| `sqflite` | Banco de dados local offline-first |
| `sqflite_common_ffi` (dev) | SQLite em memória para testes unitários |
| `flutter_secure_storage` | JWT no Keychain/Keystore (não SharedPreferences) |
| `image_picker` | Câmera e galeria para fotos de campo |
| `geolocator` | GPS real com permissão e precisão configurável |
| `http` | Cliente HTTP para API REST |
| `uuid` | Geração de `external_id` estáveis no device |
| `crypto` | SHA-256 para hash de payload (idempotência na sync queue) |
| `connectivity_plus` | Detecta online/offline para disparar sync |
| `shared_preferences` | Apenas para `device_id` não-sensível |
| `provider` | Gerenciamento de estado global |
| `intl` | Formatação de datas em pt-BR |

---

*Última atualização: Abril 2026 — EnviroTrack v2*
