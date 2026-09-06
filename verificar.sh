#!/usr/bin/env bash
#
# verificar.sh - checagens objetivas da trilha de Docker da CJR.
# Uso: ./verificar.sh <numero-da-sessao>   (de 1 a 8)
#
# Cada checagem imprime OK ou FALHA com uma linha do que fazer.
# Sai com codigo 0 se tudo passou, 1 caso contrario.
#
# Ajuste por variavel de ambiente, se necessario:
#   DOCKER_DB_CONTAINER (padrao docker-db)
#   DOCKER_DB_PORT      (padrao 5432)
#   DOCKER_API_PORT     (padrao 3000)
#   DOCKER_IMAGE        (padrao ghcr.io/<org>/docker) - use a tag real nas sessoes 3 e 8

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DB_CONTAINER="${DOCKER_DB_CONTAINER:-docker-db}"
DB_PORT="${DOCKER_DB_PORT:-5432}"
API_PORT="${DOCKER_API_PORT:-3000}"
API_URL="http://localhost:${API_PORT}"
IMAGE="${DOCKER_IMAGE:-ghcr.io/<org>/docker}"
STATE_FILE="${SCRIPT_DIR}/.verificar-tamanho"

FALHOU=0

ok()    { printf 'OK    - %s\n' "$1"; }
falha() { printf 'FALHA - %s\n' "$1"; FALHOU=1; }

# --- utilidades tolerantes -------------------------------------------------

docker_disponivel() {
  command -v docker >/dev/null 2>&1
}

docker_rodando() {
  docker info >/dev/null 2>&1
}

exigir_docker() {
  if ! docker_disponivel; then
    falha "Docker nao encontrado. Instale o Docker e abra o terminal de novo."
    return 1
  fi
  if ! docker_rodando; then
    falha "Docker nao esta rodando. Inicie o Docker Desktop ou o daemon e tente de novo."
    return 1
  fi
  return 0
}

# status HTTP de uma URL; imprime 000 se nao respondeu.
http_status() {
  curl -s -o /dev/null -m 5 -w '%{http_code}' "$1" 2>/dev/null || echo "000"
}

# espera ate a URL responder; want="any" aceita qualquer resposta HTTP.
wait_http() {
  local url="$1" want="$2" tries="${3:-15}" code="000" i
  for i in $(seq 1 "$tries"); do
    code="$(http_status "$url")"
    if [ "$want" = "any" ]; then
      [ "$code" != "000" ] && { echo "$code"; return 0; }
    else
      [ "$code" = "$want" ] && { echo "$code"; return 0; }
    fi
    sleep 1
  done
  echo "$code"
  return 1
}

# nome do primeiro container Postgres em execucao.
find_pg_container() {
  docker ps --format '{{.Names}}'$'\t''{{.Image}}' 2>/dev/null \
    | awk -F'\t' 'tolower($2) ~ /postgres/ {print $1; exit}'
}

# container da API: em execucao, publicando a porta da API, e nao o banco.
find_api_container() {
  local pg n; pg="$(find_pg_container)"
  for n in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    [ "$n" = "$pg" ] && continue
    if docker port "$n" 2>/dev/null | grep -qE ":${API_PORT}$"; then
      echo "$n"; return 0
    fi
  done
  return 1
}

networks_of() {
  docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" 2>/dev/null
}

db_named_volume() {
  docker inspect -f '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/postgresql/data")}}{{.Name}}{{end}}{{end}}' \
    "$DB_CONTAINER" 2>/dev/null
}

compose_disponivel() {
  docker compose version >/dev/null 2>&1
}

# --- sessoes ---------------------------------------------------------------

sessao1() {
  echo "Sessao 1: Postgres em container aceitando conexao"
  exigir_docker || return
  local c; c="$(find_pg_container)"
  if [ -z "$c" ]; then
    falha "Nenhum container Postgres rodando. Suba um (ex: docker run -d -p ${DB_PORT}:5432 -e POSTGRES_PASSWORD=docker postgres:16-alpine)."
    return
  fi
  ok "Container Postgres em execucao: $c"
  if docker exec "$c" pg_isready -q >/dev/null 2>&1; then
    ok "Postgres aceitando conexao dentro do container."
  else
    falha "Postgres nao respondeu a pg_isready. Aguarde a inicializacao ou confira as variaveis do banco."
  fi
  if docker port "$c" 2>/dev/null | grep -qE ":${DB_PORT}$"; then
    ok "Porta ${DB_PORT} publicada no host."
  else
    falha "Porta ${DB_PORT} nao publicada. Suba com -p ${DB_PORT}:5432."
  fi
}

sessao2() {
  echo "Sessao 2: container docker-db, exec e logs"
  exigir_docker || return
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
    falha "Container '${DB_CONTAINER}' nao esta rodando. Suba com --name ${DB_CONTAINER}."
    return
  fi
  ok "Container '${DB_CONTAINER}' em execucao."
  if docker exec "$DB_CONTAINER" true >/dev/null 2>&1; then
    ok "docker exec funciona em '${DB_CONTAINER}'."
  else
    falha "Nao foi possivel executar docker exec em '${DB_CONTAINER}'."
  fi
  if docker logs "$DB_CONTAINER" 2>&1 | grep -q "ready to accept connections"; then
    ok "Log contem 'ready to accept connections'."
  else
    falha "Log sem 'ready to accept connections'. Veja: docker logs ${DB_CONTAINER}"
  fi
}

