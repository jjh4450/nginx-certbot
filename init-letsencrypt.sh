#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

function show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]
This script automates the process of obtaining and renewing SSL certificates for multiple domains using Let's Encrypt, NGINX, and Docker Compose.

Options:
  -h, --help                Show this help message and exit
  -d, --domains DOMAINS     List of domains to request certificates for (e.g. "example.org www.example.org")
  -e, --email EMAIL         Email address for Let's Encrypt registration (optional, but recommended)
  -s, --staging             Use Let's Encrypt's staging environment for testing (avoids request limits)
  -k, --keysize SIZE        Specify the RSA key size for the certificate (default: 4096)
  -p, --path PATH           Path to store certbot data (default: ./data/certbot)
  -n, --cert-name NAME      Specify a name for the certificate (default: first domain name)

Examples:
  $(basename "$0") -d "example.org www.example.org" -e "admin@example.org"
  $(basename "$0") -d "example.org" -s -n "my-fixed-cert-name"
EOF
}

domains=()
rsa_key_size=4096
data_path="./data/certbot"
email=""
staging=0
cert_name=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -d|--domains)
      if [ -z "$2" ]; then
        echo "Error: --domains requires an argument"
        exit 1
      fi
      IFS=' ' read -r -a domains <<< "$2"
      shift 2
      ;;
    -e|--email)
      if [ -z "$2" ]; then
        echo "Error: --email requires an argument"
        exit 1
      fi
      email="$2"
      shift 2
      ;;
    -s|--staging)
      staging=1
      shift
      ;;
    -k|--keysize)
      if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --keysize requires a numeric argument"
        exit 1
      fi
      rsa_key_size="$2"
      shift 2
      ;;
    -p|--path)
      if [ -z "$2" ]; then
        echo "Error: --path requires an argument"
        exit 1
      fi
      data_path="$2"
      shift 2
      ;;
    -n|--cert-name)
      if [ -z "$2" ]; then
        echo "Error: --cert-name requires an argument"
        exit 1
      fi
      cert_name="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

if [ ${#domains[@]} -eq 0 ]; then
  echo "Error: At least one domain must be specified using -d or --domains"
  show_help
  exit 1
fi

if [ -z "$cert_name" ]; then
  cert_name="${domains[0]}"
fi

if ! [ -x "$(command -v docker compose)" ]; then
  echo 'Error: docker compose is not installed.' >&2
  exit 1
fi

if [ -d "$data_path" ]; then
  read -p "Existing data found for ${domains[*]}. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for ${domains[*]} ..."
path="/etc/letsencrypt/live/$cert_name"
mkdir -p "$data_path/conf/live/$cert_name"

if ! docker compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot; then
  echo "Failed to create dummy certificate"
  exit 1
fi

echo "### Starting nginx ..."
if ! docker compose up --force-recreate -d nginx; then
  echo "Failed to start nginx"
  exit 1
fi

echo "### Deleting dummy certificate for ${domains[*]} ..."
if ! docker compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$cert_name && \
  rm -Rf /etc/letsencrypt/archive/$cert_name && \
  rm -Rf /etc/letsencrypt/renewal/$cert_name.conf" certbot; then
  echo "Failed to delete dummy certificate"
  exit 1
fi

echo "### Requesting Let's Encrypt certificate for ${domains[*]} ..."
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

if [ $staging != "0" ]; then staging_arg="--staging"; fi

if ! docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal \
    --cert-name $cert_name" certbot; then
  echo "Failed to obtain SSL certificate"
  exit 1
fi

echo "### Reloading nginx ..."
if ! docker compose exec nginx nginx -s reload; then
  echo "Failed to reload nginx"
  exit 1
fi

echo "SSL certificate installation completed successfully!"
