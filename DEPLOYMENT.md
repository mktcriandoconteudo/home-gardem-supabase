# 🚀 Home Garden Manual - Guia de Deploy

## Arquitetura Híbrida

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ARQUITETURA DE PRODUÇÃO                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────────────────┐           ┌─────────────────────────┐    │
│  │    VPS Ubuntu 24.04   │           │   Lovable Cloud         │    │
│  │   srv1057913.hstgr    │           │   (Supabase)            │    │
│  │   82.29.60.101        │           │                         │    │
│  │                       │   HTTPS   │  - PostgreSQL (25 tabs) │    │
│  │  ┌─────────────────┐  │ ────────► │  - Authentication       │    │
│  │  │  EasyPanel      │  │           │  - 21 Edge Functions    │    │
│  │  │   + Docker      │  │ ◄──────── │  - Storage (3 buckets)  │    │
│  │  │   + Nginx       │  │           │  - Realtime             │    │
│  │  │   + SSL Auto    │  │           │  - Cron Jobs            │    │
│  │  └─────────────────┘  │           │                         │    │
│  │          │            │           └─────────────────────────┘    │
│  │          ▼            │                                          │
│  │  ┌─────────────────┐  │                                          │
│  │  │  React SPA      │  │                                          │
│  │  │  (Static Files) │  │                                          │
│  │  └─────────────────┘  │                                          │
│  │                       │                                          │
│  │  homegardenmanual.com │                                          │
│  └───────────────────────┘                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Especificações do Servidor

| Item | Valor |
|------|-------|
| **SO** | Ubuntu 24.04 com EasyPanel |
| **Hostname** | srv1057913.hstgr.cloud |
| **IP** | 82.29.60.101 |
| **CPU** | 2 núcleos |
| **RAM** | 8 GB |
| **Disco** | 100 GB |
| **Localização** | Brasil - São Paulo |
| **Domínio** | homegardenmanual.com |

---

## 🔧 Pré-Requisitos

- [x] Ubuntu 24.04 instalado
- [x] EasyPanel instalado e acessível
- [x] Domínio registrado (homegardenmanual.com)
- [x] Repositório GitHub conectado ao Lovable
- [x] Lovable Cloud (Supabase) configurado

---

## 📦 Configuração do EasyPanel

### Passo 1: Acessar EasyPanel

```
http://82.29.60.101:3000
```

### Passo 2: Criar Novo App

1. Clique em **"+ Create"** → **"App"**
2. Nome do App: `home-garden-manual`
3. Clique em **"Create"**

### Passo 3: Conectar GitHub

1. Na aba **"Source"**, selecione **"GitHub"**
2. Clique em **"Connect GitHub"**
3. Autorize o EasyPanel no GitHub
4. Selecione o repositório do projeto
5. Configure:
   - **Branch**: `main`
   - **Build Method**: `Dockerfile`
   - **Dockerfile Path**: `./Dockerfile`

### Passo 4: Variáveis de Ambiente

Na aba **"Environment"**, adicione:

| Variável | Valor |
|----------|-------|
| `VITE_SUPABASE_URL` | `https://lhtetfcujdzulfyekiub.supabase.co` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_Fzh5c8vspjn7jXwyBivbSA_OUJNwwXQ` |
| `VITE_SUPABASE_PROJECT_ID` | `lhtetfcujdzulfyekiub` |

⚠️ **Importante**: No EasyPanel, marque as variáveis como **"Build Arg"** para que sejam injetadas durante o build do Docker.

### Passo 5: Configurar Domínios

Na aba **"Domains"**:

1. Clique em **"+ Add Domain"**
2. Adicione: `homegardenmanual.com`
3. Clique em **"+ Add Domain"** novamente
4. Adicione: `www.homegardenmanual.com`
5. Ative **"HTTPS"** (Let's Encrypt automático)
6. Defina `homegardenmanual.com` como **Primary**

### Passo 6: Deploy

1. Clique em **"Deploy"**
2. Aguarde o build (5-10 minutos no primeiro deploy)
3. Verifique os logs para erros

---

## 🌐 Configuração DNS

No seu provedor de domínio, configure:

| Tipo | Nome | Valor | TTL |
|------|------|-------|-----|
| A | @ | 82.29.60.101 | 3600 |
| A | www | 82.29.60.101 | 3600 |

### Verificar DNS

```bash
# Testar resolução
dig homegardenmanual.com +short
# Deve retornar: 82.29.60.101

