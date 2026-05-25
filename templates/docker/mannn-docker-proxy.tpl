server {
    listen      %ip%:%web_port%;
    server_name %domain_idn% %alias_idn%;
    error_log   /var/log/nginx/domains/%domain%.error.log error;

    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    location ~ /\.(?!well-known\/) { deny all; return 404; }

    include %home%/%user%/conf/web/%domain%/nginx.proxy.conf;

    location /error/ {
        alias %home%/%user%/web/%domain%/document_errors/;
    }

    include /etc/nginx/conf.d/phpmyadmin.inc*;
    include /etc/nginx/conf.d/phppgadmin.inc*;
    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
