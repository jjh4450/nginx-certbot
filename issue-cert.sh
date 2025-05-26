#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

#######################################
# 도움말
#######################################
help() {
  cat <<EOF
사용법: $(basename "$0") -d "example.com *.example.com" [옵션]

필수 옵션
  -d, --domains          공백으로 구분된 도메인 목록

선택 옵션
  -e, --email            연락용 이메일 주소
  -k, --keysize          RSA 키 길이 (기본 4096)
  -s, --staging          Let’s Encrypt 스테이징 환경 사용
  --remove-orphans       certbot 재시작 시 고아 컨테이너도 함께 정리
  -h, --help             도움말

※ Cloudflare API 토큰 파일은 **./data/credentials/cloudflare.ini** 로 고정되어 있으며
   **/etc/letsencrypt/cloudflare.ini** 로 마운트됩니다.
   `./data/certbot/conf` 안에 *동명의 디렉터리*가 있으면 반드시 삭제 후 실행하세요.
EOF
}

# ---------- 기본값 ----------
TOKEN_FILE="./data/credentials/cloudflare.ini"
remove_orphans=0
domains=()
email=""
rsa_key_size=4096
staging=0

# ---------- 옵션 파싱 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domains)   IFS=' ' read -r -a domains <<< "$2"; shift 2;;
    -e|--email)     email="$2"; shift 2;;
    -k|--keysize)   rsa_key_size="$2"; shift 2;;
    -s|--staging)   staging=1; shift;;
    --remove-orphans) remove_orphans=1; shift;;
    -h|--help)      help; exit 0;;
    *) echo "Unknown option: $1"; help; exit 1;;
  esac
done

[[ ${#domains[@]} -gt 0 ]] || { help; exit 1; }
[[ -f "$TOKEN_FILE" ]] || { echo "❌  $TOKEN_FILE 파일이 없습니다"; exit 1; }
chmod 600 "$TOKEN_FILE" || true

# ---------- 인수 조립 ----------
email_arg=${email:+--email "$email"}
[[ $staging -eq 1 ]] && staging_arg="--staging" || staging_arg=""

domain_args=""; for d in "${domains[@]}"; do domain_args+=" -d $d"; done

echo "🔒  certbot 자동 갱신 컨테이너 중지 및 정리…"
docker compose stop certbot --timeout 30 2>/dev/null || true
# 고아 컨테이너, 잠금 파일 정리
(docker compose ps --all -q | xargs -r docker rm -f >/dev/null 2>&1 || true)
find ./data/certbot/conf -type f -name 'lock*' -delete 2>/dev/null || true

echo "🚀  최초/수동 발급 시작…"
docker compose run --rm \
  --entrypoint certbot \
  certbot \
    certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 30 \
    $staging_arg $email_arg $domain_args \
    --rsa-key-size "$rsa_key_size" \
    --agree-tos --non-interactive --force-renewal

echo "🔄  nginx TLS 설정 리로드…"
docker compose exec nginx nginx -s reload || echo "⚠️  nginx 컨테이너가 없거나 재로드 실패"

echo "🔁  certbot 갱신 루프 재가동…"
if [[ $remove_orphans -eq 1 ]]; then
  docker compose up -d certbot --remove-orphans
else
  docker compose up -d certbot
fi

echo "✅  인증서 발급 및 적용 완료!"