dig www.homegardenmanual.com +short
# Deve retornar: 82.29.60.101
```

---

## 🔄 Fluxo de Deploy Automático

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Lovable   │ ───► │   GitHub    │ ───► │  EasyPanel  │ ───► │  Produção   │
│   (Edits)   │      │   (Push)    │      │  (Build)    │      │   (Live)    │
└─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘
      │                    │                    │                    │
      │  Sync automático   │  Webhook trigger   │  Docker build      │  Site online
      │                    │                    │  + Deploy          │
      ▼                    ▼                    ▼                    ▼
   Código              main branch         Container Nginx    homegardenmanual.com
```

### Como funciona:

1. **Você edita no Lovable** → Sync automático para GitHub
2. **Push no GitHub** → Webhook dispara build no EasyPanel
3. **EasyPanel** → Executa `docker build` usando o `Dockerfile`
4. **Container** → Novo container Nginx substitui o anterior
5. **Produção** → Site atualizado em ~3-5 minutos

---

## 🗄️ Backend (Lovable Cloud)

O backend permanece no Lovable Cloud (Supabase) e não precisa de configuração adicional.

### Banco de Dados - 25 Tabelas

| Categoria | Tabelas |
|-----------|---------|
| **Usuários** | `profiles`, `user_roles`, `audit_logs` |
| **Conteúdo** | `content_articles`, `article_images`, `article_views`, `article_likes` |
| **Afiliados** | `affiliate_banner_clicks` |
| **Geração IA** | `generation_history`, `image_generation_queue`, `image_backup_logs` |
| **Auto Pilot** | `auto_generation_config`, `auto_generation_logs`, `auto_generation_schedules` |
| **Contato** | `contact_messages`, `contact_message_replies`, `contact_reply_templates` |
| **Newsletter** | `newsletter_subscribers`, `newsletter_send_history`, `newsletter_email_tracking`, `email_templates` |
| **Notificações** | `notifications`, `push_subscriptions` |
| **Configurações** | `site_settings`, `commemorative_date_settings` |

### Edge Functions - 21 Funções

1. `admin-user-management`
2. `auto-generate-article`
3. `backup-images`
4. `check-commemorative-dates`
5. `expand-excerpts`
6. `generate-ai-reply`
7. `generate-article-image`
8. `generate-full-article`
9. `generate-sitemap`
10. `invite-admin`
11. `migrate-images-to-webp`
12. `newsletter-tracking`
13. `newsletter-unsubscribe`
14. `notify-article-ready`
15. `process-image-queue`
16. `reply-contact-message`
17. `restore-images`
18. `send-contact-email`
19. `send-newsletter`
20. `send-push-notification`
21. `translate-content`

### Storage Buckets

| Bucket | Tipo | Uso |
|--------|------|-----|
| `article-images` | Público | Imagens dos artigos |
| `avatars` | Público | Avatares dos usuários |
| `article-images-backup` | Privado | Backup de imagens |

---

## ✅ Checklist de Deploy

### Pré-Deploy

- [ ] Dockerfile criado na raiz do projeto
- [ ] nginx.conf criado na raiz do projeto
- [ ] robots.txt atualizado com domínio final
- [ ] index.html com meta tags SEO
- [ ] Código commitado e pushado para GitHub

### Deploy no EasyPanel

