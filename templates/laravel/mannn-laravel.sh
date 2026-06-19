#!/bin/bash
# mannn-laravel.sh — hook script for the mannn-laravel PHP-FPM template
#
# Unlike the proxy templates (nodejs/go/python/frankenphp/docker), a Laravel
# PHP-FPM domain needs no systemd service, port provisioning, or iptables rule:
# HestiaCP + PHP-FPM serve public/ directly. This file exists only because
# install.sh expects a .sh alongside every .tpl/.stpl pair, and HestiaCP runs
# it on domain create/rebuild. It is intentionally a safe no-op (exit 0).

exit 0