sessao3() {
  echo "Sessao 3: imagem ${IMAGE} puxada e rodando"
  exigir_docker || return
  local img=""
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    img="$IMAGE"
  else
    # tolera <org> nao substituido: procura qualquer imagem local .../docker
    img="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
            | grep -E '/docker(:|$)' | head -n1)"
  fi
  if [ -z "$img" ]; then
    falha "Imagem da API nao encontrada localmente. Rode: docker pull ${IMAGE} (defina DOCKER_IMAGE com a tag real)."
    return
  fi
  ok "Imagem presente localmente: $img"
  if docker run --rm "$img" node -e "process.exit(0)" >/dev/null 2>&1; then
    ok "Imagem roda (node executou dentro do container)."
  else
    falha "Nao foi possivel rodar a imagem $img."
  fi
}

sessao4() {
  echo "Sessao 4: Dockerfile na raiz, build e /health"
  exigir_docker || return
  if [ ! -f "${SCRIPT_DIR}/Dockerfile" ]; then
    falha "Nao existe Dockerfile na raiz. Escreva um (veja gabarito/dockerfile-sessao4)."
    return
  fi
  ok "Dockerfile encontrado na raiz."
  if docker build -t docker-local:sessao4 "$SCRIPT_DIR" >/dev/null 2>&1; then
    ok "Imagem builda."
  else
    falha "Build falhou. Rode 'docker build -t docker-local:sessao4 .' para ver o erro."
    return
  fi
  local cid
  cid="$(docker run -d -p "${API_PORT}:${API_PORT}" -e PORT="${API_PORT}" docker-local:sessao4 2>/dev/null)"
  if [ -z "$cid" ]; then
    falha "Container nao subiu. Confira a porta ${API_PORT} livre."
    return
  fi
  local code; code="$(wait_http "${API_URL}/health" any 15)"
  if [ "$code" = "200" ] || [ "$code" = "503" ]; then
    ok "/health respondeu (HTTP ${code}). 503 e esperado sem banco nesta sessao."
  else
    falha "/health nao respondeu (codigo ${code}). Veja: docker logs $cid"
  fi
  docker rm -f "$cid" >/dev/null 2>&1
}

sessao5() {
  echo "Sessao 5: multi-stage, imagem < 200MB, .dockerignore"
  exigir_docker || return
  if [ ! -f "${SCRIPT_DIR}/Dockerfile" ]; then
    falha "Nao existe Dockerfile na raiz."
    return
  fi
  local froms
  froms="$(grep -ciE '^[[:space:]]*FROM ' "${SCRIPT_DIR}/Dockerfile")"
  if [ "${froms:-0}" -ge 2 ]; then
    ok "Dockerfile e multi-stage (${froms} etapas FROM)."
  else
    falha "Dockerfile nao e multi-stage. Use mais de uma etapa FROM (veja gabarito/dockerfile-sessao5-multistage)."
  fi
  if [ -f "${SCRIPT_DIR}/.dockerignore" ] && grep -q "node_modules" "${SCRIPT_DIR}/.dockerignore"; then
    ok ".dockerignore existe e ignora node_modules."
  else
    falha ".dockerignore ausente ou sem node_modules. Renomeie .dockerignore.exemplo para .dockerignore."
  fi
  if ! docker build -t docker-local:sessao5 "$SCRIPT_DIR" >/dev/null 2>&1; then
    falha "Build falhou. Rode 'docker build -t docker-local:sessao5 .' para ver o erro."
    return
  fi
  local bytes mb antes
  bytes="$(docker image inspect --format '{{.Size}}' docker-local:sessao5 2>/dev/null)"
  mb="$(awk -v b="${bytes:-0}" 'BEGIN{printf "%.1f", b/1048576}')"
  if [ -f "$STATE_FILE" ]; then
    antes="$(awk -v b="$(cat "$STATE_FILE" 2>/dev/null)" 'BEGIN{printf "%.1f", b/1048576}')"
    echo "        Tamanho antes: ${antes} MB  ->  agora: ${mb} MB"
  fi
  echo "$bytes" > "$STATE_FILE" 2>/dev/null
  if awk -v b="${bytes:-0}" 'BEGIN{exit !(b < 200*1048576)}'; then
    ok "Imagem tem ${mb} MB (abaixo de 200MB)."
  else
    falha "Imagem tem ${mb} MB (acima de 200MB). Use base alpine e copie so o necessario."
  fi
}

