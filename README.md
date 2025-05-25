# Nginx with Let's Encrypt on Docker (2024 Update)

This project provides a solution for running Nginx with Let's Encrypt SSL certificates using Docker Compose. It's based on the [nginx-certbot project](https://github.com/wmnnd/nginx-certbot) and aims to simplify the process of obtaining and renewing SSL certificates for multiple domains.

## Features

- **Docker Compose Integration**: Uses the latest Docker Compose command for easy service management.
- **Automated SSL Management**: Automatically obtains and renews Let's Encrypt SSL certificates for your domains.
- **Multi-Domain Support**: Easily manage SSL certificates for multiple domains.

## Prerequisites

Make sure you have the following installed:

- Docker: [Get Docker](https://docs.docker.com/get-docker/)
- Docker Compose: Included with Docker since 2022. Verify with:

    ```bash
    docker compose version
    ```

## Setup and Usage

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/nginx-certbot.git
cd nginx-certbot
```

### 2. Configure Nginx

Edit the `data/nginx/app.conf` file to match your domain(s). Example:

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    server_tokens off;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name yourdomain.com www.yourdomain.com;
    server_tokens off;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://your_backend_service;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Replace `yourdomain.com` with your actual domain(s) and update the backend service as needed.

### 3. Run the Initialization Script

Initialize the setup with:

```bash
sudo ./init-letsencrypt.sh -d "yourdomain.com www.yourdomain.com" -e "your-email@example.com"
```

This script will:

- Generate a temporary SSL certificate
- Start Nginx
- Obtain a real SSL certificate from Let's Encrypt
- Reload Nginx with the valid SSL certificate

### 4. Certificate Renewal

SSL certificates will automatically renew before expiration. No manual restart is needed after running the `init-letsencrypt.sh` script.

To manually test the renewal process:

```bash
docker compose run --rm certbot renew
```

### 5. Stopping Services

To stop the Nginx and Certbot services:

```bash
docker compose down
```

## init-letsencrypt.sh Script Options

The `init-letsencrypt.sh` script supports various options:

- **-d, --domains**: Specify the domain(s) for the certificate
- **-e, --email**: Your email for Let's Encrypt notifications
- **-s, --staging**: Use Let's Encrypt staging environment (for testing)
- **-k, --keysize**: Specify the RSA key size (default: 4096)
- **-p, --path**: Set the path for Certbot data storage
- **-n, --cert-name**: Provide a custom name for the certificate

For a full list of options:

```bash
sudo ./init-letsencrypt.sh --help
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to submit issues, pull requests, or suggestions for improvements.
