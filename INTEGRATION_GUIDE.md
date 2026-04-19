# EcoFlowApp — Guia de Integração com o Backend

Este documento descreve como o app mobile foi integrado ao backend NestJS
especificado no projeto principal, como rodar contra um backend em desenvolvimento,
como testar o fluxo completo de autenticação e sincronização, e quais são os
próximos passos recomendados.

---

## 1. Visão arquitetural da integração

O app segue um modelo **offline-first** com sync em background. O SQLite local
permanece como **fonte de verdade operacional** (o técnico pode trabalhar o dia
todo sem rede), e o backend recebe as mudanças em lotes quando há conexão.

```
┌──────────────────────────────────────────────────────────────────┐
│                     FLUXO DE DADOS                                │
│                                                                   │
│  UI (screens)                                                     │
│    │                                                              │
│    ▼                                                              │
│  AppState ─── muta ───► SQLite (source of truth operacional)     │
│    │                                                              │
│    └─ enqueue ─► SyncQueue (tabela sync_queue no SQLite)         │
│                    │                                              │
│                    ▼                                              │
│               SyncService                                         │
│                    │                                              │
│                    ├─ push: POST /mobile/sync/batch               │
│                    └─ pull: GET  /mobile/sync/pull                │
│                    │                                              │
│                    ▼                                              │
│                Backend NestJS                                     │
└──────────────────────────────────────────────────────────────────┘
```

### Componentes adicionados

| Camada | Arquivo | Responsabilidade |
|---|---|---|
| Config | `lib/api/api_config.dart` | URL base, endpoints, limites de batch, timeouts |
| HTTP | `lib/api/api_client.dart` | Wrapper sobre `package:http` com auth + refresh + erros tipados |
| Auth | `lib/api/auth_service.dart` | Login, logout, persistência e refresh de sessão |
| Erros | `lib/api/api_exceptions.dart` | Network / Unauthorized / Conflict / Validation / UpgradeRequired |
| Mappers | `lib/api/sync_mappers.dart` | Conversores local ↔ payloads da API |
| Device | `lib/sync/device_info.dart` | `device_id` persistente por instalação |
| Fila | `lib/sync/sync_queue.dart` | Persistência de operações pendentes em SQLite |
| Orquestração | `lib/sync/sync_service.dart` | Push/pull em batches, monitoramento de conectividade |
| Upload | `lib/sync/evidence_uploader.dart` | Upload de fotos em 3 etapas via URL pré-assinada |
| UI | `lib/screens/login_screen.dart` | Tela de login com validação e tratamento de erros |

### Alterações em arquivos existentes

| Arquivo | Alteração |
|---|---|
| `pubspec.yaml` | `http`, `shared_preferences`, `uuid`, `crypto`, `connectivity_plus` |
| `lib/database/database_helper.dart` | Migração v2→v3: colunas `external_id`, `server_version`, `dirty`; novas tabelas `sync_queue`, `collection_evidences`, `sync_log`; helpers de sync |
| `lib/app_state.dart` | `init()` restaura sessão + liga `SyncService`; cada mutação enfileira no sync; `logout()` real |
| `lib/main.dart` | `AuthGate` que decide entre `LoginScreen` e `HomeScreen` |
| `lib/screens/profile_screen.dart` | Botão "Sair" executa logout real e navega para login |

---

## 2. Configuração e execução

### 2.1. Dependências

Rode após pull para instalar as novas libs:

```bash
flutter pub get
```

### 2.2. URL do backend

A URL base é controlada por `--dart-define` em tempo de build/run. O fallback
é `http://10.0.2.2:4000` (que em emulador Android aponta para `localhost` do
host — útil para desenvolvimento local).

```bash
# desenvolvimento local (emulador Android, backend rodando em localhost:4000)
flutter run

# backend em rede local acessível pelo dispositivo físico
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000

# staging
flutter run --dart-define=API_BASE_URL=https://api-staging.envirotrack.com

# produção
flutter build apk --release --dart-define=API_BASE_URL=https://api.envirotrack.com
```

### 2.3. Permissões Android/iOS

O Flutter `http` requer permissão de internet:

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

**iOS** (`ios/Runner/Info.plist`) — se usar backend HTTP não-TLS em dev,
adicione:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

Para produção use sempre HTTPS.

---

## 3. Contrato de integração com o backend

### 3.1. Endpoints consumidos pelo app

