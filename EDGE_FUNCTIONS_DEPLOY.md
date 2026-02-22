# Deploy das Edge Functions no Supabase Externo

Este guia explica como fazer deploy das Edge Functions no seu projeto Supabase externo (lhtetfcujdzulfyekiub).

## Pré-requisitos

1. **Supabase CLI** instalado:
```bash
npm install -g supabase
```

2. **Access Token** do Supabase:
   - Acesse: https://supabase.com/dashboard/account/tokens
   - Crie um novo token

## Passo 1: Login no Supabase CLI

```bash
supabase login
# Cole o access token quando solicitado
```

## Passo 2: Linkar ao Projeto

```bash
supabase link --project-ref lhtetfcujdzulfyekiub
# Quando solicitado, cole a senha do banco de dados
```

## Passo 3: Configurar Secrets

Configure todos os secrets necessários pelas Edge Functions:

```bash
# API Keys principais
supabase secrets set OPENAI_API_KEY="sua_chave_openai"
supabase secrets set REPLICATE_API_KEY="sua_chave_replicate"
supabase secrets set LOVABLE_API_KEY="sua_chave_lovable_ai"
supabase secrets set RESEND_API_KEY="sua_chave_resend"

# Supabase (apontando para si mesmo)
supabase secrets set EXTERNAL_SUPABASE_URL="https://lhtetfcujdzulfyekiub.supabase.co"
supabase secrets set EXTERNAL_SUPABASE_SERVICE_KEY="sua_service_role_key"

# SMTP (para envio de emails)
supabase secrets set SMTP_HOST="seu_smtp_host"
supabase secrets set SMTP_PORT="587"
supabase secrets set SMTP_USER="seu_usuario_smtp"
supabase secrets set SMTP_PASSWORD="sua_senha_smtp"
```

### Onde encontrar as chaves:

| Secret | Onde encontrar |
|--------|----------------|
| `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| `REPLICATE_API_KEY` | https://replicate.com/account/api-tokens |
| `LOVABLE_API_KEY` | Fornecida pelo Lovable para AI features |
| `RESEND_API_KEY` | https://resend.com/api-keys |
| `EXTERNAL_SUPABASE_SERVICE_KEY` | Supabase Dashboard → Settings → API → service_role key |

## Passo 4: Deploy das Funções

### Deploy de todas as funções de uma vez:

```bash
supabase functions deploy
```

### Ou deploy individual:

```bash
supabase functions deploy generate-full-article
supabase functions deploy generate-article-image
supabase functions deploy auto-generate-article
supabase functions deploy send-newsletter
supabase functions deploy notify-article-ready
supabase functions deploy process-image-queue
supabase functions deploy translate-content
supabase functions deploy send-contact-email
supabase functions deploy generate-ai-reply
supabase functions deploy reply-contact-message
supabase functions deploy invite-admin
supabase functions deploy admin-user-management
supabase functions deploy backup-images
supabase functions deploy restore-images
supabase functions deploy migrate-images-to-webp
supabase functions deploy get-email-templates
supabase functions deploy update-email-template
supabase functions deploy manage-contact-messages
supabase functions deploy search-youtube-video
supabase functions deploy process-video-queue
supabase functions deploy serve-ads-txt
supabase functions deploy newsletter-tracking
supabase functions deploy newsletter-unsubscribe
supabase functions deploy get-public-settings
supabase functions deploy seed-email-templates
supabase functions deploy expand-excerpts
supabase functions deploy check-commemorative-dates
supabase functions deploy generate-sitemap
```

## Passo 5: Verificar Deploy

```bash
supabase functions list
```

Todas as funções devem aparecer com status "Active".

## Passo 6: Configurar CRON Jobs (Opcional)

Se você usa tarefas agendadas (como processamento de fila de imagens), configure no SQL Editor do Supabase:

```sql
-- Habilitar extensões necessárias
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Agendar processamento de imagens a cada 5 minutos
SELECT cron.schedule(
  'process-image-queue-every-5-min',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://lhtetfcujdzulfyekiub.supabase.co/functions/v1/process-image-queue',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxodGV0ZmN1amR6dWxmeWVraXViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzc0NzQyMzgsImV4cCI6MjA1MzA1MDIzOH0.Ej-x1zchcUPLK-9N4yXGCfN6zIPT_xDgOPVK496lxKM"}'::jsonb,
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- Verificar datas comemorativas diariamente às 8h
SELECT cron.schedule(
  'check-commemorative-dates-daily',
  '0 8 * * *',
  $$
  SELECT net.http_post(
    url := 'https://lhtetfcujdzulfyekiub.supabase.co/functions/v1/check-commemorative-dates',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxodGV0ZmN1amR6dWxmeWVraXViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzc0NzQyMzgsImV4cCI6MjA1MzA1MDIzOH0.Ej-x1zchcUPLK-9N4yXGCfN6zIPT_xDgOPVK496lxKM"}'::jsonb,
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
```

## Troubleshooting

### Ver logs de uma função:

```bash
supabase functions logs generate-full-article --tail
```

### Testar uma função localmente:

```bash
supabase functions serve generate-full-article --env-file .env.local
```

### Erro de CORS:

Todas as funções já incluem headers CORS. Se tiver problemas, verifique se a função está retornando os headers corretamente para requisições OPTIONS.

### Erro de autenticação:

Verifique se os secrets estão configurados:

```bash
supabase secrets list
```

## Arquitetura Final

```
┌─────────────────────────────────────────────────────────────┐
│                        VPS (EasyPanel)                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Frontend React (Nginx)                      │ │
│  │         https://homegardenmanual.com                     │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│             Supabase Externo (lhtetfcujdzulfyekiub)          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  • PostgreSQL Database                                   │ │
│  │  • Auth (Autenticação)                                   │ │
│  │  • Storage (article-images, avatars)                     │ │
│  │  • Edge Functions (17+ funções)                          │ │
│  │  • Cron Jobs (pg_cron)                                   │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

Agora tudo está hospedado no seu Supabase externo, sem dependência do Lovable Cloud!