sessao6() {
  echo "Sessao 6: volume nomeado, persistencia e rede do usuario"
  exigir_docker || return

  local vol; vol="$(db_named_volume)"
  if [ -n "$vol" ]; then
    ok "Banco usa volume nomeado: $vol"
  else
    falha "Banco sem volume nomeado em /var/lib/postgresql/data. Crie um volume nomeado para '${DB_CONTAINER}'."
  fi

  local code; code="$(http_status "${API_URL}/recados")"
  if [ "$code" = "200" ]; then
    local marker="persist-$(date +%s)"
    curl -s -m 5 -X POST "${API_URL}/recados" \
      -H 'Content-Type: application/json' \
      -d "{\"autor\":\"verificar\",\"texto\":\"${marker}\"}" >/dev/null 2>&1
    docker restart "$DB_CONTAINER" >/dev/null 2>&1
    docker exec "$DB_CONTAINER" sh -c 'for i in $(seq 1 20); do pg_isready -q && exit 0; sleep 1; done; exit 1' >/dev/null 2>&1
    wait_http "${API_URL}/recados" 200 15 >/dev/null
    if curl -s -m 5 "${API_URL}/recados" 2>/dev/null | grep -q "$marker"; then
      ok "Recado persistiu apos derrubar e subir o banco."
    else
      falha "Recado nao persistiu. Confirme que os dados estao no volume nomeado."
    fi
  else
    falha "API nao respondeu em ${API_URL}/recados (codigo ${code}). Suba API e banco antes desta checagem."
  fi

  local api; api="$(find_api_container)"
  if [ -z "$api" ]; then
    falha "Container da API nao encontrado publicando a porta ${API_PORT}."
    return
  fi
  local shared="" n
  for n in $(networks_of "$api"); do
    case "$n" in
      bridge|host|none) continue;;
    esac
    if networks_of "$DB_CONTAINER" | grep -qw "$n"; then
      shared="$n"; break
    fi
  done
  if [ -n "$shared" ]; then
    ok "API e banco na mesma rede do usuario: $shared"
  else
    falha "API e banco nao compartilham uma rede definida pelo usuario. Crie uma rede e conecte os dois."
  fi
}

sessao7() {
  echo "Sessao 7: compose sobe API e banco, .env, /health 200"
  exigir_docker || return
  if ! compose_disponivel; then
    falha "'docker compose' indisponivel. Atualize o Docker."
    return
  fi
  local compose_file=""
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [ -f "${SCRIPT_DIR}/$f" ] && { compose_file="$f"; break; }
  done
  if [ -z "$compose_file" ]; then
    falha "Nao existe compose.yaml na raiz (veja gabarito/compose-sessao7.yaml)."
    return
  fi
  ok "Arquivo de compose encontrado: $compose_file"
  if [ -f "${SCRIPT_DIR}/.env" ]; then
    ok ".env presente (variaveis do compose)."
  else
    falha ".env ausente. Copie de .env.example."
  fi
  if ( cd "$SCRIPT_DIR" && docker compose up -d --build >/dev/null 2>&1 ); then
    ok "docker compose up subiu os servicos."
  else
    falha "docker compose up falhou. Rode 'docker compose up -d --build' para ver o erro."
    return
  fi
  local code; code="$(wait_http "${API_URL}/health" 200 30)"
  if [ "$code" = "200" ]; then
    ok "/health respondeu 200 com o compose no ar."
  else
    falha "/health nao respondeu 200 (codigo ${code}). Veja: docker compose logs"
  fi
}

sessao8() {
  echo "Sessao 8: imagem publicada e compose funcionando"
  exigir_docker || return
  if docker manifest inspect "$IMAGE" >/dev/null 2>&1; then
    ok "Tag remota existe no registro: $IMAGE"
  else
    falha "Tag remota nao encontrada. Publique com 'docker push ${IMAGE}' (defina DOCKER_IMAGE com a tag real)."
  fi
  if ! compose_disponivel; then
    falha "'docker compose' indisponivel. Atualize o Docker."
    return
  fi
  local compose_file=""
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [ -f "${SCRIPT_DIR}/$f" ] && { compose_file="$f"; break; }
  done
  if [ -z "$compose_file" ]; then
    falha "Nao existe compose.yaml na raiz."
    return
  fi
  if ( cd "$SCRIPT_DIR" && docker compose up -d >/dev/null 2>&1 ); then
    ok "docker compose up subiu os servicos."
  else
    falha "docker compose up falhou. Veja 'docker compose up -d'."
    return
  fi
  local code; code="$(wait_http "${API_URL}/health" 200 30)"
  if [ "$code" = "200" ]; then
    ok "/health respondeu 200 com o compose no ar."
  else
    falha "/health nao respondeu 200 (codigo ${code}). Veja: docker compose logs"
  fi
}

# --- entrada ---------------------------------------------------------------

n="${1:-}"
case "$n" in
  1) sessao1;;
  2) sessao2;;
  3) sessao3;;
  4) sessao4;;
  5) sessao5;;
  6) sessao6;;
  7) sessao7;;
  8) sessao8;;
  *)
    echo "Uso: ./verificar.sh <numero-da-sessao>   (de 1 a 8)"
    exit 1
    ;;
esac

echo
if [ "$FALHOU" -eq 0 ]; then
  echo "Resultado: tudo passou."
  exit 0
else
  echo "Resultado: ha falhas acima."
  exit 1
fi