- [ ] App criado no EasyPanel
- [ ] GitHub conectado
- [ ] Branch `main` selecionado
- [ ] Dockerfile como método de build
- [ ] 3 variáveis de ambiente configuradas (como Build Args)
- [ ] Domínio `homegardenmanual.com` adicionado
- [ ] Domínio `www.homegardenmanual.com` adicionado
- [ ] HTTPS/SSL ativado
- [ ] Primeiro deploy executado com sucesso

### Pós-Deploy

- [ ] Site carrega em `https://homegardenmanual.com`
- [ ] Redirecionamento www → sem www funciona
- [ ] SSL válido (cadeado verde)
- [ ] robots.txt acessível
- [ ] sitemap.xml funciona (proxy para Edge Function)
- [ ] Login de admin funciona
- [ ] Criação de artigo funciona
- [ ] Geração de imagens funciona
- [ ] Newsletter funciona

### SEO

- [ ] Sitemap submetido ao Google Search Console
- [ ] Meta tags verificadas com Facebook Debugger
- [ ] Meta tags verificadas com Twitter Card Validator

---

## 🔧 Troubleshooting

### Build falha no EasyPanel

**Sintoma**: Erro durante `npm ci` ou `npm run build`

**Solução**:
1. Verifique os logs do build no EasyPanel
2. Certifique-se que as variáveis de ambiente estão marcadas como "Build Arg"
3. Tente limpar o cache: "Rebuild without cache"

### Site não carrega

**Sintoma**: Timeout ou erro 502

**Solução**:
1. Verifique se o container está rodando: EasyPanel → App → Logs
2. Verifique se o DNS está propagado: `dig homegardenmanual.com`
3. Teste localmente: `curl http://82.29.60.101`

### SSL não funciona

**Sintoma**: Certificado inválido ou erro de HTTPS

**Solução**:
1. Verifique se o DNS está apontando para o IP correto
2. Aguarde até 10 minutos após configurar o domínio
3. No EasyPanel, desative e reative o HTTPS

### Sitemap não funciona

**Sintoma**: `/sitemap.xml` retorna erro

**Solução**:
1. Verifique se a Edge Function `generate-sitemap` está deployada
2. Teste diretamente: `https://gcdwdjacrxmdsciwqtlc.supabase.co/functions/v1/generate-sitemap`
3. Verifique logs da Edge Function no Lovable Cloud

### Login não funciona

**Sintoma**: Erro de autenticação

**Solução**:
1. Verifique se `VITE_SUPABASE_URL` está correto
2. Verifique se `VITE_SUPABASE_PUBLISHABLE_KEY` está correto
3. Abra o console do navegador e verifique erros de rede

---

## 📊 Monitoramento

### Logs do Container

```bash
# Via EasyPanel UI
App → Logs → Container Logs

# Via SSH (se necessário)
ssh root@82.29.60.101
docker logs home-garden-manual
```

### Métricas

O EasyPanel fornece métricas básicas:
- CPU usage
- Memory usage
- Network I/O
- Disk usage

### Uptime

Configure monitoramento externo (opcional):
- UptimeRobot (gratuito)
- Pingdom
- StatusCake

---

## 🔄 Atualizações

### Deploy Manual (se necessário)

```bash
# No EasyPanel
App → Deploy → Deploy Now
```

### Rollback

```bash
# No EasyPanel
App → Deployments → Selecione versão anterior → Rollback
```

---

## 📞 Suporte

- **Lovable**: [docs.lovable.dev](https://docs.lovable.dev)
- **EasyPanel**: [easypanel.io/docs](https://easypanel.io/docs)
- **Supabase**: [supabase.com/docs](https://supabase.com/docs)

---

## 📝 Notas

- O backend (Lovable Cloud/Supabase) não precisa de configuração na VPS
- Edge Functions são deployadas automaticamente pelo Lovable
- Secrets do backend são gerenciados no Lovable Cloud
- Imagens são armazenadas no Supabase Storage (não na VPS)
- Cron jobs rodam no Supabase (não na VPS)

---

*Última atualização: Janeiro 2026*