| Método | Path | Uso |
|---|---|---|
| `POST` | `/api/v1/auth/login` | Login do técnico |
| `POST` | `/api/v1/auth/refresh` | Renovação silenciosa do token |
| `POST` | `/api/v1/mobile/sync/batch` | Push de mudanças locais em lote |
| `GET`  | `/api/v1/mobile/sync/pull` | Pull de mudanças vindas do web |
| `POST` | `/api/v1/mobile/evidences/upload-url` | Pedir URL pré-assinada para foto |
| `POST` | `/api/v1/mobile/evidences/:id/confirm` | Confirmar upload de foto |

### 3.2. Headers sempre enviados

- `Authorization: Bearer <jwt>` (quando autenticado)
- `X-Device-Id: <uuid>` (persistente por instalação)
- `X-App-Version: 1.0.0`
- `X-Schema-Version: 1`

### 3.3. Payload de `POST /mobile/sync/batch`

```json
{
  "sync_token": "uuid-do-batch",
  "client_generated_at": "2026-04-18T14:30:00.000Z",
  "items": [
    {
      "item_index": 0,
      "entity": "mobile_campaign",
      "external_id": "<uuid estável>",
      "operation": "upsert",
      "client_updated_at": "2026-04-18T14:20:00.000Z",
      "client_version": 3,
      "payload": { ... }
    }
  ]
}
```

As entidades enviadas, em ordem de dependência:
1. `mobile_campaign`
2. `collection_point`
3. `collection_record`
4. `collection_evidence`

O app ordena automaticamente. O backend responde com um resultado **por item**
(`processed` / `duplicated` / `conflict` / `failed`).

### 3.4. Resposta esperada

```json
{
  "sync_token": "...",
  "received_at": "...",
  "processed_at": "...",
  "summary": { "total": 4, "processed": 3, "duplicated": 0, "failed": 0, "conflict": 1 },
  "results": [
    { "item_index": 0, "status": "processed", "server_version": 3 },
    { "item_index": 1, "status": "duplicated", "server_version": 1 },
    { "item_index": 2, "status": "conflict", "resolution": "server_kept" },
    { "item_index": 3, "status": "failed", "error_message": "..." }
  ]
}
```

---

## 4. Como testar o fluxo completo

### 4.1. Pré-requisitos

1. Backend NestJS rodando (ver projeto principal)
2. Pelo menos um usuário técnico cadastrado com credenciais válidas
3. Emulador Android ou dispositivo físico

### 4.2. Cenário 1 — Login e sync inicial

1. Abra o app pela primeira vez → tela de login.
2. Informe email e senha → submit.
3. Deve navegar para HomeScreen.
4. `SyncService.syncNow()` é disparado automaticamente: pull de campanhas
   atribuídas no web.
5. Verifique na tela de campanhas que as campanhas server-seeded aparecem.

### 4.3. Cenário 2 — Coleta offline, sync ao reconectar

1. Ative modo avião no dispositivo.
2. Abra uma campanha, colete pontos (mark done, NC, GPS).
3. Toda mutação enfileira em `sync_queue` sem erro visível.
4. Desative modo avião → connectivity listener dispara sync automaticamente.
5. Confira no backend que campanhas/pontos/records chegaram.

### 4.4. Cenário 3 — Idempotência

1. Com uma campanha já sincronizada, encerre-a novamente (mesmo payload).
2. A fila detecta que `payload_hash` é igual ao último → no-op.
3. Se for enviado mesmo assim, backend responde `duplicated`.

### 4.5. Cenário 4 — Logout preserva fila

1. Faça coleta com itens pendentes na fila.
2. Vá em Perfil → Sair → confirme.
3. Faça login novamente.
4. A fila permanece e é reprocessada.

### 4.6. Inspecionar o estado local

Pelo Android Studio → Device File Explorer:
```
/data/data/com.example.ecoflowapp/databases/ecoflow.db
```

Tabelas úteis para debug:
- `sync_queue` — itens pendentes/failed
- `sync_log` — histórico de batches enviados
- `collection_evidences` — status de upload por foto

---

## 5. Comportamento e políticas

### 5.1. Coalescing na fila

Se uma mutação é enfileirada sobre outra pendente para o mesmo
`(entity, external_id)`, a nova substitui a anterior e `client_version` é
incrementado. Isso mantém a fila pequena e evita enviar estados intermediários.

### 5.2. Conflito

