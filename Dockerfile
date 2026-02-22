# ============================================
# Home Garden Manual - Production Dockerfile
# Ubuntu 24.04 + EasyPanel + GitHub Auto-Deploy
# ============================================

# Stage 1: Build
FROM node:20-alpine AS build

WORKDIR /app

# Copiar arquivos de dependências
COPY package.json ./
COPY package-lock.json* ./

# Instalar dependências (com fallback)
RUN npm ci --legacy-peer-deps || npm install --legacy-peer-deps

# Copiar código fonte
COPY . .

# HARDCODED: Variáveis de ambiente para o Vite build
# Nota: Estas são chaves públicas (anon key JWT), seguras para expor
# Supabase Externo: casa_jardim (lhtetfcujdzulfyekiub)
# IMPORTANTE: Usar sempre o JWT completo, não o formato curto (sb_publishable_...)
ENV VITE_SUPABASE_URL="https://lhtetfcujdzulfyekiub.supabase.co"
ENV VITE_SUPABASE_PROJECT_ID="lhtetfcujdzulfyekiub"
ENV VITE_SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxodGV0ZmN1amR6dWxmeWVraXViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTMzNTYsImV4cCI6MjA4NDQyOTM1Nn0.NOHNkC65PjsBql23RNa5KU3NauN6C3BmPrM02lETBoc"
ENV VITE_SUPABASE_PUBLISHABLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxodGV0ZmN1amR6dWxmeWVraXViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4NTMzNTYsImV4cCI6MjA4NDQyOTM1Nn0.NOHNkC65PjsBql23RNa5KU3NauN6C3BmPrM02lETBoc"

# Build de produção
RUN npm run build

# Stage 2: Production (Nginx)
FROM nginx:alpine

# IMPORTANTE: Remover configurações default que conflitam
RUN rm -rf /etc/nginx/conf.d/*

# Copiar arquivos buildados
COPY --from=build /app/dist /usr/share/nginx/html

# Copiar configuração customizada do Nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Validar configuração do Nginx (falha o build se inválida)
RUN nginx -t

# Expor porta 80
EXPOSE 80

# Health check simplificado
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=5 \
  CMD wget -q --spider http://127.0.0.1/ || exit 1

# Iniciar Nginx
CMD ["nginx", "-g", "daemon off;"]
