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

# ----------- RÉGÉNÉRER L'AUTOLOADER APRÈS AVOIR COPIÉ TOUS LES FICHIERS -----------
RUN composer dump-autoload --optimize --no-dev --classmap-authoritative

# ----------- INSTALLER LES DÉPENDANCES NPM ET BUILD -----------
RUN npm install --legacy-peer-deps --no-audit --no-fund
RUN npm run build

# ----------- PUBLIER LES ASSETS FILAMENT -----------
RUN php artisan filament:assets || true

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

# Nettoyer TOUS les caches
echo "🧹 Nettoyage complet des caches..."
rm -rf bootstrap/cache/*.php
php artisan config:clear || true
php artisan cache:clear || true
php artisan view:clear || true
php artisan route:clear || true
php artisan event:clear || true

# IMPORTANT: Régénérer l'autoloader pour découvrir les commandes
echo "🔄 Régénération de l'autoloader..."
composer dump-autoload --optimize

# Vérifier que la commande existe
echo "🔍 Vérification de la commande user:create-admin..."
if php artisan list | grep -q "user:create-admin"; then
    echo "✅ Commande user:create-admin trouvée !"
else
    echo "⚠️  Commande user:create-admin non trouvée, utilisation de Tinker..."
fi

# Vérifier la connexion DB
echo "🔍 Test de connexion à la base de données..."
php artisan db:show || echo "⚠️ Attention: Impossible d'afficher les infos DB"

# Migrations
echo "📊 Exécution des migrations..."
php artisan migrate --force

# Créer l'utilisateur admin - Essayer d'abord avec la commande, sinon utiliser Tinker
echo "👤 Création de l'utilisateur admin..."
if php artisan user:create-admin 2>/dev/null; then
    echo "✅ Admin créé via la commande Artisan"
else
    echo "⚠️  Commande échouée, utilisation de Tinker..."
    php artisan tinker --execute="
    \$email = 'admin@example.com';
    if (!\App\Models\User::where('email', \$email)->exists()) {
        \App\Models\User::create([
            'name' => 'Admin',
            'email' => \$email,
            'password' => \Illuminate\Support\Facades\Hash::make('password'),
            'telephone' => '0000000000',
            'role' => 'admin',
            'actif' => true,
            'email_verified_at' => now(),
        ]);
        echo 'Admin créé avec succès via Tinker';
    } else {
        echo 'Admin existe déjà';
    }
    " || echo "⚠️ Impossible de créer l'admin"
fi

# Lien storage
echo "🔗 Création du lien symbolique..."
php artisan storage:link --force || true

# Cacher les configs (APRÈS les migrations et la création de l'admin)
echo "⚡ Génération des caches optimisés..."
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan filament:optimize || true

echo ""
echo "✅ =================================="
echo "✅  Application Laravel prête !"
echo "✅ =================================="
echo ""
echo "📧 Email admin: admin@example.com"
echo "🔑 Mot de passe: password"
echo ""
echo "⚠️  ⚠️  ⚠️  CHANGEZ CE MOT DE PASSE IMMÉDIATEMENT ! ⚠️  ⚠️  ⚠️"
echo ""

# Démarrer Apache
echo "🌐 Démarrage du serveur Apache..."
apache2-foreground
EOF

RUN chmod +x /start.sh

# ----------- EXPOSER LE PORT 80 -----------
EXPOSE 80

# ----------- COMMANDE DE DÉMARRAGE -----------
CMD ["/start.sh"]