Política default: **server_version vence**. Quando o backend retorna
`conflict`, o app marca o item local como sincronizado (server kept) e descarta
a mutação. Um hardening futuro deve trazer o payload do servidor e aplicar
localmente (atualmente isso é feito implicitamente pelo próximo pull).

### 5.3. Retry de falhas

Itens `failed` permanecem no banco. O auto-sync (a cada 2 minutos quando
online) pode reprocessá-los após um `SyncQueue.retryFailed()` explícito — vou
expor isso na tela de perfil numa próxima iteração.

### 5.4. Evidências órfãs

Se uma foto sobe mas o record não chega ao backend, ela fica referenciada por
`record_external_id` esperando materialização. O backend deve tolerar isso —
evidências chegam antes ou depois do record sem quebrar.

### 5.5. Schema version

Quando o contrato de sync mudar de forma incompatível, incremente
`ApiConfig.schemaVersion`. O backend pode responder `426 Upgrade Required` e
o app bloqueia sync até ser atualizado.

---

## 6. O que ainda não está implementado

**Captura real de fotos:** o `EvidenceUploader` está pronto, mas não há
UI de câmera/galeria integrada ainda. Hoje o app só tem um flag `hasPhoto`
sem arquivo real. Passo natural: integrar `image_picker`, salvar em
`getApplicationDocumentsDirectory()`, e chamar
`EvidenceUploader.instance.uploadAndRegister(...)`.

**Reconciliação pós-conflito:** quando o backend devolve `conflict`, o app
apenas descarta. Ideal: também trazer o payload server e sobrescrever o
registro local, ou abrir uma fila de "conflitos a revisar".

**Tela de diagnóstico de sync:** uma tela admin mostrando
`sync_log`, itens `failed`, botão "forçar retry", versão do schema, device_id.
Útil pra suporte em campo.

**Captura de clima, checklist POP, cadeia de custódia no payload:** esses
campos chegam vazios hoje porque a UI não os captura estruturadamente.
Os mappers (`SyncMappers.recordPayload`) têm placeholders (`null`) que
devem ser preenchidos quando a UI expuser esses dados (alguns existem em
constantes como `kClimateOptions`, `kObsTags` mas não são persistidos).

**Conta do técnico:** `technician_external_id` precisa vir do backend no
login e ser usado nas chamadas. Hoje o `AuthService` já extrai o campo
do response de login (se o backend enviar); verifique que a API inclui
`user.technician_external_id` no JSON de `/auth/login`.

**Autenticação biométrica e secure storage:** `SharedPreferences` é OK para
MVP, mas produção deve usar `flutter_secure_storage` para o JWT e
suporte opcional a biometria antes de destravar o app.

---

## 7. Referência rápida dos modelos de dados

### Campanha local (tabela `campaigns`)
```
id, code, name, client, responsible, deadline, totalPoints, donePoints, status,
external_id, server_version, last_synced_at, dirty
```

### Ponto local (tabela `field_points`)
```
id, campaignId, code, name, type, typeLabel, status, gpsLat, gpsLng,
ncReported, ncMotive, stabilization_*, final_parameter_values_json,
external_id, record_external_id, server_version, last_synced_at, dirty
```

### Fila de sync (tabela `sync_queue`)
```
entity, external_id, local_id, operation, payload_json, payload_hash,
client_version, client_updated_at, status, attempts, last_error
```

### Evidência (tabela `collection_evidences`)
```
external_id, field_point_id, record_external_id, local_file_path,
mime_type, size_bytes, sha256, captured_at, upload_status, upload_key,
remote_url, attempts, last_error
```

---

## 8. Próximos passos sugeridos (em ordem de ROI)

1. **Captura real de fotos com `image_picker`** e integração com
   `EvidenceUploader` no `collect_screen`.
2. **Tela de diagnóstico de sync** acessível via menu do perfil.
3. **Estruturar clima, checklist POP e cadeia de custódia** na UI e
   pipeline de payload.
4. **Trocar `SharedPreferences` por `flutter_secure_storage`** para o JWT.
5. **Testes de integração** contra um backend mockado (dockerizar o
   backend NestJS pra ter ambiente reproduzível).
6. **Implementar a fila de revisão de conflitos** como tela admin.

---

Qualquer dúvida sobre o que ficou e o que não ficou, abra no código dos
arquivos listados — todos têm comentários in-line explicando as decisões.
