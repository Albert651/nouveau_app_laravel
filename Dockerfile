# ----------- IMAGE DE BASE -----------
FROM php:8.2-apache

# ----------- INSTALLER LES DÉPENDANCES SYSTÈME -----------
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    zip \
    g++ \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    libzip-dev \
    libpq-dev \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ----------- INSTALLER LES EXTENSIONS PHP -----------
RUN docker-php-ext-install \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    intl

# ----------- INSTALLER COMPOSER -----------
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# ----------- ACTIVER MOD_REWRITE POUR LARAVEL -----------
RUN a2enmod rewrite

# ----------- DÉFINIR LE RÉPERTOIRE DE TRAVAIL -----------
WORKDIR /var/www/html

# ----------- COPIER COMPOSER FILES UNIQUEMENT -----------
COPY composer.json composer.lock ./

# ----------- INSTALLER LES DÉPENDANCES COMPOSER -----------
RUN COMPOSER_MEMORY_LIMIT=-1 composer install \
    --no-dev \
    --no-scripts \
    --no-autoloader \
    --no-interaction

# ----------- COPIER LE RESTE DES FICHIERS -----------
COPY . .

# ----------- NETTOYER ET RÉGÉNÉRER L'AUTOLOADER -----------
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

# ----------- INSTALLER LES DÉPENDANCES NPM ET BUILD -----------
RUN npm install --legacy-peer-deps --no-audit --no-fund
RUN npm run build

# ----------- PUBLIER LES ASSETS FILAMENT -----------
RUN php artisan filament:assets || true

# ----------- NE PAS GÉNÉRER LES CACHES PENDANT LE BUILD -----------
# Les caches seront générés au démarrage avec les vraies variables d'environnement

# ----------- DONNER LES PERMISSIONS -----------
RUN chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache \
    /var/www/html/public

RUN chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

# ----------- CONFIGURATION APACHE POUR LARAVEL -----------
RUN cat > /etc/apache2/sites-available/000-default.conf <<'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html/public
    <Directory /var/www/html/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# ----------- SCRIPT DE DÉMARRAGE -----------
RUN cat > /start.sh <<'EOF'
#!/bin/bash
set -e

echo "🚀 Démarrage de l'application Laravel..."

# IMPORTANT: Nettoyer TOUS les caches avant de faire quoi que ce soit
echo "🧹 Nettoyage complet des caches..."
rm -rf bootstrap/cache/*.php
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

# Vérifier la connexion à la base de données
echo "🔍 Vérification de la connexion à la base de données..."
php artisan db:show || echo "⚠️  Impossible d'afficher les infos DB, mais on continue..."

# Exécuter les migrations
echo "📊 Exécution des migrations..."
php artisan migrate --force

# Créer l'utilisateur admin
echo "👤 Création de l'utilisateur admin..."
php artisan user:create-admin

# Créer le lien symbolique storage
echo "🔗 Création du lien symbolique storage..."
php artisan storage:link --force || true

# Régénérer les caches optimisés (APRÈS les migrations)
echo "⚡ Génération des caches optimisés..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Optimisations Filament
echo "🎨 Optimisation Filament..."
php artisan filament:optimize || true

echo "✅ Application prête !"
echo "📧 Utilisateur admin: admin@example.com"
echo "🔑 Mot de passe: password"
echo "⚠️  CHANGEZ CE MOT DE PASSE IMMÉDIATEMENT !"

# Démarrer Apache
echo "🌐 Démarrage du serveur Apache..."
apache2-foreground
EOF

RUN chmod +x /start.sh

# ----------- EXPOSER LE PORT 80 -----------
EXPOSE 80

# ----------- COMMANDE DE DÉMARRAGE -----------
CMD ["/start.sh"]
