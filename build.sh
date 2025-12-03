#!/usr/bin/env bash
# exit on error
set -o errexit

echo "🔧 Installation des dépendances Composer..."
composer install --no-dev --optimize-autoloader
echo "📁 Configuration des permissions..."
chmod -R 775 storage bootstrap/cache
echo "⚡ Mise en cache des configurations..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "🗄️ Migration de la base de données..."
php artisan migrate --force

echo "🔗 Création du lien symbolique storage..."
php artisan storage:link || true

echo "🚀 Optimisation de l'application..."
php artisan optimize

echo "✅ Build terminé avec succès!"
