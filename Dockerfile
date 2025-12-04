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

# ----------- RÉGÉNÉRER L'AUTOLOADER -----------
RUN composer dump-autoload --optimize --no-dev

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

echo "🚀 Démarrage de l'application Laravel..."

# Nettoyer TOUS les caches (sans set -e pour éviter les erreurs fatales)
echo "🧹 Nettoyage des caches..."
rm -rf bootstrap/cache/*.php 2>/dev/null || true
php artisan config:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
php artisan view:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true

# Régénérer l'autoloader
echo "🔄 Régénération de l'autoloader..."
composer dump-autoload --optimize 2>/dev/null || echo "⚠️ Autoloader déjà généré"

# Vérifier la connexion DB
echo "🔍 Test de connexion à la base de données..."
if php artisan db:show 2>/dev/null; then
    echo "✅ Connexion DB réussie"
else
    echo "⚠️ Impossible d'afficher les infos DB (mais on continue)"
fi

# Migrations
echo "📊 Exécution des migrations..."
if php artisan migrate --force 2>&1; then
    echo "✅ Migrations exécutées"
else
    echo "❌ Erreur lors des migrations"
    # Ne pas exit pour voir les autres logs
fi

# Seeder uniquement si aucun utilisateur
echo "👤 Vérification des utilisateurs..."
php artisan tinker --execute="
try {
    \$count = \App\Models\User::count();
    if (\$count === 0) {
        echo 'Aucun utilisateur, exécution du seeder...' . PHP_EOL;
        // On ne peut pas appeler db:seed depuis tinker, on crée juste l'admin
        \App\Models\User::create([
            'name' => 'Administrateur',
            'email' => 'admin@example.com',
            'password' => \Illuminate\Support\Facades\Hash::make('password'),
            'telephone' => '0123456789',
            'role' => 'admin',
            'actif' => true,
        ]);
        echo '✅ Admin créé' . PHP_EOL;
    } else {
        echo '✅ ' . \$count . ' utilisateur(s) trouvé(s)' . PHP_EOL;
    }
} catch (\Exception \$e) {
    echo '⚠️ Erreur: ' . \$e->getMessage() . PHP_EOL;
}
" 2>/dev/null || echo "⚠️ Impossible de vérifier les utilisateurs"

# Lien storage
echo "🔗 Création du lien symbolique..."
php artisan storage:link --force 2>/dev/null || echo "⚠️ Lien déjà existant"

# Cacher les configs
echo "⚡ Génération des caches..."
php artisan config:cache 2>/dev/null || echo "⚠️ Config cache échoué"
php artisan route:cache 2>/dev/null || echo "⚠️ Route cache échoué"
php artisan view:cache 2>/dev/null || echo "⚠️ View cache échoué"
php artisan filament:optimize 2>/dev/null || echo "⚠️ Filament optimize échoué"

echo ""
echo "✅ ======================================"
echo "✅  Application Laravel prête !"
echo "✅ ======================================"
echo ""
echo "🔐 Compte admin:"
echo "   📧 Email: admin@example.com"
echo "   🔑 Mot de passe: password"
echo ""
echo "⚠️  CHANGEZ CE MOT DE PASSE EN PRODUCTION !"
echo ""

# Démarrer Apache (IMPORTANT: ne pas mettre en background)
echo "🌐 Démarrage du serveur Apache sur le port 80..."
exec apache2-foreground
EOF

RUN chmod +x /start.sh

# ----------- EXPOSER LE PORT 80 -----------
EXPOSE 80

# ----------- COMMANDE DE DÉMARRAGE -----------
CMD ["/start.sh"]
