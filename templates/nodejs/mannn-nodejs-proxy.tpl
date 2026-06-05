server {
    listen      %ip%:%web_port%;
    server_name %domain_idn% %alias_idn%;
    error_log   /var/log/nginx/domains/%domain%.error.log error;
    access_log  /var/log/nginx/domains/%domain%.log combined;
    access_log  /var/log/nginx/domains/%domain%.bytes bytes;

    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    server_tokens off;
    client_max_body_size 10m;
    limit_req zone=mannn burst=20 nodelay;

    location ~ /\.(?!well-known\/) { deny all; return 404; }

    # Block access to private directory
    location ^~ /private/ { return 404; }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self'; font-src 'self'; frame-ancestors 'none';" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    proxy_hide_header X-Powered-By;

    # Block sensitive file extensions
    location ~* \.(bak|backup|old|orig|save|swp|tmp|sql|zip|tar|gz|rar|log)(\.gz)?$ {
        return 404;
    }

    # Block common config file paths
    location ~* ^/(wp-config\.php|config\.php|settings\.php|database\.yml|appsettings\.json)$ {
        return 404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.proxy.conf;

    location /error/ {
        alias %home%/%user%/web/%domain%/document_errors/;
    }

    include /etc/nginx/conf.d/phpmyadmin.inc*;
    include /etc/nginx/conf.d/phppgadmin.inc*;
    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}

